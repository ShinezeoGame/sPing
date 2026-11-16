import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/device.dart';
import '../crypto/crypto.dart';
import 'protocol.dart';

/// Délais des échanges.
class LinkTimings {
  const LinkTimings({
    this.handshake = const Duration(seconds: 10),
    this.decision = const Duration(minutes: 2),
    this.ping = const Duration(seconds: 20),
    this.silence = const Duration(seconds: 50),
  });

  /// Attente maximale d'un message pendant la poignée de main.
  final Duration handshake;

  /// Temps laissé à l'utilisateur pour comparer les codes et accepter l'appairage.
  final Duration decision;

  /// Intervalle des messages de maintien (liaison inactive).
  final Duration ping;

  /// Une liaison silencieuse plus longtemps que cela est considérée comme coupée.
  final Duration silence;
}

/// Ce que cet appareil présente de lui-même lors d'une connexion.
class LocalDevice {
  const LocalDevice({required this.id, required this.name, required this.identity, required this.role});

  final String id;
  final String name;
  final Identity identity;
  final DeviceRole role;
}

/// Raisons de refus envoyées par le téléphone.
abstract final class Refusal {
  /// Le PC n'est pas (ou plus) appairé avec ce téléphone.
  static const unknown = 'inconnu';

  /// Le téléphone n'attend pas d'appairage (« Appairer un PC » n'a pas été ouvert).
  static const pairingClosed = 'appairage_ferme';

  /// Un autre appairage est déjà en cours.
  static const busy = 'occupe';
}

/// Le téléphone a refusé la connexion.
class LinkRefused extends LinkClosed {
  const LinkRefused(this.reason) : super('Connexion refusée ($reason).');

  final String reason;
}

/// Liaison établie et authentifiée avec un appareil appairé : tous les messages sont
/// chiffrés.
class Link {
  Link._(this._framed, this._channel, this.peer, this.timings) {
    _lastReceived = DateTime.now();
    unawaited(_readLoop());
    _keepAlive = Timer.periodic(timings.ping, (_) => _checkAlive());
  }

  final FramedSocket _framed;
  final SecureChannel _channel;

  /// L'appareil au bout de la liaison (son nom peut avoir changé depuis l'appairage).
  final PairedDevice peer;
  final LinkTimings timings;

  final _messages = StreamController<Map<String, dynamic>>();
  final _closed = Completer<String>();
  Future<void> _sendChain = Future.value();
  late DateTime _lastReceived;
  late final Timer _keepAlive;

  InternetAddress get remoteAddress => _framed.remoteAddress;

  /// Messages reçus (hors messages de maintien). Un seul abonné.
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  /// Se termine, avec la raison, quand la liaison est coupée.
  Future<String> get done => _closed.future;
  bool get isClosed => _closed.isCompleted;

  Future<void> _readLoop() async {
    try {
      while (!isClosed) {
        final frame = await _framed.next();
        _lastReceived = DateTime.now();
        final message = decodeJson(await _channel.open(frame));
        switch (message['type']) {
          case 'ping':
            send({'type': 'pong'});
          case 'pong':
            break;
          default:
            _messages.add(message);
        }
      }
    } on Object catch (error) {
      close(error is LinkClosed || error is CryptoFailure ? error.toString() : 'Liaison interrompue : $error');
    }
  }

  void _checkAlive() {
    if (DateTime.now().difference(_lastReceived) > timings.silence) {
      close('L\'autre appareil ne répond plus.');
    } else {
      send({'type': 'ping'});
    }
  }

  /// Envoie un message chiffré. Les messages partent dans l'ordre des appels.
  Future<void> send(Map<String, dynamic> message) {
    if (isClosed) return Future.value();
    final clear = utf8.encode(jsonEncode(message));
    return _sendChain = _sendChain.then((_) async {
      if (isClosed) return;
      try {
        _framed.send(await _channel.seal(clear));
      } on Object catch (error) {
        close('Envoi impossible : $error');
      }
    });
  }

  void close([String reason = 'Liaison fermée.']) {
    if (isClosed) return;
    _closed.complete(reason);
    _keepAlive.cancel();
    unawaited(_messages.close());
    unawaited(_sendChain.whenComplete(_framed.close));
  }

  // ── Ouverture d'une session : PC (initiateur) ──

  /// Le PC se connecte au téléphone [phone], avec lequel il est déjà appairé.
  static Future<Link> connect({
    required InternetAddress address,
    required int port,
    required LocalDevice self,
    required PairedDevice phone,
    LinkTimings timings = const LinkTimings(),
  }) async {
    final socket = await Socket.connect(address, port, timeout: timings.handshake);
    final framed = FramedSocket(socket, maxFrame: Limits.handshakeBytes);
    try {
      final ephemeral = await SPingCrypto.x25519.newKeyPair();
      final ephemeralPublic = (await ephemeral.extractPublicKey()).bytes;
      final nonce = SPingCrypto.randomBytes(16);
      framed.sendJson({
        'sping': 1,
        'type': 'session',
        'id': self.id,
        'nom': self.name,
        'eph': base64.encode(ephemeralPublic),
        'nonce': base64.encode(nonce),
      });
      final reply = await framed.nextJson(timeout: timings.handshake);
      _throwIfRefused(reply);
      if (reply['type'] != 'session' || reply['id'] != phone.id) {
        throw const LinkClosed('Ce n\'est pas le téléphone attendu.');
      }
      final keys = await SessionKeys.derive(
        initiator: true,
        identity: self.identity,
        peerPublicKey: phone.publicKey,
        ephemeral: ephemeral,
        ephemeralPublic: ephemeralPublic,
        peerEphemeral: b64Field(reply, 'eph', 32),
        initiatorNonce: nonce,
        responderNonce: b64Field(reply, 'nonce', 16),
      );
      final channel = SecureChannel(keys);
      framed.send(await channel.seal(utf8.encode(jsonEncode({'type': 'pret'}))));
      // La réponse chiffrée du téléphone prouve qu'il détient bien la clé retenue à l'appairage.
      final ready = decodeJson(await channel.open(await framed.next(timeout: timings.handshake)));
      if (ready['type'] != 'pret') throw const LinkClosed('Poignée de main invalide.');
      framed.maxFrame = Limits.frameBytes;
      return Link._(framed, channel, phone.copyWith(name: _name(reply, phone.name)), timings);
    } on Object catch (error) {
      await framed.close();
      if (error is CryptoFailure) throw LinkClosed('Le téléphone n\'a pas prouvé son identité ($error).');
      rethrow;
    }
  }

  /// Le PC demande l'appairage au téléphone : renvoie l'appairage en attente de décision.
  static Future<PendingPairing> pair({
    required InternetAddress address,
    required int port,
    required LocalDevice self,
    LinkTimings timings = const LinkTimings(),
  }) async {
    final socket = await Socket.connect(address, port, timeout: timings.handshake);
    final framed = FramedSocket(socket, maxFrame: Limits.handshakeBytes);
    try {
      final nonce = SPingCrypto.randomBytes(16);
      final publicKey = self.identity.publicKey;
      framed.sendJson({
        'sping': 1,
        'type': 'appairage',
        'id': self.id,
        'nom': self.name,
        'engagement': base64.encode(await Pairing.commitment(publicKey, nonce)),
      });
      final reply = await framed.nextJson(timeout: timings.handshake);
      _throwIfRefused(reply);
      if (reply['type'] != 'appairage') throw const LinkClosed('Réponse inattendue.');
      final phoneId = _id(reply);
      final phoneKey = b64Field(reply, 'cle', 32);
      final phoneNonce = b64Field(reply, 'nonce', 16);
      // Le PC ne révèle sa clé qu'après avoir reçu celle du téléphone.
      framed.sendJson({'type': 'revelation', 'cle': base64.encode(publicKey), 'nonce': base64.encode(nonce)});
      final code = await Pairing.code(
        initiatorKey: publicKey,
        responderKey: phoneKey,
        initiatorNonce: nonce,
        responderNonce: phoneNonce,
      );
      return PendingPairing._(
        framed,
        PairedDevice(id: phoneId, name: _name(reply, 'Téléphone'), publicKey: phoneKey, pairedAt: DateTime.now()),
        code,
        timings,
      );
    } on Object {
      await framed.close();
      rethrow;
    }
  }

  // ── Accueil d'une connexion : téléphone (répondeur) ──

  /// Traite une connexion entrante sur le téléphone.
  ///
  /// Renvoie un [Link] pour un PC appairé, un [PendingPairing] pour une demande
  /// d'appairage acceptable ; lève [LinkClosed] sinon (après avoir répondu par un refus).
  static Future<Object> accept(
    Socket socket, {
    required LocalDevice self,
    required PairedDevice? Function(String id) findPeer,
    required String? Function() pairingRefusal,
    LinkTimings timings = const LinkTimings(),
  }) async {
    final framed = FramedSocket(socket, maxFrame: Limits.handshakeBytes);
    try {
      final hello = await framed.nextJson(timeout: timings.handshake);
      if (hello['sping'] != 1) throw const LinkClosed('Ce n\'est pas sPing.');
      final peerId = _id(hello);
      switch (hello['type']) {
        case 'session':
          final peer = findPeer(peerId);
          if (peer == null) {
            framed.sendJson({'type': 'refus', 'raison': Refusal.unknown});
            throw const LinkRefused(Refusal.unknown);
          }
          final ephemeral = await SPingCrypto.x25519.newKeyPair();
          final ephemeralPublic = (await ephemeral.extractPublicKey()).bytes;
          final nonce = SPingCrypto.randomBytes(16);
          final keys = await SessionKeys.derive(
            initiator: false,
            identity: self.identity,
            peerPublicKey: peer.publicKey,
            ephemeral: ephemeral,
            ephemeralPublic: ephemeralPublic,
            peerEphemeral: b64Field(hello, 'eph', 32),
            initiatorNonce: b64Field(hello, 'nonce', 16),
            responderNonce: nonce,
          );
          framed.sendJson({
            'type': 'session',
            'id': self.id,
            'nom': self.name,
            'eph': base64.encode(ephemeralPublic),
            'nonce': base64.encode(nonce),
          });
          final channel = SecureChannel(keys);
          // Seul le PC appairé peut chiffrer ce premier message : un appareil qui reprend
          // son identifiant sans avoir sa clé échoue ici, avant d'avoir rien reçu.
          final ready = decodeJson(await channel.open(await framed.next(timeout: timings.handshake)));
          if (ready['type'] != 'pret') throw const LinkClosed('Poignée de main invalide.');
          framed.send(await channel.seal(utf8.encode(jsonEncode({'type': 'pret'}))));
          framed.maxFrame = Limits.frameBytes;
          return Link._(framed, channel, peer.copyWith(name: _name(hello, peer.name)), timings);
        case 'appairage':
          final refusal = pairingRefusal();
          if (refusal != null) {
            framed.sendJson({'type': 'refus', 'raison': refusal});
            throw LinkRefused(refusal);
          }
          final commitment = b64Field(hello, 'engagement', 32);
          final nonce = SPingCrypto.randomBytes(16);
          framed.sendJson({
            'type': 'appairage',
            'id': self.id,
            'nom': self.name,
            'cle': base64.encode(self.identity.publicKey),
            'nonce': base64.encode(nonce),
          });
          final reveal = await framed.nextJson(timeout: timings.handshake);
          if (reveal['type'] != 'revelation') throw const LinkClosed('Réponse inattendue.');
          final pcKey = b64Field(reveal, 'cle', 32);
          final pcNonce = b64Field(reveal, 'nonce', 16);
          final expected = await Pairing.commitment(pcKey, pcNonce);
          if (!_equal(expected, commitment)) throw const LinkClosed('Le PC a changé de clé en cours d\'appairage.');
          final code = await Pairing.code(
            initiatorKey: pcKey,
            responderKey: self.identity.publicKey,
            initiatorNonce: pcNonce,
            responderNonce: nonce,
          );
          return PendingPairing._(
            framed,
            PairedDevice(id: peerId, name: _name(hello, 'PC'), publicKey: pcKey, pairedAt: DateTime.now()),
            code,
            timings,
          );
        default:
          throw const LinkClosed('Demande inconnue.');
      }
    } on Object catch (error) {
      await framed.close();
      if (error is CryptoFailure) throw LinkClosed('Le PC n\'a pas prouvé son identité ($error).');
      rethrow;
    }
  }

  static void _throwIfRefused(Map<String, dynamic> reply) {
    if (reply['type'] == 'refus') {
      final reason = reply['raison'];
      throw LinkRefused(reason is String ? reason : 'inconnue');
    }
  }

  static String _id(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || !validId(id)) throw const LinkClosed('Identifiant invalide.');
    return id;
  }

  static String _name(Map<String, dynamic> json, String fallback) {
    final name = json['nom'];
    final clean = name is String ? cleanName(name) : '';
    return clean.isEmpty ? fallback : clean;
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Appairage en cours : les deux appareils affichent [code] ; chacun doit accepter.
class PendingPairing {
  PendingPairing._(this._framed, this.peer, this.code, LinkTimings timings) {
    _timeout = Timer(timings.decision, () => _finish(false, 'Délai dépassé.'));
    unawaited(_listen());
  }

  final FramedSocket _framed;

  /// L'autre appareil et sa clé publique, à retenir si l'appairage aboutit.
  final PairedDevice peer;

  /// Code de vérification à comparer (« 482 913 »).
  final String code;

  late final Timer _timeout;
  final _result = Completer<bool>();
  bool? _local;
  bool? _remote;
  String? _failure;

  /// Vrai si les deux appareils ont accepté ; faux sinon.
  Future<bool> get result => _result.future;

  /// Pourquoi l'appairage n'a pas abouti.
  String? get failure => _failure;

  bool get isDone => _result.isCompleted;

  /// L'autre appareil a déjà accepté.
  bool get remoteAccepted => _remote == true;

  /// Cet appareil a déjà répondu.
  bool get answered => _local != null;

  Future<void> _listen() async {
    try {
      final message = await _framed.nextJson();
      if (message['type'] != 'decision') throw const LinkClosed('Réponse inattendue.');
      _remote = message['accepte'] == true;
      if (_remote == false) return _finish(false, 'Appairage refusé sur l\'autre appareil.');
      _check();
    } on Object {
      if (!isDone) _finish(false, 'L\'autre appareil a interrompu l\'appairage.');
    }
  }

  /// Réponse de l'utilisateur, après comparaison des codes.
  void decide(bool accepted) {
    if (isDone || _local != null) return;
    _local = accepted;
    try {
      _framed.sendJson({'type': 'decision', 'accepte': accepted});
    } on Object {
      // La fermeture est traitée par _listen.
    }
    if (!accepted) return _finish(false, 'Appairage refusé.');
    _check();
  }

  /// Abandonne l'appairage.
  void cancel() => decide(false);

  void _check() {
    if (_local == true && _remote == true) _finish(true, null);
  }

  void _finish(bool ok, String? failure) {
    if (isDone) return;
    _failure = failure;
    _timeout.cancel();
    _result.complete(ok);
    unawaited(_framed.close());
  }
}

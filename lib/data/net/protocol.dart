import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Port par défaut : annonces du téléphone (UDP) et liaison avec le PC (TCP).
/// sDrop utilise 47873 : les deux applications cohabitent.
const spingPort = 47874;

/// Groupe de multidiffusion des annonces, limité au réseau local.
const spingMulticastGroup = '239.83.80.73';

/// Garde-fous appliqués à ce qui arrive du réseau.
abstract final class Limits {
  /// Taille maximale d'un message, en octets (une notification avec son icône).
  static const frameBytes = 256 * 1024;

  /// Taille maximale d'un message avant chiffrement (poignée de main).
  static const handshakeBytes = 4096;

  /// Longueur maximale d'une réponse écrite sur le PC.
  static const replyLength = 2000;
}

/// Une liaison coupée ou un échange invalide.
class LinkClosed implements Exception {
  const LinkClosed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Messages encadrés sur une connexion TCP : longueur sur 4 octets, puis le contenu.
class FramedSocket {
  FramedSocket(this.socket, {this.maxFrame = Limits.frameBytes}) {
    _subscription = socket.listen(
      _onData,
      onError: (Object error) => _fail(LinkClosed('Connexion interrompue : $error')),
      onDone: () => _fail(const LinkClosed('Connexion fermée par l\'autre appareil.')),
      cancelOnError: true,
    );
  }

  final Socket socket;
  int maxFrame;
  late final StreamSubscription<Uint8List> _subscription;
  final _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);
  final _frames = <Uint8List>[];
  Completer<Uint8List>? _waiting;
  Object? _error;
  bool _closed = false;

  InternetAddress get remoteAddress => socket.remoteAddress;

  void _onData(Uint8List data) {
    _buffer.add(_pending);
    _buffer.add(data);
    var bytes = _buffer.takeBytes();
    var offset = 0;
    while (bytes.length - offset >= 4) {
      final length = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
      if (length > maxFrame) {
        _fail(const LinkClosed('Message trop grand.'));
        return;
      }
      if (bytes.length - offset - 4 < length) break;
      _deliver(Uint8List.fromList(bytes.sublist(offset + 4, offset + 4 + length)));
      offset += 4 + length;
    }
    _pending = offset == 0 ? bytes : Uint8List.fromList(bytes.sublist(offset));
    bytes = Uint8List(0);
  }

  void _deliver(Uint8List frame) {
    final waiting = _waiting;
    if (waiting != null) {
      _waiting = null;
      waiting.complete(frame);
    } else {
      _frames.add(frame);
    }
  }

  void _fail(Object error) {
    _error ??= error;
    final waiting = _waiting;
    _waiting = null;
    waiting?.completeError(_error!);
    close();
  }

  /// Message suivant ; lève [LinkClosed] si la connexion se ferme ou si rien n'arrive à temps.
  Future<Uint8List> next({Duration? timeout}) {
    if (_frames.isNotEmpty) return Future.value(_frames.removeAt(0));
    if (_error != null) return Future.error(_error!);
    final completer = _waiting = Completer<Uint8List>();
    if (timeout == null) return completer.future;
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _fail(const LinkClosed('L\'autre appareil ne répond pas.'));
        throw const LinkClosed('L\'autre appareil ne répond pas.');
      },
    );
  }

  void send(List<int> frame) {
    if (_closed) throw const LinkClosed('Connexion fermée.');
    final header = ByteData(4)..setUint32(0, frame.length);
    socket.add(header.buffer.asUint8List());
    socket.add(frame);
  }

  Future<Map<String, dynamic>> nextJson({Duration? timeout}) async => decodeJson(await next(timeout: timeout));

  void sendJson(Map<String, dynamic> message) => send(utf8.encode(jsonEncode(message)));

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _error ??= const LinkClosed('Connexion fermée.');
    final waiting = _waiting;
    _waiting = null;
    waiting?.completeError(_error!);
    await _subscription.cancel();
    try {
      await socket.flush().timeout(const Duration(seconds: 1));
    } on Object {
      // Déjà fermée.
    }
    socket.destroy();
  }
}

/// Lit un objet JSON ; lève [LinkClosed] si ce n'en est pas un.
Map<String, dynamic> decodeJson(List<int> bytes) {
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is Map<String, dynamic>) return value;
  } on Object {
    // Traité ci-dessous.
  }
  throw const LinkClosed('Message illisible.');
}

/// Lit des octets encodés en base64 d'une longueur donnée.
List<int> b64Field(Map<String, dynamic> json, String key, int length) {
  final value = json[key];
  if (value is String) {
    try {
      final bytes = base64.decode(value);
      if (bytes.length == length) return bytes;
    } on FormatException {
      // Traité ci-dessous.
    }
  }
  throw LinkClosed('Champ « $key » invalide.');
}

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Chiffrement de sPing.
///
/// * Chaque appareil a une **identité** : une paire de clés X25519 tirée au hasard à la
///   première ouverture, gardée dans le stockage sécurisé du système.
/// * **Appairage** : les deux appareils échangent leurs clés publiques et affichent un code
///   à 6 chiffres calculé à partir des deux clés ; l'utilisateur vérifie qu'il est le même
///   des deux côtés. Le PC s'engage d'abord sur sa clé (empreinte envoyée avant la clé
///   elle-même) : un intermédiaire ne peut pas choisir ses clés pour retomber sur le même
///   code des deux côtés.
/// * **Session** : à chaque connexion, chaque appareil tire une clé éphémère. La clé de
///   session combine le secret des clés durables (seuls les deux appareils appairés le
///   connaissent) et celui des clés éphémères (une clé durable volée plus tard ne déchiffre
///   pas les échanges passés). Les messages sont chiffrés en AES-256-GCM, une clé par sens,
///   numérotés : un message rejoué, retiré, déplacé ou modifié coupe la liaison.
abstract final class SPingCrypto {
  static final x25519 = X25519();
  static final aes = AesGcm.with256bits();
  static final sha256 = Sha256();

  /// Octets aléatoires sûrs.
  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList([for (var i = 0; i < length; i++) random.nextInt(256)]);
  }

  static Future<Uint8List> hash(List<List<int>> parts) async {
    final sink = sha256.newHashSink();
    for (final part in parts) {
      sink.add(part);
    }
    sink.close();
    return Uint8List.fromList((await sink.hash()).bytes);
  }

  static Future<Uint8List> sharedSecret(SimpleKeyPair mine, List<int> theirPublicKey) async {
    final secret = await x25519.sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(theirPublicKey, type: KeyPairType.x25519),
    );
    final bytes = Uint8List.fromList(await secret.extractBytes());
    // Une clé publique « faible » (point d'ordre faible) donne un secret nul : refusée.
    if (bytes.every((b) => b == 0)) throw const CryptoFailure('Clé publique invalide.');
    return bytes;
  }

  static Future<Uint8List> hkdf(
    List<int> secret, {
    required List<int> salt,
    required List<int> info,
    int length = 64,
  }) async {
    final key = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: length,
    ).deriveKey(secretKey: SecretKey(secret), nonce: salt, info: info);
    return Uint8List.fromList(await key.extractBytes());
  }

  static List<int> label(String text) => utf8.encode(text);
}

/// Échec d'une opération cryptographique : la liaison doit être coupée.
class CryptoFailure implements Exception {
  const CryptoFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Identité durable d'un appareil.
class Identity {
  Identity._(this.keyPair, this.publicKey, this.seed);

  final SimpleKeyPair keyPair;

  /// Clé publique (32 octets) : c'est elle que l'autre appareil retient à l'appairage.
  final Uint8List publicKey;

  /// Graine de la clé privée (32 octets), à conserver dans le stockage sécurisé.
  final Uint8List seed;

  static Future<Identity> fromSeed(List<int> seed) async {
    if (seed.length != 32) throw const CryptoFailure('Graine d\'identité invalide.');
    final pair = await SPingCrypto.x25519.newKeyPairFromSeed(seed);
    final public = await pair.extractPublicKey();
    return Identity._(pair, Uint8List.fromList(public.bytes), Uint8List.fromList(seed));
  }

  static Future<Identity> generate() => fromSeed(SPingCrypto.randomBytes(32));
}

/// Calculs de l'appairage. « initiateur » = le PC, « répondeur » = le téléphone.
abstract final class Pairing {
  /// Empreinte par laquelle le PC s'engage sur sa clé avant de la révéler.
  static Future<Uint8List> commitment(List<int> publicKey, List<int> nonce) =>
      SPingCrypto.hash([SPingCrypto.label('sPing engagement v1'), publicKey, nonce]);

  /// Code de vérification à 6 chiffres, identique des deux côtés si personne ne s'est
  /// glissé entre les appareils.
  static Future<String> code({
    required List<int> initiatorKey,
    required List<int> responderKey,
    required List<int> initiatorNonce,
    required List<int> responderNonce,
  }) async {
    final digest = await SPingCrypto.hash([
      SPingCrypto.label('sPing code v1'),
      initiatorKey,
      responderKey,
      initiatorNonce,
      responderNonce,
    ]);
    final value = ByteData.sublistView(digest).getUint32(0) % 1000000;
    final text = value.toString().padLeft(6, '0');
    return '${text.substring(0, 3)} ${text.substring(3)}';
  }
}

/// Clés d'une session : une par sens.
class SessionKeys {
  const SessionKeys({required this.send, required this.receive});

  final SecretKey send;
  final SecretKey receive;

  /// Dérive les clés de session. [initiator] : cet appareil est le PC.
  static Future<SessionKeys> derive({
    required bool initiator,
    required Identity identity,
    required List<int> peerPublicKey,
    required SimpleKeyPair ephemeral,
    required List<int> ephemeralPublic,
    required List<int> peerEphemeral,
    required List<int> initiatorNonce,
    required List<int> responderNonce,
  }) async {
    final staticSecret = await SPingCrypto.sharedSecret(identity.keyPair, peerPublicKey);
    final ephemeralSecret = await SPingCrypto.sharedSecret(ephemeral, peerEphemeral);
    final initiatorKey = initiator ? identity.publicKey : peerPublicKey;
    final responderKey = initiator ? peerPublicKey : identity.publicKey;
    final initiatorEph = initiator ? ephemeralPublic : peerEphemeral;
    final responderEph = initiator ? peerEphemeral : ephemeralPublic;
    final material = await SPingCrypto.hkdf(
      [...staticSecret, ...ephemeralSecret],
      salt: [...initiatorNonce, ...responderNonce],
      info: [
        ...SPingCrypto.label('sPing session v1'),
        ...initiatorKey,
        ...responderKey,
        ...initiatorEph,
        ...responderEph,
      ],
    );
    final toResponder = SecretKey(material.sublist(0, 32));
    final toInitiator = SecretKey(material.sublist(32, 64));
    return initiator
        ? SessionKeys(send: toResponder, receive: toInitiator)
        : SessionKeys(send: toInitiator, receive: toResponder);
  }
}

/// Chiffre et déchiffre les messages d'une session, dans l'ordre.
class SecureChannel {
  SecureChannel(this.keys);

  final SessionKeys keys;
  int _sent = 0;
  int _received = 0;

  static const _counterBytes = 8;
  static const _macBytes = 16;

  static Uint8List _nonce(int counter) {
    final nonce = Uint8List(12);
    ByteData.sublistView(nonce).setUint64(4, counter);
    return nonce;
  }

  /// Message chiffré : numéro (8 octets), texte chiffré, code d'authentification (16 octets).
  Future<Uint8List> seal(List<int> clear) async {
    final counter = _sent++;
    final box = await SPingCrypto.aes.encrypt(clear, secretKey: keys.send, nonce: _nonce(counter));
    final out = BytesBuilder(copy: false)
      ..add((ByteData(_counterBytes)..setUint64(0, counter)).buffer.asUint8List())
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.takeBytes();
  }

  /// Déchiffre le message suivant ; lève [CryptoFailure] s'il a été modifié, rejoué ou
  /// s'il n'arrive pas dans l'ordre.
  Future<Uint8List> open(Uint8List frame) async {
    if (frame.length < _counterBytes + _macBytes) throw const CryptoFailure('Message tronqué.');
    final counter = ByteData.sublistView(frame, 0, _counterBytes).getUint64(0);
    if (counter != _received) throw const CryptoFailure('Message hors séquence.');
    final box = SecretBox(
      frame.sublist(_counterBytes, frame.length - _macBytes),
      nonce: _nonce(counter),
      mac: Mac(frame.sublist(frame.length - _macBytes)),
    );
    try {
      final clear = await SPingCrypto.aes.decrypt(box, secretKey: keys.receive);
      _received++;
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const CryptoFailure('Message falsifié ou clé incorrecte.');
    }
  }
}

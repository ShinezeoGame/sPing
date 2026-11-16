import 'dart:convert';

/// Rôle d'un appareil sPing : le téléphone relaie ses notifications, le PC les reçoit.
enum DeviceRole {
  phone('telephone'),
  computer('ordinateur');

  const DeviceRole(this.code);

  /// Valeur échangée sur le réseau.
  final String code;

  static DeviceRole? parse(Object? code) => switch (code) {
    'telephone' => phone,
    'ordinateur' => computer,
    _ => null,
  };
}

/// Nettoie un nom reçu du réseau : sans caractère de contrôle, 60 caractères au plus.
String cleanName(String name) {
  final clean = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  return clean.length > 60 ? clean.substring(0, 60) : clean;
}

/// Ce qu'un téléphone annonce de lui-même sur le réseau local.
class Announce {
  const Announce({required this.id, required this.name, required this.port});

  /// Identifiant tiré au hasard à la première ouverture de l'application.
  final String id;
  final String name;

  /// Port sur lequel le téléphone attend les PC.
  final int port;

  Map<String, dynamic> toJson() => {'sping': 1, 'id': id, 'nom': name, 'port': port};

  /// Lit une annonce ; `null` si elle n'est pas valide.
  static Announce? fromJson(Object? json) {
    if (json is! Map || json['sping'] != 1) return null;
    final id = json['id'], name = json['nom'], port = json['port'];
    if (id is! String || !validId(id)) return null;
    if (name is! String || cleanName(name).isEmpty) return null;
    if (port is! int || port < 1 || port > 65535) return null;
    return Announce(id: id, name: cleanName(name), port: port);
  }
}

/// Un identifiant d'appareil acceptable : 4 à 64 caractères simples.
bool validId(String id) => RegExp(r'^[A-Za-z0-9_-]{4,64}$').hasMatch(id);

/// Un appareil avec lequel celui-ci est appairé : sa clé publique durable est la seule
/// preuve de son identité (l'identifiant et le nom ne sont que des étiquettes).
class PairedDevice {
  const PairedDevice({required this.id, required this.name, required this.publicKey, required this.pairedAt});

  final String id;
  final String name;

  /// Clé publique X25519 de l'appareil (32 octets).
  final List<int> publicKey;
  final DateTime pairedAt;

  PairedDevice copyWith({String? name}) =>
      PairedDevice(id: id, name: name ?? this.name, publicKey: publicKey, pairedAt: pairedAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': name,
    'cle': _b64(publicKey),
    'depuis': pairedAt.millisecondsSinceEpoch,
  };

  static PairedDevice? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['nom'], key = json['cle'], since = json['depuis'];
    if (id is! String || name is! String || key is! String) return null;
    final bytes = _unb64(key);
    if (bytes == null || bytes.length != 32) return null;
    return PairedDevice(
      id: id,
      name: name,
      publicKey: bytes,
      pairedAt: DateTime.fromMillisecondsSinceEpoch(since is int ? since : 0),
    );
  }
}

String _b64(List<int> bytes) => base64.encode(bytes);

List<int>? _unb64(String text) {
  try {
    return base64.decode(text);
  } on FormatException {
    return null;
  }
}

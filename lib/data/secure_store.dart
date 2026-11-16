import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Coffre des secrets : la clé privée de l'appareil et la liste des appareils appairés.
/// Ils ne sont jamais écrits dans les réglages ordinaires.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Stockage sécurisé du système : Keystore sur Android, chiffrement DPAPI du compte
/// Windows sur le PC.
class SystemSecretStore implements SecretStore {
  const SystemSecretStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Coffre en mémoire (tests).
class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? values]) : values = values ?? {};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Thème de l'interface : automatique (suit le réglage du système), clair ou sombre.
enum AppThemeMode { auto, light, dark }

/// Réglages ordinaires (rien de secret : la clé de l'appareil et les appairages sont dans
/// le coffre, voir `secure_store.dart`).
class Settings {
  const Settings({
    this.theme = AppThemeMode.auto,
    this.deviceId = '',
    this.deviceName = '',
    this.discreet = false,
    this.relay = true,
    this.desktopNotifications = true,
    this.keepInTray = true,
    this.manualAddress = '',
  });

  final AppThemeMode theme;

  /// Identifiant de cet appareil, tiré au hasard à la première ouverture.
  final String deviceId;

  /// Nom sous lequel l'autre appareil voit celui-ci.
  final String deviceName;

  /// PC : mode discret, le contenu des notifications est masqué.
  final bool discreet;

  /// Téléphone : relais des notifications activé.
  final bool relay;

  /// PC : une notification Windows pour chaque notification reçue.
  final bool desktopNotifications;

  /// PC : fermer la fenêtre garde sPing dans la zone de notification.
  final bool keepInTray;

  /// PC : adresse du téléphone saisie à la main (`192.168.1.20`), si la découverte
  /// automatique ne passe pas sur ce réseau.
  final String manualAddress;

  Settings copyWith({
    AppThemeMode? theme,
    String? deviceId,
    String? deviceName,
    bool? discreet,
    bool? relay,
    bool? desktopNotifications,
    bool? keepInTray,
    String? manualAddress,
  }) => Settings(
    theme: theme ?? this.theme,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    discreet: discreet ?? this.discreet,
    relay: relay ?? this.relay,
    desktopNotifications: desktopNotifications ?? this.desktopNotifications,
    keepInTray: keepInTray ?? this.keepInTray,
    manualAddress: manualAddress ?? this.manualAddress,
  );
}

/// Identifiant aléatoire (32 chiffres hexadécimaux).
String randomHex([int bytes = 16]) {
  final random = Random.secure();
  return [for (var i = 0; i < bytes; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

/// Lecture et écriture des réglages sur le disque.
class SettingsStore {
  Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('theme');
    return Settings(
      theme: AppThemeMode.values.firstWhere((mode) => mode.name == themeName, orElse: () => AppThemeMode.auto),
      deviceId: prefs.getString('deviceId') ?? '',
      deviceName: prefs.getString('deviceName') ?? '',
      discreet: prefs.getBool('discreet') ?? false,
      relay: prefs.getBool('relay') ?? true,
      desktopNotifications: prefs.getBool('desktopNotifications') ?? true,
      keepInTray: prefs.getBool('keepInTray') ?? true,
      manualAddress: prefs.getString('manualAddress') ?? '',
    );
  }

  Future<void> save(Settings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', s.theme.name);
    await prefs.setString('deviceId', s.deviceId);
    await prefs.setString('deviceName', s.deviceName);
    await prefs.setBool('discreet', s.discreet);
    await prefs.setBool('relay', s.relay);
    await prefs.setBool('desktopNotifications', s.desktopNotifications);
    await prefs.setBool('keepInTray', s.keepInTray);
    await prefs.setString('manualAddress', s.manualAddress);
  }
}

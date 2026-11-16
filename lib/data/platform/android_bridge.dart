import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../models/phone_notification.dart';

/// État des autorisations du téléphone.
class PhoneStatus {
  const PhoneStatus({this.access = false, this.listening = false, this.batteryUnrestricted = true});

  /// L'utilisateur a accordé « Accès aux notifications » à sPing.
  final bool access;

  /// Android a démarré le service d'écoute des notifications.
  final bool listening;

  /// sPing est exclu de l'optimisation de la batterie.
  final bool batteryUnrestricted;
}

/// Source des notifications du téléphone et exécution des réponses.
abstract class NotificationSource {
  /// Notifications publiées ou mises à jour.
  Stream<PhoneNotification> get posted;

  /// Clés des notifications retirées du téléphone.
  Stream<String> get removed;

  /// Changement d'état (accès accordé, service démarré ou arrêté).
  Stream<void> get changed;

  /// Notifications présentes en ce moment sur le téléphone.
  Future<List<PhoneNotification>> active();

  /// Répond à la notification [key] ; renvoie `null` si c'est fait, sinon la raison de l'échec.
  Future<String?> reply(String key, String text);

  Future<PhoneStatus> status();

  /// Nom donné au téléphone par son propriétaire (« Galaxy S25 »).
  Future<String?> deviceName();

  Future<void> openAccessSettings();
  Future<void> openBatterySettings();
  Future<void> openAppDetails();
}

/// Pont vers `android/.../SPingEngine.kt` (canal `sping/android`). Le service d'écoute des
/// notifications fait tourner ce code même quand l'écran de sPing est fermé.
class AndroidBridge implements NotificationSource {
  AndroidBridge() {
    if (Platform.isAndroid) _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('sping/android');

  final _posted = StreamController<PhoneNotification>.broadcast();
  final _removed = StreamController<String>.broadcast();
  final _changed = StreamController<void>.broadcast();

  @override
  Stream<PhoneNotification> get posted => _posted.stream;

  @override
  Stream<String> get removed => _removed.stream;

  @override
  Stream<void> get changed => _changed.stream;

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'notification':
        final notification = PhoneNotification.fromJson(_jsonMap(call.arguments));
        if (notification != null) _posted.add(notification);
      case 'retiree':
        if (call.arguments is String) _removed.add(call.arguments as String);
      case 'etat':
        _changed.add(null);
    }
    return null;
  }

  /// Le canal transmet des `Map<Object?, Object?>` et l'icône en octets bruts : on les
  /// remet au format JSON attendu par [PhoneNotification.fromJson].
  static Map<String, dynamic>? _jsonMap(Object? value) {
    if (value is! Map) return null;
    final map = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is String) map[entry.key as String] = entry.value;
    }
    final icon = map['icone'];
    if (icon is Uint8List) map['icone'] = base64.encode(icon);
    return map;
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on Object {
      return null;
    }
  }

  @override
  Future<List<PhoneNotification>> active() async {
    final list = await _invoke<List<Object?>>('actives');
    return [for (final item in list ?? const []) ?PhoneNotification.fromJson(_jsonMap(item))];
  }

  @override
  Future<String?> reply(String key, String text) async {
    if (!Platform.isAndroid) return 'Réponse possible seulement sur Android.';
    try {
      await _channel.invokeMethod<void>('repondre', {'cle': key, 'texte': text});
      return null;
    } on PlatformException catch (error) {
      return error.message ?? 'Réponse impossible.';
    } on Object catch (error) {
      return 'Réponse impossible : $error';
    }
  }

  @override
  Future<PhoneStatus> status() async {
    final map = await _invoke<Map<Object?, Object?>>('etat');
    if (map == null) return const PhoneStatus();
    return PhoneStatus(
      access: map['acces'] == true,
      listening: map['ecoute'] == true,
      batteryUnrestricted: map['batterieLibre'] != false,
    );
  }

  @override
  Future<String?> deviceName() => _invoke<String>('nomAppareil');

  @override
  Future<void> openAccessSettings() => _invoke<void>('ouvrirAcces');

  @override
  Future<void> openBatterySettings() => _invoke<void>('ouvrirBatterie');

  @override
  Future<void> openAppDetails() => _invoke<void>('ouvrirInfosAppli');
}

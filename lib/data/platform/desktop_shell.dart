import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../models/phone_notification.dart';

/// Ce que le PC fait en dehors de sa fenêtre : notifications Windows, icône de la zone de
/// notification, démarrage avec Windows.
abstract class DesktopShell {
  /// [onReply] : réponse écrite dans une notification Windows (clé, texte).
  /// [onToggleDiscreet] : « Mode discret » choisi dans le menu de l'icône.
  Future<void> start({
    required void Function(String key, String text) onReply,
    required void Function() onToggleDiscreet,
  });

  /// Affiche une notification Windows pour [notification].
  Future<void> show(PhoneNotification notification, {required bool discreet});

  /// Coche ou décoche « Mode discret » dans le menu de l'icône.
  Future<void> setDiscreet(bool discreet);

  /// Fermer la fenêtre la cache (sPing reste dans la zone de notification) ou quitte.
  Future<void> setKeepInTray(bool keep);

  Future<bool> launchAtStartup();
  Future<void> setLaunchAtStartup(bool enabled);
}

/// Sans effet (téléphone, tests).
class NoDesktopShell implements DesktopShell {
  const NoDesktopShell();

  @override
  Future<void> start({
    required void Function(String key, String text) onReply,
    required void Function() onToggleDiscreet,
  }) async {}

  @override
  Future<void> show(PhoneNotification notification, {required bool discreet}) async {}

  @override
  Future<void> setDiscreet(bool discreet) async {}

  @override
  Future<void> setKeepInTray(bool keep) async {}

  @override
  Future<bool> launchAtStartup() async => false;

  @override
  Future<void> setLaunchAtStartup(bool enabled) async {}
}

/// Texte d'une notification Windows : le mode discret ne montre que l'expéditeur.
({String title, String body}) toastText(PhoneNotification n, {required bool discreet}) {
  if (discreet) return (title: n.appName, body: n.discreetSummary);
  final title = n.conversation != null && n.conversation != n.from ? '${n.from} · ${n.conversation}' : n.from;
  return (title: title.isEmpty ? n.appName : title, body: n.text);
}

/// Windows : notifications par `flutter_local_notifications`, le reste par le runner
/// (`windows/runner/flutter_window.cpp`, canal `sping/fenetre`).
class WindowsShell implements DesktopShell {
  static const _channel = MethodChannel('sping/fenetre');
  static const _replyInput = 'reponse';
  static const _replyAction = 'repondre';

  final _plugin = FlutterLocalNotificationsPlugin();
  final _ids = <String, int>{};
  bool _toasts = false;

  @override
  Future<void> start({
    required void Function(String key, String text) onReply,
    required void Function() onToggleDiscreet,
  }) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'basculerDiscret') onToggleDiscreet();
      return null;
    });
    try {
      final icon = File(
        '${File(Platform.resolvedExecutable).parent.path}\\data\\flutter_assets\\assets\\branding\\logo.png',
      );
      _toasts =
          await _plugin.initialize(
            settings: InitializationSettings(
              windows: WindowsInitializationSettings(
                appName: 'sPing',
                appUserModelId: 'ShinezeoGame.sPing',
                guid: 'b6a3c1e2-4f57-4d8a-9e21-7c3f0a5d9b64',
                iconPath: icon.existsSync() ? icon.path : null,
              ),
            ),
            onDidReceiveNotificationResponse: (response) {
              final key = response.payload;
              if (key == null || key.isEmpty) return;
              if (response.actionId == _replyAction) {
                final text = response.data[_replyInput];
                if (text is String && text.trim().isNotEmpty) onReply(key, text.trim());
              } else {
                unawaited(_invoke('afficher'));
              }
            },
          ) ??
          false;
    } on Object {
      _toasts = false;
    }
  }

  @override
  Future<void> show(PhoneNotification notification, {required bool discreet}) async {
    if (!_toasts) return;
    final text = toastText(notification, discreet: discreet);
    // Une notification mise à jour remplace la précédente plutôt que de s'empiler.
    final id = _ids.putIfAbsent(notification.key, () => _ids.length + 1);
    try {
      await _plugin.show(
        id: id,
        title: text.title,
        body: text.body,
        payload: notification.key,
        notificationDetails: NotificationDetails(
          windows: WindowsNotificationDetails(
            subtitle: discreet ? null : notification.appName,
            timestamp: notification.time,
            inputs: notification.canReply
                ? const [WindowsTextInput(id: _replyInput, placeHolderContent: 'Répondre…')]
                : const [],
            actions: notification.canReply
                ? const [WindowsAction(content: 'Envoyer', arguments: _replyAction, inputId: _replyInput)]
                : const [],
          ),
        ),
      );
    } on Object {
      // Les notifications Windows peuvent être désactivées : la fenêtre reste à jour.
    }
  }

  Future<Object?> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> setDiscreet(bool discreet) => _invoke('discret', discreet);

  @override
  Future<void> setKeepInTray(bool keep) => _invoke('garderEnZone', keep);

  @override
  Future<bool> launchAtStartup() async => await _invoke('demarrageAuto') == true;

  @override
  Future<void> setLaunchAtStartup(bool enabled) => _invoke('demarrageAuto', enabled);
}

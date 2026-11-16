import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sping/data/net/link.dart';
import 'package:sping/data/platform/android_bridge.dart';
import 'package:sping/data/platform/desktop_shell.dart';
import 'package:sping/data/secure_store.dart';
import 'package:sping/data/settings.dart';
import 'package:sping/models/device.dart';
import 'package:sping/models/phone_notification.dart';
import 'package:sping/state/ping_controller.dart';

/// Réglages gardés en mémoire : chaque appareil simulé a les siens.
class MemoryStore extends SettingsStore {
  MemoryStore(this.value);

  Settings value;

  @override
  Future<Settings> load() async => value;

  @override
  Future<void> save(Settings s) async => value = s;
}

/// Les notifications d'un téléphone simulé.
class FakeSource implements NotificationSource {
  final _posted = StreamController<PhoneNotification>.broadcast();
  final _removed = StreamController<String>.broadcast();
  final _changed = StreamController<void>.broadcast();

  /// Notifications présentes sur le téléphone.
  final List<PhoneNotification> current = [];

  /// Réponses reçues : (clé, texte).
  final List<(String, String)> replies = [];

  /// Erreur renvoyée par la prochaine réponse (`null` : réussite).
  String? replyError;

  PhoneStatus statusValue = const PhoneStatus(access: true, listening: true);

  void post(PhoneNotification notification) {
    current
      ..removeWhere((n) => n.key == notification.key)
      ..add(notification);
    _posted.add(notification);
  }

  void remove(String key) {
    current.removeWhere((n) => n.key == key);
    _removed.add(key);
  }

  @override
  Stream<PhoneNotification> get posted => _posted.stream;

  @override
  Stream<String> get removed => _removed.stream;

  @override
  Stream<void> get changed => _changed.stream;

  @override
  Future<List<PhoneNotification>> active() async => [...current];

  @override
  Future<String?> reply(String key, String text) async {
    replies.add((key, text));
    return replyError;
  }

  @override
  Future<PhoneStatus> status() async => statusValue;

  @override
  Future<String?> deviceName() async => null;

  @override
  Future<void> openAccessSettings() async {}

  @override
  Future<void> openBatterySettings() async {}

  @override
  Future<void> openAppDetails() async {}
}

/// Les notifications Windows d'un PC simulé.
class FakeShell extends NoDesktopShell {
  final List<({String title, String body, bool canReply})> shown = [];
  void Function(String key, String text)? replyHandler;

  @override
  Future<void> start({
    required void Function(String key, String text) onReply,
    required void Function() onToggleDiscreet,
  }) async {
    replyHandler = onReply;
  }

  @override
  Future<void> show(PhoneNotification notification, {required bool discreet}) async {
    final text = toastText(notification, discreet: discreet);
    shown.add((title: text.title, body: text.body, canReply: notification.canReply));
  }
}

/// Attend qu'une condition devienne vraie (les échanges réseau sont asynchrones).
Future<void> until(bool Function() condition, {String? reason, Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition jamais remplie${reason == null ? '' : ' : $reason'}');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Un port libre sur cette machine (TCP et UDP).
Future<int> freePort() async {
  while (true) {
    final socket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final port = socket.port;
    await socket.close();
    try {
      final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      udp.close();
      return port;
    } on SocketException {
      continue;
    }
  }
}

const fastTimings = LinkTimings(
  handshake: Duration(seconds: 3),
  decision: Duration(seconds: 5),
  ping: Duration(milliseconds: 300),
  silence: Duration(seconds: 2),
);

/// Un appareil sPing simulé.
class TestDevice {
  TestDevice(this.controller, this.store, this.secrets, {this.source, this.shell});

  final PingController controller;
  final MemoryStore store;
  final MemorySecretStore secrets;
  final FakeSource? source;
  final FakeShell? shell;

  /// Téléphone à l'écoute sur [port], qui s'annonce au PC écoutant sur [announceTo].
  static Future<TestDevice> phone(
    String name, {
    required int port,
    required int announceTo,
    MemoryStore? store,
    MemorySecretStore? secrets,
    FakeSource? source,
  }) async {
    store ??= MemoryStore(Settings(deviceId: 'tel-${name.replaceAll(' ', '')}', deviceName: name));
    secrets ??= MemorySecretStore();
    source ??= FakeSource();
    final controller = PingController(
      role: DeviceRole.phone,
      store: store,
      secrets: secrets,
      source: source,
      port: port,
      announceTargets: [(InternetAddress.loopbackIPv4, announceTo)],
      timings: fastTimings,
      announceFast: const Duration(milliseconds: 100),
      announceSlow: const Duration(milliseconds: 400),
      pairingWindow: const Duration(seconds: 20),
    );
    await controller.loadSettings();
    await controller.start();
    return TestDevice(controller, store, secrets, source: source);
  }

  /// PC qui écoute les annonces sur [port].
  static Future<TestDevice> computer(
    String name, {
    required int port,
    MemoryStore? store,
    MemorySecretStore? secrets,
  }) async {
    store ??= MemoryStore(Settings(deviceId: 'pc-${name.replaceAll(' ', '')}', deviceName: name));
    secrets ??= MemorySecretStore();
    final shell = FakeShell();
    final controller = PingController(
      role: DeviceRole.computer,
      store: store,
      secrets: secrets,
      shell: shell,
      port: port,
      listenMulticast: false,
      timings: fastTimings,
      reconnectDelay: const Duration(milliseconds: 200),
      phoneTimeout: const Duration(seconds: 3),
      replyTimeout: const Duration(seconds: 3),
    );
    await controller.loadSettings();
    await controller.start();
    return TestDevice(controller, store, secrets, shell: shell);
  }

  VisiblePhone visible(String name) => controller.visiblePhones.firstWhere((p) => p.name == name);

  Future<void> stop() => controller.shutdown();
}

PhoneNotification message({
  String key = '0|com.whatsapp|1|null|10123',
  String from = 'Marie',
  String text = 'On se retrouve à 19 h ?',
  bool canReply = true,
  String? conversation,
}) => PhoneNotification(
  key: key,
  packageName: 'com.whatsapp',
  appName: 'WhatsApp',
  title: from,
  text: text,
  time: DateTime(2026, 11, 16, 18, 42),
  sender: from,
  conversation: conversation,
  isMessage: true,
  canReply: canReply,
);

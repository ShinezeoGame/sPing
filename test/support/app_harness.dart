import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sping/app.dart';
import 'package:sping/data/net/discovery.dart';
import 'package:sping/data/secure_store.dart';
import 'package:sping/data/settings.dart';
import 'package:sping/models/device.dart';
import 'package:sping/models/phone_notification.dart';
import 'package:sping/state/ping_controller.dart';

import 'harness.dart';

/// Charge les vraies polices pour que les mesures de texte correspondent à l'application.
Future<void> loadFonts() async {
  final outfit = FontLoader('Outfit');
  for (final weight in ['300Light', '400Regular', '500Medium', '600SemiBold']) {
    final bytes = File('assets/fonts/Outfit_$weight.ttf').readAsBytesSync();
    outfit.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await outfit.load();

  // Les icônes Material viennent du SDK Flutter ; sans elles, des carrés les remplacent.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!icons.existsSync()) return;
  final material = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
  await material.load();
}

/// Clé de la zone capturée pour la documentation.
const captureKey = ValueKey('capture');

final galaxy = PairedDevice(
  id: 'tel-galaxy',
  name: 'Galaxy S25',
  publicKey: List.filled(32, 1),
  pairedAt: DateTime(2026, 11, 16),
);
final officePc = PairedDevice(
  id: 'pc-bureau',
  name: 'PC du bureau',
  publicKey: List.filled(32, 2),
  pairedAt: DateTime(2026, 11, 16),
);

final galaxySighting = Sighting(
  const Announce(id: 'tel-galaxy', name: 'Galaxy S25', port: 47874),
  InternetAddress('192.168.1.20'),
);

/// Appairage affiché, sans réseau.
class FakePairing implements PairingView {
  FakePairing(this.peer, {this.answered = false, this.remoteAccepted = false});

  @override
  final PairedDevice peer;
  @override
  String get code => '482 913';
  @override
  final bool answered;
  @override
  final bool remoteAccepted;
}

DateTime _today(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

/// Quelques notifications typiques reçues sur le PC.
List<NotificationEntry> sampleEntries() {
  final whatsapp = NotificationEntry(
    'tel-galaxy',
    PhoneNotification(
      key: 'wa-1',
      packageName: 'com.whatsapp',
      appName: 'WhatsApp',
      title: 'Marie',
      text: 'On se retrouve à 19 h devant le cinéma ? J\'ai pris les places pour la séance de 19 h 30.',
      time: _today(18, 42),
      sender: 'Marie',
      isMessage: true,
      canReply: true,
    ),
  )..replies.add(ReplyItem('r1', 'Parfait, à tout à l\'heure !')..state = ReplyState.sent);
  final sms = NotificationEntry(
    'tel-galaxy',
    PhoneNotification(
      key: 'sms-1',
      packageName: 'com.samsung.android.messaging',
      appName: 'Messages',
      title: 'Paul',
      text: 'Bien arrivé, merci pour tout',
      time: _today(17, 5),
      sender: 'Paul',
      conversation: 'Famille',
      isMessage: true,
      canReply: true,
    ),
  );
  final mail = NotificationEntry(
    'tel-galaxy',
    PhoneNotification(
      key: 'gm-1',
      packageName: 'com.google.android.gm',
      appName: 'Gmail',
      title: 'La Poste',
      text: 'Votre colis sera livré demain entre 9 h et 13 h.',
      time: _today(9, 12),
    ),
  )..removed = true;
  return [whatsapp, sms, mail];
}

/// Affiche l'application dans une fenêtre de la taille donnée, sans réseau : l'état est
/// imposé avec `debugSetState`.
Future<PingController> pumpApp(
  WidgetTester tester,
  Size size, {
  DeviceRole role = DeviceRole.computer,
  Settings? settings,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = PingController(
    role: role,
    store: MemoryStore(
      settings ??
          Settings(
            deviceId: role == DeviceRole.phone ? 'tel-galaxy' : 'pc-bureau',
            deviceName: role == DeviceRole.phone ? 'Galaxy S25' : 'PC du bureau',
          ),
    ),
    secrets: MemorySecretStore(),
    source: FakeSource(),
    shell: FakeShell(),
  );
  await tester.runAsync(controller.loadSettings);
  controller.debugSetState(ready: true, addresses: const ['192.168.1.20']);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: SPingApp(controller: controller),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return controller;
}

Future<void> tearDownApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

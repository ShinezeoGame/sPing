// Captures d'écran de la documentation (`docs/captures`). Elles ne sont produites que sur
// demande, pour ne pas réécrire des images à chaque exécution des tests :
//
//     SPING_CAPTURES=1 flutter test test/captures_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sping/data/platform/android_bridge.dart';
import 'package:sping/data/settings.dart';
import 'package:sping/models/device.dart';

import 'support/app_harness.dart';

const _window = Size(420, 760);

Future<void> capture(WidgetTester tester, String name) async {
  // Le logo de l'en-tête se charge en différé : on l'attend avant de capturer.
  final element = tester.element(find.byKey(captureKey));
  await tester.runAsync(() => precacheImage(const AssetImage('assets/branding/logo.png'), element));
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/captures/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  final enabled = Platform.environment.containsKey('SPING_CAPTURES');
  setUpAll(loadFonts);

  for (final dark in [false, true]) {
    final suffix = dark ? '-sombre' : '';
    final theme = dark ? AppThemeMode.dark : AppThemeMode.light;

    testWidgets('PC : notifications$suffix', skip: !enabled, (tester) async {
      final controller = await pumpApp(
        tester,
        _window,
        settings: Settings(deviceId: 'pc-bureau', deviceName: 'PC du bureau', theme: theme),
      );
      controller.debugSetState(paired: [galaxy], connected: {galaxy.id}, entries: sampleEntries());
      await tester.pump(const Duration(milliseconds: 300));
      await capture(tester, 'pc-notifications$suffix');
      await tearDownApp(tester);
    });

    testWidgets('PC : appairage$suffix', skip: !enabled, (tester) async {
      final controller = await pumpApp(
        tester,
        _window,
        settings: Settings(deviceId: 'pc-bureau', deviceName: 'PC du bureau', theme: theme),
      );
      controller.debugSetState(visible: [galaxySighting], pairing: FakePairing(galaxy));
      await tester.pump(const Duration(milliseconds: 300));
      await capture(tester, 'pc-appairage$suffix');
      await tearDownApp(tester);
    });

    testWidgets('téléphone$suffix', skip: !enabled, (tester) async {
      final controller = await pumpApp(
        tester,
        _window,
        role: DeviceRole.phone,
        settings: Settings(deviceId: 'tel-galaxy', deviceName: 'Galaxy S25', theme: theme),
      );
      controller.debugSetState(
        status: const PhoneStatus(access: true, listening: true),
        paired: [officePc],
        connected: {officePc.id},
        relayed: 128,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await capture(tester, 'telephone$suffix');
      await tearDownApp(tester);
    });
  }

  testWidgets('PC : mode discret', skip: !enabled, (tester) async {
    final controller = await pumpApp(
      tester,
      _window,
      settings: const Settings(deviceId: 'pc-bureau', deviceName: 'PC du bureau', discreet: true),
    );
    controller.debugSetState(paired: [galaxy], connected: {galaxy.id}, entries: sampleEntries());
    await tester.pump(const Duration(milliseconds: 300));
    await capture(tester, 'pc-discret');
    await tearDownApp(tester);
  });

  testWidgets('téléphone : premier lancement', skip: !enabled, (tester) async {
    await pumpApp(tester, _window, role: DeviceRole.phone);
    await capture(tester, 'telephone-autorisation');
    await tearDownApp(tester);
  });
}

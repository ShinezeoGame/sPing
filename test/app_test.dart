import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sping/data/platform/android_bridge.dart';
import 'package:sping/data/settings.dart';
import 'package:sping/models/device.dart';
import 'package:sping/ui/widgets/ping_widgets.dart';

import 'support/app_harness.dart';

void main() {
  setUpAll(loadFonts);

  const sizes = {
    'fenêtre minimale 360×480': Size(360, 480),
    'fenêtre par défaut 420×760': Size(420, 760),
    'fenêtre agrandie 1100×700': Size(1100, 700),
  };

  /// Fait défiler la page jusqu'en bas : tout le contenu est construit et mesuré.
  Future<void> scrollThrough(WidgetTester tester) async {
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> show(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 120, scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Settings longNames(DeviceRole role, bool dark) => Settings(
    deviceId: role == DeviceRole.phone ? 'tel-galaxy' : 'pc-bureau',
    deviceName: role == DeviceRole.phone
        ? 'Galaxy S25 Ultra de Marie-Christine'
        : 'PC du bureau de Marie-Christine au premier étage',
    theme: dark ? AppThemeMode.dark : AppThemeMode.light,
  );

  for (final MapEntry(key: label, value: size) in sizes.entries) {
    group(label, () {
      for (final dark in [false, true]) {
        final theme = dark ? 'sombre' : 'clair';

        testWidgets('PC : appairage puis notifications ($theme)', (tester) async {
          final controller = await pumpApp(tester, size, settings: longNames(DeviceRole.computer, dark));
          expect(find.text('Aucun téléphone pour l\'instant'), findsOneWidget);
          expect(tester.takeException(), isNull);

          controller.debugSetState(visible: [galaxySighting]);
          await tester.pump();
          expect(find.text('Galaxy S25'), findsOneWidget);
          await scrollThrough(tester);

          controller.debugSetState(pairing: FakePairing(galaxy));
          await tester.pump();
          await show(tester, find.text('482 913'));
          expect(find.text('Le code est identique'), findsOneWidget);
          expect(tester.takeException(), isNull);
          controller.debugSetState(pairing: FakePairing(galaxy, answered: true));
          await tester.pump();
          expect(find.textContaining('Acceptez-le aussi sur le téléphone'), findsOneWidget);

          controller.debugSetState(
            clearPairing: true,
            paired: [galaxy],
            connected: {galaxy.id},
            entries: sampleEntries(),
          );
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
          await tester.pump();
          await show(tester, find.text('Galaxy S25'));
          expect(find.text('Connecté'), findsOneWidget);
          expect(find.textContaining('On se retrouve à 19 h'), findsOneWidget);
          expect(find.text('Vous : Parfait, à tout à l\'heure !'), findsOneWidget);
          await show(tester, find.text('Lue sur le téléphone'));
          expect(find.text('Lue sur le téléphone'), findsOneWidget);
          await scrollThrough(tester);

          // Répondre depuis la fenêtre.
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
          await tester.pump();
          await show(tester, find.text('Répondre').first);
          await tester.tap(find.text('Répondre').first);
          await tester.pump();
          expect(find.byTooltip('Envoyer la réponse'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Mode discret : plus aucun contenu à l'écran.
          await controller.setDiscreet(true);
          await tester.pump();
          expect(find.textContaining('On se retrouve à 19 h'), findsNothing);
          expect(find.text('Nouveau message de Marie'), findsOneWidget);
          expect(find.text('Vous avez répondu'), findsOneWidget);
          expect(find.textContaining('Parfait'), findsNothing);
          await scrollThrough(tester);

          // Téléphone injoignable.
          controller.debugSetState(
            connected: {},
            linkErrors: {galaxy.id: 'Ce téléphone ne reconnaît plus ce PC : appairez-les de nouveau.'},
          );
          await tester.pump();
          await scrollThrough(tester);
          await tearDownApp(tester);
        });

        testWidgets('téléphone : autorisations, appairage, relais ($theme)', (tester) async {
          final controller = await pumpApp(
            tester,
            size,
            role: DeviceRole.phone,
            settings: longNames(DeviceRole.phone, dark),
          );
          expect(find.text('Autorisez sPing à lire les notifications'), findsOneWidget);
          expect(find.text('Aucun PC appairé'), findsOneWidget);
          await scrollThrough(tester);

          controller.debugSetState(
            status: const PhoneStatus(access: true, listening: true, batteryUnrestricted: false),
          );
          await tester.pump();
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
          await tester.pump();
          expect(find.text('Laissez sPing travailler en veille'), findsOneWidget);

          controller.debugSetState(pairingOpen: true);
          await tester.pump();
          expect(find.text('En attente du PC'), findsOneWidget);
          expect(find.textContaining('192.168.1.20'), findsOneWidget);
          await scrollThrough(tester);

          controller.debugSetState(pairing: FakePairing(officePc, remoteAccepted: true));
          await tester.pump();
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
          await tester.pump();
          expect(find.text('482 913'), findsOneWidget);
          expect(find.text('Le PC a déjà accepté.'), findsOneWidget);
          await scrollThrough(tester);

          controller.debugSetState(
            clearPairing: true,
            pairingOpen: false,
            status: const PhoneStatus(access: true, listening: true),
            paired: [officePc],
            connected: {officePc.id},
            relayed: 128,
          );
          await tester.pump();
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
          await tester.pump();
          expect(find.text('Connecté : les notifications y arrivent'), findsOneWidget);
          await show(tester, find.text('128 relayées depuis le démarrage'));
          await scrollThrough(tester);
          await tearDownApp(tester);
        });

        for (final role in DeviceRole.values) {
          testWidgets('réglages, ${role.code} ($theme)', (tester) async {
            final controller = await pumpApp(tester, size, role: role, settings: longNames(role, dark));
            controller.debugSetState(paired: [role == DeviceRole.phone ? officePc : galaxy]);
            await tester.pump();
            await tester.tap(find.byTooltip('Réglages'));
            await tester.pumpAndSettle();
            expect(find.text('Réglages'), findsOneWidget);
            await scrollThrough(tester);
            await show(tester, find.text('Oublier'));
            await tester.tap(find.text('Oublier'));
            await tester.pumpAndSettle();
            expect(find.textContaining('Oublier « '), findsOneWidget);
            await tester.tap(find.text('Annuler'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tearDownApp(tester);
          });
        }
      }
    });
  }

  test('heure des notifications', () {
    final now = DateTime(2026, 11, 16, 20);
    expect(formatTime(DateTime(2026, 11, 16, 8, 5), now: now), '08:05');
    expect(formatTime(DateTime(2026, 11, 15, 18, 42), now: now), 'hier, 18:42');
    expect(formatTime(DateTime(2026, 11, 2, 18, 42), now: now), '02/11, 18:42');
  });
}

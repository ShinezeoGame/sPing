import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sping/data/crypto/crypto.dart';
import 'package:sping/data/net/link.dart';
import 'package:sping/data/net/protocol.dart';
import 'package:sping/data/platform/desktop_shell.dart';
import 'package:sping/models/device.dart';
import 'package:sping/models/phone_notification.dart';
import 'package:sping/state/ping_controller.dart';

import 'support/harness.dart';

/// Appaire le téléphone et le PC comme le ferait l'utilisateur.
Future<void> pair(TestDevice phone, TestDevice pc) async {
  phone.controller.openPairing();
  await until(() => pc.controller.visiblePhones.isNotEmpty, reason: 'le PC voit le téléphone');
  final target = pc.controller.visiblePhones.first;
  final pairing = pc.controller.pairWith(target.address, target.port, name: target.name);
  await until(() => phone.controller.pairing != null && pc.controller.pairing != null, reason: 'codes affichés');
  expect(phone.controller.pairing!.code, pc.controller.pairing!.code, reason: 'le même code des deux côtés');
  expect(phone.controller.pairing!.code, matches(RegExp(r'^\d{3} \d{3}$')));
  phone.controller.decidePairing(true);
  pc.controller.decidePairing(true);
  await pairing;
  await until(() => phone.controller.connected(pc.store.value.deviceId), reason: 'liaison établie');
  await until(() => pc.controller.connected(phone.store.value.deviceId), reason: 'liaison établie côté PC');
}

void main() {
  late int phonePort, pcPort;
  final devices = <TestDevice>[];

  Future<TestDevice> phone(String name) async {
    final d = await TestDevice.phone(name, port: phonePort, announceTo: pcPort);
    devices.add(d);
    return d;
  }

  Future<TestDevice> computer(String name) async {
    final d = await TestDevice.computer(name, port: pcPort);
    devices.add(d);
    return d;
  }

  setUp(() async {
    phonePort = await freePort();
    pcPort = await freePort();
  });

  tearDown(() async {
    for (final d in devices) {
      await d.stop();
    }
    devices.clear();
  });

  group('Chiffrement', () {
    test('un message modifié, rejoué ou déplacé est refusé', () async {
      final a = await Identity.generate(), b = await Identity.generate();
      final ea = await SPingCrypto.x25519.newKeyPair(), eb = await SPingCrypto.x25519.newKeyPair();
      final pa = (await ea.extractPublicKey()).bytes, pb = (await eb.extractPublicKey()).bytes;
      final na = SPingCrypto.randomBytes(16), nb = SPingCrypto.randomBytes(16);
      final ka = await SessionKeys.derive(
        initiator: true,
        identity: a,
        peerPublicKey: b.publicKey,
        ephemeral: ea,
        ephemeralPublic: pa,
        peerEphemeral: pb,
        initiatorNonce: na,
        responderNonce: nb,
      );
      final kb = await SessionKeys.derive(
        initiator: false,
        identity: b,
        peerPublicKey: a.publicKey,
        ephemeral: eb,
        ephemeralPublic: pb,
        peerEphemeral: pa,
        initiatorNonce: na,
        responderNonce: nb,
      );
      final sender = SecureChannel(ka), receiver = SecureChannel(kb);
      final first = await sender.seal(utf8.encode('bonjour'));
      final second = await sender.seal(utf8.encode('suite'));
      expect(utf8.decode(await receiver.open(first)), 'bonjour');

      // Rejeu du premier message.
      await expectLater(receiver.open(first), throwsA(isA<CryptoFailure>()));
      // Message modifié.
      final tampered = Uint8List.fromList(second)..[10] ^= 1;
      await expectLater(receiver.open(tampered), throwsA(isA<CryptoFailure>()));
      expect(utf8.decode(await receiver.open(second)), 'suite');

      // Le texte chiffré ne contient pas le texte clair.
      expect(utf8.decode(first, allowMalformed: true), isNot(contains('bonjour')));
      // Un message renvoyé à son expéditeur (clé de l'autre sens) est refusé.
      final back = SecureChannel(ka);
      await expectLater(back.open(await SecureChannel(ka).seal([1, 2, 3])), throwsA(isA<CryptoFailure>()));
    });

    test('le code d\'appairage change si une seule clé change', () async {
      final a = SPingCrypto.randomBytes(32), b = SPingCrypto.randomBytes(32), c = SPingCrypto.randomBytes(32);
      final n1 = SPingCrypto.randomBytes(16), n2 = SPingCrypto.randomBytes(16);
      final code = await Pairing.code(initiatorKey: a, responderKey: b, initiatorNonce: n1, responderNonce: n2);
      final same = await Pairing.code(initiatorKey: a, responderKey: b, initiatorNonce: n1, responderNonce: n2);
      final other = await Pairing.code(initiatorKey: c, responderKey: b, initiatorNonce: n1, responderNonce: n2);
      expect(code, same);
      expect(code, isNot(other));
    });

    test('l\'identité est gardée dans le coffre et retrouvée au redémarrage', () async {
      final d = await phone('Galaxy S25');
      final seed = d.secrets.values['identite'];
      expect(seed, isNotNull);
      expect(d.store.value.deviceId, isNot(contains(seed!)));
      final again = Identity.fromSeed(base64.decode(seed));
      expect((await again).publicKey, hasLength(32));
    });
  });

  group('Appairage', () {
    test('les deux appareils affichent le même code et s\'appairent', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      expect(tel.controller.paired.single.name, 'PC du bureau');
      expect(pc.controller.paired.single.name, 'Galaxy S25');
      expect(pc.controller.paired.single.publicKey, hasLength(32));
      // Appairages conservés dans le coffre, pas dans les réglages ordinaires.
      expect(pc.secrets.values['appairages'], contains('Galaxy S25'));
    });

    test('un refus sur le téléphone n\'appaire personne', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      tel.controller.openPairing();
      await until(() => pc.controller.visiblePhones.isNotEmpty);
      final target = pc.controller.visiblePhones.first;
      final pairing = pc.controller.pairWith(target.address, target.port);
      await until(() => tel.controller.pairing != null);
      pc.controller.decidePairing(true);
      tel.controller.decidePairing(false);
      await pairing;
      expect(tel.controller.paired, isEmpty);
      expect(pc.controller.paired, isEmpty);
      expect(pc.controller.notice!.error, isTrue);
    });

    test('le téléphone refuse l\'appairage tant qu\'on ne l\'a pas ouvert', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await until(() => pc.controller.visiblePhones.isNotEmpty);
      final target = pc.controller.visiblePhones.first;
      await pc.controller.pairWith(target.address, target.port);
      expect(pc.controller.notice!.message, contains('n\'attend pas'));
      expect(tel.controller.pairing, isNull);
      expect(tel.controller.paired, isEmpty);
    });

    test('appairage par adresse saisie à la main', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      tel.controller.openPairing();
      final pairing = pc.controller.pairWithAddress('127.0.0.1:$phonePort');
      await until(() => tel.controller.pairing != null && pc.controller.pairing != null);
      tel.controller.decidePairing(true);
      pc.controller.decidePairing(true);
      await pairing;
      expect(pc.controller.settings.manualAddress, '127.0.0.1:$phonePort');
      await until(() => pc.controller.connected(tel.store.value.deviceId), reason: 'connexion par l\'adresse');
    });
  });

  group('Sécurité', () {
    test('un PC non appairé qui reprend l\'identifiant d\'un PC appairé n\'obtient rien', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      final phoneDevice = pc.controller.paired.single;
      // Même identifiant, même nom, mais pas la clé privée du vrai PC.
      final impostor = LocalDevice(
        id: pc.store.value.deviceId,
        name: 'PC du bureau',
        identity: await Identity.generate(),
        role: DeviceRole.computer,
      );
      await expectLater(
        Link.connect(
          address: InternetAddress.loopbackIPv4,
          port: phonePort,
          self: impostor,
          phone: phoneDevice,
          timings: fastTimings,
        ),
        throwsA(isA<LinkClosed>()),
      );
      // Le vrai PC est toujours le seul connecté.
      expect(tel.controller.connectedCount, 1);
    });

    test('un appareil inconnu est refusé avant tout échange chiffré', () async {
      await phone('Galaxy S25');
      final stranger = LocalDevice(
        id: 'inconnu-1234',
        name: 'Inconnu',
        identity: await Identity.generate(),
        role: DeviceRole.computer,
      );
      final fakePhone = PairedDevice(
        id: 'tel-GalaxyS25',
        name: 'Galaxy S25',
        publicKey: (await Identity.generate()).publicKey,
        pairedAt: DateTime.now(),
      );
      await expectLater(
        Link.connect(
          address: InternetAddress.loopbackIPv4,
          port: phonePort,
          self: stranger,
          phone: fakePhone,
          timings: fastTimings,
        ),
        throwsA(isA<LinkClosed>()),
      );
    });

    test('un faux téléphone (mauvaise clé) est démasqué par le PC', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      final realPhone = pc.controller.paired.single;
      // Un téléphone qui prétend être le vrai, avec sa propre clé.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final fake = LocalDevice(
        id: realPhone.id,
        name: realPhone.name,
        identity: await Identity.generate(),
        role: DeviceRole.phone,
      );
      server.listen((socket) {
        Link.accept(
          socket,
          self: fake,
          timings: fastTimings,
          findPeer: (id) => PairedDevice(
            id: id,
            name: 'PC',
            publicKey: pc.controller.paired.single.publicKey,
            pairedAt: DateTime.now(),
          ),
          pairingRefusal: () => Refusal.pairingClosed,
        ).catchError((Object _) => Object());
      });
      final pcIdentity = Identity.fromSeed(base64.decode(pc.secrets.values['identite']!));
      await expectLater(
        Link.connect(
          address: InternetAddress.loopbackIPv4,
          port: server.port,
          self: LocalDevice(
            id: pc.store.value.deviceId,
            name: 'PC',
            identity: await pcIdentity,
            role: DeviceRole.computer,
          ),
          phone: realPhone,
          timings: fastTimings,
        ),
        throwsA(isA<LinkClosed>()),
      );
      await server.close();
    });

    test('un message trop grand coupe la connexion', () async {
      await phone('Galaxy S25');
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, phonePort);
      final header = ByteData(4)..setUint32(0, 10 * 1024 * 1024);
      socket.add(header.buffer.asUint8List());
      await socket.flush();
      await expectLater(socket.drain<void>().timeout(const Duration(seconds: 5)), completes);
      socket.destroy();
    });
  });

  group('Relais', () {
    test('une notification du téléphone arrive sur le PC et s\'affiche dans Windows', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      tel.source!.post(message());
      await until(() => pc.controller.entries.isNotEmpty);
      final entry = pc.controller.entries.single;
      expect(entry.notification.from, 'Marie');
      expect(entry.notification.text, 'On se retrouve à 19 h ?');
      expect(entry.canReply, isTrue);
      await until(() => pc.shell!.shown.isNotEmpty);
      expect(pc.shell!.shown.single.title, 'Marie');
      expect(pc.shell!.shown.single.body, 'On se retrouve à 19 h ?');
      expect(pc.shell!.shown.single.canReply, isTrue);
      expect(tel.controller.relayedCount, 1);

      // Mise à jour sans changement : pas de deuxième notification Windows.
      tel.source!.post(message());
      tel.source!.post(message(key: 'autre', from: 'Paul', text: 'Bien arrivé'));
      await until(() => pc.controller.entries.length == 2);
      expect(pc.shell!.shown.map((s) => s.title), ['Marie', 'Paul']);

      // Retirée du téléphone : on ne peut plus y répondre.
      tel.source!.remove('autre');
      await until(() => pc.controller.entries.first.removed);
      expect(pc.controller.entries.first.canReply, isFalse);
    });

    test('mode discret : la notification Windows ne montre que l\'expéditeur', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      await pc.controller.setDiscreet(true);
      tel.source!.post(message());
      await until(() => pc.shell!.shown.isNotEmpty);
      expect(pc.shell!.shown.single.title, 'WhatsApp');
      expect(pc.shell!.shown.single.body, 'Nouveau message de Marie');
    });

    test('les notifications déjà présentes arrivent à la connexion, sans notification Windows', () async {
      final tel = await phone('Galaxy S25');
      tel.source!.current.add(message(text: 'Déjà là'));
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      await until(() => pc.controller.entries.isNotEmpty);
      expect(pc.controller.entries.single.notification.text, 'Déjà là');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(pc.shell!.shown, isEmpty);
    });

    test('relais coupé sur le téléphone : rien n\'est envoyé', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      await tel.controller.setRelay(false);
      tel.source!.post(message());
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(pc.controller.entries, isEmpty);
    });

    test('notification d\'essai', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      await tel.controller.sendTest();
      await until(() => pc.controller.entries.isNotEmpty);
      expect(pc.controller.entries.single.notification.appName, 'sPing');
    });
  });

  group('Réponses', () {
    test('une réponse écrite sur le PC part du téléphone', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      tel.source!.post(message());
      await until(() => pc.controller.entries.isNotEmpty);
      final entry = pc.controller.entries.single;
      await pc.controller.reply(entry, '  Oui, à tout à l\'heure  ');
      await until(() => entry.replies.single.state == ReplyState.sent);
      expect(tel.source!.replies.single, (message().key, 'Oui, à tout à l\'heure'));
    });

    test('réponse depuis la notification Windows', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      tel.source!.post(message());
      await until(() => pc.controller.entries.isNotEmpty);
      pc.shell!.replyHandler!(message().key, 'Parfait');
      await until(() => tel.source!.replies.isNotEmpty);
      expect(tel.source!.replies.single.$2, 'Parfait');
    });

    test('un échec sur le téléphone est signalé sur le PC', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      tel.source!.replyError = 'La notification n\'est plus sur le téléphone.';
      tel.source!.post(message());
      await until(() => pc.controller.entries.isNotEmpty);
      final entry = pc.controller.entries.single;
      await pc.controller.reply(entry, 'Oui');
      await until(() => entry.replies.single.state == ReplyState.failed);
      expect(entry.replies.single.error, contains('plus sur le téléphone'));
    });
  });

  group('Liaison', () {
    test('le PC se reconnecte quand le téléphone revient', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      await tel.stop();
      devices.remove(tel);
      await until(() => pc.controller.connectedCount == 0, reason: 'coupure détectée');
      // Le téléphone redémarre avec ses réglages et son coffre.
      final again = await TestDevice.phone(
        'Galaxy S25',
        port: phonePort,
        announceTo: pcPort,
        store: tel.store,
        secrets: tel.secrets,
      );
      devices.add(again);
      await until(() => pc.controller.connectedCount == 1, reason: 'reconnexion');
      again.source!.post(message(text: 'Après la coupure'));
      await until(() => pc.controller.entries.isNotEmpty);
    });

    test('oublier le téléphone sur le PC le fait oublier des deux côtés', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      await pc.controller.unpair(pc.controller.paired.single);
      await until(() => tel.controller.paired.isEmpty);
      expect(pc.controller.paired, isEmpty);
      tel.source!.post(message());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(pc.controller.entries, isEmpty);
    });

    test('un téléphone qui a oublié le PC le dit clairement', () async {
      final tel = await phone('Galaxy S25');
      final pc = await computer('PC du bureau');
      await pair(tel, pc);
      // Le téléphone perd ses appairages (réinstallation, par exemple), le PC les garde.
      await tel.stop();
      devices.remove(tel);
      tel.secrets.values.remove('appairages');
      final again = await TestDevice.phone(
        'Galaxy S25',
        port: phonePort,
        announceTo: pcPort,
        store: tel.store,
        secrets: tel.secrets,
      );
      devices.add(again);
      final id = pc.controller.paired.single.id;
      await until(() => pc.controller.linkError(id) != null);
      expect(pc.controller.linkError(id), contains('appairez-les de nouveau'));
    });
  });

  group('Formats', () {
    test('une notification reçue est nettoyée et bornée', () {
      final parsed = PhoneNotification.fromJson({
        'cle': 'k',
        'paquet': 'com.app',
        'appli': 'App\u0000',
        'titre': 'Titre\nsur deux lignes',
        'texte': 'x' * 10000,
        'heure': 0,
      })!;
      expect(parsed.title, 'Titre sur deux lignes');
      expect(parsed.text.length, NotificationLimits.text + 1);
      expect(parsed.appName, 'App');
      expect(PhoneNotification.fromJson({'cle': 'k'}), isNull);
    });

    test('textes du mode discret', () {
      expect(message().discreetSummary, 'Nouveau message de Marie');
      expect(message(conversation: 'Famille').discreetSummary, 'Nouveau message de Marie dans Famille');
      final email = PhoneNotification(
        key: 'g',
        packageName: 'com.google.android.gm',
        appName: 'Gmail',
        title: 'Banque',
        text: 'Votre relevé',
        time: DateTime(2026),
      );
      expect(email.discreetSummary, 'Nouvelle notification');
      expect(toastText(email, discreet: true), (title: 'Gmail', body: 'Nouvelle notification'));
      expect(toastText(message(conversation: 'Famille'), discreet: false).title, 'Marie · Famille');
    });

    test('adresses saisies à la main', () {
      expect(parseAddress('192.168.1.20', defaultPort: 47874)!.$2, 47874);
      expect(parseAddress(' 192.168.1.20:5000 ', defaultPort: 47874)!.$2, 5000);
      expect(parseAddress('mon-telephone', defaultPort: 47874), isNull);
      expect(parseAddress('192.168.1.20:99999', defaultPort: 47874), isNull);
    });

    test('annonces', () {
      expect(Announce.fromJson({'sping': 1, 'id': 'tel-1234', 'nom': 'Galaxy', 'port': 47874})!.name, 'Galaxy');
      expect(Announce.fromJson({'sping': 1, 'id': '../x', 'nom': 'Galaxy', 'port': 47874}), isNull);
      expect(Announce.fromJson({'sdrop': 1, 'id': 'tel-1234', 'nom': 'Galaxy', 'port': 47874}), isNull);
      expect(Limits.frameBytes, greaterThan(NotificationLimits.icon * 2));
    });
  });
}

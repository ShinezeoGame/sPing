import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/crypto/crypto.dart';
import '../data/net/discovery.dart';
import '../data/net/link.dart';
import '../data/net/protocol.dart';
import '../data/platform/android_bridge.dart';
import '../data/platform/desktop_shell.dart';
import '../data/secure_store.dart';
import '../data/settings.dart';
import '../models/device.dart';
import '../models/phone_notification.dart';

/// Message affiché en haut de l'écran après une action.
class Notice {
  const Notice(this.message, {this.error = false});

  final String message;
  final bool error;
}

/// Une réponse écrite sur le PC.
enum ReplyState { sending, sent, failed }

class ReplyItem {
  ReplyItem(this.id, this.text);

  final String id;
  final String text;
  ReplyState state = ReplyState.sending;
  String? error;
}

/// Une notification reçue par le PC.
class NotificationEntry {
  NotificationEntry(this.phoneId, this.notification);

  final String phoneId;
  PhoneNotification notification;

  /// Retirée du téléphone (lue, effacée) : on ne peut plus y répondre.
  bool removed = false;
  final List<ReplyItem> replies = [];

  bool get canReply => notification.canReply && !removed;
}

/// Un téléphone vu sur le réseau par le PC.
class VisiblePhone {
  VisiblePhone(this.sighting, this.lastSeen);

  Sighting sighting;
  DateTime lastSeen;

  String get id => sighting.announce.id;
  String get name => sighting.announce.name;
  InternetAddress get address => sighting.address;
  int get port => sighting.announce.port;
}

/// Appairage affiché à l'écran (vrai ou imposé par les tests d'affichage).
abstract interface class PairingView {
  PairedDevice get peer;
  String get code;
  bool get answered;
  bool get remoteAccepted;
}

class _PendingPairingView implements PairingView {
  _PendingPairingView(this.pending);

  final PendingPairing pending;

  @override
  PairedDevice get peer => pending.peer;

  @override
  String get code => pending.code;

  @override
  bool get answered => pending.answered;

  @override
  bool get remoteAccepted => pending.remoteAccepted;
}

/// État de l'application, pour les deux rôles : le téléphone relaie, le PC reçoit.
class PingController extends ChangeNotifier {
  PingController({
    DeviceRole? role,
    SettingsStore? store,
    SecretStore? secrets,
    NotificationSource? source,
    DesktopShell? shell,
    this.port = spingPort,
    this.announceTargets,
    this.listenMulticast = true,
    this.timings = const LinkTimings(),
    this.announceFast = const Duration(seconds: 3),
    this.announceSlow = const Duration(seconds: 15),
    this.reconnectDelay = const Duration(seconds: 3),
    this.phoneTimeout = const Duration(seconds: 40),
    this.pairingWindow = const Duration(minutes: 3),
    this.replyTimeout = const Duration(seconds: 20),
  }) : role = role ?? (Platform.isAndroid ? DeviceRole.phone : DeviceRole.computer),
       _store = store ?? SettingsStore(),
       _secrets = secrets ?? const SystemSecretStore(),
       source = source ?? AndroidBridge(),
       shell = shell ?? (Platform.isWindows ? WindowsShell() : const NoDesktopShell());

  final DeviceRole role;
  final SettingsStore _store;
  final SecretStore _secrets;

  /// Téléphone : notifications d'Android.
  final NotificationSource source;

  /// PC : notifications Windows, zone de notification.
  final DesktopShell shell;

  /// Port du téléphone (liaison TCP) et des annonces (UDP).
  final int port;

  /// Téléphone : destinataires imposés des annonces (tests).
  final List<(InternetAddress, int)>? announceTargets;

  /// PC : rejoindre le groupe de multidiffusion.
  final bool listenMulticast;
  final LinkTimings timings;

  /// Téléphone : intervalle des annonces sans PC connecté, puis avec.
  final Duration announceFast;
  final Duration announceSlow;

  /// PC : attente entre deux tentatives de connexion au téléphone.
  final Duration reconnectDelay;

  /// PC : un téléphone qui ne s'annonce plus est oublié de la liste après ce délai.
  final Duration phoneTimeout;

  /// Téléphone : durée pendant laquelle un PC peut demander l'appairage.
  final Duration pairingWindow;

  /// PC : une réponse sans nouvelles du téléphone est déclarée échouée après ce délai.
  final Duration replyTimeout;

  bool get isPhone => role == DeviceRole.phone;

  Settings _settings = const Settings();
  Settings get settings => _settings;

  Identity? _identity;
  List<PairedDevice> _paired = const [];

  /// Appareils appairés avec celui-ci.
  List<PairedDevice> get paired => _paired;

  final Map<String, Link> _links = {};

  /// Nombre d'appareils appairés connectés en ce moment.
  int get connectedCount => _paired.where((d) => connected(d.id)).length;

  bool _ready = false;
  bool get ready => _ready;

  String? _startError;
  String? get startError => _startError;

  Notice? _notice;
  Notice? get notice => _notice;

  List<String> _addresses = const [];

  /// Adresses de cet appareil sur le réseau local.
  List<String> get addresses => _addresses;

  bool _disposed = false;
  Timer? _tickTimer;
  final _subscriptions = <StreamSubscription<Object?>>[];

  // ── Téléphone ──
  ServerSocket? _server;
  Announcer? _announcer;
  DateTime? _pairingUntil;
  PendingPairing? _incoming;
  PhoneStatus _status = const PhoneStatus();
  int _relayed = 0;
  final Map<Link, Set<String>> _iconsSent = {};

  /// Téléphone : un PC peut demander l'appairage en ce moment.
  bool get pairingOpen => _pairingUntil != null && DateTime.now().isBefore(_pairingUntil!);

  PhoneStatus get phoneStatus => _status;

  /// Téléphone : notifications relayées depuis le démarrage.
  int get relayedCount => _relayed;

  // ── PC ──
  AnnounceListener? _listener;
  final Map<String, VisiblePhone> _visible = {};
  final Map<String, DateTime> _lastAttempt = {};
  final Set<String> _connecting = {};
  final Map<String, String> _linkErrors = {};
  final List<NotificationEntry> _entries = [];
  final Map<String, Uint8List> _icons = {};
  final Map<String, (ReplyItem, Timer)> _pendingReplies = {};
  PendingPairing? _outgoing;
  String? _pairingTarget;

  /// PC : téléphones visibles sur le réseau, par ordre alphabétique.
  List<VisiblePhone> get visiblePhones =>
      _visible.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// PC : notifications reçues, de la plus récente à la plus ancienne.
  List<NotificationEntry> get entries => List.unmodifiable(_entries);

  /// PC : icône d'une application du téléphone, si elle a été reçue.
  Uint8List? iconFor(String packageName) => _icons[packageName];

  /// PC : pourquoi la liaison avec ce téléphone ne s'établit pas.
  String? linkError(String id) => _linkErrors[id];

  /// PC : le téléphone appairé est visible sur le réseau.
  bool isVisible(String id) => _visible.containsKey(id);

  /// PC : appairage demandé à ce téléphone, en attente de réponse.
  String? get pairingTarget => _pairingTarget;

  PairingView? _debugPairing;

  /// Appairage en cours (des deux côtés).
  PairingView? get pairing {
    if (_debugPairing != null) return _debugPairing;
    final pending = isPhone ? _incoming : _outgoing;
    return pending == null || pending.isDone ? null : _PendingPairingView(pending);
  }

  LocalDevice get _self =>
      LocalDevice(id: _settings.deviceId, name: _settings.deviceName, identity: _identity!, role: role);

  // ── Démarrage et arrêt ──

  /// Lit les réglages, l'identité et les appairages ; au premier lancement, crée l'identité.
  Future<void> loadSettings() async {
    var settings = await _store.load();
    if (settings.deviceId.isEmpty || settings.deviceName.isEmpty) {
      var name = settings.deviceName;
      if (name.isEmpty && isPhone) name = (await source.deviceName())?.trim() ?? '';
      if (name.isEmpty) name = _hostName();
      settings = settings.copyWith(
        deviceId: settings.deviceId.isEmpty ? randomHex() : null,
        deviceName: cleanName(name),
      );
      await _store.save(settings);
    }
    _settings = settings;
    _identity = await _loadIdentity();
    _paired = await _loadPaired();
    _notify();
  }

  Future<Identity> _loadIdentity() async {
    final stored = await _secrets.read('identite');
    if (stored != null) {
      try {
        return await Identity.fromSeed(base64.decode(stored));
      } on Object {
        // Graine illisible : une nouvelle identité oblige à appairer de nouveau.
      }
    }
    final identity = await Identity.generate();
    await _secrets.write('identite', base64.encode(identity.seed));
    return identity;
  }

  Future<List<PairedDevice>> _loadPaired() async {
    try {
      final list = jsonDecode(await _secrets.read('appairages') ?? '[]');
      if (list is List) {
        return [for (final item in list) ?PairedDevice.fromJson(item)];
      }
    } on Object {
      // Liste illisible : aucun appairage.
    }
    return const [];
  }

  Future<void> _savePaired() =>
      _secrets.write('appairages', jsonEncode([for (final device in _paired) device.toJson()]));

  static String _hostName() {
    try {
      final name = Platform.localHostname;
      if (name.isNotEmpty && name != 'localhost') return name;
    } on Object {
      // Nom indisponible.
    }
    return Platform.isAndroid ? 'Téléphone' : 'PC';
  }

  /// Met l'appareil en route : à l'écoute des PC (téléphone) ou des téléphones (PC).
  Future<void> start() async {
    try {
      if (isPhone) {
        await _startPhone();
      } else {
        await _startComputer();
      }
      _ready = true;
    } on Object catch (error) {
      _startError = isPhone
          ? 'sPing ne peut pas attendre le PC sur le réseau : $error'
          : 'sPing ne peut pas écouter le réseau (une autre copie de sPing est peut-être ouverte) : $error';
    }
    _tickTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    unawaited(_refreshAddresses());
    _notify();
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    _tickTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _incoming?.cancel();
    _outgoing?.cancel();
    for (final (_, timer) in _pendingReplies.values) {
      timer.cancel();
    }
    for (final link in [..._links.values]) {
      link.close('Arrêt de sPing.');
    }
    _announcer?.stop();
    await _server?.close();
    await _listener?.stop();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _say(String message, {bool error = false}) {
    _notice = Notice(message, error: error);
    _notify();
  }

  void clearNotice() {
    _notice = null;
    _notify();
  }

  Future<void> _refreshAddresses() async {
    final found = await localAddresses();
    if (listEquals(found, _addresses)) return;
    _addresses = found;
    _notify();
  }

  void _tick() {
    if (_disposed) return;
    if (isPhone) {
      if (_pairingUntil != null && !pairingOpen) {
        _pairingUntil = null;
        _notify();
      }
    } else {
      final now = DateTime.now();
      final before = _visible.length;
      _visible.removeWhere((_, phone) => now.difference(phone.lastSeen) > phoneTimeout);
      if (_visible.length != before) _notify();
      _connectPhones();
    }
  }

  // ── Réglages communs ──

  Future<void> _update(Settings settings) async {
    _settings = settings;
    _notify();
    await _store.save(settings);
  }

  Future<void> setTheme(AppThemeMode theme) => _update(_settings.copyWith(theme: theme));

  Future<void> rename(String name) async {
    final clean = cleanName(name);
    if (clean.isEmpty || clean == _settings.deviceName) return;
    await _update(_settings.copyWith(deviceName: clean));
    _announcer?.announceNow();
  }

  /// Oublie un appareil appairé : il ne pourra plus se connecter sans nouvel appairage.
  Future<void> unpair(PairedDevice device) async {
    final link = _links[device.id];
    if (link != null) {
      await link.send({'type': 'oubli'});
      link.close('Appairage supprimé.');
    }
    await _forget(device.id);
    _say('« ${device.name} » est oublié. Il faudra l\'appairer de nouveau pour le reconnecter.');
  }

  Future<void> _forget(String id) async {
    _paired = [..._paired.where((device) => device.id != id)];
    _linkErrors.remove(id);
    _notify();
    await _savePaired();
  }

  Future<void> _remember(PairedDevice device) async {
    _paired = [..._paired.where((d) => d.id != device.id), device];
    _linkErrors.remove(device.id);
    _notify();
    await _savePaired();
  }

  void _register(Link link) {
    _links[link.peer.id]?.close('Remplacée par une nouvelle liaison.');
    _links[link.peer.id] = link;
    _linkErrors.remove(link.peer.id);
    // Le nom de l'autre appareil a pu changer depuis l'appairage.
    final known = _paired.where((d) => d.id == link.peer.id).firstOrNull;
    if (known != null && known.name != link.peer.name) {
      _paired = [for (final d in _paired) d.id == known.id ? d.copyWith(name: link.peer.name) : d];
      unawaited(_savePaired());
    }
    _subscriptions.add(link.messages.listen((message) => _onMessage(link, message)));
    unawaited(
      link.done.then((reason) {
        if (_links[link.peer.id] == link) _links.remove(link.peer.id);
        _iconsSent.remove(link);
        if (isPhone) _announcer?.announceNow();
        _notify();
      }),
    );
    if (isPhone) {
      _iconsSent[link] = {};
      unawaited(_sendActive(link));
    }
    _notify();
  }

  void _onMessage(Link link, Map<String, dynamic> message) {
    if (message['type'] == 'oubli') {
      link.close('Appairage supprimé sur l\'autre appareil.');
      unawaited(_forget(link.peer.id));
      _say('« ${link.peer.name} » a supprimé l\'appairage.', error: true);
      return;
    }
    if (isPhone) {
      _onPhoneMessage(link, message);
    } else {
      _onComputerMessage(link, message);
    }
  }

  // ── Téléphone ──

  Future<void> _startPhone() async {
    _subscriptions
      ..add(source.posted.listen(_relay))
      ..add(source.removed.listen(_relayRemoval))
      ..add(source.changed.listen((_) => refreshStatus()));
    unawaited(refreshStatus());
    final server = _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _subscriptions.add(server.listen(_onIncoming));
    final announcer = _announcer = Announcer(
      self: () => Announce(id: _settings.deviceId, name: _settings.deviceName, port: server.port),
      port: port,
      targets: announceTargets,
      interval: () => _links.isEmpty || pairingOpen ? announceFast : announceSlow,
    );
    await announcer.start();
  }

  /// Relit les autorisations du téléphone (au retour dans l'application, par exemple).
  Future<void> refreshStatus() async {
    if (!isPhone) return;
    _status = await source.status();
    _notify();
  }

  Future<void> _onIncoming(Socket socket) async {
    try {
      final result = await Link.accept(
        socket,
        self: _self,
        timings: timings,
        findPeer: (id) => _paired.where((d) => d.id == id).firstOrNull,
        pairingRefusal: () {
          if (!pairingOpen) return Refusal.pairingClosed;
          if (_incoming != null && !_incoming!.isDone) return Refusal.busy;
          return null;
        },
      );
      if (_disposed) {
        if (result is Link) result.close();
        if (result is PendingPairing) result.cancel();
        return;
      }
      if (result is Link) {
        _register(result);
      } else if (result is PendingPairing) {
        _incoming = result;
        _notify();
        final ok = await result.result;
        if (ok) {
          await _remember(result.peer);
          _pairingUntil = null;
          _say('Appairé avec « ${result.peer.name} ». Les notifications arrivent maintenant sur ce PC.');
        } else {
          _say(result.failure ?? 'Appairage interrompu.', error: true);
        }
      }
    } on Object {
      // Connexion refusée ou invalide : rien n'a été transmis.
    }
  }

  /// Ouvre l'appairage : pendant quelques minutes, un PC peut le demander.
  void openPairing() {
    _pairingUntil = DateTime.now().add(pairingWindow);
    _announcer?.announceNow();
    _notify();
  }

  void closePairing() {
    _pairingUntil = null;
    _incoming?.cancel();
    _notify();
  }

  /// Réponse de l'utilisateur à l'appairage en cours (des deux côtés).
  void decidePairing(bool accepted) {
    final pending = isPhone ? _incoming : _outgoing;
    if (pending == null) return;
    pending.decide(accepted);
    _notify();
  }

  Future<void> setRelay(bool enabled) => _update(_settings.copyWith(relay: enabled));

  Future<void> _sendActive(Link link) async {
    if (!_settings.relay) return;
    final active = await source.active();
    active.sort((a, b) => a.time.compareTo(b.time));
    for (final notification in active) {
      await _sendNotification(link, notification, fresh: false);
    }
  }

  Future<void> _sendNotification(Link link, PhoneNotification notification, {required bool fresh}) async {
    final sent = _iconsSent[link];
    if (sent == null) return;
    final withIcon = notification.icon != null && sent.add(notification.packageName);
    await link.send({'type': 'notif', 'nouvelle': fresh, 'n': notification.toJson(withIcon: withIcon)});
  }

  void _relay(PhoneNotification notification) {
    if (!_settings.relay || _links.isEmpty) return;
    _relayed++;
    for (final link in [..._links.values]) {
      unawaited(_sendNotification(link, notification, fresh: true));
    }
    _notify();
  }

  void _relayRemoval(String key) {
    for (final link in [..._links.values]) {
      unawaited(link.send({'type': 'retiree', 'cle': key}));
    }
  }

  /// Envoie une notification d'essai aux PC connectés.
  Future<void> sendTest() async {
    if (_links.isEmpty) {
      _say('Aucun PC connecté pour l\'instant.', error: true);
      return;
    }
    final test = PhoneNotification(
      key: 'sping-essai-${DateTime.now().millisecondsSinceEpoch}',
      packageName: 'com.shinezeogame.sping',
      appName: 'sPing',
      title: 'Essai réussi',
      text: 'Les notifications de « ${_settings.deviceName} » arrivent bien sur ce PC.',
      time: DateTime.now(),
    );
    for (final link in [..._links.values]) {
      await _sendNotification(link, test, fresh: true);
    }
    _say('Notification d\'essai envoyée.');
  }

  Future<void> _onPhoneMessage(Link link, Map<String, dynamic> message) async {
    if (message['type'] != 'repondre') return;
    final id = message['id'], key = message['cle'], text = message['texte'];
    if (id is! String || key is! String || text is! String) return;
    String? error;
    if (text.trim().isEmpty || text.length > Limits.replyLength) {
      error = 'Réponse vide ou trop longue.';
    } else {
      error = await source.reply(key, text.trim());
    }
    await link.send({'type': 'resultat', 'id': id, 'ok': error == null, 'erreur': ?error});
  }

  // ── PC ──

  Future<void> _startComputer() async {
    await shell.start(onReply: _replyFromToast, onToggleDiscreet: () => setDiscreet(!_settings.discreet));
    unawaited(shell.setDiscreet(_settings.discreet));
    unawaited(shell.setKeepInTray(_settings.keepInTray));
    final listener = _listener = AnnounceListener(port: port, multicast: listenMulticast);
    _subscriptions.add(listener.sightings.listen(_onSighting));
    await listener.start();
  }

  void _onSighting(Sighting sighting) {
    final id = sighting.announce.id;
    final known = _visible[id];
    if (known != null) {
      final changed = known.name != sighting.announce.name;
      known
        ..sighting = sighting
        ..lastSeen = DateTime.now();
      if (changed) _notify();
    } else {
      _visible[id] = VisiblePhone(sighting, DateTime.now());
      _notify();
    }
    // Un téléphone appairé qui réapparaît : on tente la connexion sans attendre.
    if (_paired.any((d) => d.id == id) && !_links.containsKey(id)) _lastAttempt.remove(id);
  }

  /// Se connecte aux téléphones appairés qui ne le sont pas encore.
  void _connectPhones() {
    for (final phone in _paired) {
      if (_links.containsKey(phone.id) || _connecting.contains(phone.id)) continue;
      final last = _lastAttempt[phone.id];
      if (last != null && DateTime.now().difference(last) < reconnectDelay) continue;
      final visible = _visible[phone.id];
      final manual = _manualTarget();
      if (visible != null) {
        unawaited(_connect(phone, visible.address, visible.port));
      } else if (manual != null) {
        unawaited(_connect(phone, manual.$1, manual.$2));
      }
    }
  }

  (InternetAddress, int)? _manualTarget() {
    final text = _settings.manualAddress.trim();
    if (text.isEmpty) return null;
    return parseAddress(text, defaultPort: port);
  }

  Future<void> _connect(PairedDevice phone, InternetAddress address, int port) async {
    _connecting.add(phone.id);
    _lastAttempt[phone.id] = DateTime.now();
    try {
      final link = await Link.connect(address: address, port: port, self: _self, phone: phone, timings: timings);
      if (_disposed || !_paired.any((d) => d.id == phone.id)) {
        link.close();
        return;
      }
      _register(link);
    } on LinkRefused catch (refused) {
      if (refused.reason == Refusal.unknown) {
        _linkErrors[phone.id] = 'Ce téléphone ne reconnaît plus ce PC : appairez-les de nouveau.';
        _notify();
      }
    } on LinkClosed catch (error) {
      _linkErrors[phone.id] = error.message;
      _notify();
    } on Object {
      // Téléphone injoignable pour l'instant : nouvel essai plus tard.
    } finally {
      _connecting.remove(phone.id);
    }
  }

  /// Demande l'appairage au téléphone [address]:[port].
  Future<void> pairWith(InternetAddress address, int port, {String? name}) async {
    if (_outgoing != null && !_outgoing!.isDone) return;
    _pairingTarget = name ?? address.address;
    _notify();
    try {
      final pending = _outgoing = await Link.pair(address: address, port: port, self: _self, timings: timings);
      _notify();
      final ok = await pending.result;
      if (ok) {
        await _remember(pending.peer);
        _lastAttempt.remove(pending.peer.id);
        _say('Appairé avec « ${pending.peer.name} ». Ses notifications vont s\'afficher ici.');
        _connectPhones();
      } else {
        _say(pending.failure ?? 'Appairage interrompu.', error: true);
      }
    } on LinkRefused catch (refused) {
      _say(switch (refused.reason) {
        Refusal.pairingClosed => 'Le téléphone n\'attend pas d\'appairage. Sur le téléphone, ouvrez sPing et touchez « Appairer un PC », puis réessayez.',
        Refusal.busy => 'Le téléphone est déjà en train de s\'appairer avec un autre PC.',
        _ => 'Le téléphone a refusé la connexion.',
      }, error: true);
    } on Object catch (error) {
      _say('Impossible de joindre le téléphone : ${error is LinkClosed ? error.message : error}', error: true);
    } finally {
      _pairingTarget = null;
      _notify();
    }
  }

  /// Demande l'appairage à un téléphone dont l'utilisateur a saisi l'adresse ; l'adresse
  /// est retenue pour les connexions suivantes.
  Future<void> pairWithAddress(String text) async {
    final target = parseAddress(text, defaultPort: port);
    if (target == null) {
      _say('Adresse invalide. Exemple : 192.168.1.20', error: true);
      return;
    }
    await _update(_settings.copyWith(manualAddress: text.trim()));
    await pairWith(target.$1, target.$2);
  }

  Future<void> setManualAddress(String text) async {
    if (text.trim().isNotEmpty && parseAddress(text, defaultPort: port) == null) {
      _say('Adresse invalide. Exemple : 192.168.1.20', error: true);
      return;
    }
    await _update(_settings.copyWith(manualAddress: text.trim()));
  }

  Future<void> setDiscreet(bool discreet) async {
    await _update(_settings.copyWith(discreet: discreet));
    await shell.setDiscreet(discreet);
  }

  Future<void> setDesktopNotifications(bool enabled) => _update(_settings.copyWith(desktopNotifications: enabled));

  Future<void> setKeepInTray(bool keep) async {
    await _update(_settings.copyWith(keepInTray: keep));
    await shell.setKeepInTray(keep);
  }

  void _onComputerMessage(Link link, Map<String, dynamic> message) {
    switch (message['type']) {
      case 'notif':
        final notification = PhoneNotification.fromJson(message['n']);
        if (notification != null) _receive(link.peer.id, notification, fresh: message['nouvelle'] == true);
      case 'retiree':
        final key = message['cle'];
        for (final entry in _entries) {
          if (entry.phoneId == link.peer.id && entry.notification.key == key) entry.removed = true;
        }
        _notify();
      case 'resultat':
        final id = message['id'];
        final pending = _pendingReplies.remove(id);
        if (pending == null) return;
        final (reply, timer) = pending;
        timer.cancel();
        if (message['ok'] == true) {
          reply.state = ReplyState.sent;
        } else {
          reply
            ..state = ReplyState.failed
            ..error = message['erreur'] is String ? message['erreur'] as String : 'Réponse impossible.';
        }
        _notify();
    }
  }

  /// Nombre maximal de notifications gardées dans la fenêtre.
  static const maxEntries = 150;

  void _receive(String phoneId, PhoneNotification notification, {required bool fresh}) {
    final icon = notification.icon;
    if (icon != null) _icons[notification.packageName] = icon;
    final index = _entries.indexWhere((e) => e.phoneId == phoneId && e.notification.key == notification.key);
    var changed = true;
    if (index >= 0) {
      final entry = _entries.removeAt(index);
      changed = !entry.notification.sameContent(notification);
      entry
        ..notification = notification
        ..removed = false;
      // Une mise à jour sans changement (Android en publie souvent) garde sa place.
      _entries.insert(changed ? 0 : index, entry);
    } else {
      _entries.insert(0, NotificationEntry(phoneId, notification));
      if (_entries.length > maxEntries) _entries.removeLast();
    }
    if (fresh && changed && _settings.desktopNotifications) {
      unawaited(shell.show(notification, discreet: _settings.discreet));
    }
    _notify();
  }

  void _replyFromToast(String key, String text) {
    final entry = _entries.where((e) => e.notification.key == key).firstOrNull;
    if (entry != null) unawaited(reply(entry, text));
  }

  /// Répond à une notification depuis le PC.
  Future<void> reply(NotificationEntry entry, String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    if (clean.length > Limits.replyLength) {
      _say('Réponse trop longue (${Limits.replyLength} caractères au plus).', error: true);
      return;
    }
    final link = _links[entry.phoneId];
    final item = ReplyItem(randomHex(8), clean);
    entry.replies.add(item);
    if (link == null) {
      item
        ..state = ReplyState.failed
        ..error = 'Téléphone déconnecté.';
      _notify();
      return;
    }
    _pendingReplies[item.id] = (
      item,
      Timer(replyTimeout, () {
        if (_pendingReplies.remove(item.id) == null) return;
        item
          ..state = ReplyState.failed
          ..error = 'Le téléphone n\'a pas confirmé l\'envoi.';
        _notify();
      }),
    );
    _notify();
    await link.send({'type': 'repondre', 'id': item.id, 'cle': entry.notification.key, 'texte': clean});
  }

  /// Vide la liste des notifications du PC (rien n'est effacé sur le téléphone).
  void clearEntries() {
    _entries.clear();
    _notify();
  }

  // ── Tests d'affichage ──

  /// Impose un état sans réseau (tests d'affichage et captures).
  @visibleForTesting
  void debugSetState({
    bool? ready,
    List<String>? addresses,
    List<PairedDevice>? paired,
    Set<String>? connected,
    List<Sighting>? visible,
    List<NotificationEntry>? entries,
    Map<String, Uint8List>? icons,
    PhoneStatus? status,
    PairingView? pairing,
    bool clearPairing = false,
    bool? pairingOpen,
    int? relayed,
    Notice? notice,
    Map<String, String>? linkErrors,
  }) {
    if (ready != null) _ready = ready;
    if (addresses != null) _addresses = addresses;
    if (paired != null) _paired = paired;
    if (connected != null) {
      _debugConnected
        ..clear()
        ..addAll(connected);
    }
    if (visible != null) {
      _visible
        ..clear()
        ..addAll({
          for (final s in visible) s.announce.id: VisiblePhone(s, DateTime.now().add(const Duration(days: 1))),
        });
    }
    if (entries != null) {
      _entries
        ..clear()
        ..addAll(entries);
    }
    if (icons != null) _icons.addAll(icons);
    if (status != null) _status = status;
    if (pairing != null) _debugPairing = pairing;
    if (clearPairing) _debugPairing = null;
    if (pairingOpen != null) _pairingUntil = pairingOpen ? DateTime.now().add(const Duration(days: 1)) : null;
    if (relayed != null) _relayed = relayed;
    if (notice != null) _notice = notice;
    if (linkErrors != null) _linkErrors.addAll(linkErrors);
    _notify();
  }

  final Set<String> _debugConnected = {};

  /// Connecté, réellement ou dans un état imposé par les tests.
  bool connected(String id) => _links.containsKey(id) || _debugConnected.contains(id);
}

/// Lit « 192.168.1.20 » ou « 192.168.1.20:47874 ».
(InternetAddress, int)? parseAddress(String text, {required int defaultPort}) {
  final match = RegExp(r'^\s*(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?\s*$').firstMatch(text);
  if (match == null) return null;
  final address = InternetAddress.tryParse(match.group(1)!);
  final port = match.group(2) == null ? defaultPort : int.parse(match.group(2)!);
  if (address == null || port < 1 || port > 65535) return null;
  return (address, port);
}

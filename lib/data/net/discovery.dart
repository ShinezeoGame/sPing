import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/device.dart';
import 'protocol.dart';

/// Une annonce reçue d'un téléphone.
class Sighting {
  const Sighting(this.announce, this.address);

  final Announce announce;
  final InternetAddress address;
}

/// Le téléphone s'annonce sur le réseau local par un petit message UDP, envoyé à la fois
/// en multidiffusion et en diffusion (selon les box, l'un des deux seulement passe).
///
/// Le téléphone ne fait qu'envoyer : il n'a pas besoin du verrou de multidiffusion
/// d'Android, coûteux en batterie. C'est le PC qui écoute, puis se connecte au téléphone.
class Announcer {
  Announcer({required this.self, this.port = spingPort, this.targets, required this.interval});

  /// Ce que le téléphone annonce (relu à chaque envoi : le nom peut changer).
  final Announce Function() self;

  /// Port des annonces.
  final int port;

  /// Destinataires imposés (tests). `null` : multidiffusion et diffusion du réseau local.
  final List<(InternetAddress, int)>? targets;

  /// Intervalle entre deux annonces ; relu après chaque annonce (plus lent une fois le PC
  /// connecté, pour la batterie).
  final Duration Function() interval;

  RawDatagramSocket? _socket;
  Timer? _timer;
  List<(InternetAddress, int)> _resolved = const [];
  DateTime _resolvedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    final socket = _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    _schedule(Duration.zero);
  }

  void _schedule(Duration wait) {
    _timer?.cancel();
    _timer = Timer(wait, () async {
      await announce();
      if (_socket != null) _schedule(interval());
    });
  }

  /// Annonce tout de suite (et reprend le rythme ensuite).
  void announceNow() {
    if (_socket != null) _schedule(Duration.zero);
  }

  Future<void> announce() async {
    final socket = _socket;
    if (socket == null) return;
    final data = utf8.encode(jsonEncode(self().toJson()));
    for (final (address, targetPort) in await _destinations()) {
      try {
        socket.send(data, address, targetPort);
      } on Object {
        // Réseau momentanément indisponible : la prochaine annonce repassera.
      }
    }
  }

  Future<List<(InternetAddress, int)>> _destinations() async {
    final fixed = targets;
    if (fixed != null) return fixed;
    // Les interfaces changent rarement (Wi-Fi coupé, autre réseau) : relues toutes les 20 s.
    if (DateTime.now().difference(_resolvedAt) < const Duration(seconds: 20)) return _resolved;
    final addresses = <String>{spingMulticastGroup, '255.255.255.255'};
    try {
      for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final address in interface.addresses) {
          // Diffusion dirigée, en supposant le masque courant des réseaux domestiques (/24).
          final parts = address.address.split('.');
          if (parts.length == 4 && !address.isLoopback) addresses.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    } on Object {
      // On garde la multidiffusion et la diffusion générale.
    }
    _resolved = [for (final address in addresses) (InternetAddress(address), port)];
    _resolvedAt = DateTime.now();
    return _resolved;
  }

  void stop() {
    _timer?.cancel();
    _socket?.close();
    _socket = null;
  }
}

/// Le PC écoute les annonces des téléphones.
class AnnounceListener {
  AnnounceListener({this.port = spingPort, this.multicast = true});

  final int port;

  /// Rejoindre le groupe de multidiffusion (inutile dans les tests, en local).
  final bool multicast;

  final _sightings = StreamController<Sighting>.broadcast();
  Stream<Sighting> get sightings => _sightings.stream;

  RawDatagramSocket? _socket;

  /// Lève [SocketException] si le port est déjà pris (autre copie de sPing).
  Future<void> start() async {
    final socket = _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
    socket.broadcastEnabled = true;
    if (multicast) await _joinMulticast(socket);
    socket.listen(_onEvent, onError: (Object _) {});
  }

  Future<void> _joinMulticast(RawDatagramSocket socket) async {
    final group = InternetAddress(spingMulticastGroup);
    try {
      socket.joinMulticast(group);
    } on Object {
      // Certains systèmes exigent de nommer l'interface : on essaie ci-dessous.
    }
    try {
      for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        try {
          socket.joinMulticast(group, interface);
        } on Object {
          // Interface sans multidiffusion : la diffusion prendra le relais.
        }
      }
    } on Object {
      // Liste des interfaces indisponible.
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    for (var datagram = socket.receive(); datagram != null; datagram = socket.receive()) {
      if (datagram.data.length > 1024) continue;
      Announce? announce;
      try {
        announce = Announce.fromJson(jsonDecode(utf8.decode(datagram.data)));
      } on Object {
        continue;
      }
      if (announce != null) _sightings.add(Sighting(announce, datagram.address));
    }
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    await _sightings.close();
  }
}

/// Adresses de cet appareil sur le réseau local, pour les afficher à l'utilisateur.
Future<List<String>> localAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (!address.isLoopback && !address.isLinkLocal) address.address,
    ];
  } on Object {
    return const [];
  }
}

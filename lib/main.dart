import 'package:flutter/material.dart';

import 'app.dart';
import 'state/ping_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = PingController();
  // Les réglages sont lus avant le premier affichage : le thème choisi s'applique d'emblée.
  await controller.loadSettings();
  runApp(SPingApp(controller: controller));
  // Sur Android, ce code tourne aussi sans écran, dans le service d'écoute des notifications :
  // le relais fonctionne même quand l'interface de sPing est fermée.
  await controller.start();
}

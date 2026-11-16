import 'package:flutter/widgets.dart';

import 'ping_controller.dart';

/// Rend le contrôleur accessible à toute l'interface, et la reconstruit quand il change.
class PingScope extends InheritedNotifier<PingController> {
  const PingScope({super.key, required PingController controller, required super.child}) : super(notifier: controller);

  static PingController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PingScope>()!.notifier!;

  /// Récupère le contrôleur sans s'abonner aux changements (pour les actions).
  static PingController read(BuildContext context) => context.getInheritedWidgetOfExactType<PingScope>()!.notifier!;
}

import 'package:flutter/material.dart';

import '../../state/ping_scope.dart';
import '../theme.dart';
import '../widgets/tiles.dart';
import 'page_scaffold.dart';

/// Page d'accueil (provisoire : l'interface complète arrive au prochain envoi).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PingScope.of(context);
    final t = context.text;
    return AppPage(
      header: Row(
        children: [
          Image.asset('assets/branding/logo.png', height: 44, filterQuality: FilterQuality.medium),
          const SizedBox(width: 10),
          Text('sPing', style: t.pageTitle),
        ],
      ),
      children: [
        const NoticeArea(),
        EmptyHint(
          icon: Icons.notifications_none_rounded,
          title: controller.isPhone ? 'Téléphone' : 'PC',
          text: 'Interface en cours de construction.',
        ),
      ],
    );
  }
}

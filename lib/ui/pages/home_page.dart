import 'package:flutter/material.dart';

import '../../state/ping_controller.dart';
import '../../state/ping_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/dialogs.dart';
import '../widgets/ping_widgets.dart';
import '../widgets/tiles.dart';
import 'page_scaffold.dart';
import 'settings_page.dart';

/// Page d'accueil : celle du téléphone (relais) ou celle du PC (notifications reçues).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PingScope.of(context);
    return AppPage(
      header: const _HomeHeader(),
      children: [
        const NoticeArea(),
        if (controller.startError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.gap),
            child: MessageBanner(error: true, message: controller.startError!),
          ),
        if (controller.pairing case final pairing?)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.gap),
            child: PairingTile(pairing: pairing),
          ),
        ...(controller.isPhone ? _phone(context, controller) : _computer(context, controller)),
      ],
    );
  }

  // ── Téléphone ──

  List<Widget> _phone(BuildContext context, PingController controller) {
    final t = context.text;
    final status = controller.phoneStatus;
    final paired = controller.paired;
    return [
      if (controller.pairingOpen && controller.pairing == null)
        Padding(
          padding: const EdgeInsets.only(bottom: Dim.gap),
          child: const _WaitingForComputer(),
        ),
      if (!status.access) ...[
        const _AccessTile(),
        const SizedBox(height: Dim.gap),
      ] else if (!status.batteryUnrestricted) ...[
        const _BatteryTile(),
        const SizedBox(height: Dim.gap),
      ],
      SectionTitle(
        'PC appairés',
        detail: paired.isEmpty
            ? null
            : '${controller.connectedCount} connecté${controller.connectedCount > 1 ? 's' : ''}',
      ),
      if (paired.isEmpty)
        EmptyHint(
          icon: Icons.desktop_windows_outlined,
          title: 'Aucun PC appairé',
          text: 'Installez sPing sur votre PC, puis appairez-le une fois pour toutes.',
          action: controller.pairingOpen
              ? null
              : AppButton(
                  label: 'Appairer un PC',
                  icon: Icons.add_link_rounded,
                  kind: ButtonKind.primary,
                  onPressed: controller.openPairing,
                ),
        )
      else ...[
        for (final pc in paired)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.gap),
            child: _DeviceTile(
              name: pc.name,
              icon: Icons.desktop_windows_outlined,
              connected: controller.connected(pc.id),
              state: controller.connected(pc.id) ? 'Connecté : les notifications y arrivent' : 'En attente du PC',
            ),
          ),
        if (!controller.pairingOpen)
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Appairer un autre PC',
              icon: Icons.add_link_rounded,
              onPressed: controller.openPairing,
            ),
          ),
      ],
      const SectionTitle('Relais'),
      Tile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingRow(
              title: 'Relayer les notifications',
              subtitle: controller.settings.relay
                  ? '${controller.relayedCount} relayée${controller.relayedCount > 1 ? 's' : ''} depuis le démarrage'
                  : 'En pause : rien n\'est envoyé au PC',
              trailing: AppSwitch(
                value: controller.settings.relay,
                label: 'Relayer les notifications',
                onChanged: controller.setRelay,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Envoyer une notification d\'essai',
                icon: Icons.notifications_active_outlined,
                compact: true,
                onPressed: controller.connectedCount > 0 ? controller.sendTest : null,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: Dim.sectionGap),
      Text('Le relais continue quand cet écran est fermé. Les échanges avec le PC sont chiffrés.', style: t.caption),
    ];
  }

  // ── PC ──

  List<Widget> _computer(BuildContext context, PingController controller) {
    final c = context.colors;
    final t = context.text;
    final paired = controller.paired;
    final entries = controller.entries;
    return [
      if (controller.pairingTarget != null && controller.pairing == null)
        Padding(
          padding: const EdgeInsets.only(bottom: Dim.gap),
          child: MessageBanner(busy: true, message: 'Connexion à « ${controller.pairingTarget} »…'),
        ),
      if (paired.isEmpty) ...[
        const SectionTitle('Appairer votre téléphone'),
        Tile(
          child: StepList([
            'Installez sPing sur le téléphone et accordez-lui l\'accès aux notifications.',
            'Sur le téléphone, touchez « Appairer un PC ».',
            'Choisissez le téléphone ci-dessous et comparez le code affiché des deux côtés.',
          ]),
        ),
        SectionTitle('Téléphones visibles', detail: controller.visiblePhones.isEmpty ? null : 'sur le même Wi-Fi'),
        if (controller.visiblePhones.isEmpty)
          EmptyHint(
            icon: Icons.wifi_tethering_rounded,
            title: 'Aucun téléphone pour l\'instant',
            text: 'Ouvrez sPing sur le téléphone, connecté au même Wi-Fi que ce PC.',
            action: AppButton(
              label: 'Saisir son adresse',
              icon: Icons.edit_outlined,
              onPressed: () => _pairByAddress(context),
            ),
          )
        else ...[
          for (final phone in controller.visiblePhones)
            Padding(
              padding: const EdgeInsets.only(bottom: Dim.gap),
              child: Tile(
                child: Row(
                  children: [
                    const IconBadge(icon: Icons.smartphone_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(phone.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.itemTitle),
                          Text(phone.address.address, style: t.caption),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Appairer',
                      kind: ButtonKind.primary,
                      compact: true,
                      onPressed: controller.pairingTarget == null && controller.pairing == null
                          ? () => controller.pairWith(phone.address, phone.port, name: phone.name)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _pairByAddress(context),
              child: Text(
                'Il n\'est pas dans la liste ? Saisir son adresse',
                style: t.secondary.copyWith(color: c.accent),
              ),
            ),
          ),
        ],
      ] else ...[
        for (final phone in paired)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.gap),
            child: _DeviceTile(
              name: phone.name,
              icon: Icons.smartphone_rounded,
              connected: controller.connected(phone.id),
              state: controller.connected(phone.id)
                  ? 'Connecté'
                  : controller.linkError(phone.id) ??
                        (controller.isVisible(phone.id)
                            ? 'Connexion en cours…'
                            : 'Recherche du téléphone sur le réseau…'),
              error: !controller.connected(phone.id) && controller.linkError(phone.id) != null,
            ),
          ),
        SectionTitle(
          'Notifications',
          detail: controller.settings.discreet ? 'contenu masqué' : null,
          trailing: entries.isEmpty
              ? null
              : InkWell(
                  onTap: controller.clearEntries,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Text('Effacer', style: t.button.copyWith(color: c.accent)),
                      ),
                    ),
                  ),
                ),
        ),
        if (entries.isEmpty)
          const EmptyHint(
            icon: Icons.notifications_none_rounded,
            title: 'Rien de nouveau',
            text: 'Les notifications du téléphone s\'afficheront ici, et dans les notifications de Windows.',
          )
        else
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: Dim.gap),
              child: NotificationCard(key: ValueKey('${entry.phoneId}/${entry.notification.key}'), entry: entry),
            ),
      ],
    ];
  }

  Future<void> _pairByAddress(BuildContext context) async {
    final controller = PingScope.read(context);
    final address = await askText(
      context,
      title: 'Adresse du téléphone',
      hint: '192.168.1.20',
      confirm: 'Appairer',
      help: 'Elle s\'affiche sur le téléphone quand vous touchez « Appairer un PC ».',
      initial: controller.settings.manualAddress,
    );
    if (address != null && address.trim().isNotEmpty) await controller.pairWithAddress(address);
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final controller = PingScope.of(context);
    final t = context.text;
    final discreet = controller.settings.discreet;
    final String subtitle;
    if (controller.isPhone) {
      subtitle = 'Ce téléphone : ${controller.settings.deviceName}';
    } else {
      final connected = controller.paired.where((p) => controller.connected(p.id)).map((p) => p.name).toList();
      subtitle = controller.paired.isEmpty
          ? 'Aucun téléphone appairé'
          : connected.isEmpty
          ? 'Téléphone déconnecté'
          : 'Relié à ${connected.join(', ')}';
    }
    return Row(
      children: [
        Image.asset('assets/branding/logo.png', height: 44, filterQuality: FilterQuality.medium),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('sPing', style: t.pageTitle),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
            ],
          ),
        ),
        if (!controller.isPhone) ...[
          SquareButton(
            icon: discreet ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            tooltip: discreet ? 'Mode discret activé : afficher le contenu' : 'Passer en mode discret',
            onPressed: () => controller.setDiscreet(!discreet),
          ),
          const SizedBox(width: 8),
        ],
        SquareButton(
          icon: Icons.tune_rounded,
          tooltip: 'Réglages',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
        ),
      ],
    );
  }
}

/// Un appareil appairé et l'état de la liaison.
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.name,
    required this.icon,
    required this.connected,
    required this.state,
    this.error = false,
  });

  final String name;
  final IconData icon;
  final bool connected;
  final String state;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Tile(
      child: Row(
        children: [
          IconBadge(icon: icon, tone: connected ? BadgeTone.accent : BadgeTone.neutral),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.itemTitle),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: StatusDot(color: connected ? c.success : (error ? c.danger : c.textFaint)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(state, style: t.secondary.copyWith(color: error ? c.danger : null)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Téléphone : appairage ouvert, en attente du PC.
class _WaitingForComputer extends StatelessWidget {
  const _WaitingForComputer();

  @override
  Widget build(BuildContext context) {
    final controller = PingScope.of(context);
    final c = context.colors;
    final t = context.text;
    final addresses = controller.addresses;
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.accent)),
              const SizedBox(width: 12),
              Expanded(child: Text('En attente du PC', style: t.itemTitle)),
            ],
          ),
          const SizedBox(height: 12),
          StepList([
            'Sur le PC, ouvrez sPing.',
            'Choisissez « ${controller.settings.deviceName} » dans la liste.',
            'Comparez le code affiché sur les deux appareils.',
          ]),
          if (addresses.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Adresse de ce téléphone : ${addresses.join(', ')}', style: t.caption),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(label: 'Annuler', compact: true, onPressed: controller.closePairing),
          ),
        ],
      ),
    );
  }
}

/// Téléphone : l'accès aux notifications n'est pas encore accordé.
class _AccessTile extends StatelessWidget {
  const _AccessTile();

  @override
  Widget build(BuildContext context) {
    final controller = PingScope.of(context);
    final t = context.text;
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.notifications_off_outlined, tone: BadgeTone.accent),
              const SizedBox(width: 12),
              Expanded(child: Text('Autorisez sPing à lire les notifications', style: t.itemTitle)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'C\'est ce qui permet de les afficher sur le PC et d\'y répondre. Dans le réglage qui s\'ouvre, '
            'activez sPing.',
            style: t.secondary,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Ouvrir le réglage',
              icon: Icons.open_in_new_rounded,
              kind: ButtonKind.primary,
              onPressed: controller.source.openAccessSettings,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Interrupteur grisé (« paramètre restreint ») ? Android bloque ce réglage pour les applications '
            'installées hors du Play Store : ouvrez « Infos sur l\'appli », touchez les trois points en haut à droite, puis '
            '« Autoriser les paramètres restreints », et revenez ici.',
            style: t.caption,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(label: 'Infos sur l\'appli', compact: true, onPressed: controller.source.openAppDetails),
          ),
        ],
      ),
    );
  }
}

/// Téléphone : l'économie de batterie risque d'endormir le relais.
class _BatteryTile extends StatelessWidget {
  const _BatteryTile();

  @override
  Widget build(BuildContext context) {
    final controller = PingScope.of(context);
    final t = context.text;
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.battery_alert_outlined),
              const SizedBox(width: 12),
              Expanded(child: Text('Laissez sPing travailler en veille', style: t.itemTitle)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'L\'économie d\'énergie de Samsung peut couper sPing écran éteint : les notifications n\'arrivent '
            'alors plus sur le PC. Autorisez sPing à ignorer l\'optimisation de la batterie. Si cela ne suffit '
            'pas : Paramètres › Applications › sPing › Batterie › « Non restreinte ».',
            style: t.secondary,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Autoriser',
              icon: Icons.open_in_new_rounded,
              onPressed: controller.source.openBatterySettings,
            ),
          ),
        ],
      ),
    );
  }
}

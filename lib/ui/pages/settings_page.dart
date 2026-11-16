import 'package:flutter/material.dart';

import '../../data/settings.dart';
import '../../models/device.dart';
import '../../state/ping_controller.dart';
import '../../state/ping_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/dialogs.dart';
import '../widgets/tiles.dart';
import 'page_scaffold.dart';

/// Réglages : apparence, nom, notifications, Windows, appareils appairés.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PingScope.of(context);
    final settings = controller.settings;
    final t = context.text;
    return AppPage(
      header: const PageHeader(title: 'Réglages'),
      children: [
        const NoticeArea(),
        const SectionTitle('Apparence'),
        Tile(
          child: SettingBlock(
            title: 'Thème',
            child: Segmented<AppThemeMode>(
              values: AppThemeMode.values,
              selected: settings.theme,
              labelOf: (mode) => switch (mode) {
                AppThemeMode.auto => 'Auto',
                AppThemeMode.light => 'Clair',
                AppThemeMode.dark => 'Sombre',
              },
              onSelected: controller.setTheme,
            ),
          ),
        ),
        const SectionTitle('Cet appareil'),
        Tile(
          child: SettingRow(
            title: 'Nom',
            subtitle: settings.deviceName,
            trailing: AppButton(
              label: 'Modifier',
              compact: true,
              onPressed: () async {
                final name = await askText(
                  context,
                  title: 'Nom de cet appareil',
                  hint: controller.isPhone ? 'Galaxy S25' : 'PC du bureau',
                  confirm: 'Enregistrer',
                  help: 'C\'est le nom que voit l\'autre appareil.',
                  initial: settings.deviceName,
                );
                if (name != null) await controller.rename(name);
              },
            ),
          ),
        ),
        if (controller.isPhone) ..._phone(context, controller) else ..._computer(context, controller),
        SectionTitle(controller.isPhone ? 'PC appairés' : 'Téléphones appairés'),
        if (controller.paired.isEmpty)
          Tile(child: Text('Aucun pour l\'instant.', style: t.secondary))
        else
          Tile(
            child: Column(
              children: [
                for (final device in controller.paired)
                  SettingRow(
                    title: device.name,
                    subtitle: 'Appairé le ${_date(device.pairedAt)}',
                    trailing: AppButton(
                      label: 'Oublier',
                      compact: true,
                      onPressed: () => _unpair(context, controller, device),
                    ),
                  ),
              ],
            ),
          ),
        const SectionTitle('Sécurité'),
        Tile(
          child: Text(
            'Seuls les appareils appairés échangent avec sPing : un appairage se fait une fois, en comparant '
            'le même code sur les deux écrans. Tout est ensuite chiffré (X25519 et AES-256-GCM) avec des clés '
            'qui ne quittent pas les appareils, et rien ne passe par Internet.',
            style: t.secondary,
          ),
        ),
        const SizedBox(height: Dim.sectionGap),
        Text('sPing 1.0 — de la famille sPack, avec sDash, sPhone et sDrop.', style: t.caption),
      ],
    );
  }

  List<Widget> _phone(BuildContext context, PingController controller) {
    final status = controller.phoneStatus;
    return [
      const SectionTitle('Autorisations'),
      Tile(
        child: Column(
          children: [
            SettingRow(
              title: 'Accès aux notifications',
              subtitle: status.access ? 'Accordé' : 'Non accordé : rien n\'est relayé',
              trailing: AppButton(label: 'Ouvrir', compact: true, onPressed: controller.source.openAccessSettings),
            ),
            SettingRow(
              title: 'Batterie',
              subtitle: status.batteryUnrestricted ? 'Non restreinte' : 'Optimisée : le relais peut s\'endormir',
              trailing: AppButton(label: 'Ouvrir', compact: true, onPressed: controller.source.openBatterySettings),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _computer(BuildContext context, PingController controller) {
    final settings = controller.settings;
    return [
      const SectionTitle('Notifications'),
      Tile(
        child: Column(
          children: [
            SettingRow(
              title: 'Notifications Windows',
              subtitle: 'Une notification Windows pour chaque notification du téléphone',
              trailing: AppSwitch(
                value: settings.desktopNotifications,
                label: 'Notifications Windows',
                onChanged: controller.setDesktopNotifications,
              ),
            ),
            SettingRow(
              title: 'Mode discret',
              subtitle: 'N\'affiche que « Nouveau message de Marie », jamais le contenu',
              trailing: AppSwitch(value: settings.discreet, label: 'Mode discret', onChanged: controller.setDiscreet),
            ),
          ],
        ),
      ),
      const SectionTitle('Windows'),
      Tile(
        child: Column(
          children: [
            SettingRow(
              title: 'Rester dans la zone de notification',
              subtitle: 'Fermer la fenêtre ne coupe pas sPing (icône près de l\'horloge)',
              trailing: AppSwitch(
                value: settings.keepInTray,
                label: 'Rester dans la zone de notification',
                onChanged: controller.setKeepInTray,
              ),
            ),
            const _StartupRow(),
          ],
        ),
      ),
      const SectionTitle('Connexion'),
      Tile(
        child: SettingRow(
          title: 'Adresse du téléphone',
          subtitle: settings.manualAddress.isEmpty ? 'Automatique (trouvé sur le Wi-Fi)' : settings.manualAddress,
          trailing: AppButton(
            label: 'Modifier',
            compact: true,
            onPressed: () async {
              final address = await askText(
                context,
                title: 'Adresse du téléphone',
                hint: '192.168.1.20',
                confirm: 'Enregistrer',
                help:
                    'À remplir seulement si le téléphone n\'est pas trouvé tout seul. Laissez vide pour '
                    'revenir à la recherche automatique.',
                initial: settings.manualAddress,
              );
              if (address != null) await controller.setManualAddress(address);
            },
          ),
        ),
      ),
    ];
  }

  Future<void> _unpair(BuildContext context, PingController controller, PairedDevice device) async {
    final other = controller.isPhone ? 'Ce PC' : 'Ce téléphone';
    final ok = await confirmAction(
      context,
      title: 'Oublier « ${device.name} » ?',
      text: '$other ne pourra plus se connecter. Pour le retrouver, il faudra l\'appairer de nouveau.',
      confirm: 'Oublier',
    );
    if (ok) await controller.unpair(device);
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Démarrer avec Windows : l'état est lu dans le registre.
class _StartupRow extends StatefulWidget {
  const _StartupRow();

  @override
  State<_StartupRow> createState() => _StartupRowState();
}

class _StartupRowState extends State<_StartupRow> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    PingScope.read(context).shell.launchAtStartup().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = PingScope.of(context).shell;
    return SettingRow(
      title: 'Démarrer avec Windows',
      subtitle: 'sPing se lance caché, dans la zone de notification',
      trailing: AppSwitch(
        value: _enabled ?? false,
        label: 'Démarrer avec Windows',
        onChanged: (value) async {
          setState(() => _enabled = value);
          await shell.setLaunchAtStartup(value);
        },
      ),
    );
  }
}

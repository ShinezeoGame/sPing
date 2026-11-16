import 'package:flutter/material.dart';

import '../../state/ping_controller.dart';
import '../../state/ping_scope.dart';
import '../theme.dart';
import 'controls.dart';
import 'tiles.dart';

/// Heure d'une notification : « 18:42 », « hier, 18:42 », « 14/11, 18:42 ».
String formatTime(DateTime time, {DateTime? now}) {
  now ??= DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final clock = '${two(time.hour)}:${two(time.minute)}';
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days == 0) return clock;
  if (days == 1) return 'hier, $clock';
  return '${two(time.day)}/${two(time.month)}, $clock';
}

/// Appairage en cours : le code à comparer et la décision. Tuile ambrée : c'est l'action
/// qui attend l'utilisateur.
class PairingTile extends StatelessWidget {
  const PairingTile({super.key, required this.pairing});

  final PairingView pairing;

  @override
  Widget build(BuildContext context) {
    final controller = PingScope.of(context);
    final c = context.colors;
    final t = context.text;
    final other = controller.isPhone ? 'le PC' : 'le téléphone';
    return Tile(
      active: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.verified_user_outlined, tone: BadgeTone.onActive),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Appairage avec « ${pairing.peer.name} »',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.itemTitle.copyWith(color: c.onActive),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Vérifiez que ce code s\'affiche aussi sur $other :', style: t.secondary.copyWith(color: c.onActive)),
          const SizedBox(height: 6),
          Semantics(
            label: 'Code de vérification ${pairing.code}',
            child: Text(pairing.code, style: t.pageTitle.copyWith(fontSize: 38, letterSpacing: 3, color: c.onActive)),
          ),
          const SizedBox(height: 12),
          if (pairing.answered)
            Row(
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.onActive)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Code accepté. Acceptez-le aussi sur $other.',
                    style: t.secondary.copyWith(color: c.onActive),
                  ),
                ),
              ],
            )
          else ...[
            if (pairing.remoteAccepted)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${controller.isPhone ? 'Le PC' : 'Le téléphone'} a déjà accepté.',
                  style: t.caption.copyWith(color: c.onActive),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  label: 'Le code est identique',
                  icon: Icons.check_rounded,
                  kind: ButtonKind.primary,
                  onActive: true,
                  onPressed: () => controller.decidePairing(true),
                ),
                AppButton(label: 'Refuser', onActive: true, onPressed: () => controller.decidePairing(false)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Codes différents ? Refusez : un autre appareil essaie peut-être de se faire passer pour $other.',
              style: t.caption.copyWith(color: c.onActive),
            ),
          ],
        ],
      ),
    );
  }
}

/// Icône d'une application du téléphone (reçue du téléphone), ou pastille neutre.
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.packageName, this.size = 28});

  final String packageName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = PingScope.of(context).iconFor(packageName);
    if (icon == null) return IconBadge(icon: Icons.notifications_none_rounded, size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.memory(
        icon,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => IconBadge(icon: Icons.notifications_none_rounded, size: size),
      ),
    );
  }
}

/// Une notification reçue sur le PC, avec ses réponses et le champ pour répondre.
class NotificationCard extends StatefulWidget {
  const NotificationCard({super.key, required this.entry});

  final NotificationEntry entry;

  @override
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard> {
  final _field = TextEditingController();
  bool _composing = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _send() {
    final text = _field.text.trim();
    if (text.isEmpty) return;
    PingScope.read(context).reply(widget.entry, text);
    _field.clear();
    setState(() => _composing = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = PingScope.of(context);
    final discreet = controller.settings.discreet;
    final entry = widget.entry;
    final n = entry.notification;
    final c = context.colors;
    final t = context.text;
    final where = n.conversation != null && n.conversation != n.from ? ' · ${n.conversation}' : '';
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(packageName: n.packageName),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${n.appName} · ${formatTime(n.time)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption,
                ),
              ),
              if (entry.removed) Text('Lue sur le téléphone', style: t.caption.copyWith(color: c.textFaint)),
            ],
          ),
          const SizedBox(height: 8),
          if (discreet)
            Text(n.discreetSummary, style: t.itemTitle)
          else ...[
            Text('${n.from}$where', maxLines: 2, overflow: TextOverflow.ellipsis, style: t.itemTitle),
            if (n.text.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(n.text, maxLines: 8, overflow: TextOverflow.ellipsis, style: t.body),
            ],
          ],
          for (final reply in entry.replies) _ReplyLine(reply: reply, discreet: discreet),
          if (entry.canReply) ...[
            const SizedBox(height: 10),
            if (_composing)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _field,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 4,
                      style: t.body,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(hintText: 'Répondre à ${n.from}…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SquareButton(icon: Icons.send_rounded, tooltip: 'Envoyer la réponse', onPressed: _send),
                ],
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  label: 'Répondre',
                  icon: Icons.reply_rounded,
                  compact: true,
                  onPressed: () => setState(() => _composing = true),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReplyLine extends StatelessWidget {
  const _ReplyLine({required this.reply, required this.discreet});

  final ReplyItem reply;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final (icon, color, status) = switch (reply.state) {
      ReplyState.sending => (Icons.schedule_rounded, c.textMuted, 'envoi…'),
      ReplyState.sent => (Icons.done_rounded, c.success, 'envoyée'),
      ReplyState.failed => (Icons.error_outline_rounded, c.danger, reply.error ?? 'échec'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Dim.buttonRadius)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    discreet ? 'Vous avez répondu' : 'Vous : ${reply.text}',
                    style: t.secondary.copyWith(color: c.text),
                  ),
                  Text(status, style: t.caption.copyWith(color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

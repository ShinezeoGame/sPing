import 'package:flutter/material.dart';

import '../theme.dart';
import 'controls.dart';

/// Cadre commun des boîtes de dialogue.
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Demande un texte ; renvoie `null` si l'utilisateur annule.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirm,
  String? help,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _InputDialog(title: title, hint: hint, confirm: confirm, help: help, initial: initial),
);

/// Demande confirmation d'une action ; renvoie vrai si l'utilisateur confirme.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String text,
  required String confirm,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _DialogFrame(
      children: [
        Text(title, style: context.text.sectionTitle),
        const SizedBox(height: 8),
        Text(text, style: context.text.secondary),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton(label: 'Annuler', compact: true, onPressed: () => Navigator.of(context).pop(false)),
            AppButton(
              label: confirm,
              kind: ButtonKind.primary,
              compact: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ],
    ),
  );
  return result ?? false;
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({required this.title, required this.hint, required this.confirm, this.help, this.initial = ''});

  final String title;
  final String hint;
  final String confirm;
  final String? help;
  final String initial;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  // Le champ appartient à la boîte : il vit jusqu'à la fin de son animation de fermeture.
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return _DialogFrame(
      children: [
        Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.sectionTitle),
        if (widget.help != null) ...[const SizedBox(height: 6), Text(widget.help!, style: t.secondary)],
        const SizedBox(height: 14),
        TextField(
          controller: _field,
          autofocus: true,
          style: t.body,
          onSubmitted: (value) => Navigator.of(context).pop(value),
          decoration: InputDecoration(hintText: widget.hint),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton(label: 'Annuler', compact: true, onPressed: () => Navigator.of(context).pop()),
            AppButton(
              label: widget.confirm,
              kind: ButtonKind.primary,
              compact: true,
              onPressed: () => Navigator.of(context).pop(_field.text),
            ),
          ],
        ),
      ],
    );
  }
}

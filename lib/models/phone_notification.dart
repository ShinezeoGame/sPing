import 'dart:convert';
import 'dart:typed_data';

/// Garde-fous sur le contenu d'une notification reçue.
abstract final class NotificationLimits {
  static const key = 512;
  static const label = 200;
  static const text = 4000;

  /// Icône de l'application (PNG), en octets.
  static const icon = 64 * 1024;
}

/// Une notification du téléphone, telle que le PC la reçoit.
class PhoneNotification {
  const PhoneNotification({
    required this.key,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.text,
    required this.time,
    this.conversation,
    this.sender,
    this.isMessage = false,
    this.canReply = false,
    this.icon,
  });

  /// Clé Android de la notification : elle désigne la notification pour y répondre, et
  /// une notification mise à jour garde la même clé.
  final String key;

  /// Paquet de l'application (« com.whatsapp »).
  final String packageName;

  /// Nom de l'application (« WhatsApp »).
  final String appName;

  /// Titre : souvent l'expéditeur pour une messagerie.
  final String title;
  final String text;
  final DateTime time;

  /// Nom du groupe pour un message de groupe.
  final String? conversation;

  /// Auteur du dernier message, quand l'application le précise.
  final String? sender;

  /// Message d'une personne (SMS, messagerie) plutôt que notification d'une application.
  final bool isMessage;

  /// La notification propose une réponse rapide.
  final bool canReply;

  /// Icône de l'application (PNG), envoyée une fois par application et par connexion.
  final Uint8List? icon;

  /// Qui a écrit : l'expéditeur, sinon le titre.
  String get from => (sender != null && sender!.isNotEmpty) ? sender! : title;

  /// Résumé sans contenu, pour le mode discret.
  String get discreetSummary {
    if (isMessage && from.isNotEmpty) {
      final where = conversation != null && conversation!.isNotEmpty && conversation != from
          ? ' dans $conversation'
          : '';
      return 'Nouveau message de $from$where';
    }
    return 'Nouvelle notification';
  }

  PhoneNotification copyWith({Uint8List? icon}) => PhoneNotification(
    key: key,
    packageName: packageName,
    appName: appName,
    title: title,
    text: text,
    time: time,
    conversation: conversation,
    sender: sender,
    isMessage: isMessage,
    canReply: canReply,
    icon: icon ?? this.icon,
  );

  /// Même contenu affiché (une mise à jour sans changement ne doit pas notifier deux fois).
  bool sameContent(PhoneNotification other) =>
      title == other.title && text == other.text && conversation == other.conversation && sender == other.sender;

  Map<String, dynamic> toJson({bool withIcon = true}) => {
    'cle': key,
    'paquet': packageName,
    'appli': appName,
    'titre': title,
    'texte': text,
    'heure': time.millisecondsSinceEpoch,
    if (conversation != null) 'conversation': conversation,
    if (sender != null) 'expediteur': sender,
    if (isMessage) 'message': true,
    if (canReply) 'repondre': true,
    if (withIcon && icon != null) 'icone': base64.encode(icon!),
  };

  /// Lit une notification reçue ; `null` si elle est invalide. Les textes trop longs sont
  /// tronqués plutôt que refusés.
  static PhoneNotification? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['cle'], packageName = json['paquet'], time = json['heure'];
    if (key is! String || key.isEmpty || key.length > NotificationLimits.key) return null;
    if (packageName is! String || packageName.isEmpty || packageName.length > NotificationLimits.label) return null;
    if (time is! int) return null;
    Uint8List? icon;
    final rawIcon = json['icone'];
    if (rawIcon is String && rawIcon.length <= NotificationLimits.icon * 4 ~/ 3 + 4) {
      try {
        icon = base64.decode(rawIcon);
      } on FormatException {
        icon = null;
      }
    }
    final appName = _text(json['appli'], NotificationLimits.label);
    return PhoneNotification(
      key: key,
      packageName: packageName,
      appName: appName.isEmpty ? packageName : appName,
      title: _text(json['titre'], NotificationLimits.label),
      text: _text(json['texte'], NotificationLimits.text, multiline: true),
      time: DateTime.fromMillisecondsSinceEpoch(time),
      conversation: _optional(json['conversation']),
      sender: _optional(json['expediteur']),
      isMessage: json['message'] == true,
      canReply: json['repondre'] == true,
      icon: icon,
    );
  }

  static String? _optional(Object? value) {
    final text = _text(value, NotificationLimits.label);
    return text.isEmpty ? null : text;
  }

  static String _text(Object? value, int max, {bool multiline = false}) {
    if (value is! String) return '';
    final pattern = multiline ? RegExp(r'[\x00-\x09\x0b-\x1f\x7f]') : RegExp(r'[\x00-\x1f\x7f]');
    final clean = value.replaceAll(pattern, ' ').trim();
    return clean.length > max ? '${clean.substring(0, max)}…' : clean;
  }
}

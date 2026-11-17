[← Retour à la présentation](../README.md)

# sPing : fonctionnement et développement

## Comment ça marche

sPing est une application [Flutter](https://flutter.dev), avec le même code pour Android
(le téléphone **relaie**) et Windows (le PC **reçoit**).

- **Android** : un `NotificationListenerService` (`SPingListener.kt`) lit les notifications
  et exécute les réponses (`RemoteInput` + `PendingIntent` de l'action « Répondre »). Il
  démarre et garde en marche un moteur Flutter unique (`SPingEngine.kt`), dans lequel tourne
  le code Dart : réseau, chiffrement, état. L'écran de sPing (`MainActivity`) se rattache à ce
  même moteur. Le relais fonctionne donc sans que l'écran soit ouvert, et le protocole n'est
  écrit qu'une fois, en Dart, testé de bout en bout.
- **Découverte** : le téléphone s'annonce toutes les 3 s (15 s quand un PC est connecté) par
  un message UDP en multidiffusion et en diffusion, port 47874. Le PC écoute. Le téléphone
  n'a pas besoin du verrou de multidiffusion d'Android, coûteux en batterie.
- **Liaison** : le PC se connecte au téléphone (TCP, port 47874), une connexion permanente
  dans les deux sens, avec un message de maintien toutes les 20 s. Messages encadrés
  (longueur sur 4 octets, 256 Kio au plus).

### Chiffrement

`lib/data/crypto/crypto.dart`, paquet [`cryptography`](https://pub.dev/packages/cryptography).

- **Identité** : une paire de clés X25519 par appareil, créée au premier lancement, gardée
  dans `flutter_secure_storage` (Keystore sur Android, DPAPI sur Windows), avec la liste
  des appareils appairés.
- **Appairage** (PC = initiateur, téléphone = répondeur) :
  1. PC → téléphone : identifiant, nom, **engagement** `SHA-256(clé publique du PC ‖ aléa)`.
  2. téléphone → PC : sa clé publique et son aléa.
  3. PC → téléphone : sa clé publique et son aléa ; le téléphone vérifie l'engagement.
  4. Chacun affiche `SHA-256("sPing code v1" ‖ clés ‖ aléas)` réduit à 6 chiffres.
  L'engagement empêche un intermédiaire de choisir ses clés après coup pour retomber sur le
  même code des deux côtés (il n'aurait qu'une chance sur un million). Le téléphone n'accepte
  de demande d'appairage que si l'utilisateur a ouvert « Appairer un PC » (3 minutes).
- **Session** : chaque connexion tire des clés éphémères ;
  `HKDF-SHA256(DH(durables) ‖ DH(éphémères), sel = aléas, info = clés)` donne deux clés
  AES-256-GCM, une par sens. Les messages sont numérotés (le numéro sert de nonce) et doivent
  arriver dans l'ordre : rejeu, suppression, déplacement ou modification coupent la liaison.
  Le premier message chiffré de chaque côté (« prêt ») prouve la possession de la clé
  durable : un appareil qui reprend l'identifiant d'un autre échoue avant d'avoir rien reçu.

### Messages (chiffrés, JSON)

| Sens | Type | Contenu |
| --- | --- | --- |
| téléphone → PC | `notif` | notification (`cle`, `paquet`, `appli`, `titre`, `texte`, `heure`, `conversation`, `expediteur`, `message`, `repondre`, `icone` une fois par application et par connexion), `nouvelle` |
| téléphone → PC | `retiree` | clé d'une notification retirée du téléphone |
| PC → téléphone | `repondre` | `id`, `cle`, `texte` |
| téléphone → PC | `resultat` | `id`, `ok`, `erreur` |
| les deux | `oubli` | l'appairage est supprimé |
| les deux | `ping` / `pong` | maintien de la liaison |

## Développement

Flutter 3.47. Pour Windows, Visual Studio avec la charge « Développement Desktop en C++ » ;
pour Android, le SDK Android et Java 17.

```
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

- `lib/state/ping_controller.dart` : tout l'état, pour les deux rôles.
- `lib/data/net/` : `discovery.dart` (annonces), `link.dart` (poignées de main, liaison
  chiffrée), `protocol.dart` (encadrement, limites).
- `lib/data/platform/` : `android_bridge.dart` ↔ `SPingEngine.kt` (canal `sping/android`),
  `desktop_shell.dart` ↔ `windows/runner/flutter_window.cpp` (canal `sping/fenetre` :
  zone de notification, fermeture qui cache la fenêtre, démarrage avec Windows) et
  notifications Windows avec champ de réponse (`flutter_local_notifications`).
- Le runner Windows n'autorise qu'une copie de sPing (`main.cpp`) ; lancé avec
  `--demarrage`, il démarre caché.
- `test/core_test.dart` fait dialoguer un téléphone et un PC réels sur des ports locaux
  (`test/support/harness.dart`) : appairage, refus, imposteurs, message falsifié, relais,
  mode discret, réponses, reconnexion, oubli. `test/app_test.dart` parcourt l'interface des
  deux rôles à trois tailles de fenêtre, en thème clair et sombre.
- Captures de la documentation : `SPING_CAPTURES=1 flutter test test/captures_test.dart`.
- `.github/workflows/build.yml` teste, compile l'APK et l'application Windows (qu'il lance
  pour de bon : fenêtre, écoute du réseau, copie unique, fermeture), et publie la version à
  chaque envoi sur `main` ou à la demande (bouton « Run workflow », case « Publier »).
- Clé de signature Android : secrets `ANDROID_KEYSTORE_BASE64` et `ANDROID_KEYSTORE_PASSWORD`
  du dépôt (clé propre à sPing, alias `sping`, en place depuis la version suivant la 1.0.4).
  Les mises à jour s'installent ainsi par-dessus l'ancienne version. Sans ces secrets, la CI
  signe avec une clé de debug.

### Ce qui n'est vérifié que par la compilation

Ni téléphone ni Windows dans l'environnement où sPing a été écrit : la partie Android
(`SPingListener.kt`, `SPingEngine.kt`, moteur partagé) et le runner Windows (icône de la zone
de notification, menu, démarrage avec Windows, notifications Windows avec réponse) ne sont
vérifiés que par la CI (compilation, et lancement de l'application Windows).

## Logo

sPing partage sa marque avec sDash, sPhone et sDrop : le même carré orange, le même trait
clair, et le même point ambre, toujours au même endroit. Seul le dessin change — ici une
cloche, centrée dans le carré ; le point ambre, posé ensuite dans l'angle, est la lumière de
la notification.

Les sources vectorielles sont dans `docs/logo/` ;
`tools/logo/generer_logo.py` les produit, `tools/logo/exporter.py` en tire les PNG et les
icônes Windows et Android. Les icônes de la famille sPack (`docs/logo/famille/`) sont
produites par le même générateur, puis rendues en PNG 192 × 192.

## Licences

Police [Outfit](https://github.com/Outfitio/Outfit-Fonts) sous licence SIL Open Font License 1.1
(`assets/fonts/OFL.txt`).

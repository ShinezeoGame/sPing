# sPing — notes pour Claude

- **Toujours communiquer avec l'utilisateur en français.** L'interface, les commentaires
  et les messages de commit sont aussi en français.
- Application Flutter pour **Android et Windows** (même code) : les notifications du
  téléphone de l'utilisateur (Samsung Galaxy S25, Android 15+) s'affichent en direct sur son
  PC Windows, sur le réseau local ; on peut y répondre depuis le PC ; mode discret. Le
  téléphone **relaie**, le PC **reçoit** (`DeviceRole`, déduit de la plateforme).
- Hors de cette version (choix de l'utilisateur, on pourra y revenir) : effacer une
  notification du téléphone depuis le PC, choisir les applications relayées.
- Architecture :
  - Android : `SPingListener.kt` (`NotificationListenerService` : lecture des notifications,
    réponses par `RemoteInput`) et `SPingEngine.kt` (moteur Flutter **unique**, démarré par le
    service, auquel `MainActivity` se rattache ; canal `sping/android`). Le code Dart tourne
    donc sans écran : pas de réseau ni de chiffrement en Kotlin.
  - `lib/data/net/` : `discovery.dart` (le téléphone s'annonce en UDP, le PC écoute),
    `link.dart` (poignées de main d'appairage et de session, liaison chiffrée),
    `protocol.dart` (encadrement, limites). Port 47874 (sDrop utilise 47873).
  - `lib/data/crypto/crypto.dart` : X25519, engagement + code à 6 chiffres, HKDF, AES-256-GCM.
  - `lib/data/platform/` : `android_bridge.dart`, `desktop_shell.dart` (notifications
    Windows avec champ de réponse via `flutter_local_notifications`, canal `sping/fenetre`
    vers `windows/runner/flutter_window.cpp` : icône de la zone de notification, fermeture qui
    cache la fenêtre, démarrage avec Windows dans la clé « Run »). `main.cpp` : copie unique,
    `--demarrage` = démarrage caché.
  - `lib/state/ping_controller.dart` : tout l'état, pour les deux rôles.
- Règles de sécurité à ne pas affaiblir : rien ne transite en clair après la poignée de
  main ; un appareil non appairé ne reçoit rien et ne peut rien envoyer ; l'identité repose
  sur la clé durable (jamais sur l'identifiant ou le nom annoncés) ; le téléphone n'accepte
  un appairage que fenêtre « Appairer un PC » ouverte ; le PC s'engage sur sa clé avant de la
  révéler ; messages numérotés et dans l'ordre ; clé privée et appairages dans le coffre
  (`secure_store.dart`), jamais dans les réglages ordinaires ; ce qui arrive du réseau est
  borné et nettoyé (`PhoneNotification.fromJson`, `Limits`). Le mode discret ne doit jamais
  laisser passer de contenu (ni fenêtre, ni notification Windows).
- Direction artistique : celle de **sPack** (sDash, sPhone, sDrop). Interface à plat (ni
  texture, ni flou, ni dégradé décoratif), tons chauds, thème clair et sombre, police Outfit.
  - Couleurs uniquement par rôle : `context.colors` / `context.text` (`lib/ui/theme.dart`),
    jamais de couleur en dur dans un widget.
  - Tuile ambrée = appairage à traiter ; ses boutons utilisent `AppButton(onActive: true)`.
  - Zones cliquables d'au moins 44 px (`AppButton` compact et `SquareButton` : 44).
  - Composants dans `lib/ui/widgets/` ; chaque page passe par `AppPage` (`page_scaffold.dart`).
  - Fenêtre 420 × 760 par défaut, 360 × 480 au minimum, calée à droite de l'écran : tout
    doit tenir sans débordement à ces tailles.
  - La police Outfit n'a pas tous les symboles (« ⋮ » s'affiche en carré) : vérifier les
    captures après avoir ajouté un caractère inhabituel.
- Vérifications avant de pousser : `flutter analyze` et `flutter test`. `test/core_test.dart`
  fait dialoguer un téléphone et un PC réels sur des ports locaux (`test/support/harness.dart`,
  fausse source de notifications) ; `test/app_test.dart` parcourt l'interface à trois tailles.
- Formatage : `dart format -l 120 lib test`.
- Captures de la documentation : `SPING_CAPTURES=1 flutter test test/captures_test.dart`.
- La CI (`.github/workflows/build.yml`) teste, compile l'APK (`sping-android`) et
  l'application Windows (`sping-windows` : installateur Inno Setup `tools/installer/sping.iss`
  et archive), lance l'exécutable Windows (fenêtre, écoute UDP 47874, copie unique,
  fermeture). La Release n'est publiée que sur `main` ou à la demande.
  Une modification de documentation seule (`*.md`, `docs/`, `tools/logo/`) ne relance pas la CI
  et ne publie donc pas de version.
  APK signé avec la clé personnelle de sPing (secrets du dépôt) : ne jamais la remplacer, sinon
  les mises à jour ne s'installent plus par-dessus.
- Jamais essayé sur un vrai téléphone ni sur un vrai Windows au moment de l'écriture : le
  Kotlin, le runner C++ et les notifications Windows ne sont vérifiés que par la CI. Le
  conteneur de développement n'a pas de SDK Android (dl.google.com y est bloqué).
- Logo : marque « s » de sPack. Même carré arrondi orange `#C2571A`, même trait clair à
  bouts ronds, dessin **centré** (une cloche pour sPing), **point ambre posé ensuite dans
  l'angle en haut à droite**, toujours au même endroit et de la même taille (ne jamais
  décaler le dessin pour lui faire de la place). Source : `tools/logo/generer_logo.py`
  (identique dans tous les dépôts de sPack, seule `APPLI_DU_DEPOT` diffère ; le recopier
  dans les autres après chaque modification) → `docs/logo/*.svg`,
  puis `tools/logo/exporter.py` → PNG, icône Windows et icônes Android. Le fond de l'icône
  adaptative Android est la couleur `sping_icon_background` (`values/colors.xml`).

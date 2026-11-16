[← Retour à la présentation](../README.md)

# Guide d'utilisation de sPing

## Installation

- **Téléphone** : téléchargez [`sping.apk`](https://github.com/ShinezeoGame/sPing/releases/latest/download/sping.apk),
  ouvrez-le et autorisez l'installation d'applications de sources inconnues si Android le
  demande. Android 11 au minimum.
- **PC** : téléchargez [`sping-setup.exe`](https://github.com/ShinezeoGame/sPing/releases/latest/download/sping-setup.exe)
  et lancez-le. L'application n'est pas signée : si Windows affiche « Windows a protégé
  votre ordinateur », cliquez sur « Informations complémentaires » puis « Exécuter quand
  même ». **Au premier lancement, autorisez sPing sur les réseaux privés** quand le
  pare-feu Windows le demande : sans cela, le PC n'entend pas le téléphone.
- **Version portable** : [`sping-windows.zip`](https://github.com/ShinezeoGame/sPing/releases/latest/download/sping-windows.zip),
  à décompresser, puis lancez `sping.exe`.

Les compilations de chaque branche sont aussi disponibles en artefacts **sping-android** et
**sping-windows** dans l'onglet **Actions** du dépôt.

## Premier réglage du téléphone

1. Ouvrez sPing et touchez **Ouvrir le réglage**, puis activez sPing dans « Accès aux
   notifications ».
2. **Interrupteur grisé ?** Android protège ce réglage pour les applications installées hors
   du Play Store (« paramètre restreint »). Touchez **Infos sur l'appli** dans sPing, puis
   les trois points en haut à droite, **Autoriser les paramètres restreints**, confirmez,
   et recommencez l'étape 1.
3. **Batterie** : pour que le relais continue écran éteint, touchez **Autoriser** quand sPing
   le propose (« ne pas optimiser la batterie »). Sur Samsung, vérifiez aussi :
   **Paramètres › Applications › sPing › Batterie › Non restreinte**, et que sPing n'est pas
   dans **Paramètres › Entretien de l'appareil › Batterie › Limites d'utilisation en
   arrière-plan › Applications en veille**.

## Appairage

À faire une seule fois, téléphone et PC sur le même Wi-Fi.

1. Sur le téléphone, touchez **Appairer un PC**. Il attend le PC pendant trois minutes.
2. Sur le PC, le téléphone apparaît sous **Téléphones visibles** : cliquez **Appairer**.
3. Un code à six chiffres s'affiche sur les deux écrans. **S'il est identique**, touchez
   **Le code est identique** des deux côtés. S'il est différent, refusez : un autre appareil
   essaie peut-être de s'interposer.

Le téléphone n'apparaît pas ? Le réseau bloque peut-être la découverte (Wi-Fi invité,
isolation des appareils sur certaines box). Cliquez **Saisir son adresse** sur le PC et
entrez l'adresse affichée sur le téléphone pendant l'appairage (par exemple `192.168.1.20`).
Cette adresse est retenue pour les connexions suivantes (modifiable dans **Réglages ›
Connexion**). Une box peut changer l'adresse du téléphone : dans ce cas, réservez-lui une
adresse fixe dans les réglages de la box.

## Au quotidien

- Chaque notification du téléphone s'affiche en **notification Windows** et dans la
  **fenêtre de sPing**. Une notification mise à jour remplace la précédente.
- **Répondre** : dans la notification Windows, écrivez dans le champ « Répondre… » puis
  **Envoyer** ; ou, dans la fenêtre, **Répondre** sous le message. sPing indique
  « envoyée » quand le téléphone a transmis la réponse à l'application.
- **Mode discret** : l'œil en haut de la fenêtre, ou le menu de l'icône près de l'horloge.
  Seul l'expéditeur s'affiche (« Nouveau message de Marie »).
- **Fermer la fenêtre** ne coupe pas sPing : il reste dans la zone de notification (icône
  près de l'horloge, parfois sous la flèche « ^ »). Clic : rouvrir. Clic droit : mode
  discret, quitter.
- **Effacer** vide la liste de la fenêtre ; rien n'est effacé sur le téléphone.
- **Démarrer avec Windows** : dans les réglages ; sPing se lance alors caché, près de
  l'horloge.
- **Sur le téléphone**, l'interrupteur **Relayer les notifications** met le relais en pause.
  **Envoyer une notification d'essai** vérifie que tout fonctionne.

## En cas de souci

| Symptôme | Solution |
| --- | --- |
| Le téléphone n'apparaît pas sur le PC | Même Wi-Fi des deux côtés ; sPing autorisé sur les **réseaux privés** dans le pare-feu Windows (Paramètres › Confidentialité et sécurité › Sécurité Windows › Pare-feu › Autoriser une application) ; sinon, **Saisir son adresse**. |
| « Le téléphone n'attend pas d'appairage » | Sur le téléphone, touchez d'abord **Appairer un PC**. |
| « Ce téléphone ne reconnaît plus ce PC » | Le téléphone a perdu l'appairage (réinstallation, données effacées). Sur le PC, **Réglages › Oublier**, puis appairez de nouveau. |
| Plus rien n'arrive quand l'écran du téléphone est éteint | Réglages de batterie ci-dessus ; vérifiez aussi que l'accès aux notifications est toujours accordé. |
| Rien n'arrive alors que le téléphone est « Connecté » | **Relayer les notifications** est peut-être en pause sur le téléphone. |
| Pas de notification Windows | **Réglages › Notifications Windows** dans sPing, et Paramètres › Système › Notifications de Windows (sPing autorisé, « Ne pas déranger » désactivé). |
| Une réponse échoue | La notification a peut-être été lue ou effacée sur le téléphone entre-temps. Certaines applications n'acceptent pas les réponses rapides venues d'ailleurs. |
| Un code de vérification (SMS) n'apparaît pas | Android 15 peut masquer aux applications comme sPing le contenu des notifications sensibles (codes à usage unique) : c'est une protection du système. |

## Confidentialité et sécurité

- **Rien ne sort de chez vous.** Le téléphone et le PC se parlent directement sur le réseau
  local ; aucun serveur, aucun compte.
- **Appairage vérifié.** Les deux appareils échangent leurs clés et affichent un code
  calculé à partir des deux clés : s'il est identique, personne ne s'est glissé entre eux.
- **Tout est chiffré.** Notifications et réponses sont chiffrées (AES-256-GCM) avec une clé
  propre à chaque connexion ; un message modifié, rejoué ou envoyé par un appareil non
  appairé est rejeté.
- **Clés protégées.** La clé de chaque appareil est gardée par le système (Keystore
  d'Android, chiffrement du compte Windows).
- **Sur le PC, sPing n'écrit pas les notifications sur le disque** : sa liste disparaît
  quand il se ferme. Les notifications Windows, elles, restent dans le centre de
  notifications de Windows jusqu'à ce que vous les effaciez ; le mode discret évite d'y
  laisser le contenu.

## Première version

sPing 1.0 a été construit et testé automatiquement (un téléphone et un PC simulés qui
dialoguent pour de bon, l'application Windows compilée et lancée), mais **pas encore essayé
sur un vrai téléphone** au moment de sa publication. Si quelque chose ne marche pas, la
partie Android (lecture des notifications, réponses) est la première à soupçonner.

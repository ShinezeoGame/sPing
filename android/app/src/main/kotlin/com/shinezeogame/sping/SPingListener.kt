package com.shinezeogame.sping

import android.app.ActivityOptions
import android.app.Notification
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.io.ByteArrayOutputStream

/**
 * Écoute des notifications du téléphone. Android démarre ce service quand l'utilisateur a
 * accordé « Accès aux notifications » à sPing et le relance s'il s'arrête. Il ne fait que
 * lire les notifications et exécuter les réponses : le réseau et le chiffrement sont en
 * Dart, dans le moteur partagé ([SPingEngine]) qu'il garde en marche.
 */
class SPingListener : NotificationListenerService() {
    /** Action « Répondre » de chaque notification qui en a une, par clé. */
    private val replyActions = object : LinkedHashMap<String, Notification.Action>() {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Notification.Action>?) = size > 300
    }

    /** Dernier contenu relayé par clé : une mise à jour identique n'est pas relayée deux fois. */
    private val lastContent = object : LinkedHashMap<String, String>() {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>?) = size > 300
    }

    /** Icônes des applications (PNG), calculées une fois. */
    private val icons = HashMap<String, ByteArray>()

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        SPingEngine.get(applicationContext)
        SPingEngine.send("etat", null)
    }

    override fun onListenerDisconnected() {
        instance = null
        SPingEngine.send("etat", null)
        // Demande à Android de reconnecter le service dès que possible.
        requestRebind(ComponentName(this, SPingListener::class.java))
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val map = describe(sbn) ?: return
        val content = "${map["titre"]}\u0000${map["texte"]}"
        if (lastContent[sbn.key] == content) return
        lastContent[sbn.key] = content
        SPingEngine.send("notification", map)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        replyActions.remove(sbn.key)
        lastContent.remove(sbn.key)
        SPingEngine.send("retiree", sbn.key)
    }

    /** Notifications présentes en ce moment, pour un PC qui vient de se connecter. */
    fun currentNotifications(): List<Map<String, Any?>> = try {
        activeNotifications?.mapNotNull { describe(it) } ?: emptyList()
    } catch (e: Exception) {
        emptyList()
    }

    /** Envoie [text] par l'action « Répondre » de la notification [key] ; renvoie l'erreur éventuelle. */
    fun reply(key: String, text: String): String? {
        val action = replyActions[key] ?: return "La notification n'est plus sur le téléphone, ou ne permet pas de répondre."
        val inputs = action.remoteInputs ?: return "Cette notification ne permet pas de répondre."
        return try {
            val results = Bundle()
            for (input in inputs) {
                if (input.allowFreeFormInput) results.putCharSequence(input.resultKey, text)
            }
            val intent = Intent().addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            RemoteInput.addResultsToIntent(inputs, intent, results)
            RemoteInput.setResultsSource(intent, RemoteInput.SOURCE_FREE_FORM_INPUT)
            if (Build.VERSION.SDK_INT >= 34) {
                @Suppress("DEPRECATION")
                val options = ActivityOptions.makeBasic()
                    .setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                    .toBundle()
                action.actionIntent.send(this, 0, intent, null, null, null, options)
            } else {
                action.actionIntent.send(this, 0, intent)
            }
            null
        } catch (e: Exception) {
            "L'application a refusé la réponse (${e.javaClass.simpleName})."
        }
    }

    /** Ce que le PC reçoit d'une notification ; `null` pour celles qu'on ne relaie pas. */
    private fun describe(sbn: StatusBarNotification): Map<String, Any?>? {
        val n = sbn.notification ?: return null
        if (sbn.packageName == packageName) return null
        // Résumés de groupe (chaque message a déjà sa notification) et notifications
        // permanentes (lecture de musique, appel en cours, service en arrière-plan).
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return null
        if (sbn.isOngoing || n.flags and Notification.FLAG_FOREGROUND_SERVICE != 0) return null
        val extras = n.extras ?: return null
        var title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        var text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))
            ?.toString()?.trim() ?: ""
        val conversation = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()?.trim()
        var sender: String? = null
        lastMessage(extras)?.let { message ->
            message.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { text = it }
            sender = message.senderPerson?.name?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        }
        if (title.isEmpty() && text.isEmpty()) return null
        if (title.isEmpty()) title = appName(sbn.packageName)

        val action = replyAction(n)
        if (action != null) replyActions[sbn.key] = action else replyActions.remove(sbn.key)
        val isMessage = n.category == Notification.CATEGORY_MESSAGE || extras.containsKey(Notification.EXTRA_MESSAGES)

        return mapOf(
            "cle" to sbn.key,
            "paquet" to sbn.packageName,
            "appli" to appName(sbn.packageName),
            "titre" to title,
            "texte" to text,
            "heure" to sbn.postTime,
            "conversation" to conversation?.takeIf { it.isNotEmpty() },
            "expediteur" to sender,
            "message" to isMessage,
            "repondre" to (action != null),
            "icone" to icon(sbn.packageName),
        )
    }

    private fun lastMessage(extras: Bundle): Notification.MessagingStyle.Message? = try {
        @Suppress("DEPRECATION")
        val array = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        if (array == null) null else Notification.MessagingStyle.Message.getMessagesFromBundleArray(array).lastOrNull()
    } catch (e: Exception) {
        null
    }

    /** L'action de réponse rapide : une action avec un champ de saisie libre. */
    private fun replyAction(n: Notification): Notification.Action? {
        fun usable(action: Notification.Action) = action.remoteInputs?.any { it.allowFreeFormInput } == true
        n.actions?.firstOrNull(::usable)?.let { return it }
        // Certaines messageries ne la proposent qu'aux montres.
        return try {
            Notification.WearableExtender(n).actions.firstOrNull(::usable)
        } catch (e: Exception) {
            null
        }
    }

    private fun appName(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }

    private fun icon(pkg: String): ByteArray? {
        icons[pkg]?.let { return it }
        return try {
            val drawable = packageManager.getApplicationIcon(pkg)
            val size = 72
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(Canvas(bitmap))
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray().also { icons[pkg] = it }
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        /** Le service, quand Android l'a démarré. */
        @Volatile
        var instance: SPingListener? = null
            private set
    }
}

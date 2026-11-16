package com.shinezeogame.sping

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Le moteur Flutter unique de sPing, partagé par le service d'écoute des notifications et
 * par l'écran. Le code Dart (réseau, chiffrement, état) y tourne une seule fois, que l'écran
 * soit ouvert ou non. Il dialogue avec ce code par le canal `sping/android`
 * (`lib/data/platform/android_bridge.dart`).
 */
object SPingEngine {
    private const val CACHE_ID = "sping"
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    /** Le moteur, créé et démarré au premier appel. À appeler sur le fil principal. */
    fun get(context: Context): FlutterEngine {
        engine?.let { return it }
        val app = context.applicationContext
        val created = FlutterEngine(app)
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val createdChannel = MethodChannel(created.dartExecutor.binaryMessenger, "sping/android")
        createdChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "etat" -> result.success(status(app))
                "nomAppareil" -> result.success(deviceName(app))
                "actives" -> result.success(SPingListener.instance?.currentNotifications() ?: emptyList<Any>())
                "repondre" -> {
                    val key = call.argument<String>("cle")
                    val text = call.argument<String>("texte")
                    val listener = SPingListener.instance
                    when {
                        key == null || text == null -> result.error("arguments", "Réponse incomplète.", null)
                        listener == null -> result.error("service", "L'accès aux notifications n'est pas actif.", null)
                        else -> {
                            val error = listener.reply(key, text)
                            if (error == null) result.success(null) else result.error("reponse", error, null)
                        }
                    }
                }
                "ouvrirAcces" -> {
                    openAccessSettings(app)
                    result.success(null)
                }
                "ouvrirBatterie" -> {
                    openBatterySettings(app)
                    result.success(null)
                }
                "ouvrirInfosAppli" -> {
                    start(app, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${app.packageName}")))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel = createdChannel
        created.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "main"),
        )
        FlutterEngineCache.getInstance().put(CACHE_ID, created)
        engine = created
        return created
    }

    /** Envoie un évènement au code Dart (sur le fil principal). */
    fun send(method: String, arguments: Any?) {
        main.post { channel?.invokeMethod(method, arguments) }
    }

    private fun status(context: Context): Map<String, Any> {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return mapOf(
            "acces" to accessGranted(context),
            "ecoute" to (SPingListener.instance != null),
            "batterieLibre" to power.isIgnoringBatteryOptimizations(context.packageName),
        )
    }

    fun accessGranted(context: Context): Boolean {
        val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: return false
        val mine = ComponentName(context, SPingListener::class.java)
        return enabled.split(":").any { ComponentName.unflattenFromString(it) == mine }
    }

    /** Nom donné au téléphone par son propriétaire, à défaut son modèle. */
    private fun deviceName(context: Context): String {
        val chosen = try {
            Settings.Global.getString(context.contentResolver, "device_name")
        } catch (e: Exception) {
            null
        }
        return if (chosen.isNullOrBlank()) Build.MODEL else chosen
    }

    private fun openAccessSettings(context: Context) {
        // Android 11+ : directement la page de sPing ; sinon la liste des applications.
        val detail = Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
            Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
            ComponentName(context, SPingListener::class.java).flattenToString(),
        )
        if (!start(context, detail)) start(context, Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
    }

    private fun openBatterySettings(context: Context) {
        val request = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${context.packageName}"))
        if (!start(context, request)) start(context, Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }

    private fun start(context: Context, intent: Intent): Boolean = try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }
}

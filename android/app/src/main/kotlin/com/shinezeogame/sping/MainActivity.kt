package com.shinezeogame.sping

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * L'écran de sPing. Il ne crée pas son propre moteur Flutter : il se rattache à celui de
 * [SPingEngine], que le service d'écoute des notifications fait tourner en permanence. Fermer
 * l'écran n'arrête donc pas le relais.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine = SPingEngine.get(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onResume() {
        super.onResume()
        // L'utilisateur revient peut-être des réglages d'Android : l'interface relit l'état.
        SPingEngine.send("etat", null)
    }
}

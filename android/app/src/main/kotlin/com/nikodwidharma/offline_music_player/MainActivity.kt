package com.nikodwidharma.offline_music_player

import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceFragmentActivity is the stable variant of the audio_service
// activity: the plain AudioServiceActivity crashed right after the
// notification was created on some devices (especially custom ROMs and
// skins such as XOS, MIUI). It extends FlutterFragmentActivity and needs a
// Theme.AppCompat descendant theme (see values/styles.xml).
class MainActivity : AudioServiceFragmentActivity() {
    private var widgetChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Register our in-app effect helpers (native equalizer, audio effect
        // session broadcasts, noisy listener). External plugins are added by
        // the generated plugin registrant; this one is ours.
        flutterEngine.plugins.add(SwaraAudioEffects())
        // Home screen widget: Dart pushes title/artist/playing on every
        // playback change, and the native side keeps the widget up to date.
        // The reverse direction is used for button taps coming back in.
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "swara/widget",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidget" -> {
                        val args = call.arguments as? Map<*, *>
                        val title = args?.get("title") as? String ?: "Swara"
                        val artist = args?.get("artist") as? String ?: ""
                        val playing = args?.get("playing") as? Boolean ?: false
                        SwaraWidgetProvider.updateAll(this@MainActivity, title, artist, playing)
                        result.success(null)
                    }
                    "getInitialAction" -> {
                        result.success(intent?.getStringExtra("swara_widget_action"))
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // Live bridge so a widget tap with the app already running reaches
        // Flutter without restarting anything.
        SwaraWidgetBridge.handler = { action ->
            widgetChannel?.invokeMethod("onWidgetAction", action)
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // Widget tapped while the activity is already up; forward the action.
        val action = intent.getStringExtra("swara_widget_action")
        if (action != null) {
            widgetChannel?.invokeMethod("onWidgetAction", action)
        }
    }

    override fun onDestroy() {
        SwaraWidgetBridge.handler = null
        super.onDestroy()
    }
}

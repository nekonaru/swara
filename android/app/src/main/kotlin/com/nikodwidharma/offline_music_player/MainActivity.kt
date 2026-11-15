package com.nikodwidharma.offline_music_player

import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
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
    // Widget rebinds touch RemoteViews and the widget manager; keep that
    // off the main looper.
    private val widgetExecutor =
        java.util.concurrent.Executors.newSingleThreadExecutor()
    // A widget tap that lands before the Flutter handler is armed is kept
    // here instead of being dropped; getInitialAction replays it.
    private var pendingWidgetAction: String? = null
    // Set by Flutter once its method-call handler is armed; widget taps
    // only forward directly after that (before it, they are stashed).
    private var flutterHandlerReady = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Android 12+ native splash (navy tile, brand glyph); a no-op on
        // older devices, which fall back to LaunchTheme's windowBackground.
        installSplashScreen()
        super.onCreate(savedInstanceState)
    }

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
                        val artPath = args?.get("artPath") as? String
                        widgetExecutor.execute {
                            SwaraWidgetProvider.updateAll(
                                this@MainActivity,
                                title,
                                artist,
                                playing,
                                artPath,
                            )
                        }
                        result.success(null)
                    }
                    "getInitialAction" -> {
                        // Replay the widget tap that cold-started the app;
                        // consume it so a restart never double-fires it.
                        // Also drains a tap that arrived before Flutter's
                        // handler was armed.
                        val action = pendingWidgetAction
                            ?: intent?.getStringExtra("swara_widget_action")
                        pendingWidgetAction = null
                        intent?.removeExtra("swara_widget_action")
                        result.success(action)
                    }
                    "notifyHandlerReady" -> {
                        // Flutter arms its Dart-side handler only at a
                        // post-frame callback; forward taps only after this.
                        flutterHandlerReady = true
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // If the app was launched from a widget tap while the process was
        // dead, the extra still exists; Flutter's getInitialAction replay
        // picks it up during engine startup. Taps that land while the engine
        // is running go through onNewIntent; Flutter arms forwarding via
        // notifyHandlerReady, and taps that arrive before it are stashed.
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // Widget tapped while the activity is already up; forward the action.
        // Remove the extra right away so a later cold start never replays it.
        val action = intent.getStringExtra("swara_widget_action")
        if (action != null) {
            intent.removeExtra("swara_widget_action")
            if (flutterHandlerReady) {
                widgetChannel?.invokeMethod("onWidgetAction", action)
            } else {
                // Flutter's handler is not armed yet (engine
                // still booting); keep the action instead of dropping it.
                pendingWidgetAction = action
            }
        }
    }

    override fun onDestroy() {
        widgetExecutor.shutdown()
        super.onDestroy()
    }
}

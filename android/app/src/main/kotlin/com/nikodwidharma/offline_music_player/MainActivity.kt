package com.nikodwidharma.offline_music_player

import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.RejectedExecutionException

// AudioServiceFragmentActivity is the stable variant of the audio_service
// activity: the plain AudioServiceActivity crashed right after the
// notification was created on some devices (especially custom ROMs and
// skins such as XOS, MIUI). It extends FlutterFragmentActivity and needs a
// Theme.AppCompat descendant theme (see values/styles.xml).
class MainActivity : AudioServiceFragmentActivity() {
    private var widgetChannel: MethodChannel? = null
    private var shareChannel: MethodChannel? = null
    private val pendingImportUris = ArrayList<String>()
    private var shareHandlerReady = false
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
        // Cross-fade the system splash over the Flutter frame instead of
        // cutting abruptly to it.
        installSplashScreen().setOnExitAnimationListener { splash ->
            splash.view.animate()
                .alpha(0f)
                .setDuration(120)
                .withEndAction { splash.remove() }
                .start()
        }
        super.onCreate(savedInstanceState)
        collectImportIntent(intent)
    }

    private fun collectImportIntent(intent: android.content.Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        val uris = ArrayList<android.net.Uri>()
        if (action == android.content.Intent.ACTION_VIEW) {
            intent.data?.let { uris.add(it) }
        } else if (action == android.content.Intent.ACTION_SEND ||
            action == android.content.Intent.ACTION_SEND_MULTIPLE
        ) {
            intent.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
            } ?: intent.data?.let { uris.add(it) }
            if (uris.isEmpty()) {
                @Suppress("DEPRECATION")
                val stream = intent.getParcelableExtra<android.net.Uri>(
                    android.content.Intent.EXTRA_STREAM)
                stream?.let { uris.add(it) }
            }
        }
        for (uri in uris) {
            // Import only reads the shared file; never take a write grant.
            val flags = intent.flags and
                android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
            if (flags != 0 && uri.scheme == "content") {
                try {
                    applicationContext.contentResolver.takePersistableUriPermission(uri, flags)
                } catch (_: Exception) {
                    // Some providers refuse persistable grants; the copy reads
                    // immediately, so this is not fatal.
                }
            }
            val value = uri.toString()
            if (!pendingImportUris.contains(value)) pendingImportUris.add(value)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Register our in-app effect helpers (native equalizer, audio effect
        // session broadcasts, noisy listener). External plugins are added by
        // the generated plugin registrant; this one is ours.
        flutterEngine.plugins.add(SwaraAudioEffects())
        flutterEngine.plugins.add(SwaraFileRename())
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
                        val positionMs = (args?.get("positionMs") as? Number)?.toLong() ?: 0L
                        val nextTitle = args?.get("nextTitle") as? String ?: ""
                        // Caching and rebinds run on a background thread; a
                        // tap that lands after onDestroy must not crash the
                        // app, it is simply dropped (the widget will refresh
                        // on the next onUpdate).
                        try {
                            widgetExecutor.execute {
                                SwaraWidgetProvider.updateAll(
                                    applicationContext,
                                    title,
                                    artist,
                                    playing,
                                    artPath,
                                    positionMs,
                                    nextTitle,
                                )
                            }
                        } catch (_: RejectedExecutionException) {
                            // Executor is shut down (activity is finishing).
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
        // Audio files shared from other apps are copied into Music/Swara Imports.
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "swara/share_import",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialImport" -> {
                        val uris = ArrayList(pendingImportUris)
                        pendingImportUris.clear()
                        result.success(uris)
                    }
                    "notifyHandlerReady" -> {
                        shareHandlerReady = true
                        if (pendingImportUris.isNotEmpty()) {
                            val uris = ArrayList(pendingImportUris)
                            pendingImportUris.clear()
                            invokeMethod("onImportUris", uris)
                        }
                        result.success(null)
                    }
                    "importAudioFiles" -> {
                        @Suppress("UNCHECKED_CAST")
                        val uris = (call.arguments as? List<String>) ?: emptyList()
                        val parsed = uris.mapNotNull {
                            try { android.net.Uri.parse(it) } catch (_: Exception) { null }
                        }
                        SwaraAudioImport.import(applicationContext, parsed) { data ->
                            result.success(data)
                        }
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
        collectImportIntent(intent)
        if (shareHandlerReady && pendingImportUris.isNotEmpty()) {
            val uris = ArrayList(pendingImportUris)
            pendingImportUris.clear()
            shareChannel?.invokeMethod("onImportUris", uris)
        }
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
                // The first pre-ready tap wins; a second tap overwriting it
                // would silently discard the user's first intent.
                if (pendingWidgetAction == null) {
                    pendingWidgetAction = action
                }
            }
        }
    }

    override fun onDestroy() {
        widgetExecutor.shutdown()
        super.onDestroy()
    }
}

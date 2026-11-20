package com.nikodwidharma.offline_music_player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.os.Build
import java.io.File
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Native audio effect helpers for Swara. One MethodChannel carries every call:
//  - Open/close the audio effect control session, so system effect apps
//    (Wavelet, OEM equalizers) can attach to our audio session while music
//    plays. External effect apps (system Music FX, Wavelet) attach the same way.
//  - A real in-process equalizer (android.media.audiofx.Equalizer), so the
//    in-app 5-band curve is applied by the system DSP, not drawn on screen.
//  - Opening the system equalizer panel for this audio session.
//  - A noisy broadcast listener (ACTION_AUDIO_BECOMING_NOISY) so unplugging a
//    headset pauses playback instead of blasting the speakers.
class SwaraAudioEffects : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var appContext: Context? = null
    private var equalizer: Equalizer? = null
    private var equalizerSessionId: Int = -1
    private var loudness: LoudnessEnhancer? = null
    private var loudnessSessionId: Int = -1
    private var noisyReceiver: BroadcastReceiver? = null
    // Streaming a large update APK through SHA-256 must not run on the
    // platform main looper; keep it on a small background pool.
    private val digestExecutor =
        java.util.concurrent.Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "swara/audio_effects")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        releaseEqualizer()
        releaseLoudness()
        unregisterNoisy()
        digestExecutor.shutdown()
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Broadcast that an audio effect control session opened. External
            // effect apps (Wavelet and similar) attach to the session for the
            // duration of playback. Open on play, close on pause and stop.
            "openAudioEffectSession" -> {
                val sessionId = call.argument<Int>("sessionId")
                broadcastAudioEffectEvent(
                    AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION,
                    sessionId,
                )
                result.success(null)
            }
            "closeAudioEffectSession" -> {
                val sessionId = call.argument<Int>("sessionId")
                broadcastAudioEffectEvent(
                    AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION,
                    sessionId,
                )
                result.success(null)
            }
            // Attach the system DSP equalizer to this audio session. Reuses
            // the live effect if the session did not change.
            "attachEqualizer" -> {
                val sessionId = call.argument<Int>("sessionId") ?: -1
                result.success(attachEqualizer(sessionId))
            }
            "releaseEqualizer" -> {
                releaseEqualizer()
                result.success(null)
            }
            // Native loudness normalization: a real LoudnessEnhancer DSP on
            // the audio session, lifting quiet passages by a fixed, gentle
            // amount. The effect is recreated only when the session changes.
            "attachLoudness" -> {
                val sessionId = call.argument<Int>("sessionId") ?: -1
                result.success(attachLoudness(sessionId))
            }
            "releaseLoudness" -> {
                releaseLoudness()
                result.success(null)
            }
            "setLoudnessEnabled" -> {
                try {
                    loudness?.enabled = call.argument<Boolean>("enabled") ?: false
                    result.success(null)
                } catch (e: Exception) {
                    result.error("loudness_enable_failed", e.message, null)
                }
            }
            // Read the bands the device reports for the effect.
            "getEqualizerInfo" -> {
                val effect = equalizer
                if (effect == null) {
                    result.success(null)
                    return
                }
                try {
                    val bands = effect.numberOfBands.toInt()
                    val range = effect.bandLevelRange
                    val centerFreqs = mutableListOf<Int>()
                    for (band in 0 until bands) {
                        centerFreqs.add(effect.getCenterFreq(band.toShort()))
                    }
                    result.success(
                        mapOf(
                            "bands" to bands,
                            "minLevelMilliBels" to range[0].toInt(),
                            "maxLevelMilliBels" to range[1].toInt(),
                            "centerFreqsMilliHz" to centerFreqs,
                        ),
                    )
                } catch (e: Exception) {
                    result.success(null)
                }
            }
            "setEqualizerEnabled" -> {
                try {
                    equalizer?.enabled = call.argument<Boolean>("enabled") ?: false
                    result.success(null)
                } catch (e: Exception) {
                    result.error("eq_enable_failed", e.message, null)
                }
            }
            // band in [0, numberOfBands), gain in millibels.
            "setBandLevel" -> {
                val band = call.argument<Int>("band") ?: -1
                val milliBels = call.argument<Int>("milliBels") ?: 0
                try {
                    val effect = equalizer
                    if (effect == null) {
                        result.error("eq_not_attached", "Equalizer is not attached.", null)
                        return
                    }
                    val clamped = milliBels.coerceIn(
                        effect.bandLevelRange[0].toInt(),
                        effect.bandLevelRange[1].toInt(),
                    ).toShort()
                    effect.setBandLevel(band.toShort(), clamped)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("eq_band_failed", e.message, null)
                }
            }
            // Open the system equalizer UI for this audio session, the standard flow
            // does, so users with Wavelet or an OEM equalizer get its panel.
            "openEqualizerPanel" -> {
                val sessionId = call.argument<Int>("sessionId") ?: -1
                result.success(openEqualizerPanel(sessionId))
            }
            // Start listening for ACTION_AUDIO_BECOMING_NOISY (headset
            // unplugged, bluetooth route lost). Every event is pushed back
            // to Dart as "onAudioBecomingNoisy".
            "registerNoisyListener" -> {
                registerNoisy()
                result.success(null)
            }
            "unregisterNoisyListener" -> {
                unregisterNoisy()
                result.success(null)
            }
            // The device's supported ABIs, so the updater can pick the right
            // split APK (arm64-v8a on modern phones, armeabi-v7a on older).
            "deviceAbi" -> {
                val abis = mutableListOf<String>()
                abis.addAll(Build.SUPPORTED_64_BIT_ABIS)
                abis.addAll(Build.SUPPORTED_32_BIT_ABIS)
                result.success(abis)
            }
            // SHA-256 of a local file, streamed. Used to verify an update
            // APK against the digest GitHub publishes for the asset before
            // handing it to the installer. Runs on the background digest
            // executor; the result answers asynchronously.
            "sha256" -> {
                val path = call.argument<String>("path")
                digestExecutor.execute {
                    try {
                        result.success(sha256(path))
                    } catch (_: Exception) {
                        result.success(null)
                    }
                }
            }
            // Hand the downloaded update APK to the system package installer.
            // Installing an APK signed with the same key over the current
            // install is an in-place upgrade. Returns "ok" when the installer
            // is running, "no_permission" when the user must first allow
            // installing unknown apps for this package, "error" otherwise.
            "installApk" -> {
                val path = call.argument<String>("path")
                result.success(installApk(path))
            }
            else -> result.notImplemented()
        }
    }

    // Stream a file through SHA-256 and return the hex digest, or null when
    // the file cannot be read. Computed here so the Dart side does not need
    // a hashing dependency for a single integrity check.
    private fun sha256(path: String?): String? {
        if (path.isNullOrEmpty()) return null
        return try {
            val md = java.security.MessageDigest.getInstance("SHA-256")
            File(path).inputStream().use { input ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    md.update(buffer, 0, read)
                }
            }
            md.digest().joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            null
        }
    }

    private fun broadcastAudioEffectEvent(action: String, sessionId: Int?) {
        val context = appContext ?: return
        val intent = Intent(action)
            .putExtra(AudioEffect.EXTRA_PACKAGE_NAME, context.packageName)
        if (sessionId != null && sessionId > 0) {
            intent.putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
            intent.putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
        }
        try {
            context.sendBroadcast(intent)
        } catch (_: Exception) {
            // A missing receiver is fine.
        }
    }

    private fun attachEqualizer(sessionId: Int): Boolean {
        if (sessionId <= 0) return false
        if (equalizer != null && equalizerSessionId == sessionId) {
            return true
        }
        releaseEqualizer()
        return try {
            val effect = Equalizer(0, sessionId)
            effect.enabled = true
            equalizer = effect
            equalizerSessionId = sessionId
            true
        } catch (e: Exception) {
            equalizer = null
            equalizerSessionId = -1
            false
        }
    }

    private fun releaseEqualizer() {
        try {
            equalizer?.enabled = false
            equalizer?.release()
        } catch (_: Exception) {
            // Best effort, the effect is gone either way.
        } finally {
            equalizer = null
            equalizerSessionId = -1
        }
    }

    private fun attachLoudness(sessionId: Int): Boolean {
        if (sessionId <= 0) return false
        if (loudness != null && loudnessSessionId == sessionId) return true
        releaseLoudness()
        return try {
            val effect = LoudnessEnhancer(0, sessionId)
            // +6 dB of target gain, applied to quiet content only.
            effect.setTargetGain(600)
            effect.enabled = true
            loudness = effect
            loudnessSessionId = sessionId
            true
        } catch (e: Exception) {
            loudness = null
            loudnessSessionId = -1
            false
        }
    }

    private fun releaseLoudness() {
        try {
            loudness?.enabled = false
            loudness?.release()
        } catch (_: Exception) {
            // Best effort; the native effect is released on detach as well.
        } finally {
            loudness = null
            loudnessSessionId = -1
        }
    }

    private fun openEqualizerPanel(sessionId: Int): Boolean {
        val context = appContext ?: return false
        return try {
            val intent = Intent(AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL)
                .putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
                .putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
                .putExtra(AudioEffect.EXTRA_PACKAGE_NAME, context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun registerNoisy() {
        val context = appContext ?: return
        if (noisyReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                try {
                    channel.invokeMethod("onAudioBecomingNoisy", null)
                } catch (_: Exception) {
                    // The engine is gone; nothing to notify.
                }
            }
        }
        if (Build.VERSION.SDK_INT >= 33) {
            // Android 13+ requires receivers to declare their export scope;
            // this one only hears ACTION_AUDIO_BECOMING_NOISY, so restrict it
            // to system broadcasts.
            context.registerReceiver(
                receiver,
                IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            context.registerReceiver(receiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        }
        noisyReceiver = receiver
    }

    private fun unregisterNoisy() {
        val receiver = noisyReceiver ?: return
        noisyReceiver = null
        val context = appContext ?: return
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {
            // Already unregistered; nothing to do.
        }
    }

    // Hand the downloaded update APK to the system package installer. On
    // Android 8+ the user must first grant "Install unknown apps" to Swara;
    // when it is not granted we send them to the matching Settings page and
    // report "no_permission" so the UI can say so. Returns "ok" when the
    // installer intent was launched, "no_permission" when the grant screen
    // was opened, or "error" otherwise.
    private fun installApk(path: String?): String {
        val context = appContext ?: return "error"
        if (path.isNullOrEmpty()) return "error"
        val file = File(path)
        if (!file.exists()) return "error"
        // On Android 8+ installing an unknown-source package requires the
        // per-app "Install unknown apps" special access; the manifest alone
        // is not enough.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()) {
            try {
                val intent = Intent(
                    android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    android.net.Uri.parse("package:${context.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
            } catch (_: Exception) {
                return "error"
            }
            return "no_permission"
        }
        return try {
            val uri = androidx.core.content.FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            "ok"
        } catch (_: Exception) {
            "error"
        }
    }
}

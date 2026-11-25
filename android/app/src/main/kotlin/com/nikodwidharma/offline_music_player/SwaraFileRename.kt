package com.nikodwidharma.offline_music_player

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.media.MediaScannerConnection
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Renames the actual music file, not just our database title.
 *
 * API 26-29 uses File.renameTo with WRITE_EXTERNAL_STORAGE. API 30+ uses
 * MediaStore.createWriteRequest so the user grants write access to that one
 * item, then updates DISPLAY_NAME. SAF cannot rename in place, so it is not
 * used here.
 */
class SwaraFileRename : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private val executor = Executors.newSingleThreadExecutor()

    private var pendingResult: MethodChannel.Result? = null
    private var pendingId: Int? = null
    private var pendingNewName: String? = null
    private var pendingOldPath: String? = null
    private var pendingUri: Uri? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.activity = binding.activity
        this.binding = binding
        binding.addActivityResultListener(this::onActivityResult)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        binding?.removeActivityResultListener(this::onActivityResult)
        failPending("activity_gone")
        activity = null
        binding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        this.activity = binding.activity
        this.binding = binding
        binding.addActivityResultListener(this::onActivityResult)
    }

    override fun onDetachedFromActivity() {
        binding?.removeActivityResultListener(this::onActivityResult)
        failPending("activity_gone")
        activity = null
        binding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "getSdkInt") {
            result.success(Build.VERSION.SDK_INT)
            return
        }
        if (call.method != "rename") {
            result.notImplemented()
            return
        }
        val id = call.argument<Int>("id")
        val oldPath = call.argument<String>("oldPath")
        val newDisplayName = call.argument<String>("newDisplayName")?.trim()
        if (id == null || oldPath.isNullOrEmpty() || newDisplayName.isNullOrEmpty()) {
            result.error("failed", "Missing rename arguments", null)
            return
        }
        val appContext = context
        if (appContext == null) {
            result.error("failed", "Plugin not attached", null)
            return
        }
        if (newDisplayName.contains('/') || newDisplayName.contains('\\')) {
            result.error("failed", "Invalid display name", null)
            return
        }

        val oldFile = File(oldPath)
        val parent = oldFile.parent
        if (parent.isNullOrEmpty()) {
            result.error("failed", "Missing parent directory", null)
            return
        }
        val newPath = File(parent, newDisplayName).absolutePath
        if (newPath == oldPath) {
            success(result, id, newPath, newDisplayName)
            return
        }
        if (File(newPath).exists()) {
            result.error("target_exists", "Target file already exists", null)
            return
        }

        // createWriteRequest exists from API 30. API 29 uses the legacy
        // filesystem path with requestLegacyExternalStorage enabled.
        if (Build.VERSION.SDK_INT >= 30) {
            requestScopedWrite(appContext, id, oldPath, newPath, newDisplayName, result)
        } else {
            executor.execute {
                if (ContextCompat.checkSelfPermission(
                        appContext,
                        android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    result.error("no_permission", "Write permission missing", null)
                    return@execute
                }
                val renamed = oldFile.renameTo(File(newPath))
                if (!renamed) {
                    result.error("failed", "File rename failed", null)
                    return@execute
                }
                MediaScannerConnection.scanFile(
                    appContext,
                    arrayOf(oldPath, newPath),
                    null,
                    null,
                )
                appContext.mainExecutor.execute { success(result, id, newPath, newDisplayName) }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun requestScopedWrite(
        context: Context,
        id: Int,
        oldPath: String,
        newPath: String,
        newDisplayName: String,
        result: MethodChannel.Result,
    ) {
        val resolver = context.contentResolver
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME)
        val selection = "${MediaStore.MediaColumns.DATA}=?"
        val cursor = resolver.query(collection, projection, selection, arrayOf(oldPath), null)
        val uri: Uri? = cursor?.use { c ->
            if (c.moveToFirst()) {
                val column = c.getColumnIndex(MediaStore.MediaColumns._ID)
                if (column >= 0) {
                    MediaStore.Audio.Media.getContentUriForPath(oldPath)
                        ?.buildUpon()
                        ?.appendEncodedPath(c.getLong(column).toString())
                        ?.build()
                } else null
            } else null
        }
        if (uri == null) {
            result.error("not_found", "MediaStore row not found", null)
            return
        }
        val request = try {
            MediaStore.createWriteRequest(resolver, listOf(uri))
        } catch (e: Exception) {
            result.error("failed", e.message ?: "Could not request write access", null)
            return
        }
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("activity_gone", "No activity to show consent", null)
            return
        }
        pendingResult = result
        pendingId = id
        pendingNewName = newDisplayName
        pendingOldPath = oldPath
        pendingUri = uri
        try {
            currentActivity.startIntentSenderForResult(
                request.intentSender,
                REQUEST_WRITE,
                null,
                0,
                0,
                0,
                null,
            )
        } catch (e: Exception) {
            clearPending()
            result.error("failed", e.message ?: "Could not start consent", null)
        }
    }

    private fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_WRITE) return false
        val result = pendingResult ?: return true
        val id = pendingId
        val newName = pendingNewName
        val oldPath = pendingOldPath
        val targetUri = pendingUri
        clearPending()
        if (resultCode != Activity.RESULT_OK || id == null || newName.isNullOrEmpty() || oldPath.isNullOrEmpty()) {
            result.error("consent_denied", "Write consent denied", null)
            return true
        }
        val appContext = context
        if (appContext == null) {
            result.error("failed", "Plugin not attached", null)
            return true
        }
        executor.execute {
            val values = android.content.ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, newName)
                put(MediaStore.Audio.Media.TITLE, newName.substringBeforeLast('.'))
            }
            val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            @Suppress("DEPRECATION")
            val selection = "${MediaStore.MediaColumns.DATA}=?"
            val updated = if (targetUri != null) {
                appContext.contentResolver.update(targetUri, values, null, null)
            } else {
                appContext.contentResolver.update(
                    collection,
                    values,
                    selection,
                    arrayOf(oldPath),
                )
            }
            if (updated <= 0) {
                result.error("failed", "MediaStore update failed", null)
                return@execute
            }
            @Suppress("DEPRECATION")
            val cursor = appContext.contentResolver.query(
                collection,
                arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                selection,
                arrayOf(oldPath),
                null,
            )
            val actualName = cursor?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                    if (idx >= 0) c.getString(idx) else newName
                } else newName
            } ?: newName
            val parent = File(oldPath).parent ?: ""
            val newPath = File(parent, actualName).absolutePath
            appContext.mainExecutor.execute { success(result, id, newPath, actualName) }
        }
        return true
    }

    private fun failPending(code: String) {
        pendingResult?.error(code, "Rename interrupted", null)
        clearPending()
    }

    private fun clearPending() {
        pendingResult = null
        pendingId = null
        pendingNewName = null
        pendingOldPath = null
        pendingUri = null
    }

    private fun success(result: MethodChannel.Result, id: Int, path: String, displayName: String) {
        result.success(
            mapOf(
                "id" to id,
                "path" to path,
                "displayName" to displayName,
            )
        )
    }

    companion object {
        const val CHANNEL = "swara/file_rename"
        const val REQUEST_WRITE = 4102
    }
}

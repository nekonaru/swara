package com.nikodwidharma.offline_music_player

import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/** Copies audio shared from other apps into the public Music/Swara Imports
 * folder so the normal library scanner can index it. No new permission:
 * the share grant provides read access and MediaStore provides the write. */
object SwaraAudioImport {
    private const val BUFFER = 8192
    private val executor = Executors.newSingleThreadExecutor()
    private val extensions = Regex("(?i)\\.(mp3|flac|wav|m4a|ogg|opus|aac|wma)$")
    private val swaraDir =
        Environment.DIRECTORY_MUSIC + "/Swara Imports"

    fun import(context: Context, uris: List<Uri>, callback: (Map<String, Any>) -> Unit) {
        executor.execute {
            var imported = 0
            var skipped = 0
            var failed = 0
            val paths = ArrayList<String>()
            for (uri in uris) {
                try {
                    val name = displayName(context, uri)
                    if (name == null || !extensions.containsMatchIn(name)) {
                        failed++
                        continue
                    }
                    val path = copy(context, uri, name)
                    if (path == null) {
                        failed++
                    } else {
                        imported++
                        paths.add(path)
                    }
                } catch (_: Exception) {
                    failed++
                }
            }
            context.mainExecutor.execute {
                callback(
                    mapOf(
                        "imported" to imported,
                        "skipped" to skipped,
                        "failed" to failed,
                        "paths" to paths,
                    )
                )
            }
        }
    }

    private fun displayName(context: Context, uri: Uri): String? {
        val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
        val cursor = context.contentResolver.query(uri, projection, null, null, null)
        val raw = cursor?.use { c ->
            if (c.moveToFirst()) {
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) c.getString(idx) else null
            } else null
        } ?: uri.lastPathSegment
        if (raw.isNullOrEmpty()) return null
        return raw.replace("/", "_").replace("\\", "_").trim()
    }

    private fun copy(context: Context, uri: Uri, name: String): String? {
        if (Build.VERSION.SDK_INT >= 29) {
            val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val projection = arrayOf(MediaStore.MediaColumns._ID)
            val selection = "${MediaStore.MediaColumns.DISPLAY_NAME}=?"
            val existing = context.contentResolver.query(
                collection, projection, selection, arrayOf(name), null)
            val found = existing?.use { it.count > 0 } == true
            if (found) return null
            val values = android.content.ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeOf(name))
                put(MediaStore.MediaColumns.RELATIVE_PATH, swaraDir)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val target = context.contentResolver.insert(collection, values)
                ?: return null
            try {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    context.contentResolver.openOutputStream(target)?.use { output ->
                        val buffer = ByteArray(BUFFER)
                        while (true) {
                            val read = input.read(buffer)
                            if (read <= 0) break
                            output.write(buffer, 0, read)
                        }
                        output.flush()
                    }
                } ?: throw IllegalStateException("Could not open source")
                val done = android.content.ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                context.contentResolver.update(target, done, null, null)
                return target.toString()
            } catch (e: Exception) {
                context.contentResolver.delete(target, null, null)
                throw e
            }
        }
        // API 26-28: WRITE_EXTERNAL_STORAGE is already declared.
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            "Swara Imports",
        )
        if (!dir.exists()) dir.mkdirs()
        val target = File(dir, name)
        if (target.exists()) return null
        context.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(target).use { output ->
                val buffer = ByteArray(BUFFER)
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    output.write(buffer, 0, read)
                }
                output.flush()
            }
        } ?: throw IllegalStateException("Could not open source")
        MediaScannerConnection.scanFile(
            context, arrayOf(target.absolutePath), arrayOf(mimeOf(name)), null)
        return target.absolutePath
    }

    private fun mimeOf(name: String): String = when {
        name.endsWith(".flac", true) -> "audio/flac"
        name.endsWith(".wav", true) -> "audio/wav"
        name.endsWith(".m4a", true) -> "audio/mp4"
        name.endsWith(".ogg", true) || name.endsWith(".opus", true) -> "audio/ogg"
        name.endsWith(".aac", true) -> "audio/aac"
        name.endsWith(".wma", true) -> "audio/x-ms-wma"
        else -> "audio/mpeg"
    }
}

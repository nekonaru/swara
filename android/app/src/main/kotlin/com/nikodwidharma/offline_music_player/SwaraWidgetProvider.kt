package com.nikodwidharma.offline_music_player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.widget.RemoteViews

// Home screen widget showing the current song with prev / play / next.
// The app pushes state to it on every track or playing change through
// SwaraWidgetProvider.updateAll. Button taps launch MainActivity carrying
// the requested action as an extra; MainActivity forwards it to Flutter
// directly when the engine is up, or Flutter replays it on cold start.
class SwaraWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // The launcher calls this on the main thread; decode artwork and
        // rebinding on the background executor instead.
        val appContext = context.applicationContext
        widgetExecutor.execute {
            // One RemoteViews tree for every placed instance. Rebuilding it
            // per id decoded the artwork and re-bound the list each time.
            val views = buildViews(appContext)
            for (id in appWidgetIds) {
                appWidgetManager.updateAppWidget(id, views)
            }
        }
    }

    companion object {
        const val ACTION_TOGGLE = "swara.widget.TOGGLE"
        const val ACTION_NEXT = "swara.widget.NEXT"
        const val ACTION_PREV = "swara.widget.PREV"
        const val PREFS = "swara_widget_prefs"
        const val KEY_TITLE = "title"
        const val KEY_ARTIST = "artist"
        const val KEY_PLAYING = "playing"
        const val KEY_ART = "art"
        const val KEY_POSITION = "position_ms"
        const val KEY_NEXT_TITLE = "next_title"
        const val KEY_QUEUE = "queue_json"
        const val ACTION_PLAY_SLOT = "swara.widget.PLAY_SLOT"

        // Decodes artwork and rebinding on a single background thread so the
        // launcher's process is never blocked during onUpdate rebinds.
        private val widgetExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()

        // One decoded cover per path, reused across state pushes and widget
        // ids. Only the widgetExecutor touches these fields.
        private var cachedArtPath: String? = null
        private var cachedArt: android.graphics.Bitmap? = null
        private var lastQueueJson: String? = null

        /// Forget the decoded cover. Called after the art cache is cleared so
        /// the widget cannot keep shipping a bitmap for a path that changed.
        fun invalidateArt() {
            widgetExecutor.execute {
                cachedArtPath = null
                cachedArt = null
            }
        }

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        // Write the latest state and refresh every placed instance of the
        // widget. Called by the Flutter side on every playback change.
        fun updateAll(
            context: Context,
            title: String,
            artist: String,
            playing: Boolean,
            artPath: String?,
            positionMs: Long,
            nextTitle: String,
            queueJson: String,
            queueLength: Int,
            compact: Boolean,
        ) {
            widgetExecutor.execute {
                prefs(context).edit()
                    .putString(KEY_TITLE, title)
                    .putString(KEY_ARTIST, artist)
                    .putBoolean(KEY_PLAYING, playing)
                    .putString(KEY_ART, artPath ?: "")
                    .putLong(KEY_POSITION, positionMs)
                    .putString(KEY_NEXT_TITLE, nextTitle)
                    .putString(KEY_QUEUE, queueJson)
                    .putInt("widget_queue_len_v5", queueLength.coerceIn(3, 8))
                    .putBoolean("widget_compact_v5", compact)
                    .apply()
                val manager = AppWidgetManager.getInstance(context)
                val component = android.content.ComponentName(
                    context,
                    SwaraWidgetProvider::class.java,
                )
                val ids = manager.getAppWidgetIds(component)
                if (ids.isEmpty()) return@execute
                // Rebuild once, not once per widget instance.
                val views = buildViews(context)
                // Rebinding the list reparses the whole queue in the launcher
                // process. Only do it when the snapshot actually changed.
                val queueChanged = lastQueueJson != queueJson
                lastQueueJson = queueJson
                for (id in ids) {
                    manager.updateAppWidget(id, views)
                    if (queueChanged) {
                        manager.notifyAppWidgetViewDataChanged(
                            id, R.id.widget_queue)
                    }
                }
            }
        }

        private fun playSlotTemplate(context: Context): android.app.PendingIntent {
            val intent = android.content.Intent(context, MainActivity::class.java)
                .putExtra("swara_widget_action", ACTION_PLAY_SLOT)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                    android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val flags = if (android.os.Build.VERSION.SDK_INT >= 31) {
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_MUTABLE
            } else {
                android.app.PendingIntent.FLAG_UPDATE_CURRENT
            }
            return android.app.PendingIntent.getActivity(
                context,
                4104,
                intent,
                flags,
            )
        }

        private fun buildViews(context: Context): RemoteViews {
            val state = prefs(context)
            val compact = state.getBoolean("widget_compact_v5", false)
            val views = RemoteViews(context.packageName, R.layout.swara_widget)
            views.setViewVisibility(
                R.id.widget_artist,
                if (compact) android.view.View.GONE else android.view.View.VISIBLE,
            )
            views.setTextViewText(R.id.widget_title, state.getString(KEY_TITLE, "Swara"))
            views.setTextViewText(R.id.widget_artist, state.getString(KEY_ARTIST, ""))
            val nextTitle = state.getString(KEY_NEXT_TITLE, "") ?: ""
            if (nextTitle.isNotEmpty()) {
                views.setTextViewText(
                    R.id.widget_next_line,
                    context.getString(R.string.widget_next_label) + " " + nextTitle,
                )
                views.setViewVisibility(R.id.widget_next_line, android.view.View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_next_line, android.view.View.GONE)
            }
            // Up-next list is rendered by a RemoteViewsFactory that reads
            // only SharedPreferences from the launcher process.
            val adapterIntent = android.content.Intent(
                context,
                SwaraWidgetViewsService::class.java,
            )
            views.setRemoteAdapter(R.id.widget_queue, adapterIntent)
            views.setPendingIntentTemplate(
                R.id.widget_queue,
                playSlotTemplate(context),
            )
            // Artwork: decode a downscaled bitmap on first build after a
            // state change. RemoteViews transactions have a size budget, so
            // never ship the full resolution image.
            val artPath = state.getString(KEY_ART, "") ?: ""
            val art = if (artPath.isEmpty()) {
                null
            } else if (artPath == cachedArtPath) {
                cachedArt
            } else {
                val decoded = decodeArt(artPath, 192)
                // Do not cache a failure: a transient decode error must clear
                // on the next push instead of pinning the placeholder.
                if (decoded != null) {
                    cachedArtPath = artPath
                    cachedArt = decoded
                }
                decoded
            }
            if (art != null) {
                views.setImageViewBitmap(R.id.widget_art, art)
            } else {
                views.setImageViewResource(R.id.widget_art, R.drawable.ic_widget_art)
            }
            val playing = state.getBoolean(KEY_PLAYING, false)
            // The chronometer counts up from a fixed base, so the elapsed
            // time keeps ticking while the app runs without pushing any
            // further state; paused stops the clock at the stored offset.
            val positionMs = state.getLong(KEY_POSITION, 0L).coerceAtLeast(0L)
            val base = android.os.SystemClock.elapsedRealtime() - positionMs
            views.setChronometer(R.id.widget_elapsed, base, null, playing)
            views.setImageViewResource(
                R.id.widget_play,
                if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
            )
            views.setOnClickPendingIntent(R.id.widget_prev, actionIntent(context, ACTION_PREV, 1001))
            views.setOnClickPendingIntent(R.id.widget_play, actionIntent(context, ACTION_TOGGLE, 1002))
            views.setOnClickPendingIntent(R.id.widget_next, actionIntent(context, ACTION_NEXT, 1003))
            return views
        }

        // Decode a downscaled artwork bitmap: first a bounds pass to pick a
        // sample size without loading the file, then a single sampled decode.
        // Returns null when the file is missing or unreadable.
        private fun decodeArt(path: String, maxPx: Int): android.graphics.Bitmap? {
            return try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
                val longest = maxOf(bounds.outWidth, bounds.outHeight)
                var sample = 1
                while (longest / sample > maxPx) sample *= 2
                val opts = BitmapFactory.Options().apply { inSampleSize = sample }
                val bmp = BitmapFactory.decodeFile(path, opts)
                // RemoteViews transactions have a size budget; refuse to hand a
                // huge bitmap to the system if it still decodes large.
                if (bmp != null && (bmp.width > 512 || bmp.height > 512)) null else bmp
            } catch (_: Exception) {
                null
            }
        }

        // Launch MainActivity carrying the requested action. Single task +
        // clear top keeps the widget responsive while the app is alive; the
        // same extra is replayed by Flutter on a cold start.
        private fun actionIntent(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                // Distinct action so the extra is always fresh on each tap.
                this.action = Intent.ACTION_MAIN
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("swara_widget_action", action)
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            return PendingIntent.getActivity(context, requestCode, intent, flags)
        }
    }
}

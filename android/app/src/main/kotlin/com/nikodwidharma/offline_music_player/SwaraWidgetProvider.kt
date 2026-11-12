package com.nikodwidharma.offline_music_player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews

// Bridge between the widget provider (which can run with the process dead)
// and the live Flutter engine. MainActivity registers a handler while the
// engine is up; the widget taps launch MainActivity with the action inside
// the intent. On a dead process the app starts, Flutter replays the action
// from the intent extra via getInitialAction; when the engine is up, the
// handler forwards it directly.
object SwaraWidgetBridge {
    @Volatile
    var handler: ((String) -> Unit)? = null
}

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
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context))
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

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        // Write the latest state and refresh every placed instance of the
        // widget. Called by the Flutter side on every playback change.
        fun updateAll(
            context: Context,
            title: String,
            artist: String,
            playing: Boolean,
        ) {
            prefs(context).edit()
                .putString(KEY_TITLE, title)
                .putString(KEY_ARTIST, artist)
                .putBoolean(KEY_PLAYING, playing)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            val component = android.content.ComponentName(
                context,
                SwaraWidgetProvider::class.java,
            )
            val ids = manager.getAppWidgetIds(component)
            for (id in ids) {
                manager.updateAppWidget(id, buildViews(context))
            }
        }

        private fun buildViews(context: Context): RemoteViews {
            val state = prefs(context)
            val views = RemoteViews(context.packageName, R.layout.swara_widget)
            views.setTextViewText(R.id.widget_title, state.getString(KEY_TITLE, "Swara"))
            views.setTextViewText(R.id.widget_artist, state.getString(KEY_ARTIST, ""))
            val playing = state.getBoolean(KEY_PLAYING, false)
            views.setImageViewResource(
                R.id.widget_play,
                if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
            )
            views.setOnClickPendingIntent(R.id.widget_prev, actionIntent(context, ACTION_PREV, 1001))
            views.setOnClickPendingIntent(R.id.widget_play, actionIntent(context, ACTION_TOGGLE, 1002))
            views.setOnClickPendingIntent(R.id.widget_next, actionIntent(context, ACTION_NEXT, 1003))
            return views
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

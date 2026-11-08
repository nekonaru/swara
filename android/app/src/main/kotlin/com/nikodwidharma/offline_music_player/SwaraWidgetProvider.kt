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
// engine is up; the receiver uses it for instant in-process actions. When the
// process is dead, the receiver launches MainActivity with the action and
// Flutter reads it on startup.
object SwaraWidgetBridge {
    @Volatile
    var handler: ((String) -> Unit)? = null
}

// Home screen widget showing the current song with prev / play / next.
// The app pushes state to it on every track or playing change through
// SwaraWidgetProvider.updateAll. Button taps go through the broadcast
// receiver below.
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
            views.setOnClickPendingIntent(R.id.widget_prev, buttonIntent(context, ACTION_PREV, 1001))
            views.setOnClickPendingIntent(R.id.widget_play, buttonIntent(context, ACTION_TOGGLE, 1002))
            views.setOnClickPendingIntent(R.id.widget_next, buttonIntent(context, ACTION_NEXT, 1003))
            return views
        }

        private fun buttonIntent(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, SwaraWidgetActionReceiver::class.java).apply {
                this.action = action
                // Distinct component so multiple buttons do not collapse.
                putExtra("request_code", requestCode)
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            return PendingIntent.getBroadcast(context, requestCode, intent, flags)
        }
    }
}

// Routes widget button taps. If the engine is alive, forward in-process; if
// the app is dead, launch the app with the action and Flutter replays it on
// startup. Either way the toggle, next and previous buttons work.
class SwaraWidgetActionReceiver : AppWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        // Keep the AppWidgetProvider semantics for direct provider calls.
        super.onReceive(context, intent)
        val action = intent.action ?: return
        when (action) {
            SwaraWidgetProvider.ACTION_TOGGLE,
            SwaraWidgetProvider.ACTION_NEXT,
            SwaraWidgetProvider.ACTION_PREV -> {
                val handler = SwaraWidgetBridge.handler
                if (handler != null) {
                    handler.invoke(action)
                } else {
                    // App process is dead; start the app and pass the action
                    // as an extra. MainActivity forwards it to Flutter.
                    val launch = Intent(context, MainActivity::class.java).apply {
                        this.action = Intent.ACTION_MAIN
                        addCategory(Intent.CATEGORY_LAUNCHER)
                        putExtra("swara_widget_action", action)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                    context.startActivity(launch)
                }
            }
        }
    }
}

package com.nikodwidharma.offline_music_player

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

class SwaraWidgetViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        SwaraWidgetViewsFactory(applicationContext)
}

class SwaraWidgetViewsFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private data class Entry(
        val slotId: Int,
        val path: String,
        val title: String,
        val artist: String,
    )

    private var entries = emptyList<Entry>()

    override fun onCreate() = load()

    override fun onDataSetChanged() = load()

    private fun load() {
        val raw = context.getSharedPreferences(
            SwaraWidgetProvider.PREFS,
            Context.MODE_PRIVATE,
        ).getString(SwaraWidgetProvider.KEY_QUEUE, "[]") ?: "[]"
        val out = ArrayList<Entry>()
        try {
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val row = array.getJSONObject(i)
                out.add(
                    Entry(
                        slotId = row.optInt("slotId", -1),
                        path = row.optString("path", ""),
                        title = row.optString("title", ""),
                        artist = row.optString("artist", ""),
                    )
                )
            }
        } catch (_: Exception) {
            // An old or corrupt queue snapshot simply renders an empty list.
        }
        entries = out
    }

    override fun onDestroy() {
        entries = emptyList()
    }

    override fun getCount(): Int = entries.size

    override fun getViewAt(position: Int): RemoteViews {
        val entry = entries.getOrNull(position)
        val views = RemoteViews(
            context.packageName,
            R.layout.swara_widget_queue_row,
        )
        if (entry == null) return views
        views.setTextViewText(R.id.widget_queue_title, entry.title)
        views.setTextViewText(R.id.widget_queue_artist, entry.artist)
        val fillIn = Intent().apply {
            putExtra(
                "swara_widget_action",
                SwaraWidgetProvider.ACTION_PLAY_SLOT + ":${entry.slotId}:${entry.path}",
            )
        }
        views.setOnClickFillInIntent(R.id.widget_queue_row, fillIn)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        entries.getOrNull(position)?.slotId?.toLong() ?: position.toLong()

    override fun hasStableIds(): Boolean = true
}

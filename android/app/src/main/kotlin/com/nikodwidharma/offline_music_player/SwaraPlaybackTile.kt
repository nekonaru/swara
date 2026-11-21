package com.nikodwidharma.offline_music_player

import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.media.MediaBrowserCompat
import androidx.media.session.MediaControllerCompat
import androidx.media.session.MediaMetadataCompat
import androidx.media.session.PlaybackStateCompat
import android.view.KeyEvent

/**
 * Quick Settings tile for play/pause. It talks straight to Swara's existing
 * MediaSession, so it needs no Dart code and keeps working when the app is
 * backgrounded. A MediaButton broadcast is the fallback on skins where the
 * MediaBrowser connection is restricted.
 */
class SwaraPlaybackTile : TileService() {
    private var browser: MediaBrowserCompat? = null
    private var controller: MediaControllerCompat? = null

    private val connectionCallback = object : MediaBrowserCompat.ConnectionCallback() {
        override fun onConnected() {
            val token = browser?.sessionToken ?: return
            try {
                controller = MediaControllerCompat(applicationContext, token)
                controller?.registerCallback(controllerCallback)
                updateTile()
            } catch (_: Exception) {
                updateTile()
            }
        }

        override fun onConnectionSuspended() {
            controller = null
            updateTile()
        }

        override fun onConnectionFailed() {
            controller = null
            updateTile()
        }
    }

    private val controllerCallback = object : MediaControllerCompat.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackStateCompat?) = updateTile()
        override fun onMetadataChanged(metadata: MediaMetadataCompat?) = updateTile()
    }

    override fun onStartListening() {
        super.onStartListening()
        if (browser == null) {
            browser = MediaBrowserCompat(
                this,
                ComponentName(this, "com.ryanheise.audioservice.AudioService"),
                connectionCallback,
                null,
            )
        }
        if (browser?.isConnected == false) browser?.connect() else updateTile()
    }

    override fun onStopListening() {
        super.onStopListening()
        try {
            controller?.unregisterCallback(controllerCallback)
        } catch (_: Exception) {
        }
        controller = null
        try {
            browser?.disconnect()
        } catch (_: Exception) {
        }
        browser = null
    }

    override fun onClick() {
        super.onClick()
        val c = controller
        if (c != null) {
            val playing = c.playbackState?.state == PlaybackStateCompat.STATE_PLAYING
            if (playing) c.transportControls.pause() else c.transportControls.play()
        } else {
            // Exported MediaButtonReceiver is always available.
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                component = ComponentName(
                    applicationContext,
                    "com.ryanheise.audioservice.MediaButtonReceiver",
                )
                putExtra(
                    Intent.EXTRA_KEY_EVENT,
                    KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE),
                )
            }
            try {
                applicationContext.sendBroadcast(intent)
            } catch (_: Exception) {
            }
        }
        updateTile()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val state = controller?.playbackState?.state
        val playing = state == PlaybackStateCompat.STATE_PLAYING
        val title = controller?.metadata?.getString(MediaMetadataCompat.METADATA_KEY_TITLE)
        tile.state = if (playing) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = if (!title.isNullOrEmpty()) title else getString(R.string.quick_tile_label)
        tile.icon = Icon.createWithResource(
            this,
            if (playing) R.drawable.ic_quick_tile_pause else R.drawable.ic_quick_tile_play,
        )
        try {
            tile.updateTile()
        } catch (_: Exception) {
        }
    }
}

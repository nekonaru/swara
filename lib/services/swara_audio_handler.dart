import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'player_service.dart';

/// Thin adapter over [PlayerService]. Translates state into the Android
/// MediaSession for notifications, the lockscreen, and the foreground service.
///
/// Notification buttons: Shuffle | Previous | Play/Pause | Next | Repeat
/// (using the state aware drawables copied from android_res_extra/ into res/)
class SwaraAudioHandler extends BaseAudioHandler {
  Timer? _positionTicker;
  // Last values seen by _syncState, used by the ticker to decide
  // between a cheap position update and a full state sync.
  int? _lastSongId;
  bool? _lastPlaying;
  // Fingerprint of the last queue pushed to the MediaSession.
  // Used to avoid re-sending a large queue on every tick.
  String? _lastQueueFingerprint;

  // Notification icon names. The off icons are plain glyphs while the on
  // icons carry a solid marker, so the active state stays clear in the
  // notification shade where colors are stripped to a white mask.
  static const _shuffleOffIcon = 'drawable/ic_notif_shuffle';
  static const _shuffleOnIcon = 'drawable/ic_notif_shuffle_on';
  static const _repeatOffIcon = 'drawable/ic_notif_repeat';
  static const _repeatAllIcon = 'drawable/ic_notif_repeat_on';
  static const _repeatOneIcon = 'drawable/ic_notif_repeat_one';

  /// Shuffle button with an icon that reflects the live shuffle state.
  MediaControl _shuffleControl(bool enabled) {
    return MediaControl(
      androidIcon: enabled ? _shuffleOnIcon : _shuffleOffIcon,
      label: 'Acak',
      action: MediaAction.custom,
      customAction: const CustomMediaAction(name: 'shuffle'),
    );
  }

  /// Repeat button with one icon per repeat mode: off, all, and one.
  MediaControl _repeatControl(SwaraRepeatMode mode) {
    switch (mode) {
      case SwaraRepeatMode.one:
        return const MediaControl(
          androidIcon: _repeatOneIcon,
          label: 'Ulangi',
          action: MediaAction.custom,
          customAction: CustomMediaAction(name: 'repeat'),
        );
      case SwaraRepeatMode.all:
        return const MediaControl(
          androidIcon: _repeatAllIcon,
          label: 'Ulangi',
          action: MediaAction.custom,
          customAction: CustomMediaAction(name: 'repeat'),
        );
      case SwaraRepeatMode.off:
        return const MediaControl(
          androidIcon: _repeatOffIcon,
          label: 'Ulangi',
          action: MediaAction.custom,
          customAction: CustomMediaAction(name: 'repeat'),
        );
    }
  }

  SwaraAudioHandler() {
    PlayerService.instance.addListener(_syncState);
    _positionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      try {
        final ps = PlayerService.instance;
        // Update the position cheaply while playing. Run a full sync
        // only when the track or the playing state actually changed.
        if (!ps.player.playing) return;
        final songId = ps.currentSong?.id;
        if (songId != _lastSongId || ps.player.playing != _lastPlaying) {
          _syncState();
        } else {
          _updatePosition();
        }
      } catch (e) {
        debugPrint('Gagal sync audio handler: $e');
      }
    });
    _syncState();
  }

  bool _disposed = false;

  /// True once this handler has been torn down. Guarded so a second call is a
  /// no-op instead of touching an already cancelled ticker.
  bool get isHandlerDisposed => _disposed;

  /// Real teardown: drop the PlayerService listener and cancel the ticker.
  ///
  /// Only called from a lifecycle callback that actually destroys the handler,
  /// never from a transport command. audio_service 0.18 exposes no onDestroy
  /// for the handler, and onTaskRemoved cannot be used here either: Android
  /// fires it when the user merely swipes the task away from recents while
  /// playback continues, which is not a teardown. So the listener removal
  /// stays here, idempotent and explicit, for whoever owns the handler
  /// lifetime.
  void disposeHandler() {
    if (_disposed) return;
    _disposed = true;
    _positionTicker?.cancel();
    _positionTicker = null;
    try {
      PlayerService.instance.removeListener(_syncState);
    } catch (_) {}
  }

  Uri? _safeArtUri(String? path) {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      // Guard against path traversal / deleted files breaking the notification.
      if (!file.existsSync()) return null;
      return Uri.file(path);
    } catch (_) {
      return null;
    }
  }

  void _syncState() {
    final ps = PlayerService.instance;
    final song = ps.currentSong;
    final slotIds = ps.queueSlotIds;
    final queueVersion = ps.queueVersion;
    // Decide FIRST whether the queue actually changed. Building the MediaItem
    // list allocates one object per queue entry, and _syncState runs on every
    // PlayerService notification (volume drag, favourite toggle, speed change,
    // crossfade steps). Comparing the fingerprint first keeps those cheap.
    // The fingerprint is order sensitive and duplicate safe because it uses
    // the stable slot ids in playback order plus the version that bumps on
    // every queue mutation.
    final fingerprint = '$queueVersion|${slotIds.join(',')}';
    if (fingerprint != _lastQueueFingerprint) {
      _lastQueueFingerprint = fingerprint;
      // Build MediaSession queue in playback order with one stable id
      // per queue entry so repeated songs stay distinct.
      final q = ps.queue;
      final items = <MediaItem>[
        for (var i = 0; i < q.length; i++)
          MediaItem(
            id: 'queue_${slotIds.length > i ? slotIds[i] : i}_${q[i].filePath}',
            title: q[i].title,
            artist: q[i].artist,
            album: q[i].album,
            duration: Duration(milliseconds: q[i].durationMs),
            artUri: _safeArtUri(q[i].albumArtPath),
          ),
      ];
      queue.add(items);
      try {
        queueTitle.add('Swara Queue');
      } catch (_) {
        // queueTitle is optional on some audio_service versions.
      }
    }
    final currentIndex = ps.currentIndex;
    // The queue length equals the play order length, so the slot ids are
    // enough to bound the index without materializing the queue list.
    final queueLength = slotIds.length;
    // This is the same item the queue entry for the current slot would
    // produce, built directly so a full list is never needed here.
    final currentItem = song == null
        ? null
        : MediaItem(
            id: 'queue_${currentIndex >= 0 && currentIndex < queueLength ? slotIds[currentIndex] : 0}_${song.filePath}',
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: Duration(milliseconds: song.durationMs),
            artUri: _safeArtUri(song.albumArtPath),
          );
    mediaItem.add(currentItem);

    final playing = ps.player.playing;
    // Pick each icon from the live PlayerService state, so the notification
    // always shows whether shuffle and repeat are active. Five combinations
    // are possible: shuffle on/off crossed with repeat off/all/one.
    final shuffleControl = _shuffleControl(ps.isShuffle);
    final repeatControl = _repeatControl(ps.repeatMode);
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          shuffleControl,
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          repeatControl,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.skipToPrevious,
          MediaAction.skipToNext,
        },
        androidCompactActionIndices: const [1, 2, 3],
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: ps.player.position,
        speed: ps.player.speed,
        queueIndex:
            (currentIndex >= 0 && currentIndex < queueLength)
                ? currentIndex
                : null,
      ),
    );
    _lastSongId = song?.id;
    _lastPlaying = playing;
  }

  /// Lightweight position update for the 1 second ticker. Refreshes only
  /// the playback position without rebuilding the media item, so the
  /// notification costs almost nothing while the song keeps playing.
  void _updatePosition() {
    final ps = PlayerService.instance;
    playbackState.add(
      playbackState.value.copyWith(
        updatePosition: ps.player.position,
        speed: ps.player.speed,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (!PlayerService.instance.player.playing) {
      await PlayerService.instance.togglePlayPause();
    }
  }

  @override
  Future<void> pause() async {
    if (PlayerService.instance.player.playing) {
      await PlayerService.instance.togglePlayPause();
    }
  }

  @override
  Future<void> skipToNext() => PlayerService.instance.next();

  @override
  Future<void> skipToPrevious() => PlayerService.instance.smartPrevious();

  @override
  Future<void> skipToQueueItem(int? index) async {
    // The platform addresses queue entries by position, which matches
    // our playback order, so the index maps directly to posInOrder.
    // Validate against the live queue at call time, never a cached copy,
    // because the queue may have changed since the last sync.
    try {
      if (index == null) return;
      final liveLength = PlayerService.instance.queue.length;
      if (index < 0 || index >= liveLength) return;
      await PlayerService.instance.playAtQueueIndex(index);
    } catch (e) {
      debugPrint('skipToQueueItem failed: $e');
    }
  }

  @override
  Future<void> seek(Duration position) =>
      PlayerService.instance.player.seek(position);

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'shuffle':
        PlayerService.instance.toggleShuffle();
        // Refresh right away so the notification icon flips without
        // waiting for the next listener event.
        _syncState();
        break;
      case 'repeat':
        PlayerService.instance.cycleRepeatMode();
        // Same as above: show the new repeat icon immediately.
        _syncState();
        break;
    }
  }

  /// A MediaSession stop means "stop the music", not "throw this handler away".
  ///
  /// This used to call disposeHandler(), which removed the PlayerService
  /// listener and cancelled the position ticker, and then super.stop(), which
  /// pushes the MediaSession to idle. Android, a headset button, or the Google
  /// Assistant can send a stop at any moment. After that PlayerService kept
  /// calling notifyListeners with nothing listening, so the title, the
  /// position, and the Shuffle and Repeat icons in the notification froze until
  /// the app was restarted.
  ///
  /// Now the listener and the ticker stay attached: stop pauses playback
  /// through PlayerService so its own state stays consistent, then re-syncs
  /// the MediaSession right away instead of waiting for the next event.
  ///
  /// super.stop() is intentionally not called. It sets processingState to idle,
  /// which makes audio_service stop the Android service and hides the
  /// notification, and it awaits a playback state that is idle, which can never
  /// arrive once the sync below pushes processingState back to ready. Pausing
  /// instead keeps the notification alive, showing the play button, so
  /// playback can start again from the notification or from the UI and the
  /// notification keeps moving.
  @override
  Future<void> stop() async {
    if (_disposed) return;
    final ps = PlayerService.instance;
    try {
      // Use the PlayerService pause path (with its fade and its own listener
      // bookkeeping) rather than touching the player directly.
      if (ps.player.playing) {
        await ps.togglePlayPause();
      }
    } catch (e) {
      debugPrint('MediaSession stop failed: $e');
    }
    if (_disposed) return;
    // Push the paused state into the notification now, so the button flips to
    // play even if PlayerService did not notify on this path.
    _syncState();
  }
}

import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'player_service.dart';

/// Thin adapter over [PlayerService]. Translates state into the Android
/// MediaSession for notifications, the lockscreen, and the foreground service.
///
/// Notification buttons: Shuffle | Previous | Play/Pause | Next | Repeat
/// (using the state aware drawables committed under android/app/src/main/res)
class SwaraAudioHandler extends BaseAudioHandler {
  Timer? _positionTicker;
  // Debounce timer for re-publishing the full MediaSession queue after
  // queue mutations (drag reorder storms).
  Timer? _queueRepublishTimer;
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
      label: 'Shuffle',
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
          label: 'Repeat',
          action: MediaAction.custom,
          customAction: CustomMediaAction(name: 'repeat'),
        );
      case SwaraRepeatMode.all:
        return const MediaControl(
          androidIcon: _repeatAllIcon,
          label: 'Repeat',
          action: MediaAction.custom,
          customAction: CustomMediaAction(name: 'repeat'),
        );
      case SwaraRepeatMode.off:
        return const MediaControl(
          androidIcon: _repeatOffIcon,
          label: 'Repeat',
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
        debugPrint('Failed to sync audio handler: $e');
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
    _queueRepublishTimer?.cancel();
    _queueRepublishTimer = null;
    try {
      PlayerService.instance.removeListener(_syncState);
    } catch (_) {}
  }

  // Memo of art path to notification Uri. _syncState runs on every player
  // notification (volume drags, crossfade steps), and an existsSync per call
  // put a synchronous syscall on the UI thread each time. A deleted file
  // after caching is harmless: the notification just shows no art.
  final Map<String, Uri?> _artUriCache = {};

  Uri? _safeArtUri(String? path) {
    if (path == null || path.isEmpty) return null;
    if (_artUriCache.containsKey(path)) return _artUriCache[path];
    Uri? result;
    try {
      final file = File(path);
      // Guard against path traversal / deleted files breaking the notification.
      if (file.existsSync()) {
        result = Uri.file(path);
      }
    } catch (_) {
      result = null;
    }
    // Evict the oldest half of the art cache instead of clearing it all:
    // a full clear re-checks every file on disk at once.
    if (_artUriCache.length >= 256) {
      final keep = _artUriCache.entries
          .toList()
          .sublist(_artUriCache.length ~/ 2)
          .map((e) => e.key)
          .toSet();
      _artUriCache.removeWhere((key, _) => !keep.contains(key));
    }
    _artUriCache[path] = result;
    return result;
  }

  // Number of songs published to the MediaSession around the current one.
  // A 10k library must not be serialized over the platform channel on every
  // track change; the window still covers the next several songs.
  static const int _queueWindowBefore = 5;
  static const int _queueWindowTotal = 40;
  int _queueWindowStart = 0;

  // Build and publish a bounded MediaSession queue window in playback order.
  // Called from the debounced timer, never directly from the notify path.
  void _publishQueue(PlayerService ps) {
    if (_disposed) return;
    final slotIds = ps.queueSlotIds;
    final q = ps.queue;
    final current = ps.currentIndex;
    final start = (current - _queueWindowBefore)
        .clamp(0, q.isEmpty ? 0 : q.length - 1);
    final end = (start + _queueWindowTotal).clamp(0, q.length);
    _queueWindowStart = start;
    final items = <MediaItem>[
      for (var i = start; i < end; i++)
        MediaItem(
          id: 'queue_${slotIds.length > i ? slotIds[i] : i}_${q[i].filePath}',
          title: q[i].title,
          artist: q[i].artist,
          album: q[i].album,
          duration: Duration(milliseconds: q[i].durationMs),
          artUri: _safeArtUri(q[i].albumArtPath),
        ),
    ];
    try {
      queue.add(items);
      queueTitle.add('Swara Queue');
    } catch (_) {
      // A dead session must never crash a timer callback.
    }
  }

  void _syncState() {
    final ps = PlayerService.instance;
    final song = ps.currentSong;
    final queueVersion = ps.queueVersion;
    // Decide FIRST whether the queue actually changed. Building the MediaItem
    // list allocates one object per queue entry, and _syncState runs on every
    // PlayerService notification (volume drag, favourite toggle, speed change,
    // crossfade steps). queueVersion bumps on every queue mutation and
    // reorder, so it alone is a sufficient invalidation token; building the
    // slot id list here would allocate an O(queue) list per notify.
    // A full republish is debounced: a drag-reorder storm emits many bumps,
    // but the MediaSession only needs a settled queue, not every step.
    // Include the current index: a crossfade flip changes the audible song
    // without a queue mutation, but the MediaSession window must re-center.
    final fingerprint = '$queueVersion:${ps.currentIndex}';
    if (fingerprint != _lastQueueFingerprint) {
      _lastQueueFingerprint = fingerprint;
      _queueRepublishTimer?.cancel();
      _queueRepublishTimer = Timer(const Duration(milliseconds: 200), () {
        _publishQueue(ps);
      });
    }
    final currentIndex = ps.currentIndex;
    // The media item id is built with queueSlotIdAt, an O(1) lookup; the
    // materialized slot id list only exists inside the branch above.
    final currentItem = song == null
        ? null
        : MediaItem(
            id: 'queue_${ps.queueSlotIdAt(currentIndex) ?? 0}_${song.filePath}',
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
          MediaAction.skipToQueueItem,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [1, 2, 3],
        // No song loaded means nothing can play: say idle instead of
        // advertising a live session the user cannot act on.
        processingState: song == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: ps.player.position,
        speed: ps.player.speed,
        queueIndex:
            (currentIndex >= 0 && currentIndex < ps.queueOrderLength)
                ? currentIndex - _queueWindowStart
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
    // Resolve the stable slot id from the published MediaItem instead of
    // adding a cached window offset: the window may have re-centered between
    // the user's tap and this callback.
    try {
      if (index == null) return;
      final published = queue.value;
      if (index < 0 || index >= published.length) return;
      final parts = published[index].id.split('_');
      if (parts.length < 2) return;
      final slotId = int.tryParse(parts[1]);
      if (slotId == null) return;
      final ps = PlayerService.instance;
      final pos = ps.queuePosForSlot(slotId);
      if (pos == null || pos < 0 || pos >= ps.queueOrderLength) return;
      await ps.playAtQueueIndex(pos);
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

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:swara/providers/language_provider.dart';
import '../models/song.dart';
import 'db_helper.dart';
import 'equalizer_service.dart';

enum SwaraRepeatMode { off, all, one }

// Decision returned by _onNaturalTrackEnd after applying sleep logic.
enum _TrackEndDecision { stop, repeatOne, advance }

class PlayerService extends ChangeNotifier {
  PlayerService._();
  static final PlayerService instance = PlayerService._();

  final AudioPlayer _player = AudioPlayer();
  // Second player for crossfade, created lazily only when crossfade is
  // actually used, so idle playback never pays its memory cost.
  AudioPlayer? _crossfadePlayer;
  bool _usingCrossfadePlayer = false;

  // _queue: the original song list (source order, never changed by shuffle)
  List<Song> _queue = [];
  // _playOrder: the actual playback order (holds indices into _queue).
  // When shuffle is off: [0,1,2,...]. When shuffle is on: shuffled once,
  // kept stable across next/previous.
  List<int> _playOrder = [];
  int _posInOrder = 0;

  bool _shuffle = false;
  SwaraRepeatMode _repeatMode = SwaraRepeatMode.off;
  // A-B repeat state. When both are non null, playback loops the segment
  // from _abRepeatA to _abRepeatB. Null means the feature is off.
  // Reset on every track change. Independent of crossfade, sleep and speed.
  Duration? _abRepeatA;
  Duration? _abRepeatB;
  // Tolerance for the B trigger, so a coarse position tick still loops.
  static const Duration abRepeatTolerance = Duration(milliseconds: 200);
  bool crossfadeEnabled = false;
  // Overlap between songs. 0 means no overlap (direct switch), max 12.
  static const int crossfadeMinSeconds = 0;
  static const int crossfadeMaxSeconds = 12;
  static const int crossfadeDefaultSeconds = 3;
  static const String _prefsCrossfadeSecondsKey = 'crossfadeSeconds';
  Duration crossfadeDuration = const Duration(seconds: 3);

  // Smart shuffle preference, persisted with the same pattern as the
  // crossfade seconds key.
  static const String _prefsSmartShuffleKey = 'smartShuffle';
  bool _smartShuffle = false;

  // Playback speed and pitch. Both are clamped to 0.5..2.0 and re-applied on
  // every track change, so the values survive song switches and crossfades.
  static const double speedMin = 0.5;
  static const double speedMax = 2.0;
  static const double pitchMin = 0.5;
  static const double pitchMax = 2.0;
  // Persisted with the same pattern as the crossfade seconds key, so the
  // chosen rate survives an app restart instead of resetting to 1.0.
  static const String _prefsSpeedKey = 'playbackSpeed';
  static const String _prefsPitchKey = 'playbackPitch';
  double _speed = 1.0;
  double _pitch = 1.0;
  // Minimum gap between two real platform speed/pitch calls. A slider drag
  // fires dozens of events per second, each one a platform channel round
  // trip and a full screen rebuild, so the apply is throttled here and the
  // final value is always applied by the trailing call.
  static const Duration speedPitchThrottleInterval =
      Duration(milliseconds: 120);
  DateTime? _lastSpeedPitchApply;
  Timer? _speedPitchApplyTimer;
  // Prefs writes are deferred the same way, so a drag never touches disk
  // more than once.
  static const Duration speedPitchPersistDelay = Duration(milliseconds: 400);
  Timer? _speedPitchPersistTimer;

  // In-memory smart shuffle statistics. Play counts come from the listening
  // history table and the last played stamp is kept locally, updated whenever
  // a song starts. They are only read while the queue order is built, so no
  // database call is ever added to the playback path.
  Map<int, int> _playCounts = const {};
  final Map<int, DateTime> _lastPlayTimes = {};

  // Overlap length in whole seconds, clamped to the allowed range.
  int get crossfadeSeconds => crossfadeDuration.inSeconds;

  // Public version counter for queue/order mutations. Incremented on every
  // queue or order change so UI can detect stale snapshots.
  int queueVersion = 0;
  int _playGeneration = 0;

  Timer? _sleepTimer;
  DateTime? sleepTimerEndTime;

  // Daily sleep schedule. Persisted separately from a running sleep timer, so
  // the schedule survives a restart while the countdown stays in memory only.
  static const String _prefsSleepScheduleEnabledKey = 'sleepScheduleEnabled';
  static const String _prefsSleepScheduleHourKey = 'sleepScheduleHour';
  static const String _prefsSleepScheduleMinuteKey = 'sleepScheduleMinute';
  static const int sleepScheduleDefaultHour = 22;
  static const int sleepScheduleDefaultMinute = 0;
  // How often the schedule clock is polled, and how long the automatic
  // session lasts once it fires.
  static const Duration sleepScheduleTickInterval = Duration(seconds: 30);
  static const Duration sleepScheduleDuration = Duration(minutes: 30);
  bool _sleepScheduleEnabled = false;
  int _sleepScheduleHour = sleepScheduleDefaultHour;
  int _sleepScheduleMinute = sleepScheduleDefaultMinute;
  Timer? _sleepScheduleTicker;
  // Day stamp (yyyy-mm-dd) of the last day the schedule already fired, so a
  // schedule never triggers twice on the same day.
  String? _sleepScheduleFiredDay;
  int? sleepSongsRemaining;
  bool _finishCurrentSongOnSleep = false;
  bool _pendingSleepStop = false;
  // Sleep fade out state. When a time based timer expires in direct stop
  // mode, volume fades to 0 over [sleepFadeDuration] instead of pausing
  // at once. Generation guards against overlapping fades.
  bool _sleepFadeActive = false;
  int _sleepFadeGeneration = 0;
  static const Duration sleepFadeDuration = Duration(seconds: 30);
  // Manual pause/resume fade state. Short 300ms ramp used only around
  // togglePlayPause, separate from the 30s sleep fade and crossfade.
  // Generation guards against overlapping fades when toggle is pressed
  // mid fade. Only the audible player is faded, never the standby one.
  int _pauseFadeGeneration = 0;
  bool _pauseFadeOutActive = false;
  static const Duration pauseFadeDuration = Duration(milliseconds: 300);
  static const int pauseFadeSteps = 4;
  // Serializes every volume and pause operation (fades, cancels,
  // restores). Overlapping fades used to interleave setVolume calls,
  // leaving the player stuck quiet. Chained ops run strictly in call
  // order and the chain never breaks (errors are logged, not rethrown).
  Future<void> _volumeChain = Future<void>.value();

  Future<void> _vol(Future<void>? Function() op) {
    final next = _volumeChain.then((_) async {
      try {
        await op();
      } catch (e) {
        debugPrint('Volume op failed: $e');
      }
    });
    _volumeChain = next;
    return next;
  }
  // File path currently preloaded in the idle player (crossfade off only).
  // Best effort cache, never played directly from here.
  String? _preloadedFilePath;
  String? lastError;

  DateTime? _playStartedAt;
  int _accumulatedListenedMs = 0;

  StreamSubscription? _positionSub;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _crossfadeStateSub;
  // Crossfade generation guards overlapping fades. Incremented on every
  // start and every cancel. A fade loop captures its own generation and
  // aborts when the global value no longer matches. _crossfadeActiveGeneration
  // tracks the in flight fade for the current song (-1 means idle) so the
  // position trigger fires only once per song without a bool flag.
  int _crossfadeGeneration = 0;
  int _crossfadeActiveGeneration = -1;
  bool _disposed = false;

  /// Subscribe to the active player position stream for crossfade triggers.
  /// Cancels any previous subscription first so only one stays active.
  Future<void> _subscribePosition() async {
    if (_disposed) return;
    await _positionSub?.cancel();
    _positionSub = null;
    if (_disposed) return;
    _positionSub = _activePlayer.positionStream.listen(_onPosition);
  }

  /// Stop listening to position updates to save battery while paused.
  Future<void> _unsubscribePosition() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  /// The player that is CURRENTLY audible (switches each time a crossfade finishes)
  AudioPlayer get _activePlayer {
    final crossfade = _crossfadePlayer;
    if (_usingCrossfadePlayer && crossfade != null) return crossfade;
    return _player;
  }

  /// The "standby" player used to fade in the next song. Creates the
  /// crossfade player on first real use so normal playback stays light.
  AudioPlayer get _fadeTargetPlayer {
    if (_usingCrossfadePlayer) return _player;
    return _ensureCrossfadePlayer();
  }

  /// Create the crossfade player on demand and attach its completion
  /// listener. Copies the current speed and pitch so the fade in starts in
  /// sync with the audible player.
  AudioPlayer _ensureCrossfadePlayer() {
    final existing = _crossfadePlayer;
    if (existing != null) return existing;
    final created = AudioPlayer();
    _crossfadePlayer = created;
    _syncSpeedPitch(created).catchError((Object e) {
      debugPrint('Crossfade speed/pitch sync failed: $e');
    });
    _crossfadeStateSub?.cancel();
    _crossfadeStateSub = created.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && _usingCrossfadePlayer) {
        _logListening();
        _onTrackFinished();
      }
    });
    return created;
  }

  /// Release the standby crossfade player and drop the reference so it
  /// holds no audio resources. Skipped while it is the audible player;
  /// that case is released on the next track change instead.
  void _releaseCrossfadePlayer() {
    if (_usingCrossfadePlayer) return;
    _preloadedFilePath = null;
    _crossfadeStateSub?.cancel();
    _crossfadeStateSub = null;
    final standby = _crossfadePlayer;
    _crossfadePlayer = null;
    standby?.dispose().catchError((Object e) {
      debugPrint('Crossfade dispose failed: $e');
    });
  }

  /// Copy the current speed and pitch onto [target]. Used on every track load
  /// so a song never starts at the default rate while another one is fast.
  Future<void> _syncSpeedPitch(AudioPlayer target) async {
    await target.setSpeed(_speed);
    await target.setPitch(_pitch);
  }

  AudioPlayer get player => _activePlayer;

  Song? get currentSong {
    if (_playOrder.isEmpty || _posInOrder < 0 || _posInOrder >= _playOrder.length) return null;
    return _queue[_playOrder[_posInOrder]];
  }

  bool get isShuffle => _shuffle;
  SwaraRepeatMode get repeatMode => _repeatMode;
  Duration? get abRepeatA => _abRepeatA;
  Duration? get abRepeatB => _abRepeatB;
  bool get hasABRepeat => _abRepeatA != null && _abRepeatB != null;

  /// Queue in the actual playback order (used by the Queue page)
  List<Song> get queue => _playOrder.map((i) => _queue[i]).toList();
  int get currentIndex => _posInOrder;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_prefsCrossfadeSecondsKey);
      if (saved != null) {
        final clamped =
            saved.clamp(crossfadeMinSeconds, crossfadeMaxSeconds);
        crossfadeDuration = Duration(seconds: clamped);
      }
      // Smart shuffle is a plain bool flag, same persistence pattern.
      _smartShuffle = prefs.getBool(_prefsSmartShuffleKey) ?? false;
      // Daily sleep schedule: enabled flag plus a 24h hour/minute pair.
      _sleepScheduleEnabled =
          prefs.getBool(_prefsSleepScheduleEnabledKey) ?? false;
      final hour = prefs.getInt(_prefsSleepScheduleHourKey);
      final minute = prefs.getInt(_prefsSleepScheduleMinuteKey);
      if (hour != null && hour >= 0 && hour <= 23) _sleepScheduleHour = hour;
      if (minute != null && minute >= 0 && minute <= 59) {
        _sleepScheduleMinute = minute;
      }
      // Playback speed and pitch. Clamped on read as well, so a corrupted or
      // out of range stored value can never produce an unplayable rate.
      // TODO L10N: no user facing string added here, English only.
      final savedSpeed = prefs.getDouble(_prefsSpeedKey);
      if (savedSpeed != null && savedSpeed.isFinite) {
        _speed = savedSpeed.clamp(speedMin, speedMax).toDouble();
      }
      final savedPitch = prefs.getDouble(_prefsPitchKey);
      if (savedPitch != null && savedPitch.isFinite) {
        _pitch = savedPitch.clamp(pitchMin, pitchMax).toDouble();
      }
    } catch (e) {
      debugPrint('Crossfade duration load failed: $e');
    }
    // The schedule ticker only runs while the schedule is enabled.
    if (_sleepScheduleEnabled) {
      // App start counts as arming time: do not fire retroactively when the
      // configured time already passed today, wait for tomorrow instead.
      _skipTodayIfAlreadyPast();
      _startSleepScheduleTicker();
    }
    // Warm the smart shuffle statistics in the background when the feature
    // was already enabled from a previous session.
    if (_smartShuffle) unawaited(refreshSmartShuffleStats());
    await _playerStateSub?.cancel();
    await _unsubscribePosition();
    _playerStateSub = _player.playerStateStream.listen((state) {
      // A running crossfade ends this track on its own and advances the
      // position itself. Without this guard the natural completion event
      // fired in the middle of the fade, called next(), bumped the play
      // generation and aborted the fade loop: an audible jump plus the
      // incoming song restarting from its first second.
      if (state.processingState == ProcessingState.completed &&
          !_usingCrossfadePlayer &&
          _crossfadeActiveGeneration == -1) {
        _logListening();
        _onTrackFinished();
      }
    });
    // The crossfade completion listener is attached inside
    // _ensureCrossfadePlayer, so nothing is created here. Reattach only
    // when the standby player already exists (for example after hot restart).
    final standby = _crossfadePlayer;
    if (standby != null) {
      await _crossfadeStateSub?.cancel();
      _crossfadeStateSub = standby.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed &&
            _usingCrossfadePlayer &&
            _crossfadeActiveGeneration == -1) {
          _logListening();
          _onTrackFinished();
        }
      });
    }
    // Subscribe only while playing so crossfade triggers keep working
    // without draining battery while paused.
    await _subscribePosition();
    // Everything is loaded now. Notify once so any UI built before init
    // finished (crossfade seconds, smart shuffle, sleep schedule, speed and
    // pitch) shows the persisted values instead of the defaults.
    if (!_disposed) notifyListeners();
  }

  /// Shared position tick for the active player. A-B repeat is checked
  /// first so the segment loops before the crossfade trigger near the
  /// track end can fire.
  void _onPosition(Duration position) {
    if (_checkABRepeat(position)) return;
    _maybeStartCrossfade(position);
  }

  /// Seek back to A once the position reaches B (with a small tolerance).
  /// Returns true when a loop seek was issued, so crossfade stays out.
  bool _checkABRepeat(Duration position) {
    final a = _abRepeatA;
    final b = _abRepeatB;
    if (a == null || b == null) return false;
    if (position + abRepeatTolerance >= b) {
      _activePlayer.seek(a).catchError((Object e) {
        debugPrint('A-B repeat seek failed: $e');
      });
      return true;
    }
    return false;
  }

  void _maybeStartCrossfade(Duration position) {
    // Trigger only once per song: an in flight fade is marked by a
    // non idle _crossfadeActiveGeneration, so later position ticks skip.
    if (!crossfadeEnabled || _crossfadeActiveGeneration != -1) return;
    final dur = _activePlayer.duration;
    if (dur == null) return;
    final remaining = dur - position;
    if (remaining <= crossfadeDuration && remaining > Duration.zero) {
      _startCrossfadeToNext();
    }
  }

  Future<void> _startCrossfadeToNext() async {
    if (_disposed) return;
    if (_playOrder.isEmpty) return;
    final playGen = _playGeneration;
    final nextPos = _computeNextPosition();
    if (nextPos == null) return;
    final nextSong = _queue[_playOrder[nextPos]];

    // Use the dynamic getters, never hardcode _player/_crossfadePlayer, so this
    // stays correct for any crossfade count, not just the first one.
    final outgoing = _activePlayer;
    final incoming = _fadeTargetPlayer;
    // Claim the trigger slot so position ticks do not start a second fade.
    final fadeGen = ++_crossfadeGeneration;
    _crossfadeActiveGeneration = fadeGen;

    try {
      await incoming.setFilePath(nextSong.filePath);
      if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;
      await _syncSpeedPitch(incoming);
      if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;
      await _vol(() => incoming.setVolume(0));
      if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;
      await incoming.play();
      if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;

      // Zero duration means no overlap: cut straight to the next song
      // at full volume instead of running a fade loop with no length.
      if (crossfadeDuration <= Duration.zero) {
        await _vol(() => incoming.setVolume(1));
        if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;
      } else {
        const steps = 20;
        final stepDuration = crossfadeDuration ~/ steps;
        for (int i = 1; i <= steps; i++) {
          await Future.delayed(stepDuration);
          // Abort without side effects when a newer navigation took over.
          if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;
          final v = i / steps;
          await _vol(() => incoming.setVolume(v));
          if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;
          await _vol(() => outgoing.setVolume(1 - v));
        }
        if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;
      }

      await _vol(() => outgoing.pause());
      if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;
      // Keep the outgoing player muted at restore level; its volume is
      // reset to full so a later reuse starts loud. Do not release it here.
      await _vol(() => outgoing.setVolume(1));
      if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;

      // IMPORTANT: record the listening history of the OLD song first (using
      // currentSong while it still points at the old song, before _posInOrder
      // moves), then reset the start clock for the NEW song, so
      // listening entries never get the wrong attribution or doubled duration.
      _logListening();
      if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;
      _usingCrossfadePlayer = !_usingCrossfadePlayer;
      // Attach the equalizer only after the flip, to the now audible player.
      // The outgoing player is left alone until its pause above.
      unawaited(EqualizerService.instance.attach(_activePlayer));
      _posInOrder = nextPos;
      _clearABRepeatSilent(); // new track, drop any A-B segment
      _playStartedAt = DateTime.now();
      _accumulatedListenedMs = 0;
      _crossfadeActiveGeneration = -1;
      _markSongPlayed(nextSong);
      await DBHelper.instance.markPlayed(nextSong.id);
      if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;

      await _subscribePosition();
      if (playGen != _playGeneration || fadeGen != _crossfadeGeneration || _disposed) return;

      // Apply the same natural end completion (sleep decrement first, then
      // repeat decision). When sleep is exhausted this pauses both players
      // at full restored volume and notifies, so return without extra notify.
      final decision = _onNaturalTrackEnd();
      if (decision == _TrackEndDecision.stop) return;

      notifyListeners();
    } catch (e) {
      debugPrint('Crossfade failed, continue normal: $e');
      if (fadeGen == _crossfadeGeneration) _crossfadeActiveGeneration = -1;
    }
  }

  /// True while a crossfade is running between the current song and the next
  /// one. The next song is already loaded in the standby player during that
  /// window, so the queue must not drop it.
  bool get isCrossfadeActive => _crossfadeActiveGeneration != -1;

  /// Queue slot (position in the play order) of the song that a running
  /// crossfade is fading in, or null when no crossfade is running.
  ///
  /// Exposed so the queue screen can leave that song alone while the user
  /// clears everything after the current one.
  /// Cancel a crossfade that is still in flight because the queue is about to
  /// change shape.
  ///
  /// The fade captured the target slot before it started, so any insert,
  /// remove or reorder while it runs makes that captured index point at a
  /// different song. Cancelling is safe: the outgoing player was never
  /// paused, so playback continues uninterrupted. The standby player is paused
  /// and its volume restored, otherwise it would keep playing faintly in the
  /// background.
  void _abortCrossfadeForQueueEdit() {
    if (!isCrossfadeActive) return;
    _cancelCrossfade();
    _stopStandbyPlayer();
  }

  /// Pause the standby player and restore its volume, so a cancelled fade
  /// cannot keep playing faintly in the background.
  void _stopStandbyPlayer() {
    final standby = _crossfadePlayer;
    if (standby == null) return;
    unawaited(standby.pause().catchError((Object e) {
      debugPrint('Failed to stop the standby player: $e');
    }));
    unawaited(standby.setVolume(1).catchError((Object e) {
      debugPrint('Failed to restore the standby volume: $e');
    }));
  }

  int? get pendingCrossfadePosition {
    if (!isCrossfadeActive) return null;
    final next = _computeNextPosition();
    return next;
  }

  int? _computeNextPosition() {
    // SwaraRepeatMode.one must be checked FIRST, before every other condition,
    // so crossfade also repeats the same song instead of moving to the next one.
    if (_repeatMode == SwaraRepeatMode.one) return _posInOrder;
    if (_posInOrder < _playOrder.length - 1) return _posInOrder + 1;
    if (_repeatMode == SwaraRepeatMode.all) return 0;
    return null;
  }

  /// Cancel any in flight crossfade by bumping the generation. The fade loop
  /// aborts without side effects when its captured generation mismatches.
  void _cancelCrossfade() {
    _crossfadeGeneration++;
    _crossfadeActiveGeneration = -1;
  }

  /// Start playing a new song list. This ALWAYS replaces the whole queue
  /// with just `songs` (called from the All Songs / Folder / Playlist /
  /// Favorites pages respectively, so the queue is automatically scoped to
  /// its source).
  Future<void> setQueueAndPlay(List<Song> songs, int startIndex) async {
    if (_disposed) return;
    _playGeneration++;
    queueVersion++;
    _logListening();
    if (_sleepFadeActive) _cancelSleepFadeOut();
    _cancelPauseFade();
    _cancelCrossfade();
    _clearABRepeatSilent(); // new track, drop any A-B segment
    // Manual navigation means the user took over, so a pending "stop after
    // this song" sleep flag must not survive. The natural end path clears it
    // inside _onNaturalTrackEnd before it ever reaches these methods.
    _pendingSleepStop = false;
    _usingCrossfadePlayer = false;
    await _vol(() => _crossfadePlayer?.pause() ?? Future<void>.value());
    // Drop the standby player while crossfade is off so manual
    // navigation does not leave audio resources allocated.
    if (!crossfadeEnabled) _releaseCrossfadePlayer();
    _queue = List.of(songs);

    if (_shuffle) {
      _playOrder = _buildShuffledOrder(_queue.length, startIndex);
      _posInOrder = 0;
    } else {
      _playOrder = List.generate(_queue.length, (i) => i);
      _posInOrder = startIndex;
    }

    notifyListeners(); // so the mini-player shows immediately, without waiting for the file to finish loading
    await _playCurrent();
    notifyListeners();
  }

  List<int> _buildShuffledOrder(int length, int startIndex) {
    final indices = List.generate(length, (i) => i);
    indices.remove(startIndex);
    return [startIndex, ..._shuffleRest(indices)];
  }

  /// Order the songs after the current one. With smart shuffle on, the song
  /// that was played least often and longest ago comes first, so the queue
  /// naturally favors forgotten tracks. Falls back to a plain shuffle when no
  /// statistics are available.
  List<int> _shuffleRest(List<int> indices) {
    if (_smartShuffle && _playCounts.isNotEmpty) {
      final weighted = _smartShuffleOrder(indices);
      if (weighted != null) return weighted;
    }
    indices.shuffle(Random());
    return indices;
  }

  /// Weighted random order: the lower the weight, the earlier the song plays.
  /// Weight combines a rarity score from the play count and a staleness score
  /// from the last played stamp, then a random jitter keeps equal songs from
  /// always landing in the same spot. Returns null when the queue has no song
  /// with known statistics, which lets the caller fall back to plain shuffle.
  List<int>? _smartShuffleOrder(List<int> indices) {
    final now = DateTime.now();
    final maxCount = _playCounts.values.fold<int>(0, (a, b) => a > b ? a : b);
    if (maxCount <= 0) return null;
    final weights = <int, double>{};
    for (final i in indices) {
      if (i < 0 || i >= _queue.length) continue;
      final id = _queue[i].id;
      final count = (_playCounts[id] ?? 0).toDouble();
      final last = _lastPlayTimes[id];
      // Rarity: 0 for the most played song, close to 1 for a never played one.
      final rarity = 1.0 - (count / maxCount);
      // Staleness: 0 when just played, grows with the idle time.
      final staleness = last == null
          ? 1.0
          : (now.difference(last).inHours / (24.0 * 30))
              .clamp(0.0, 1.0)
              .toDouble();
      weights[i] = rarity * 0.6 + staleness * 0.4 + Random().nextDouble() * 0.05;
    }
    if (weights.isEmpty) return null;
    final ordered = List<int>.of(indices)
      ..sort((a, b) =>
          (weights[a] ?? double.maxFinite)
              .compareTo(weights[b] ?? double.maxFinite));
    return ordered;
  }

  Future<void> _playCurrent() async {
    if (_disposed) return;
    final playGen = _playGeneration;
    final song = currentSong;
    if (song == null) return;
    try {
      await _player.setFilePath(song.filePath);
      if (playGen != _playGeneration || _disposed) return;
      await _syncSpeedPitch(_player);
      if (playGen != _playGeneration || _disposed) return;
      await _vol(() => _player.setVolume(1));
    } catch (e) {
      if (playGen != _playGeneration || _disposed) return;
      debugPrint('Failed to play song: $e');
      lastError = '${lookupAppLocalizations(LanguageProvider.instance.locale).corePlayFailed} "${song.title}": $e';
      notifyListeners();
      return;
    }
    if (playGen != _playGeneration || _disposed) return;
    try {
      await _player.play();
    } catch (e) {
      if (playGen != _playGeneration || _disposed) return;
      debugPrint('Play failed: $e');
      lastError = '${lookupAppLocalizations(LanguageProvider.instance.locale).corePlayFailed} "${song.title}": $e';
      notifyListeners();
      return;
    }
    if (playGen != _playGeneration || _disposed) return;
    _playStartedAt = DateTime.now();
    _accumulatedListenedMs = 0;
    _markSongPlayed(song);
    await DBHelper.instance.markPlayed(song.id);
    if (playGen != _playGeneration || _disposed) return;
    lastError = null;
    // Attach the system equalizer to this session (fire and forget,
    // the service guards its own errors and never blocks playback).
    unawaited(EqualizerService.instance.attach(_player));
    // Re-attach the position listener to the now-active player, so
    // crossfade keeps triggering for the following songs too (not just once).
    await _subscribePosition();
    if (playGen != _playGeneration || _disposed) return;
    // Warm the idle player with the next file when crossfade is off.
    _preloadNextSong();
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    // Second press while a pause fade out is still running cancels the
    // pause and keeps playback at full volume.
    if (_pauseFadeOutActive) {
      _pauseFadeGeneration++;
      _pauseFadeOutActive = false;
      await _vol(() => _activePlayer.setVolume(1));
      notifyListeners();
      return;
    }
    if (player.playing) {
      // A manual pause during a sleep fade stops the fade so the volume
      // does not keep dropping in the background.
      if (_sleepFadeActive) _cancelSleepFadeOut();
      // Cancel any in flight resume fade before starting the pause fade.
      final generation = ++_pauseFadeGeneration;
      _pauseFadeOutActive = true;
      _logListening();
      final target = _activePlayer;
      try {
        final stepDuration = pauseFadeDuration ~/ pauseFadeSteps;
        for (int i = 1; i <= pauseFadeSteps; i++) {
          await Future.delayed(stepDuration);
          if (_disposed) return;
          if (generation != _pauseFadeGeneration) return;
          final v = (1 - i / pauseFadeSteps).clamp(0.0, 1.0);
          await _vol(() => target.setVolume(v));
        }
        if (_disposed) return;
        if (generation != _pauseFadeGeneration) return;
        await _vol(() => target.pause());
        // Restore full volume on both players so the next play starts loud.
        await _vol(() => _player.setVolume(1));
        await _vol(
            () => _crossfadePlayer?.setVolume(1) ?? Future<void>.value());
      } catch (e) {
        debugPrint('Pause fade failed: $e');
      } finally {
        if (generation == _pauseFadeGeneration) {
          _pauseFadeOutActive = false;
        }
      }
      // Stop position updates while paused to save battery.
      await _unsubscribePosition();
    } else {
      // Resume path: NO volume dip. A previous resume fade left players
      // stuck silent on some devices (0 volume + aborted ramp), so resume
      // always restores full volume first, then plays. The pause fade-out
      // above keeps the audible nicety; fade-in is not worth the risk.
      if (_sleepFadeActive) _cancelSleepFadeOut();
      // Cancel any in flight pause fade before resuming.
      final generation = ++_pauseFadeGeneration;
      _pauseFadeOutActive = false;
      _playStartedAt = DateTime.now();
      final target = _activePlayer;
      await _vol(() => target.setVolume(1));
      if (_disposed) return;
      if (generation != _pauseFadeGeneration) return;
      try {
        await target.play();
      } catch (e) {
        debugPrint('Resume play failed: $e');
        lastError =
            '${lookupAppLocalizations(LanguageProvider.instance.locale).corePlayFailed}: $e';
        notifyListeners();
        return;
      }
      // Resume position updates for crossfade triggers.
      await _subscribePosition();
      // Watchdog: some devices report playing while staying silent or
      // drop the play call. If we are not audible shortly after resume
      // with no newer command, retry once instead of staying quiet.
      final watchGen = generation;
      Future.delayed(const Duration(milliseconds: 600), () async {
        if (_disposed) return;
        if (watchGen != _pauseFadeGeneration) return;
        if (watchGen != _playGeneration) return;
        try {
          if (!target.playing) {
            await target.play();
            await _vol(() => target.setVolume(1));
            notifyListeners();
          }
        } catch (e) {
          debugPrint('Resume watchdog failed: $e');
        }
      });
    }
    notifyListeners();
  }

  /// Cancel an in flight manual pause fade. Restores go through the
  /// volume chain so they can never land before a stale fade step.
  void _cancelPauseFade() {
    _pauseFadeGeneration++;
    _pauseFadeOutActive = false;
    // Restore full volume so a cancelled resume fade never leaves the
    // player quiet. Ordered by the chain, fire and forget is safe.
    _vol(() => _player.setVolume(1));
    _vol(() => _crossfadePlayer?.setVolume(1) ?? Future<void>.value());
  }

  /// Next song FOLLOWING the queue order (_playOrder). When shuffle is on,
  /// the shuffled order is fixed once up front, next never reshuffles.
  Future<void> next() async {
    if (_disposed) return;
    _playGeneration++;
    queueVersion++;
    _logListening();
    if (_sleepFadeActive) _cancelSleepFadeOut();
    _cancelPauseFade();
    _cancelCrossfade();
    _clearABRepeatSilent(); // new track, drop any A-B segment
    // Manual navigation means the user took over, so a pending "stop after
    // this song" sleep flag must not survive. The natural end path clears it
    // inside _onNaturalTrackEnd before it ever reaches these methods.
    _pendingSleepStop = false;
    await _vol(() => _crossfadePlayer?.pause() ?? Future<void>.value());
    _usingCrossfadePlayer = false;
    if (!crossfadeEnabled) _releaseCrossfadePlayer();
    if (_posInOrder < _playOrder.length - 1) {
      _posInOrder++;
    } else if (_repeatMode == SwaraRepeatMode.all) {
      _posInOrder = 0;
    } else {
      return; // already on the last song with no repeat, nothing to do
    }
    await _playCurrent();
  }

  /// Previous song FOLLOWING the queue order, truly steps one position
  /// back in _playOrder instead of picking a new random song.
  Future<void> previous() async {
    if (_disposed) return;
    _playGeneration++;
    queueVersion++;
    _logListening();
    if (_sleepFadeActive) _cancelSleepFadeOut();
    _cancelPauseFade();
    _cancelCrossfade();
    _clearABRepeatSilent(); // new track, drop any A-B segment
    // Manual navigation means the user took over, so a pending "stop after
    // this song" sleep flag must not survive. The natural end path clears it
    // inside _onNaturalTrackEnd before it ever reaches these methods.
    _pendingSleepStop = false;
    await _vol(() => _crossfadePlayer?.pause() ?? Future<void>.value());
    _usingCrossfadePlayer = false;
    if (!crossfadeEnabled) _releaseCrossfadePlayer();
    if (_posInOrder > 0) {
      _posInOrder--;
    } else if (_repeatMode == SwaraRepeatMode.all) {
      _posInOrder = _playOrder.length - 1;
    } else {
      _posInOrder = 0;
    }
    await _playCurrent();
  }

  DateTime? _lastPreviousPressAt;
  static const _previousDoubleTapWindow = Duration(seconds: 3);

  /// Smart "previous" logic shared by the player screen and the
  /// notification button: one press restarts the song, a second press
  /// within 3 seconds actually moves to the previous song.
  Future<void> smartPrevious() async {
    final now = DateTime.now();
    if (_lastPreviousPressAt != null && now.difference(_lastPreviousPressAt!) < _previousDoubleTapWindow) {
      _lastPreviousPressAt = null;
      await previous();
    } else {
      _lastPreviousPressAt = now;
      await _activePlayer.seek(Duration.zero);
      notifyListeners();
    }
  }

  Future<void> playAtQueueIndex(int posInOrder) async {
    if (_disposed) return;
    if (posInOrder < 0 || posInOrder >= _playOrder.length) return;
    _playGeneration++;
    queueVersion++;
    _logListening();
    if (_sleepFadeActive) _cancelSleepFadeOut();
    _cancelPauseFade();
    _cancelCrossfade();
    _clearABRepeatSilent(); // new track, drop any A-B segment
    // Manual navigation means the user took over, so a pending "stop after
    // this song" sleep flag must not survive. The natural end path clears it
    // inside _onNaturalTrackEnd before it ever reaches these methods.
    _pendingSleepStop = false;
    await _vol(() => _crossfadePlayer?.pause() ?? Future<void>.value());
    _usingCrossfadePlayer = false;
    if (!crossfadeEnabled) _releaseCrossfadePlayer();
    _posInOrder = posInOrder;
    await _playCurrent();
  }

  Future<void> playNext(Song song) async {
    if (_queue.isEmpty) {
      await setQueueAndPlay([song], 0);
      return;
    }
    // Inserting right after the current slot would shift the song an in
    // flight crossfade already captured its target position for, so the fade
    // would land on the wrong song. Drop the pending transition instead.
    _abortCrossfadeForQueueEdit();
    queueVersion++;
    _queue.add(song);
    _playOrder.insert(_posInOrder + 1, _queue.length - 1);
    // The next song changed, so any cached preload is stale.
    _preloadedFilePath = null;
    notifyListeners();
  }

  Future<void> addToQueueEnd(Song song) async {
    if (_queue.isEmpty) {
      await setQueueAndPlay([song], 0);
      return;
    }
    _abortCrossfadeForQueueEdit();
    queueVersion++;
    _queue.add(song);
    _playOrder.add(_queue.length - 1);
    notifyListeners();
  }

  /// Queue-slot IDs (original indices in _queue) for each _playOrder position,
  /// used by the UI so it can delete the correct song even when the list
  /// changed mid-swipe (a plain positional index may be stale, this slot ID is not).
  List<int> get queueSlotIds => List.unmodifiable(_playOrder);

  /// Position in _playOrder for a stable slot ID, or null when gone.
  int? queuePosForSlot(int slotId) {
    final pos = _playOrder.indexOf(slotId);
    if (pos == -1) return null;
    return pos;
  }

  /// Remove from the queue (position in _playOrder, not the currently playing item)
  void removeFromQueue(int posInOrder) {
    if (posInOrder == _posInOrder || posInOrder < 0 || posInOrder >= _playOrder.length) return;
    // The song a running crossfade is fading in is already loaded in the
    // standby player. Dropping it from the queue would leave that song
    // audible while the queue no longer contains it.
    if (isCrossfadeActive && posInOrder == pendingCrossfadePosition) return;
    queueVersion++;
    _playOrder.removeAt(posInOrder);
    if (posInOrder < _posInOrder) _posInOrder--;
    // Compact _queue: drop entries no longer referenced by any _playOrder slot
    // so _queue does not keep growing for the whole session without an app restart.
    _compactQueue();
    // Order changed, so any cached preload is stale.
    _preloadedFilePath = null;
    notifyListeners();
  }

  /// Drop _queue entries that are no longer in _playOrder.
  /// After compacting, remap every index in _playOrder to its new position.
  void _compactQueue() {
    final used = _playOrder.toSet();
    if (used.length == _queue.length) return; // nothing to drop

    // Build the old-index to new-index mapping
    final Map<int, int> remap = {};
    int newIdx = 0;
    final newQueue = <Song>[];
    for (int oldIdx = 0; oldIdx < _queue.length; oldIdx++) {
      if (used.contains(oldIdx)) {
        remap[oldIdx] = newIdx++;
        newQueue.add(_queue[oldIdx]);
      }
    }
    _queue = newQueue;
    _playOrder = _playOrder.map((old) => remap[old]!).toList();
  }

  /// Remove from the queue by (stable) slot ID instead of a plain positional
  /// index, safe to call from swipe-to-dismiss even when the list changed
  /// midway.
  void removeQueueSlot(int slotId) {
    final pos = _playOrder.indexOf(slotId);
    if (pos == -1) return; // already removed or changed first, safe to ignore
    queueVersion++;
    removeFromQueue(pos);
  }

  /// Drag reorder on the Queue page, only the _playOrder sequence changes
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _playOrder.length) return;
    if (newIndex < 0 || newIndex >= _playOrder.length) return;
    queueVersion++;
    final moved = _playOrder.removeAt(oldIndex);
    _playOrder.insert(newIndex, moved);

    if (oldIndex == _posInOrder) {
      _posInOrder = newIndex;
    } else if (oldIndex < _posInOrder && newIndex >= _posInOrder) {
      _posInOrder--;
    } else if (oldIndex > _posInOrder && newIndex <= _posInOrder) {
      _posInOrder++;
    }
    // Order changed, so any cached preload is stale.
    _preloadedFilePath = null;
    notifyListeners();
  }

  double get playbackSpeed => _speed;

  /// Current pitch multiplier (1.0 = untouched).
  double get playbackPitch => _pitch;

  /// Current playback speed as a display string, for example "1.0x".
  String get playbackSpeedLabel => '${_speed.toStringAsFixed(1)}x';

  /// Set the playback speed, clamped to speedMin..speedMax and applied to
  /// every player that exists right now (the standby player is only touched
  /// when it already exists, it is never created just for this).
  /// The platform call is throttled, so a slider drag stays cheap, and the
  /// new value is persisted (debounced) for the next app run.
  // TODO L10N: no user facing string added here, English only.
  Future<void> setPlaybackSpeed(double speed) async {
    if (_disposed) return;
    final clamped = speed.clamp(speedMin, speedMax).toDouble();
    if (clamped == _speed) return; // no real change, no notify and no apply
    _speed = clamped;
    notifyListeners();
    _scheduleSpeedPitchApply();
    _scheduleSpeedPitchPersist();
  }

  /// Set the pitch, clamped to pitchMin..pitchMax. Pitch is independent from
  /// speed: the tempo stays the same, only the tone height changes.
  // TODO L10N: no user facing string added here, English only.
  Future<void> setPlaybackPitch(double pitch) async {
    if (_disposed) return;
    final clamped = pitch.clamp(pitchMin, pitchMax).toDouble();
    if (clamped == _pitch) return; // no real change, no notify and no apply
    _pitch = clamped;
    notifyListeners();
    _scheduleSpeedPitchApply();
    _scheduleSpeedPitchPersist();
  }

  /// Restore both speed and pitch to 1.0 in one call.
  // TODO L10N: no user facing string added here, English only.
  Future<void> resetSpeedAndPitch() async {
    if (_disposed) return;
    _speed = 1.0;
    _pitch = 1.0;
    notifyListeners();
    _scheduleSpeedPitchApply();
    _scheduleSpeedPitchPersist();
  }

  /// Apply the current values now when the throttle window has passed, else
  /// queue exactly one trailing apply. That trailing call guarantees the last
  /// value always reaches the platform, while a drag stays limited to about
  /// one platform call per [speedPitchThrottleInterval].
  void _scheduleSpeedPitchApply() {
    if (_disposed) return;
    final last = _lastSpeedPitchApply;
    final since = last == null
        ? speedPitchThrottleInterval
        : DateTime.now().difference(last);
    if (_speedPitchApplyTimer != null) {
      // A trailing apply is already queued, it will pick up the newest value.
      return;
    }
    if (since >= speedPitchThrottleInterval) {
      _applySpeedPitchThrottled();
      return;
    }
    _speedPitchApplyTimer = Timer(speedPitchThrottleInterval - since, () {
      _speedPitchApplyTimer = null;
      _applySpeedPitchThrottled();
    });
  }

  Future<void> _applySpeedPitchThrottled() async {
    if (_disposed) return;
    _lastSpeedPitchApply = DateTime.now();
    await _applySpeedPitch();
  }

  /// Defer the prefs write so a slider drag never writes to disk more than
  /// once per [speedPitchPersistDelay].
  void _scheduleSpeedPitchPersist() {
    _speedPitchPersistTimer?.cancel();
    _speedPitchPersistTimer = Timer(
        speedPitchPersistDelay, _persistSpeedPitch);
  }

  Future<void> _persistSpeedPitch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsSpeedKey, _speed);
      await prefs.setDouble(_prefsPitchKey, _pitch);
    } catch (e) {
      debugPrint('Speed/pitch save failed: $e');
    }
  }

  /// Push the current speed and pitch to every player in the service.
  /// Errors are logged only, so a change can never break playback.
  Future<void> _applySpeedPitch() async {
    try {
      await _activePlayer.setSpeed(_speed);
      await _activePlayer.setPitch(_pitch);
      // Mirror on the standby player only when it already exists, so this
      // call never creates it. A player created later copies the values in
      // _ensureCrossfadePlayer.
      await _crossfadePlayer?.setSpeed(_speed);
      await _crossfadePlayer?.setPitch(_pitch);
    } catch (e) {
      debugPrint('Failed to set speed/pitch: $e');
    }
  }

  /// Toggle shuffle WITHOUT changing the currently playing song, only
  /// reorders the songs AFTER it (when ON) or restores the original
  /// order (when OFF).
  void toggleShuffle() {
    setShuffle(!_shuffle);
  }

  /// Set the shuffle state explicitly (not a toggle), used by the
  /// "Shuffle" button so it always TURNS shuffle on instead of turning it off.
  void setShuffle(bool value) {
    _shuffle = value;
    final song = currentSong;
    if (song == null) {
      notifyListeners();
      return;
    }
    final currentQueueIndex = _playOrder[_posInOrder];

    if (_shuffle) {
      final rest = List.generate(_queue.length, (i) => i)..remove(currentQueueIndex);
      _playOrder = [currentQueueIndex, ..._shuffleRest(rest)];
      _posInOrder = 0;
    } else {
      _playOrder = List.generate(_queue.length, (i) => i);
      _posInOrder = currentQueueIndex;
    }
    // Order changed, so any cached preload is stale.
    _preloadedFilePath = null;
    notifyListeners();
  }

  /// True when shuffle uses the weighted order (rare and long unplayed first).
  bool get smartShuffle => _smartShuffle;

  /// Enable or disable smart shuffle and persist the choice. Turning it on
  /// refreshes the play statistics, then reorders the songs after the current
  /// one so the change is visible right away.
  // TODO L10N: no user facing string added here, English only.
  Future<void> setSmartShuffle(bool value) async {
    if (_smartShuffle == value) return;
    _smartShuffle = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsSmartShuffleKey, value);
    } catch (e) {
      debugPrint('Smart shuffle save failed: $e');
    }
    if (!value) return;
    await refreshSmartShuffleStats();
    // Reorder the tail only when shuffle is active and something is playing,
    // so the current song is never interrupted.
    if (_shuffle && currentSong != null) {
      final currentQueueIndex = _playOrder[_posInOrder];
      final rest = List.generate(_queue.length, (i) => i)
        ..remove(currentQueueIndex);
      _playOrder = [currentQueueIndex, ..._shuffleRest(rest)];
      _posInOrder = 0;
      _preloadedFilePath = null;
      notifyListeners();
    }
  }

  /// Load the play counts used by smart shuffle from the listening history.
  /// The Song model carries no play count or last played field, so the counts
  /// come from DBHelper.getTopSongIdsSince.
  ///
  /// The last played stamps are loaded here too. They used to be filled only
  /// by [_markSongPlayed] while the app ran, so every launch started with an
  /// empty map: each song scored the maximum staleness and the staleness half
  /// of the weight did nothing at all. Both maps now come from the database on
  /// the same pass, and [_markSongPlayed] still overwrites an entry the moment
  /// a song starts, so a song played in this session is never stale.
  ///
  /// Fire and forget: on failure the previous (or empty) maps stay in place
  /// and smart shuffle falls back to a plain shuffle.
  // TODO L10N: no user facing string added here, English only.
  Future<void> refreshSmartShuffleStats() async {
    try {
      final rows = await DBHelper.instance.getTopSongIdsSince(
        DateTime(2000).toIso8601String(),
        limit: 500,
      );
      _playCounts = {for (final e in rows) e.key: e.value};
      final stamps = await DBHelper.instance.getLastPlayedStamps(limit: 500);
      // Merge, never replace: a song already played in this session has an in
      // memory stamp from _markSongPlayed that is newer than the row on disk,
      // so only fill a missing entry or one that the database moved forward.
      for (final entry in stamps.entries) {
        final current = _lastPlayTimes[entry.key];
        if (current == null || entry.value.isAfter(current)) {
          _lastPlayTimes[entry.key] = entry.value;
        }
      }
    } catch (e) {
      debugPrint('Smart shuffle stats load failed: $e');
    }
  }

  /// Remember that a song just started, so the next smart shuffle order can
  /// rank it lower. Called from every play path (normal load and crossfade).
  void _markSongPlayed(Song song) {
    _lastPlayTimes[song.id] = DateTime.now();
  }

  void cycleRepeatMode() {
    _repeatMode = SwaraRepeatMode.values[(_repeatMode.index + 1) % SwaraRepeatMode.values.length];
    notifyListeners();
  }

  /// Set the A-B repeat segment. Returns false when invalid: A must be
  /// before B, and both must fit inside the current track duration
  /// (when the duration is known).
  // TODO L10N: no user facing string added here, English only.
  bool setABRepeat(Duration a, Duration b) {
    if (a < Duration.zero || a >= b) return false;
    final dur = _activePlayer.duration;
    if (dur != null && (b > dur || a >= dur)) return false;
    // A crossfade in flight would end this track and silently drop the A-B
    // segment a moment later, leaving the UI showing a loop that no longer
    // runs. A deliberate A-B choice wins over a pending automatic fade.
    _abortCrossfadeForQueueEdit();
    _abRepeatA = a;
    _abRepeatB = b;
    notifyListeners();
    return true;
  }

  /// Turn A-B repeat off.
  void clearABRepeat() {
    if (_abRepeatA == null && _abRepeatB == null) return;
    _clearABRepeatSilent();
    notifyListeners();
  }

  /// Drop the A-B segment without notifying. Used on track changes where
  /// the caller notifies anyway.
  void _clearABRepeatSilent() {
    _abRepeatA = null;
    _abRepeatB = null;
  }

  void setCrossfadeEnabled(bool value) {
    crossfadeEnabled = value;
    if (!value) {
      // Cancel any fade in flight and drop any stale crossfade state.
      // A fresh gap preload is prepared below, so the idle player keeps
      // at most one cached file while crossfade stays off. When the
      // standby player is currently audible, the release is deferred to
      // the next track change inside _releaseCrossfadePlayer.
      _cancelCrossfade();
      _releaseCrossfadePlayer();
      // Refresh the gap preload for the new mode.
      _preloadNextSong();
    } else {
      // Preload cache is only used when crossfade is off.
      _preloadedFilePath = null;
    }
    notifyListeners();
  }

  // Set the crossfade overlap, clamped to 0..12 seconds and persisted.
  // 0 keeps crossfade on but switches directly with no overlap.
  // TODO L10N: no user facing string added here, English only.
  Future<void> setCrossfadeDuration(Duration duration) async {
    final clamped = duration.inSeconds
        .clamp(crossfadeMinSeconds, crossfadeMaxSeconds);
    crossfadeDuration = Duration(seconds: clamped);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsCrossfadeSecondsKey, clamped);
    } catch (e) {
      debugPrint('Crossfade duration save failed: $e');
    }
  }

  // Same as setCrossfadeDuration but takes whole seconds from a slider.
  // TODO L10N: no user facing string added here, English only.
  Future<void> setCrossfadeSeconds(int seconds) {
    return setCrossfadeDuration(Duration(seconds: seconds));
  }

  /// Time-based sleep timer with a countdown.
  /// [finishCurrentSong] true = do not stop right when the time runs out, but
  /// wait until the currently playing song ends before stopping.
  void setSleepTimer(Duration duration, {bool finishCurrentSong = false}) {
    _sleepTimer?.cancel();
    _cancelSleepFadeOut();
    sleepSongsRemaining = null; // time mode and song-count mode are mutually exclusive
    // A pending stop belongs to the timer that armed it. Starting a new
    // timer must clear it, otherwise a stale flag from an earlier session
    // (for example one that ended while the user navigated manually) would
    // stop the next session after a single song.
    _pendingSleepStop = false;
    sleepTimerEndTime = DateTime.now().add(duration);
    _finishCurrentSongOnSleep = finishCurrentSong;
    _sleepTimer = Timer(duration, () async {
      sleepTimerEndTime = null;
      if (_finishCurrentSongOnSleep) {
        _pendingSleepStop = true; // handled in _onTrackFinished()
      } else {
        await _startSleepFadeOut();
        return;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  /// Song-count based sleep timer - stops automatically after N songs
  /// (counted from the currently playing song, inclusive).
  void setSleepTimerBySongs(int songCount) {
    _sleepTimer?.cancel();
    _cancelSleepFadeOut();
    sleepTimerEndTime = null; // time mode and song-count mode are mutually exclusive
    // Song count mode has its own stop decision, so no pending time based
    // stop may survive the switch.
    _pendingSleepStop = false;
    sleepSongsRemaining = songCount;
    notifyListeners();
  }

  /// True while the running time based timer waits for the current song to
  /// finish instead of stopping at once. Lets the UI seed its checkbox from
  /// the service instead of a stale local default.
  bool get finishCurrentSongOnSleep => _finishCurrentSongOnSleep;

  /// Update whether the running time based timer waits for the current
  /// song to finish instead of fading out at once.
  /// TODO L10N: no user facing string added here, English only.
  void setFinishCurrentSongOnSleep(bool value) {
    _finishCurrentSongOnSleep = value;
    // Turning the option off must also cancel an already armed pending stop,
    // otherwise the session still ends with the current song.
    if (!value) _pendingSleepStop = false;
    notifyListeners();
  }

  Duration? get sleepTimerRemaining {
    if (sleepTimerEndTime == null) return null;
    final remaining = sleepTimerEndTime!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// True while the 30 second sleep fade out is running.
  bool get isSleepFadeOutActive => _sleepFadeActive;

  /// Cancel an in flight sleep fade and restore full volume.
  /// Used when the user cancels the timer or resumes playback mid fade.
  void _cancelSleepFadeOut() {
    if (!_sleepFadeActive) return;
    _sleepFadeGeneration++;
    _sleepFadeActive = false;
    // Restore full volume through the chain so a resume starts loud.
    // Errors are only logged because this runs from sync UI handlers.
    _vol(() => _player.setVolume(1));
    _vol(() => _crossfadePlayer?.setVolume(1) ?? Future<void>.value());
  }

  /// Fade the audible output to 0 over [sleepFadeDuration] then pause.
  /// Cancels silently when the generation changes (user cancel or play).
  Future<void> _startSleepFadeOut() async {
    if (_disposed) return;
    _cancelPauseFade();
    final isPlaying =
        _player.playing || (_crossfadePlayer?.playing ?? false);
    if (!isPlaying) {
      _logListening();
      await _unsubscribePosition();
      notifyListeners();
      return;
    }
    _sleepFadeActive = true;
    final generation = ++_sleepFadeGeneration;
    notifyListeners();
    const steps = 30;
    final stepDuration = sleepFadeDuration ~/ steps;
    for (int i = 1; i <= steps; i++) {
      await Future.delayed(stepDuration);
      if (_disposed) return;
      if (!_sleepFadeActive || generation != _sleepFadeGeneration) return;
      final v = (1 - i / steps).clamp(0.0, 1.0);
      await _vol(() => _player.setVolume(v));
      if (!_sleepFadeActive || generation != _sleepFadeGeneration) return;
      await _vol(
          () => _crossfadePlayer?.setVolume(v) ?? Future<void>.value());
    }
    if (_disposed) return;
    if (!_sleepFadeActive || generation != _sleepFadeGeneration) return;
    _sleepFadeActive = false;
    _logListening();
    // Pause both players so playback really stops even mid crossfade.
    await _vol(() => _player.pause());
    await _vol(
        () => _crossfadePlayer?.pause() ?? Future<void>.value());
    // Reset volume for the next manual play.
    await _vol(() => _player.setVolume(1));
    await _vol(
        () => _crossfadePlayer?.setVolume(1) ?? Future<void>.value());
    // No crossfade trigger needed while paused, save battery.
    await _unsubscribePosition();
    notifyListeners();
  }

  /// Prepare the next song file in the idle player when crossfade is off.
  /// Loads the file only (never plays). Errors are ignored silently
  /// apart from a debug log so preload never breaks playback.
  void _preloadNextSong() {
    if (crossfadeEnabled) return;
    if (_disposed) return;
    if (_playOrder.isEmpty) return;
    final nextPos = _computeNextPosition();
    if (nextPos == null) return;
    if (nextPos == _posInOrder) return; // repeat-one, already loaded
    final nextSong = _queue[_playOrder[nextPos]];
    if (_preloadedFilePath == nextSong.filePath) return;
    final AudioPlayer idle;
    if (_usingCrossfadePlayer) {
      idle = _player;
    } else {
      try {
        idle = _ensureCrossfadePlayer();
      } catch (e) {
        debugPrint('Preload next failed: $e');
        return;
      }
    }
    final path = nextSong.filePath;
    idle.setFilePath(path).then((_) {
      if (_disposed) return null;
      if (crossfadeEnabled) return null;
      return _syncSpeedPitch(idle);
    }).then((_) {
      if (_disposed) return;
      if (crossfadeEnabled) return;
      _preloadedFilePath = path;
    }).catchError((Object e) {
      debugPrint('Preload next failed: $e');
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerEndTime = null;
    sleepSongsRemaining = null;
    _pendingSleepStop = false;
    _cancelSleepFadeOut();
    notifyListeners();
  }

  // ---------- Daily sleep schedule ----------

  /// Today target time for the configured hour and minute.
  DateTime _sleepScheduleTargetToday([DateTime? now]) {
    final n = now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day, _sleepScheduleHour, _sleepScheduleMinute);
  }

  /// When a schedule is armed (or changed) at a moment when today's target
  /// time has already passed, today is marked as already served so the
  /// automatic session waits for tomorrow instead of firing retroactively.
  void _skipTodayIfAlreadyPast() {
    final now = DateTime.now();
    if (now.isAfter(_sleepScheduleTargetToday(now))) {
      _sleepScheduleFiredDay = _dayStamp(now);
    } else {
      _sleepScheduleFiredDay = null;
    }
  }

  /// True when a daily sleep schedule is armed.
  bool get sleepScheduleEnabled => _sleepScheduleEnabled;

  /// Scheduled hour in 24h format (0..23).
  int get sleepScheduleHour => _sleepScheduleHour;

  /// Scheduled minute (0..59).
  int get sleepScheduleMinute => _sleepScheduleMinute;

  /// Arm or disarm the daily sleep schedule and persist the flag. Enabling
  /// starts the single ticker, disabling cancels it, so no timer ever leaks.
  // TODO L10N: no user facing string added here, English only.
  Future<void> setSleepScheduleEnabled(bool value) async {
    if (_sleepScheduleEnabled == value) return;
    _sleepScheduleEnabled = value;
    if (!value) {
      _stopSleepScheduleTicker();
    } else {
      // A freshly enabled schedule may still fire today, but only when the
      // configured time has not passed yet.
      _skipTodayIfAlreadyPast();
      _startSleepScheduleTicker();
      _checkSleepSchedule();
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsSleepScheduleEnabledKey, value);
    } catch (e) {
      debugPrint('Sleep schedule save failed: $e');
    }
  }

  /// Change the scheduled time. Values outside the valid range are clamped.
  // TODO L10N: no user facing string added here, English only.
  Future<void> setSleepScheduleTime(int hour, int minute) async {
    final h = hour.clamp(0, 23).toInt();
    final m = minute.clamp(0, 59).toInt();
    if (h == _sleepScheduleHour && m == _sleepScheduleMinute) return;
    _sleepScheduleHour = h;
    _sleepScheduleMinute = m;
    // A new time deserves a fresh chance today, unless it already passed.
    _skipTodayIfAlreadyPast();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsSleepScheduleHourKey, h);
      await prefs.setInt(_prefsSleepScheduleMinuteKey, m);
    } catch (e) {
      debugPrint('Sleep schedule time save failed: $e');
    }
    if (_sleepScheduleEnabled) _checkSleepSchedule();
  }

  /// (Re)start the schedule ticker. Cancels first, so only one timer ever
  /// exists no matter how often this is called.
  void _startSleepScheduleTicker() {
    _stopSleepScheduleTicker();
    if (_disposed || !_sleepScheduleEnabled) return;
    _sleepScheduleTicker =
        Timer.periodic(sleepScheduleTickInterval, (_) => _checkSleepSchedule());
  }

  void _stopSleepScheduleTicker() {
    _sleepScheduleTicker?.cancel();
    _sleepScheduleTicker = null;
  }

  /// Day stamp used to make sure the schedule fires at most once per day.
  static String _dayStamp(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// True while a sleep timer, song countdown or fade out is already running.
  bool get _sleepSessionActive =>
      sleepTimerEndTime != null ||
      sleepSongsRemaining != null ||
      _sleepFadeActive;

  /// Poll callback for the daily schedule. Fires the automatic 30 minute
  /// session only when the configured time has been reached today, nothing is
  /// already scheduled, and the schedule has not run yet on this day.
  void _checkSleepSchedule() {
    if (_disposed || !_sleepScheduleEnabled) return;
    if (_sleepSessionActive) return;
    final now = DateTime.now();
    final today = _dayStamp(now);
    if (_sleepScheduleFiredDay == today) return;
    // Only trigger once the configured time has been reached, so a schedule
    // set for a later hour today never fires early.
    if (now.isBefore(_sleepScheduleTargetToday(now))) return;
    _sleepScheduleFiredDay = today;
    setSleepTimer(sleepScheduleDuration);
  }

  /// Shared natural track end completion used by both the normal completion
  /// listener and the crossfade swap path. Applies the sleep decrement first,
  /// then the pending sleep stop, then the repeat one decision. Stop paths
  /// pause both players, restore full volume on both, stop position updates,
  /// and notify. Returns whether playback should continue to the next song.
  _TrackEndDecision _onNaturalTrackEnd() {
    // Song count mode: decrement by 1, stop when exhausted.
    if (sleepSongsRemaining != null) {
      sleepSongsRemaining = sleepSongsRemaining! - 1;
      if (sleepSongsRemaining! <= 0) {
        sleepSongsRemaining = null;
        _logListening();
        // Fire and forget with an error guard, called from sync listeners.
        _pauseBothForSleep();
        // Stop position updates while paused to save battery.
        _unsubscribePosition();
        notifyListeners();
        return _TrackEndDecision.stop;
      }
    }
    // Time mode with finish last song: the song that just ended was the last one.
    if (_pendingSleepStop) {
      _pendingSleepStop = false;
      _logListening();
      _pauseBothForSleep();
      // Stop position updates while paused to save battery.
      _unsubscribePosition();
      notifyListeners();
      return _TrackEndDecision.stop;
    }
    if (_repeatMode == SwaraRepeatMode.one) {
      return _TrackEndDecision.repeatOne;
    }
    return _TrackEndDecision.advance;
  }

  /// Pause both players for a sleep stop and always restore full volume on
  /// both, so the next manual play starts loud.
  void _pauseBothForSleep() {
    _vol(() => _player.pause()).then((_) => _vol(() => _player.setVolume(1)));
    final standby = _crossfadePlayer;
    if (standby == null) return;
    standby.pause().catchError((Object e) {
      debugPrint('Failed to pause for sleep timer: $e');
    }).then((_) => standby.setVolume(1)).catchError((Object e) {
      debugPrint('Failed to reset volume for sleep timer: $e');
    });
  }

  void _onTrackFinished() {
    if (_disposed) return;
    final decision = _onNaturalTrackEnd();
    if (decision == _TrackEndDecision.stop) return;

    if (decision == _TrackEndDecision.repeatOne) {
      // Repeat one restarts the same song on the main player. Without bumping
      // the generation and stopping the standby player, a crossfade that was
      // still fading in kept playing at a low volume in the background.
      _playGeneration++;
      _stopStandbyPlayer();
      _usingCrossfadePlayer = false;
      _cancelCrossfade();
      _cancelPauseFade();
      if (!crossfadeEnabled) _releaseCrossfadePlayer();
      _playCurrent().then((_) {}, onError: (Object e) {
        debugPrint('Failed repeat-one: $e');
      });
      return;
    }
    next().then((_) {}, onError: (Object e) {
      debugPrint('Failed next: $e');
    });
  }

  void _logListening() {
    if (_disposed) return;
    if (_playStartedAt == null || currentSong == null) return;
    final elapsed = DateTime.now().difference(_playStartedAt!).inMilliseconds;
    _accumulatedListenedMs += elapsed;
    _playStartedAt = null;

    if (_accumulatedListenedMs > 1000) {
      // Do not await here (called from a sync listener) but catch
      // errors so a corrupt DB or full disk cannot become an unhandled async error.
      DBHelper.instance
          .addListeningEntry(ListeningEntry(
        songId: currentSong!.id,
        timestamp: DateTime.now(),
        listenedMs: _accumulatedListenedMs,
      ))
          .catchError((e) {
        debugPrint('Failed to save listening history: $e');
      });
    }
    _accumulatedListenedMs = 0;
  }

  @override
  void dispose() {
    // NOTE: _disposed is set at the very END of this method on purpose.
    // _logListening() bails out when _disposed is true, so flagging it first
    // would silently drop the final listening history flush.
    _cancelCrossfade();
    _sleepFadeGeneration++;
    _sleepFadeActive = false;
    _pauseFadeGeneration++;
    _pauseFadeOutActive = false;
    _preloadedFilePath = null;
    _logListening();
    _sleepTimer?.cancel();
    // Fire and forget: dispose is sync, the cancel future still runs.
    _unsubscribePosition();
    _playerStateSub?.cancel();
    _crossfadeStateSub?.cancel();
    _sleepScheduleTicker?.cancel();
    _sleepScheduleTicker = null;
    _speedPitchApplyTimer?.cancel();
    _speedPitchApplyTimer = null;
    // A pending speed/pitch write must still reach disk.
    if (_speedPitchPersistTimer?.isActive ?? false) {
      _speedPitchPersistTimer!.cancel();
      unawaited(_persistSpeedPitch());
    }
    _speedPitchPersistTimer = null;
    // ChangeNotifier.dispose() is sync void, never turn it into a Future.
    // Players are disposed fire and forget because the singleton lives for the whole app run.
    _player.dispose().catchError((e) {
      debugPrint('Failed to dispose player: $e');
    });
    _crossfadePlayer?.dispose().catchError((e) {
      debugPrint('Failed to dispose crossfade player: $e');
    });
    _crossfadePlayer = null;
    unawaited(EqualizerService.instance.release());
    // Everything above needed _disposed to be false. Set it last, right
    // before super.dispose(), so no async callback can slip in afterwards.
    _disposed = true;
    super.dispose();
  }
}

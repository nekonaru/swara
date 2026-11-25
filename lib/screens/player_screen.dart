import 'dart:async';
import '../utils/motion.dart';
import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../services/metadata_service.dart';
import '../services/db_helper.dart';
import '../utils/lrc.dart';
import '../utils/format.dart';
import '../providers/library_provider.dart';
import '../providers/playlist_provider.dart';
import '../utils/song_options.dart';
import '../widgets/marquee_text.dart';
import '../widgets/song_art_image.dart';
import '../widgets/sleep_timer_sheet.dart';
import 'edit_lyrics_screen.dart';
import 'queue_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin {
  final _player = PlayerService.instance;
  bool _showLyrics = false;
  bool _isFetchingLyrics = false;
  // Drag distance for the dismiss swipe, as a notifier so pointer events
  // repaint only the translate/opacity wrapper, never the whole scaffold.
  final ValueNotifier<double> _dragOffset = ValueNotifier(0);
  // True only when the vertical swipe started in the top art zone.
  // Keeps lyric scroll gestures below that zone from dismissing the screen.
  bool _verticalDismissArmed = false;

  // Synced (LRC) lyrics state. Lines load once per song from the DB,
  // then a positionStream listener highlights the active line.
  final ScrollController _lrcScrollController = ScrollController();
  StreamSubscription<Duration>? _lrcPositionSub;
  List<LrcLine> _lrcLines = [];
  int _lrcIndex = -1;
  int? _lrcSongId;
  bool _lrcLoading = false;
  bool _syncedMode = true;
  // Timing shift declared by the LRC file itself, in milliseconds.
  int _lrcFileOffsetMs = 0;
  // User correction applied on top of the file offset, in milliseconds.
  // Reset to 0 whenever the song changes, because a correction that fits
  // one song never fits the next one.
  int _lrcManualOffsetMs = 0;
  // Debounced save: nudges can arrive faster than a DB write per tap.
  Timer? _lrcOffsetSaveTimer;
  int? _pendingOffsetSongId;
  int _pendingOffsetMs = 0;
  // Generations make an older lyric load harmless when lyrics are edited
  // while that load is still in flight.
  int _lrcLoadGeneration = 0;
  // Re-point the lyric follower when the audible player changes (repeat-one
  // crossfades keep the same song id but swap the AudioPlayer instance).
  int _lrcFlipCount = -1;
  bool _lyricsSyncScheduled = false;
  DateTime? _lastSeekCommit;

  /// Fixed height of a single synced lyric row. The list uses this as its
  /// itemExtent, so the scroll estimate below is always exact.
  static const double _kLrcLineHeight = 44;
  /// Vertical target of the active row inside the viewport (0 top, 1 bottom).
  static const double _kLrcTargetAlignment = 0.4;
  static const int _kLrcOffsetStepMs = 100;

  // Smooth return when a dismiss drag does not cross the threshold.
  late final AnimationController _returnController;
  double _returnStart = 0;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerForLyrics);
    _player.lyricsRevision.addListener(_onLyricsRevision);
    _returnController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200))
      ..addListener(() {
        if (mounted) {
          _dragOffset.value = _returnStart * (1 - _returnController.value);
        }
      });
  }

  void _onPlayerForLyrics() {
    final song = _player.currentSong;
    if (song == null) return;
    if (song.id != _lrcSongId ||
        _lrcFlipCount != _player.playbackFlipCount ||
        (_showLyrics && _lrcPositionSub == null)) {
      _lrcFlipCount = _player.playbackFlipCount;
      _scheduleLyricsSync(song);
    }
  }

  Future<void> _onLyricsRevision() async {
    final song = _player.currentSong;
    if (song == null || !mounted) return;
    // A nudge right before the edit must reach the DB before the reload
    // reads the saved offset back.
    await _flushPendingLrcOffset();
    _lrcLoadGeneration++;
    _lrcLoading = false;
    _lrcSongId = -1;
    _scheduleLyricsSync(song);
  }

  void _scheduleLyricsSync(Song song) {
    if (_lyricsSyncScheduled) return;
    _lyricsSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lyricsSyncScheduled = false;
      if (!mounted) return;
      unawaited(_maybeLoadSyncedLyrics(song));
      if (_lrcLines.isNotEmpty && _syncedMode && _showLyrics) {
        _startLrcFollow();
      }
    });
  }

  /// throttle native seeks during a slider drag; the final value is always
  /// applied when the drag ends.
  void _commitSeek(double milliseconds) {
    final now = DateTime.now();
    if (_lastSeekCommit != null &&
        now.difference(_lastSeekCommit!).inMilliseconds < 120) {
      return;
    }
    _lastSeekCommit = now;
    _player.activePlayer.seek(Duration(milliseconds: milliseconds.toInt())).catchError((_) {});
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerForLyrics);
    _player.lyricsRevision.removeListener(_onLyricsRevision);
    _lrcOffsetSaveTimer?.cancel();
    unawaited(_flushPendingLrcOffset());
    _returnController.dispose();
    // If the slider is disposed mid-drag, release the seek guard so A-B
    // repeat and crossfade triggers are not suppressed for the rest of the
    // session.
    _player.setUserSeeking(false);
    _stopLrcFollow();
    _lrcScrollController.dispose();
    _dragOffset.dispose();
    super.dispose();
  }

  void _onPreviousPressed() => _player.smartPrevious();

  Future<void> _pickSleepTimer() async {
    // The timer is set directly inside SleepTimerSheet._start()
    // so there is no return value to handle here.
    await showSleepTimerSheet(context);
  }

  Future<void> _pickPlaybackSpeed() async {
    final l10n = AppLocalizations.of(context)!;
    // Mutable locals so the StatefulBuilder readouts follow the sliders.
    var speed = _player.playbackSpeed
        .clamp(PlayerService.speedMin, PlayerService.speedMax)
        .toDouble();
    var pitch = _player.playbackPitch
        .clamp(PlayerService.pitchMin, PlayerService.pitchMax)
        .toDouble();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        // StatefulBuilder keeps the numeric readouts live while dragging.
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.playerPlaybackSpeed,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          SizedBox(
                            width: 56,
                            child: Text(l10n.playerSpeed,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Expanded(
                            child: Slider(
                              value: speed,
                              min: PlayerService.speedMin,
                              max: PlayerService.speedMax,
                              divisions: 15,
                              label: '${speed.toStringAsFixed(2)}x',
                              // While dragging only the local readout
                              // changes, so a drag never rebuilds the whole
                              // player screen (art, lyrics, buttons) per frame.
                              onChanged: (v) {
                                speed = v;
                                setSheetState(() {});
                              },
                              // The final value is committed once, when the
                              // finger is released.
                              onChangeEnd: (v) => _player.setPlaybackSpeed(v),
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              '${speed.toStringAsFixed(2)}x',
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(l10n.playerPitch,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          SizedBox(
                            width: 56,
                            child: Text(l10n.playerPitch,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Expanded(
                            child: Slider(
                              value: pitch,
                              min: PlayerService.pitchMin,
                              max: PlayerService.pitchMax,
                              divisions: 15,
                              label: pitch.toStringAsFixed(2),
                              // Same as the speed slider: local readout while
                              // dragging, one commit on release.
                              onChanged: (v) {
                                pitch = v;
                                setSheetState(() {});
                              },
                              onChangeEnd: (v) => _player.setPlaybackPitch(v),
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              pitch.toStringAsFixed(2),
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: () {
                          speed = 1.0;
                          pitch = 1.0;
                          _player.resetSpeedAndPitch();
                          Navigator.pop(ctx);
                        },
                        child: Text(l10n.playerSpeedPitchReset),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Small A-B repeat dialog: capture A and B from the current position,
  /// apply the loop when both are valid, or clear it.
  Future<void> _showABRepeatDialog() async {
    final l10n = AppLocalizations.of(context)!;
    Duration? a = _player.abRepeatA;
    Duration? b = _player.abRepeatB;
    String? hint;
    bool changed = false;
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final dl10n = AppLocalizations.of(ctx)!;
          void tryApply() {
            if (a != null && b != null) {
              if (_player.setABRepeat(a!, b!)) {
                hint = null;
                changed = true;
              } else {
                hint = dl10n.abHintInvalid;
              }
            }
          }

          return AlertDialog(
            title: Text(dl10n.abTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('A: ${a == null ? '-' : _fmt(a!)}'),
                Text('B: ${b == null ? '-' : _fmt(b!)}'),
                if (hint != null) ...[
                  const SizedBox(height: 8),
                  Text(hint!,
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _player.clearABRepeat();
                  Navigator.pop(ctx, true);
                },
                child: Text(dl10n.abClear),
              ),
              TextButton(
                onPressed: () {
                  final pos = _player.activePlayer.position;
                  setDialogState(() {
                    a = pos;
                    if (b != null && a! >= b!) {
                      b = null;
                      hint = dl10n.abHintSetB;
                    } else {
                      hint = null;
                      tryApply();
                    }
                  });
                },
                child: Text(dl10n.abSetA),
              ),
              TextButton(
                onPressed: () {
                  final pos = _player.activePlayer.position;
                  setDialogState(() {
                    b = pos;
                    if (a == null) {
                      hint = dl10n.abHintSetA;
                    } else if (a! >= b!) {
                      hint = dl10n.abHintBAfterA;
                    } else {
                      hint = null;
                      tryApply();
                    }
                  });
                },
                child: Text(dl10n.abSetB),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, changed),
                child: Text(dl10n.abDone),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || applied != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_player.hasABRepeat
            ? l10n.abOn(
                _fmt(_player.abRepeatA!), _fmt(_player.abRepeatB!))
            : l10n.abOff),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _searchLyricsOnGoogle(Song song) async {
    final query = Uri.encodeComponent('${song.artist} ${song.title} lyrics lirik');
    final url = Uri.parse('https://www.google.com/search?q=$query');
    // No canLaunchUrl gate here: on Android 11+ the http/https check is always
    // false without a <queries> manifest entry, which blocked the browser
    // completely. Launching directly works, failures are reported by the
    // thrown exception or the false return value instead.
    try {
      final launched =
          await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.playerCannotOpenBrowser)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.playerSearchOpenFailed)),
        );
      }
    }
  }

  Future<void> _autoFetchLyrics(Song song) async {
    if (_isFetchingLyrics) return;
    setState(() => _isFetchingLyrics = true);
    var found = false;
    try {
      // fetchLyricsOnly does NOT overwrite title/artist/album (unlike enrichSong),
      // so manual user edits are safe; it only fills song.lyrics.
      found = await MetadataService.instance.fetchLyricsOnly(song);
      if (found && mounted) {
        await context.read<LibraryProvider>().updateMetadata(song);
        found = song.lyrics?.trim().isNotEmpty ?? false;
      }
    } catch (_) {
      found = song.lyrics?.trim().isNotEmpty ?? false;
    }
    if (!mounted) return;
    setState(() => _isFetchingLyrics = false);
    // fetchLyricsOnly also refreshes the synced store, so reload the lines.
    _lrcSongId = null;
    await _maybeLoadSyncedLyrics(song);
    if (!mounted) return;
    // A lookup can succeed with only synced LRC lines and leave plain
    // lyrics empty, so the "not found" message must consider both views.
    if (_lrcLines.isNotEmpty) found = true;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(found ? l10n.playerLyricsFound : l10n.playerLyricsNotFoundHint),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).size.height * 0.55),
      ),
    );
  }

  /// Show or hide the lyrics view, starting or stopping the synced
  /// line follower so no position updates arrive while it is hidden.
  void _setShowLyrics(bool value) {
    if (_showLyrics == value) return;
    setState(() => _showLyrics = value);
    if (value) {
      if (_lrcLines.isNotEmpty && _syncedMode) _startLrcFollow();
    } else {
      _stopLrcFollow();
    }
  }

  /// Load synced lyrics for [song] once per song from the DB and parse
  /// them into display lines. Safe to call from build: guarded by song id.
  Future<void> _maybeLoadSyncedLyrics(Song song) async {
    // Leaving a song before the debounce fires must not lose the correction.
    if (_pendingOffsetSongId != null && _pendingOffsetSongId != song.id) {
      await _flushPendingLrcOffset();
    }
    // If a different song asks for lyrics while an older load is in flight,
    // invalidate that load before the early return. Otherwise the stale load
    // keeps the current generation and wins when it finishes.
    if (_lrcLoading && _lrcSongId != song.id) {
      _lrcLoadGeneration++;
      _lrcLoading = false;
      _lrcSongId = -1;
    }
    if (_lrcSongId == song.id || _lrcLoading) return;
    final generation = ++_lrcLoadGeneration;
    _lrcSongId = song.id;
    _lrcLoading = true;
    _lrcLines = [];
    _lrcIndex = -1;
    _lrcFileOffsetMs = 0;
    _stopLrcFollow();
    try {
      // A manual correction belongs to one song, so reload the saved value
      // whenever the song changes. A DB error must still release _lrcLoading.
      _lrcManualOffsetMs =
          await DBHelper.instance.getSyncedLyricOffset(song.id);
      if (generation != _lrcLoadGeneration) return;
      final lrc = await DBHelper.instance.getSyncedLyrics(song.id);
      if (!mounted || generation != _lrcLoadGeneration) return;
      final hasLrc = lrc != null && lrc.isNotEmpty;
      final lines = hasLrc ? parseLrc(lrc) : <LrcLine>[];
      // Split once and reuse the lines for the offset scan instead of
      // scanning the file content twice.
      final lrcLinesRaw = hasLrc ? lrc.split('\n') : const <String>[];
      setState(() {
        _lrcLoading = false;
        _lrcLines = lines;
        _lrcIndex = -1;
        // parseLrc already folded this into the timestamps; keep the value
        // for display and for the manual offset readout.
        _lrcFileOffsetMs =
            lrcLinesRaw.isEmpty ? 0 : (parseLrcOffsetMs(lrcLinesRaw) ?? 0);
        // Default to synced view when lines exist, plain text otherwise.
        _syncedMode = lines.isNotEmpty;
      });
      if (lines.isNotEmpty && _showLyrics && _syncedMode) _startLrcFollow();
    } catch (_) {
      if (!mounted || generation != _lrcLoadGeneration) return;
      setState(() {
        _lrcLoading = false;
        _lrcLines = const <LrcLine>[];
        _syncedMode = false;
      });
    }
  }

  /// Follow the player position and highlight the active synced line.
  /// Rebuilds only when the active line index actually changes.
  void _startLrcFollow() {
    _stopLrcFollow();
    if (!_syncedMode || _lrcLines.isEmpty) return;
    _lrcPositionSub = _player.activePlayer.positionStream.listen((pos) {
      if (!mounted) return;
      final idx = _lrcIndexFor(pos.inMilliseconds);
      if (idx == _lrcIndex) return;
      setState(() => _lrcIndex = idx);
      _scrollToLrcLine(idx);
    });
  }

  void _stopLrcFollow() {
    _lrcPositionSub?.cancel();
    _lrcPositionSub = null;
  }

  /// Switch between the synced and plain lyric views.
  void _setSyncedMode(bool value) {
    if (_syncedMode == value) return;
    setState(() {
      _syncedMode = value;
      _lrcIndex = -1;
    });
    if (value) {
      _startLrcFollow();
    } else {
      _stopLrcFollow();
    }
  }

  /// Total timing shift in effect: file offset plus the manual correction.
  int get _lrcTotalOffsetMs => _lrcFileOffsetMs + _lrcManualOffsetMs;

  /// Index of the last line whose timestamp is at or before [positionMs].
  ///
  /// The file offset is already baked into [_lrcLines], so only the manual
  /// correction has to be applied here: it is equivalent to adding it to
  /// every timestamp, so we subtract it from the playback position.
  int _lrcIndexFor(int positionMs) {
    final effectiveMs = positionMs - _lrcManualOffsetMs;
    // _lrcLines is sorted by timeMs, so binary search instead of scanning
    // from the top on every position tick.
    var lo = 0, hi = _lrcLines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_lrcLines[mid].timeMs <= effectiveMs) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// Scroll so that line [idx] sits near the upper third of the viewport.
  ///
  /// Uses the controller and the fixed row height instead of
  /// Scrollable.ensureVisible with a GlobalKey: with ListView.builder the
  /// far off-screen rows are never built, so their context is null and the
  /// ensureVisible call silently does nothing on long lyrics.
  void _scrollToLrcLine(int idx) {
    if (idx < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_lrcScrollController.hasClients) return;
      if (!_syncedMode || _lrcLines.isEmpty) return;
      final position = _lrcScrollController.position;
      final viewport = position.viewportDimension;
      final maxScroll = position.maxScrollExtent;
      if (!viewport.isFinite || viewport <= 0) return;
      final target = (idx * _kLrcLineHeight - viewport * _kLrcTargetAlignment)
          .clamp(0.0, maxScroll.isFinite ? maxScroll : 0.0);
      if ((position.pixels - target).abs() < 1) return;
      _lrcScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Nudge the manual timing correction by [deltaMs] and re-evaluate the
  /// active line immediately so the highlight and the list stay in sync.
  void _nudgeLrcOffset(int deltaMs) {
    if (!_syncedMode || _lrcLines.isEmpty) return;
    setState(() => _lrcManualOffsetMs += deltaMs);
    final songId = _player.currentSong?.id;
    if (songId != null) {
      _lrcOffsetSaveTimer?.cancel();
      final value = _lrcManualOffsetMs;
      _pendingOffsetSongId = songId;
      _pendingOffsetMs = value;
      _lrcOffsetSaveTimer = Timer(const Duration(milliseconds: 500), () {
        _flushPendingLrcOffset();
      });
    }
    final idx = _lrcIndexFor(_player.activePlayer.position.inMilliseconds);
    setState(() => _lrcIndex = idx);
    _scrollToLrcLine(idx);
  }

  /// Write a pending timing correction immediately. Safe to call more than
  /// once. On failure the pending state is restored so a later reload or exit
  /// can retry instead of silently losing the correction.
  Future<void> _flushPendingLrcOffset() async {
    final songId = _pendingOffsetSongId;
    if (songId == null) return;
    final value = _pendingOffsetMs;
    _pendingOffsetSongId = null;
    try {
      await DBHelper.instance.setSyncedLyricOffset(songId, value);
    } catch (e) {
      debugPrint('Lyric offset save failed: $e');
      _pendingOffsetSongId = songId;
      _pendingOffsetMs = value;
    }
  }

  /// Clear the saved correction and return to the file offset.
  Future<void> _resetLrcOffset() async {
    final songId = _player.currentSong?.id;
    if (songId == null) return;
    _lrcOffsetSaveTimer?.cancel();
    _pendingOffsetSongId = null;
    try {
      await DBHelper.instance.setSyncedLyricOffset(songId, 0);
    } catch (e) {
      debugPrint('Lyric offset reset failed: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _lrcManualOffsetMs = 0);
    final idx = _lrcIndexFor(_player.activePlayer.position.inMilliseconds);
    setState(() => _lrcIndex = idx);
    _scrollToLrcLine(idx);
  }

  Future<void> _openBookmarks(Song song) async {
    final l10n = AppLocalizations.of(context)!;
    // The sheet can stay open while a notification changes the track.
    // Bookmarks always belong to the song that opened it.
    final bookmarkSongId = song.id;
    // Keep one future per generation so a save or delete refreshes the list
    // without flashing the empty state for a frame.
    var bookmarks = DBHelper.instance.getBookmarks(bookmarkSongId);
    List<Map<String, Object?>> lastRows = const <Map<String, Object?>>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => FutureBuilder<List<Map<String, Object?>>>(
            future: bookmarks,
            builder: (ctx, snapshot) {
              final data = snapshot.data;
              if (data != null) lastRows = data;
              final rows = data ?? lastRows;
              return ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l10n.playerBookmarks,
                            style: Theme.of(ctx).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: Text(l10n.playerBookmarkSave),
                          onPressed: () async {
                            if (_player.currentSong?.id != bookmarkSongId) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                    content: Text(
                                        l10n.playerBookmarkSongChanged)));
                              }
                              return;
                            }
                            final pos =
                                _player.activePlayer.position.inMilliseconds;
                            final saved = await DBHelper.instance.addBookmark(
                                bookmarkSongId, pos, formatDuration(pos));
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text(saved
                                  ? l10n.playerBookmarkSaved
                                  : l10n.playerBookmarkLimit),
                            ));
                            bookmarks = DBHelper.instance.getBookmarks(bookmarkSongId);
                            setSheetState(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                        if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(l10n.playerBookmarkEmpty,
                                textAlign: TextAlign.center),
                          ),
                        for (final row in rows)
                          ListTile(
                            title: Text((row['label'] as String?) ?? ''),
                            subtitle: Text(formatDuration(
                                (row['positionMs'] as num?)?.toInt() ?? 0)),
                            onTap: () {
                              if (_player.currentSong?.id != bookmarkSongId) {
                                Navigator.pop(ctx);
                                return;
                              }
                              final pos =
                                  (row['positionMs'] as num?)?.toInt() ?? 0;
                              Navigator.pop(ctx);
                              _player.activePlayer
                                  .seek(Duration(milliseconds: pos))
                                  .catchError((Object _) {});
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: l10n.playerBookmarkRename,
                                  onPressed: () async {
                                    final controller = TextEditingController(
                                        text: (row['label'] as String?) ?? '');
                                    final edited = await showDialog<String>(
                                      context: ctx,
                                      builder: (dialogCtx) => AlertDialog(
                                        title: Text(l10n.playerBookmarkRename),
                                        content: TextField(
                                            controller: controller,
                                            maxLines: 1,
                                            autofocus: true),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dialogCtx),
                                              child: Text(l10n.cancel)),
                                          TextButton(
                                              onPressed: () => Navigator.pop(
                                                  dialogCtx,
                                                  controller.text.trim()),
                                              child: Text(l10n.save)),
                                        ],
                                      ),
                                    );
                                    controller.dispose();
                                    if (edited == null ||
                                        edited.isEmpty ||
                                        !ctx.mounted) {
                                      return;
                                    }
                                    await DBHelper.instance.updateBookmarkLabel(
                                        (row['id'] as num).toInt(), edited);
                                    bookmarks =
                                        DBHelper.instance.getBookmarks(bookmarkSongId);
                                    setSheetState(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: l10n.delete,
                                  onPressed: () async {
                                    await DBHelper.instance.deleteBookmark(
                                        (row['id'] as num).toInt());
                                    if (!ctx.mounted) return;
                                    bookmarks = DBHelper.instance
                                        .getBookmarks(bookmarkSongId);
                                    setSheetState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addLyricsManually(Song song) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EditLyricsScreen(song: song)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _player,
      builder: (context, _) {
        final song = _player.currentSong;
        if (song == null) {
          return Scaffold(body: Center(child: Text(AppLocalizations.of(context)!.playerEmptyState)));
        }
        // Only the current song id and the favorite flag matter for the
        // scaffold, so it rebuilds on player state and on those two values,
        // never on every library notification (bulk scan ticks included).
        // A record gives value equality, so swapping in a different song
        // always rebuilds even when the favorite flag did not change.
        return Selector<LibraryProvider, (int, bool)>(
          selector: (_, lib) =>
              (song.id, lib.songById(song.id)?.isFavorite ?? song.isFavorite),
          builder: (_, value, __) => _buildScaffold(song, value.$2),
        );
      },
    );
  }

  Widget _buildScaffold(Song song, bool isFavorite) {
    return GestureDetector(
      onVerticalDragStart: (details) {
        // A new drag owns the offset: stop any in-flight return animation so
        // its listener cannot overwrite the user's movement.
        _returnController.stop();
        // Track dismiss swipes only when the drag starts in the top
        // 40 percent of the screen (art zone). Lower starts are ignored
        // for vertical so lyric lists can scroll safely.
        final height = MediaQuery.of(context).size.height;
        _verticalDismissArmed =
            details.globalPosition.dy < height * 0.4;
      },
      onVerticalDragUpdate: (details) {
        if (!_verticalDismissArmed) return;
        if (details.delta.dy > 0) {
          _dragOffset.value += details.delta.dy;
        }
      },
      onVerticalDragEnd: (details) {
        if (!_verticalDismissArmed) return;
        _verticalDismissArmed = false;
        if (_dragOffset.value > 100 || (details.primaryVelocity ?? 0) > 600) {
          Navigator.pop(context);
        } else {
          // Ease back to rest instead of snapping the whole sheet.
          _returnStart = _dragOffset.value;
          _returnController.forward(from: 0);
        }
      },
      onVerticalDragCancel: () {
        _verticalDismissArmed = false;
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -250) {
          _player.next();
        } else if (velocity > 250) {
          _player.previous();
        }
      },
      child: ValueListenableBuilder<double>(
        valueListenable: _dragOffset,
        child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  // The top area is kept empty and clean, only a
                  // minimize button to go back to the mini player,
                  // without a title or other icons.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down),
                          tooltip: AppLocalizations.of(context)!
                              .playerMinimize,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: motionDuration(context, const Duration(milliseconds: 200)),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _showLyrics ? _buildLyricsView(song) : _buildArtView(song),
                    ),
                  ),
                  _buildControls(song, isFavorite),
                ],
              ),
            ),
          ),
        builder: (context, offset, child) => Transform.translate(
          offset: Offset(0, offset),
          child: Opacity(
            opacity: (1 - (offset / 400)).clamp(0.4, 1.0),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsView(Song song) {
    // Loading and re-subscribing happen in a post-frame callback from the
    // player listener, never from build().
    final hasSynced = _lrcLines.isNotEmpty;
    final Widget body =
        (hasSynced && _syncedMode) ? _buildSyncedLyricsView() : _buildPlainLyricsView(song);
    if (!hasSynced) return body;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                  value: true,
                  label: Text(AppLocalizations.of(context)!.lyricsSynced)),
              ButtonSegment(
                  value: false,
                  label: Text(AppLocalizations.of(context)!.lyricsPlain)),
            ],
            selected: {_syncedMode},
            onSelectionChanged: (s) => _setSyncedMode(s.first),
          ),
        ),
        _buildLrcOffsetControl(),
        Expanded(child: body),
      ],
    );
  }

  /// Small manual timing correction row shown only for synced lyrics.
  ///
  /// Lets the user fix a wrong or missing `[offset:]` tag by 100 ms steps.
  /// The value shown is the file offset plus the manual correction, so the
  /// user can see the total shift currently in effect.
  Widget _buildLrcOffsetControl() {
    if (!_syncedMode || _lrcLines.isEmpty) return const SizedBox.shrink();
    final totalMs = _lrcTotalOffsetMs;
    final totalLabel = '${totalMs >= 0 ? '+' : '-'}${totalMs.abs()} ms';
    final readoutWidth =
        76 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_lrcManualOffsetMs != 0)
            _buildOffsetButton(
              icon: Icons.restart_alt,
              tooltip: AppLocalizations.of(context)!.playerLyricTimingReset,
              onPressed: _resetLrcOffset,
            ),
          Text(
            AppLocalizations.of(context)!.playerLyricTiming,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          _buildOffsetButton(
            icon: Icons.remove,
            tooltip: AppLocalizations.of(context)!.playerLyricTimingEarlier,
            onPressed: () => _nudgeLrcOffset(-_kLrcOffsetStepMs),
          ),
          SizedBox(
            width: readoutWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                totalLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          _buildOffsetButton(
            icon: Icons.add,
            tooltip: AppLocalizations.of(context)!.playerLyricTimingLater,
            onPressed: () => _nudgeLrcOffset(_kLrcOffsetStepMs),
          ),
        ],
      ),
    );
  }

  Widget _buildOffsetButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
      ),
    );
  }

  /// Synced lyrics list with the active line highlighted and kept visible.
  ///
  /// Every row uses the same fixed [_kLrcLineHeight] and the list sets
  /// itemExtent to match, so the offset math in [_scrollToLrcLine] stays
  /// exact no matter how long the lyrics are.
  Widget _buildSyncedLyricsView() {
    return ListView.builder(
      key: ValueKey('synced_$_lrcSongId'),
      controller: _lrcScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: _lrcLines.length,
      itemExtent: _kLrcLineHeight,
      itemBuilder: (context, i) {
        final line = _lrcLines[i];
        final active = i == _lrcIndex;
        return Container(
          alignment: Alignment.center,
          child: Text(
            line.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              // Fixed size so the row height never depends on the content.
              fontSize: 16,
              height: 1.25,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlainLyricsView(Song song) {
    final hasLyrics = song.lyrics != null && song.lyrics.toString().trim().isNotEmpty;
    return SingleChildScrollView(
      key: ValueKey('lyrics_${song.id}'),
      padding: const EdgeInsets.all(20),
      child: hasLyrics
          ? Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setShowLyrics(false),
                  child: Column(
                    children: [
                      Text(song.lyrics ?? '', style: const TextStyle(fontSize: 16, height: 1.6)),
                      const SizedBox(height: 16),
                      Text(AppLocalizations.of(context)!.playerTapToReturnToCover, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: () => _addLyricsManually(song),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(AppLocalizations.of(context)!.playerEditLyrics),
                ),
              ],
            )
          : Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setShowLyrics(false),
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      Icon(Icons.lyrics_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(AppLocalizations.of(context)!.playerLyricsNotFound, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(AppLocalizations.of(context)!.playerTapHereToReturnToCover, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _searchLyricsOnGoogle(song),
                      icon: const Icon(Icons.search),
                      label: Text(AppLocalizations.of(context)!.playerSearchOnGoogle),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isFetchingLyrics ? null : () => _autoFetchLyrics(song),
                      icon: _isFetchingLyrics
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_sync_outlined),
                      label: Text(AppLocalizations.of(context)!.playerAutoSearch),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _addLyricsManually(song),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(AppLocalizations.of(context)!.playerAddManually),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildArtView(Song song) {
    return Center(
      key: ValueKey('art_${song.id}'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Semantics(
            button: true,
            label: AppLocalizations.of(context)!.playerViewLyrics,
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setShowLyrics(true),
            child: StreamBuilder(
              // Key on the active player: after a crossfade flip the
              // audible player is a different instance; without a key this
              // keeps the outgoing player's state stream forever.
              key: ValueKey('art_state_${_player.activePlayer.hashCode}_${song.id}'),
              stream: _player.activePlayer.playerStateStream,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                return AnimatedScale(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  scale: playing ? 1.0 : 0.92,
                  // Isolate cover and glow repaints from the rest of the screen.
                  child: RepaintBoundary(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: playing
                            ? [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                                  blurRadius: 28,
                                  spreadRadius: 2,
                                )
                              ]
                            : [],
                      ),
                      child: Hero(
                        // Pairs with the mini player cover: the small artwork
                        // flies up into this big one when the player opens.
                        tag: 'swara_art_${song.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SongArtImage(
                            song: song,
                            width: 260, height: 260, fit: BoxFit.cover,
                            // Decode near display size to save image memory.
                            cacheWidth: 520,
                            fallback: Container(
                              width: 260, height: 260, color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: Icon(Icons.music_note, size: 80,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 280,
            child: MarqueeText(
              song.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 6),
          Text(song.artist, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildControls(Song song, bool isFavorite) {
    // Hoisted out of the position-tick StreamBuilder so the theme copy is
    // built once per control-tree rebuild instead of per tick.
    final sliderThemeData = SliderTheme.of(context).copyWith(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          StreamBuilder<Duration>(
            // See above: without a key the slider keeps the outgoing
            // player's position stream after a crossfade.
            key: ValueKey('slider_${_player.activePlayer.hashCode}_${song.id}'),
            stream: _player.activePlayer.positionStream,
            builder: (context, snapshot) {
              final pos = snapshot.data ?? Duration.zero;
              final dur = _player.activePlayer.duration ?? Duration.zero;
              return Column(
                children: [
                  SliderTheme(
                    data: sliderThemeData,
                    child: Slider(
                      value: pos.inMilliseconds.toDouble().clamp(0, dur.inMilliseconds.toDouble()),
                      max: dur.inMilliseconds.toDouble() > 0 ? dur.inMilliseconds.toDouble() : 1,
                      onChanged: _commitSeek,
                      onChangeStart: (_) => _player.setUserSeeking(true),
                      onChangeEnd: (v) {
                        _player.setUserSeeking(false);
                        _player.activePlayer
                            .seek(Duration(milliseconds: v.toInt()))
                            .catchError((_) {});
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(pos)),
                        Text(_fmt(dur)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          if (_player.hasABRepeat)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                AppLocalizations.of(context)!.abMarker(
                    _fmt(_player.abRepeatA!), _fmt(_player.abRepeatB!)),
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary),
              ),
            ),
          // Wrap instead of Row: seven 44dp buttons do not fit a 320dp
          // screen once horizontal padding is applied.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 0,
            runSpacing: 0,
            children: [
              IconButton(
                constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                iconSize: 22,
                icon: Icon(Icons.shuffle,
                    color: _player.isShuffle ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
                tooltip: AppLocalizations.of(context)!.playerShuffle,
                onPressed: _player.toggleShuffle,
              ),
              IconButton(
                constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                iconSize: 22,
                icon: const Icon(Icons.replay_10),
                tooltip: AppLocalizations.of(context)!.playerSeekBack,
                onPressed: () {
                  final dur = _player.activePlayer.duration?.inMilliseconds ?? 0;
                  final pos = _player.activePlayer.position.inMilliseconds;
                  final target = (pos - 10000).clamp(0, dur > 0 ? dur : pos);
                  _player.activePlayer
                      .seek(Duration(milliseconds: target))
                      .catchError((_) {});
                },
              ),
              IconButton(
                constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                iconSize: 22,
                icon: const Icon(Icons.skip_previous),
                tooltip: AppLocalizations.of(context)!.playerPrevious,
                onPressed: _onPreviousPressed,
              ),
              StreamBuilder(
                // Same reasoning as the other two: re-subscribe after a
                // crossfade flip instead of keeping the dead player.
                key: ValueKey('pp_${_player.activePlayer.hashCode}_${song.id}'),
                stream: _player.activePlayer.playerStateStream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                    iconSize: 40,
                    tooltip: AppLocalizations.of(context)!.playerPlayPause,
                    icon: AnimatedSwitcher(
                      duration: motionDuration(context, const Duration(milliseconds: 200)),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        key: ValueKey(playing),
                      ),
                    ),
                    // Futures passed as onPressed must not surface as
                    // unhandled async errors; a locked DB or dead player
                    // must not crash the tap path.
                    onPressed: () =>
                        _player.togglePlayPause().catchError((_) {}),
                  );
                },
              ),
              IconButton(
                constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                iconSize: 22,
                icon: const Icon(Icons.skip_next),
                tooltip: AppLocalizations.of(context)!.playerNext,
                onPressed: () => _player.next().catchError((_) {}),
              ),
              IconButton(
                constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                iconSize: 22,
                icon: const Icon(Icons.forward_10),
                tooltip: AppLocalizations.of(context)!.playerSeekForward,
                onPressed: () {
                  final dur = _player.activePlayer.duration?.inMilliseconds ?? 0;
                  final pos = _player.activePlayer.position.inMilliseconds;
                  // Stay one ms below the end so a skip never emits a
                  // completion event and advances the track by itself.
                  final target = dur > 0
                      ? (pos + 10000).clamp(0, dur - 1)
                      : pos + 10000;
                  _player.activePlayer
                      .seek(Duration(milliseconds: target))
                      .catchError((_) {});
                },
              ),
              _buildRepeatButton(),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 22,
                ),
                tooltip: AppLocalizations.of(context)!.playerFavorite,
                onPressed: () => context.read<LibraryProvider>().toggleFavorite(song, !isFavorite),
              ),
              IconButton(
                icon: Icon(Icons.playlist_add, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
                tooltip: AppLocalizations.of(context)!.playerAddToPlaylist,
                onPressed: () => pickPlaylist(context, song, context.read<PlaylistProvider>()),
              ),
              IconButton(
                icon: Icon(Icons.bookmark_border,
                    size: 22,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                tooltip: AppLocalizations.of(context)!.playerBookmarks,
                onPressed: () => _openBookmarks(song),
              ),
              // ListenableBuilder so the "N more songs" label stays updated
              // whenever sleepSongsRemaining changes (without waiting for another rebuild).
              // The time based countdown ticks inside _SleepCountdownLabel,
              // so this screen never rebuilds every second.
              ListenableBuilder(
                listenable: _player,
                builder: (context, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.bedtime_outlined,
                          color: (_player.sleepTimerRemaining != null || _player.sleepSongsRemaining != null)
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        tooltip: AppLocalizations.of(context)!.playerSleepTimer,
                        onPressed: _pickSleepTimer,
                      ),
                      const _SleepCountdownLabel(),
                    ],
                  );
                },
              ),
              // Speed and pitch chip. Shows the current speed (for example "1.0x") and
              // opens the speed/pitch sheet. Disabled while nothing is loaded.
              ListenableBuilder(
                listenable: _player,
                builder: (context, _) {
                  final hasSong = _player.currentSong != null;
                  final isAdjusted = _player.playbackSpeed != 1.0 ||
                      _player.playbackPitch != 1.0;
                  final color = Theme.of(context).colorScheme.primary;
                  return ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Center(
                      child: ActionChip(
                        avatar: Icon(Icons.speed,
                            size: 14, color: isAdjusted ? color : Theme.of(context).colorScheme.onSurfaceVariant),
                        label: Text(
                          _player.playbackSpeedLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isAdjusted ? color : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        // The chip sits in a row of 48 dp icon buttons, so
                        // give it the same hit height without changing look.
                        tooltip: AppLocalizations.of(context)!.playerPlaybackSpeed,
                        onPressed: hasSong ? _pickPlaybackSpeed : null,
                      ),
                    ),
                  );
                },
              ),
              // Small A-B repeat button. Active (looping) state uses the
              // primary color, idle uses grey.
              ListenableBuilder(
                listenable: _player,
                builder: (context, _) {
                  final abActive = _player.hasABRepeat;
                  return IconButton(
                    icon: Text(
                      AppLocalizations.of(context)!.abButton,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: abActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    tooltip:
                        AppLocalizations.of(context)!.abTooltip,
                    onPressed: _showABRepeatDialog,
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.queue_music_outlined, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
                tooltip: AppLocalizations.of(context)!.queueTitle,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QueueScreen())),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Repeat button with clear contrast for each mode: off (grey),
  /// repeat all (primary) and repeat one (primary with a "1").
  /// IconButton keeps a 44px target plus splash and tooltip.
  Widget _buildRepeatButton() {
    final mode = _player.repeatMode;
    final color = Theme.of(context).colorScheme.primary;
    final isActive = mode != SwaraRepeatMode.off;
    final l10n = AppLocalizations.of(context)!;
    final String tip;
    switch (mode) {
      case SwaraRepeatMode.one:
        tip = l10n.playerRepeatOne;
        break;
      case SwaraRepeatMode.all:
        tip = l10n.playerRepeatAll;
        break;
      case SwaraRepeatMode.off:
        tip = l10n.playerRepeatOff;
        break;
    }

    return IconButton(
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      iconSize: 22,
      tooltip: tip,
      onPressed: _player.cycleRepeatMode,
      style: IconButton.styleFrom(
        backgroundColor:
            isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
      ),
      icon: Icon(
        mode == SwaraRepeatMode.one ? Icons.repeat_one : Icons.repeat,
        color: isActive ? color : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return '${d.inMinutes}:${two(d.inSeconds % 60)}';
  }
}

/// Sleep timer countdown label with its own one second ticker, so the
/// player screen itself never rebuilds every second while the timer runs.
/// The ticker only runs while a time based timer is active and stops
/// as soon as no timer is left. Song count mode needs no ticker because
/// it only changes when the player notifies.
class _SleepCountdownLabel extends StatefulWidget {
  const _SleepCountdownLabel();

  @override
  State<_SleepCountdownLabel> createState() => _SleepCountdownLabelState();
}

class _SleepCountdownLabelState extends State<_SleepCountdownLabel> {
  final _player = PlayerService.instance;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerChanged);
    _updateTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  // Refresh the label on player changes and start or stop the ticker
  // so it only runs while a time based sleep timer is active.
  void _onPlayerChanged() {
    _updateTicker();
    if (mounted) setState(() {});
  }

  void _updateTicker() {
    final hasTimeTimer = _player.sleepTimerEndTime != null;
    if (hasTimeTimer && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_player.sleepTimerEndTime == null) {
          _ticker?.cancel();
          _ticker = null;
        }
        setState(() {});
      });
    } else if (!hasTimeTimer && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _player.sleepTimerRemaining;
    String? label;
    if (remaining != null) {
      final m = remaining.inMinutes;
      final s = remaining.inSeconds % 60;
      label = '$m:${s.toString().padLeft(2, '0')}';
    } else {
      final songsLeft = _player.sleepSongsRemaining;
      if (songsLeft != null) {
        label = AppLocalizations.of(context)!.playerSongsRemaining(songsLeft);
      }
    }
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

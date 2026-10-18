import 'dart:async';
import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../services/art_cache_service.dart';
import '../services/metadata_service.dart';
import '../services/db_helper.dart';
import '../utils/lrc.dart';
import '../providers/library_provider.dart';
import '../providers/playlist_provider.dart';
import '../utils/song_options.dart';
import '../widgets/marquee_text.dart';
import '../widgets/sleep_timer_sheet.dart';
import 'edit_lyrics_screen.dart';
import 'queue_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _player = PlayerService.instance;
  bool _showLyrics = false;
  bool _isFetchingLyrics = false;
  double _dragOffset = 0;
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

  /// Fixed height of a single synced lyric row. The list uses this as its
  /// itemExtent, so the scroll estimate below is always exact.
  static const double _kLrcLineHeight = 44;
  /// Vertical target of the active row inside the viewport (0 top, 1 bottom).
  static const double _kLrcTargetAlignment = 0.4;
  static const int _kLrcOffsetStepMs = 100;

  @override
  void dispose() {
    _stopLrcFollow();
    _lrcScrollController.dispose();
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                  final pos = _player.player.position;
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
                  final pos = _player.player.position;
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
    final query = Uri.encodeComponent('${song.artist} ${song.title} lirik lyrics');
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
    if (_lrcSongId == song.id || _lrcLoading) return;
    _lrcSongId = song.id;
    _lrcLoading = true;
    _lrcLines = [];
    _lrcIndex = -1;
    _lrcFileOffsetMs = 0;
    // A manual correction belongs to one song only, so drop it here.
    _lrcManualOffsetMs = 0;
    _stopLrcFollow();
    try {
      final lrc = await DBHelper.instance.getSyncedLyrics(song.id);
      if (!mounted) return;
      final lines =
          (lrc == null || lrc.isEmpty) ? <LrcLine>[] : parseLrc(lrc);
      setState(() {
        _lrcLoading = false;
        _lrcLines = lines;
        _lrcIndex = -1;
        // parseLrc already folded this into the timestamps; keep the value
        // for display and for the manual offset readout.
        _lrcFileOffsetMs =
            (lrc == null || lrc.isEmpty) ? 0 : (parseLrcOffsetMs(lrc.split('\n')) ?? 0);
        // Default to synced view when lines exist, plain text otherwise.
        _syncedMode = lines.isNotEmpty;
      });
      if (lines.isNotEmpty && _showLyrics && _syncedMode) _startLrcFollow();
    } catch (_) {
      if (!mounted) return;
      setState(() => _lrcLoading = false);
    }
  }

  /// Follow the player position and highlight the active synced line.
  /// Rebuilds only when the active line index actually changes.
  void _startLrcFollow() {
    _stopLrcFollow();
    if (!_syncedMode || _lrcLines.isEmpty) return;
    _lrcPositionSub = _player.player.positionStream.listen((pos) {
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
    var idx = -1;
    for (var i = 0; i < _lrcLines.length; i++) {
      if (_lrcLines[i].timeMs <= effectiveMs) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
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
    final idx = _lrcIndexFor(_player.player.position.inMilliseconds);
    setState(() => _lrcIndex = idx);
    _scrollToLrcLine(idx);
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
        return _buildScaffold(song);
      },
    );
  }

  Widget _buildScaffold(Song song) {
    final lib = context.watch<LibraryProvider>();
    final matchInLib = lib.songs.where((s) => s.id == song.id);
    final isFavorite = matchInLib.isNotEmpty ? matchInLib.first.isFavorite : false;

    return GestureDetector(
      onVerticalDragStart: (details) {
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
          setState(() => _dragOffset += details.delta.dy);
        }
      },
      onVerticalDragEnd: (details) {
        if (!_verticalDismissArmed) return;
        _verticalDismissArmed = false;
        if (_dragOffset > 100 || (details.primaryVelocity ?? 0) > 600) {
          Navigator.pop(context);
        } else {
          setState(() => _dragOffset = 0);
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
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Opacity(
          opacity: (1 - (_dragOffset / 400)).clamp(0.4, 1.0),
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
                      duration: const Duration(milliseconds: 200),
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
                  _buildControls(song, isFavorite, lib),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsView(Song song) {
    _maybeLoadSyncedLyrics(song);
    final hasSynced = _lrcLines.isNotEmpty;
    if (hasSynced && _syncedMode && _lrcPositionSub == null && _showLyrics) {
      _startLrcFollow();
    }
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
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppLocalizations.of(context)!.playerLyricTiming,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(width: 8),
          _buildOffsetButton(
            icon: Icons.remove,
            tooltip: AppLocalizations.of(context)!.playerLyricTimingEarlier,
            onPressed: () => _nudgeLrcOffset(-_kLrcOffsetStepMs),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
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
          const SizedBox(width: 8),
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
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 18),
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
                  : Colors.grey[600],
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
                      Text(AppLocalizations.of(context)!.playerTapToReturnToCover, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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
                      Icon(Icons.lyrics_outlined, size: 56, color: Colors.grey[500]),
                      const SizedBox(height: 12),
                      Text(AppLocalizations.of(context)!.playerLyricsNotFound, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(AppLocalizations.of(context)!.playerTapHereToReturnToCover, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setShowLyrics(true),
            child: StreamBuilder(
              stream: _player.player.playerStateStream,
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
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: song.albumArtUrl != null
                            // Disk cached artwork with network fallback.
                            ? CachedArtImage(
                                url: song.albumArtUrl!,
                                width: 260, height: 260, fit: BoxFit.cover,
                                // Decode near display size to save image memory.
                                cacheWidth: 520,
                                loading: Container(
                                  width: 260,
                                  height: 260,
                                  color: Colors.grey[300],
                                  child: const Center(
                                      child: CircularProgressIndicator()),
                                ),
                                fallback: Container(
                                  width: 260, height: 260, color: Colors.grey[300],
                                  child: const Icon(Icons.music_note, size: 80),
                                ),
                              )
                            : Container(
                                width: 260,
                                height: 260,
                                color: Colors.grey[300],
                                child: const Icon(Icons.music_note, size: 80),
                              ),
                      ),
                    ),
                  ),
                );
              },
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
          Text(song.artist, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildControls(Song song, bool isFavorite, LibraryProvider lib) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          StreamBuilder<Duration>(
            stream: _player.player.positionStream,
            builder: (context, snapshot) {
              final pos = snapshot.data ?? Duration.zero;
              final dur = _player.player.duration ?? Duration.zero;
              return Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: pos.inMilliseconds.toDouble().clamp(0, dur.inMilliseconds.toDouble()),
                      max: dur.inMilliseconds.toDouble() > 0 ? dur.inMilliseconds.toDouble() : 1,
                      onChanged: (v) => _player.player.seek(Duration(milliseconds: v.toInt())),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle,
                    color: _player.isShuffle ? Theme.of(context).colorScheme.primary : Colors.grey),
                onPressed: _player.toggleShuffle,
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous),
                tooltip: AppLocalizations.of(context)!.playerPrevious,
                onPressed: _onPreviousPressed,
              ),
              StreamBuilder(
                stream: _player.player.playerStateStream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    iconSize: 48,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        key: ValueKey(playing),
                      ),
                    ),
                    onPressed: _player.togglePlayPause,
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                tooltip: AppLocalizations.of(context)!.playerNext,
                onPressed: _player.next,
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
                  color: isFavorite ? Colors.red : Colors.grey,
                  size: 22,
                ),
                tooltip: AppLocalizations.of(context)!.playerFavorite,
                onPressed: () => lib.toggleFavorite(song, !isFavorite),
              ),
              IconButton(
                icon: const Icon(Icons.playlist_add, size: 22, color: Colors.grey),
                tooltip: AppLocalizations.of(context)!.playerAddToPlaylist,
                onPressed: () => pickPlaylist(context, song, context.read<PlaylistProvider>()),
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
                              : Colors.grey,
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
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ActionChip(
                      avatar: Icon(Icons.speed,
                          size: 14, color: isAdjusted ? color : Colors.grey),
                      label: Text(
                        _player.playbackSpeedLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isAdjusted ? color : Colors.grey,
                        ),
                      ),
                      // Keep the chip small, it shares one row with six
                      // icon buttons.
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      tooltip: AppLocalizations.of(context)!.playerPlaybackSpeed,
                      onPressed: hasSong ? _pickPlaybackSpeed : null,
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
                        color: abActive ? Theme.of(context).colorScheme.primary : Colors.grey,
                      ),
                    ),
                    tooltip:
                        AppLocalizations.of(context)!.abTooltip,
                    onPressed: _showABRepeatDialog,
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.queue_music_outlined, size: 22, color: Colors.grey),
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
  /// IconButton keeps the 48px target plus splash and tooltip.
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
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      tooltip: tip,
      onPressed: _player.cycleRepeatMode,
      style: IconButton.styleFrom(
        backgroundColor:
            isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
      ),
      icon: Icon(
        mode == SwaraRepeatMode.one ? Icons.repeat_one : Icons.repeat,
        color: isActive ? color : Colors.grey,
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

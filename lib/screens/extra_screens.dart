import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/player_service.dart';
import '../services/art_cache_service.dart';
import '../services/metadata_service.dart';
import '../services/db_helper.dart';
import '../utils/song_options.dart';
import '../utils/format.dart';
import '../widgets/mini_player.dart';
import '../widgets/sort_chip.dart';
import '../widgets/az_scrollbar.dart';
import '../widgets/playing_indicator.dart';
import 'playlist_detail_screen.dart';

// Upper bound for the standalone "full list" screens (Recently Added, Most
// Played). They must show every row, so this is a safety ceiling rather than a
// paging window: rendering stays lazy through the sliver list.
const int _kFullListLimit = 100000;

// Hoisted so the pattern is compiled once per file instead of once per row by
// the A-Z rails and the A-Z jumps of the folder and favorites screens.
final RegExp _leadingLetterReg = RegExp(r'^[a-zA-Z]');

// Rows below sit in a fixed height box (itemExtent 72 or 64) while the app
// allows text scales up to 2x, so the text of a row is clamped to stay inside
// that box instead of overflowing at large scales.
const double _kRowMaxTextScale = 1.5;

/// Clamped text scale for text inside a fixed height row.
TextScaler _rowTextScaler(BuildContext context) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _kRowMaxTextScale);

/// Clamp the text scale of a fixed height row built from a ListTile. ListTile
/// has no textScaler parameter, so the tile subtree gets a clamped MediaQuery.
Widget _clampRowText(BuildContext context, Widget child) {
  final scaler = _rowTextScaler(context);
  final mq = MediaQuery.of(context);
  if (scaler == mq.textScaler) return child;
  return MediaQuery(data: mq.copyWith(textScaler: scaler), child: child);
}

// ─────────────────────────────────────────────────────────────
// SHARED WIDGET: consistent song list tile used on every screen
// ─────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────
// SHARED WIDGET: pulsing grey placeholder for first load.
// Uses only Container and TweenAnimationBuilder, no new dependency.
// ─────────────────────────────────────────────────────────────

/// Single grey bar that fades in once on first load.
class _SkeletonBar extends StatelessWidget {
  final double height;
  final double width;
  final BorderRadius borderRadius;
  const _SkeletonBar({
    required this.height,
    this.width = double.infinity,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.35, end: 0.7),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, v, _) => Opacity(
        opacity: v,
        child: Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: borderRadius,
          ),
        ),
      ),
    );
  }
}

/// Simple vertical skeleton list used for first load states.
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: 8,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            _SkeletonBar(
              height: 40,
              width: 40,
              borderRadius: BorderRadius.circular(20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBar(height: 12, width: 160),
                  SizedBox(height: 6),
                  _SkeletonBar(height: 10, width: 110),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget buildSongTile(
  BuildContext context,
  Song song,
  List<Song> queue,
  int index, {
  Widget? leading,
  bool showOptions = true,
}) {
  // Normal artwork shown when this row is not the current song.
  final Widget artFallback = song.albumArtUrl != null
      // Disk cached artwork with network fallback.
      ? ClipOval(
          child: CachedArtImage(
            url: song.albumArtUrl!,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            // Decode thumbnail size only to save image memory.
            cacheWidth: 88,
            fallback: const CircleAvatar(
              child: Icon(Icons.music_note, size: 20),
            ),
          ),
        )
      : const CircleAvatar(
          child: Icon(Icons.music_note, size: 20),
        );
  // Provide the singleton locally so Selector works without
  // touching the global provider setup in main.dart.
  // Only this tile rebuilds when its own isCurrent flag flips.
  // Play and pause only rebuild the small icon inside.
  return ChangeNotifierProvider.value(
    value: PlayerService.instance,
    child: Selector<PlayerService, bool>(
      selector: (_, ps) => ps.currentSong?.id == song.id,
      builder: (context, isPlaying, _) {
        final cs = Theme.of(context).colorScheme;
        // Isolate each tile so the mini player animation does not repaint the list.
        return RepaintBoundary(
          // Fixed extent row: clamp the text scale so the two line tile cannot
          // overflow its box at large app text scales.
          child: _clampRowText(
            context,
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              tileColor:
                  isPlaying ? cs.primaryContainer.withValues(alpha: 0.25) : null,
              leading: leading ??
                  _NowPlayingIcon(songId: song.id, fallback: artFallback),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                  color: isPlaying ? cs.primary : null,
                ),
              ),
              subtitle: Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () async {
                // setQueueAndPlay can fail (missing file/unsupported format) -
                // catch it so playback errors do not disappear without a trace.
                try {
                  await PlayerService.instance.setQueueAndPlay(queue, index);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 5),
                          content: Text(AppLocalizations.of(context)!
                              .libraryPlayFailed('$e'))),
                    );
                  }
                }
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatDuration(song.durationMs),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  if (showOptions)
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: () => showSongOptions(context, song),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

// Small now playing icon that rebuilds only itself when the current
// song or the play state changes. Used as the default leading widget
// for buildSongTile so lists no longer rebuild on every notify.
class _NowPlayingIcon extends StatelessWidget {
  final int songId;
  final Widget fallback;
  const _NowPlayingIcon({required this.songId, required this.fallback});

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerService, bool>(
      selector: (_, ps) => ps.currentSong?.id == songId,
      builder: (context, isCurrent, _) {
        if (!isCurrent) return fallback;
        final cs = Theme.of(context).colorScheme;
        return Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          // Inner selector so play and pause only rebuild the bars.
          child: Selector<PlayerService, bool>(
            selector: (_, ps) => ps.player.playing,
            builder: (context, playing, _) =>
                PlayingIndicator(isPlaying: playing, color: cs.primary),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SHARED WIDGET: info header + play/shuffle buttons
// ─────────────────────────────────────────────────────────────

Widget buildCollectionHeader({
  required BuildContext context,
  required int songCount,
  required int totalMs,
  required List<Song> songs,
  Widget? extraAction,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          AppLocalizations.of(context)!
              .librarySongCountDuration(songCount, formatDurationLong(totalMs)),
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: songs.isEmpty
                    ? null
                    : () async {
                        try {
                          await PlayerService.instance.setQueueAndPlay(songs, 0);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 5),
                                  content: Text(
                                      AppLocalizations.of(context)!
                                          .libraryPlayFailed('$e'))),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(AppLocalizations.of(context)!.libraryStartPlaying),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: songs.isEmpty
                    ? null
                    : () async {
                        final r = Random().nextInt(songs.length);
                        await PlayerService.instance.setQueueAndPlay(songs, r);
                        PlayerService.instance.setShuffle(true);
                      },
                icon: const Icon(Icons.shuffle, size: 18),
                label: Text(AppLocalizations.of(context)!.libraryShuffle),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10)),
              ),
            ),
            if (extraAction != null) ...[
              const SizedBox(width: 8),
              extraAction,
            ],
          ],
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────
// SHARED WIDGET: compact play all + shuffle for the group screens
// (Artists, Genres, Albums). Reuses the same flow as buildCollectionHeader:
// build the whole queue, then PlayerService.setQueueAndPlay / setShuffle.
// ─────────────────────────────────────────────────────────────

Widget buildGroupPlayActions(BuildContext context, List<Song> queue) {
  final l = AppLocalizations.of(context)!;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.filled(
        icon: const Icon(Icons.play_arrow, size: 18),
        tooltip: l.libraryStartPlaying,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onPressed: queue.isEmpty
            ? null
            : () async {
                try {
                  await PlayerService.instance.setQueueAndPlay(queue, 0);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 5),
                          content: Text(AppLocalizations.of(context)!
                              .libraryPlayFailed('$e'))),
                    );
                  }
                }
              },
      ),
      const SizedBox(width: 4),
      IconButton.outlined(
        icon: const Icon(Icons.shuffle, size: 18),
        tooltip: l.libraryShuffle,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onPressed: queue.isEmpty
            ? null
            : () async {
                // Same order as the other screens: random start then shuffle.
                final r = Random().nextInt(queue.length);
                await PlayerService.instance.setQueueAndPlay(queue, r);
                PlayerService.instance.setShuffle(true);
              },
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────
// SHARED WIDGET: flatten a grouped map into a full song queue,
// preserving the on screen group order. Used by the group screens
// so "play all" walks the library exactly like the list does.
// ─────────────────────────────────────────────────────────────

List<Song> buildGroupQueue(List<String> keys, Map<String, List<Song>> grouped) {
  final queue = <Song>[];
  for (final key in keys) {
    queue.addAll(grouped[key] ?? const <Song>[]);
  }
  return queue;
}

// ─────────────────────────────────────────────────────────────
// FOLDERS SCREEN
// ─────────────────────────────────────────────────────────────

enum FolderSortOption { nameAZ, nameZA, songCountDesc }

class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key});
  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  List<String> _folders = [];
  Set<String> _excluded = {};
  bool _showHidden = false;
  Map<String, List<Song>> _songsByFolder = {};
  FolderSortOption _sortOption = FolderSortOption.nameAZ;
  static const _kFolderSort = 'folder_list_sort';

  @override
  void initState() {
    super.initState();
    // A prefs failure (corrupt/unavailable) must not blank the screen -
    // keep going and show folders from the DB.
    _loadPrefs().catchError((Object _) {}).then((_) => _load());
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_kFolderSort) ?? 0;
    if (!mounted) return;
    setState(() => _sortOption =
        FolderSortOption.values[idx.clamp(0, FolderSortOption.values.length - 1)]);
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFolderSort, _sortOption.index);
  }

  Future<void> _load() async {
    try {
      // ONE getAllSongs() call, then group in memory with folderOf.
      // Previously N+1: listMusicFolders + getSongsInFolder per folder,
      // where each call did a full-table-scan getAllSongs().
      final all = await DBHelper.instance.getAllSongs();
      final excluded = await DBHelper.instance.getExcludedFolders();
      final songsByFolder = <String, List<Song>>{};
      for (final s in all) {
        final folder = folderOf(s.filePath);
        (songsByFolder[folder] ??= []).add(s);
      }
      final folders = songsByFolder.keys.toList()..sort();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _excluded = excluded;
        _songsByFolder = songsByFolder;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _folders = [];
        _songsByFolder = {};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            content: Text(AppLocalizations.of(context)!
                .foldersLoadFailed('$e'))),
      );
    }
  }

  Future<void> _toggleHideFolder(String folder) async {
    final isHidden = _excluded.contains(folder);
    await DBHelper.instance.setFolderIncluded(folder, isHidden);
    await _load();
    if (mounted) {
      await context.read<LibraryProvider>().loadFromDb();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              content: Text(isHidden
                  ? AppLocalizations.of(context)!.foldersShownAgain
                  : AppLocalizations.of(context)!.foldersHidden)),
        );
      }
    }
  }

  List<String> _sortedFolders(List<String> folders) {
    final sorted = List<String>.of(folders);
    switch (_sortOption) {
      case FolderSortOption.nameAZ:
        sorted.sort(
            (a, b) => compareTitles(a.split('/').last, b.split('/').last));
        break;
      case FolderSortOption.nameZA:
        sorted.sort(
            (a, b) => compareTitles(b.split('/').last, a.split('/').last));
        break;
      case FolderSortOption.songCountDesc:
        sorted.sort((a, b) => (_songsByFolder[b]?.length ?? 0)
            .compareTo(_songsByFolder[a]?.length ?? 0));
        break;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final visibleFolders = _sortedFolders(
      _showHidden
          ? _folders
          : _folders.where((f) => !_excluded.contains(f)).toList(),
    );

    if (_folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.foldersEmpty,
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!
                      .foldersCount(visibleFolders.length),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
              PopupMenuButton<FolderSortOption>(
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sort, size: 16),
                    const SizedBox(width: 4),
                    Text(_folderSortLabel(_sortOption),
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
                onSelected: (v) {
                  setState(() => _sortOption = v);
                  _savePrefs();
                },
                itemBuilder: (context) => [
                  _sortItem(
                      FolderSortOption.nameAZ,
                      AppLocalizations.of(context)!.foldersSortNameAsc),
                  _sortItem(
                      FolderSortOption.nameZA,
                      AppLocalizations.of(context)!.foldersSortNameDesc),
                  _sortItem(
                      FolderSortOption.songCountDesc,
                      AppLocalizations.of(context)!.foldersSortCount),
                ],
              ),
              IconButton(
                constraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(
                    _showHidden ? Icons.visibility_off : Icons.visibility_outlined,
                    size: 18),
                tooltip: _showHidden
                    ? AppLocalizations.of(context)!.foldersHideHidden
                    : AppLocalizations.of(context)!.foldersShowHidden,
                onPressed: () => setState(() => _showHidden = !_showHidden),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Fixed extent matches the two line tile height, no visual change.
            itemExtent: 72,
            itemCount: visibleFolders.length,
            itemBuilder: (context, i) {
              final folder = visibleFolders[i];
              final isHidden = _excluded.contains(folder);
              final songsInFolder = _songsByFolder[folder] ?? [];
              final totalMs = songsInFolder.fold(0, (sum, s) => sum + s.durationMs);
              return TweenAnimationBuilder<double>(
                key: ValueKey('folder_$folder'),
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 180 + (i % 8) * 25),
                curve: Curves.easeOut,
                builder: (context, v, child) => Opacity(
                  opacity: v,
                  child:
                      Transform.translate(offset: Offset(0, (1 - v) * 6), child: child),
                ),
                child: _clampRowText(
                  context,
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.folder_outlined,
                        color: isHidden ? Colors.grey : Theme.of(context).colorScheme.primary),
                    title: Text(folder.split('/').last,
                        style: isHidden ? const TextStyle(color: Colors.grey) : null),
                    subtitle: Text(
                        AppLocalizations.of(context)!
                            .librarySongCountDuration(songsInFolder.length,
                                formatDurationLong(totalMs)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: Icon(
                          isHidden ? Icons.visibility_off : Icons.visibility_outlined,
                          size: 18),
                      onPressed: () => _toggleHideFolder(folder),
                    ),
                    onTap: () async {
                      await Navigator.push(
                          context,
                          PageRouteBuilder(
                            transitionDuration: const Duration(milliseconds: 280),
                            pageBuilder: (context, anim, _) => _FolderSongsScreen(
                                folderName: folder.split('/').last,
                                songs: songsInFolder),
                            transitionsBuilder: (context, anim, _, child) =>
                                SlideTransition(
                              position: Tween<Offset>(
                                      begin: const Offset(1, 0), end: Offset.zero)
                                  .animate(CurvedAnimation(
                                      parent: anim, curve: Curves.easeOutCubic)),
                              child: child,
                            ),
                          ));
                      _load();
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _folderSortLabel(FolderSortOption opt) {
    final l = AppLocalizations.of(context)!;
    switch (opt) {
      case FolderSortOption.nameAZ: return l.foldersSortNameAsc;
      case FolderSortOption.nameZA: return l.foldersSortNameDesc;
      case FolderSortOption.songCountDesc: return l.foldersSortCountShort;
    }
  }

  PopupMenuItem<FolderSortOption> _sortItem(FolderSortOption value, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (_sortOption == value) ...[
            Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: 24),
          Text(label),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FOLDER SONGS SCREEN
// ─────────────────────────────────────────────────────────────

enum _SongSortOption { titleAZ, titleZA, artistAZ, dateAddedNewest }

class _FolderSongsScreen extends StatefulWidget {
  final String folderName;
  final List<Song> songs;
  const _FolderSongsScreen({required this.folderName, required this.songs});
  @override
  State<_FolderSongsScreen> createState() => _FolderSongsScreenState();
}

class _FolderSongsScreenState extends State<_FolderSongsScreen> {
  late List<Song> _localSongs;
  final _scrollController = ScrollController();
  bool _isScanning = false;
  int _scanProgress = 0;
  _SongSortOption _sortOption = _SongSortOption.titleAZ;
  static const double _itemHeight = 72;
  static const _kFolderSongSort = 'folder_song_sort';

  @override
  void initState() {
    super.initState();
    _localSongs = List.of(widget.songs);
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_kFolderSongSort) ?? 0;
    if (mounted) {
      setState(() => _sortOption =
          _SongSortOption.values[idx.clamp(0, _SongSortOption.values.length - 1)]);
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFolderSongSort, _sortOption.index);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Song> get _sorted {
    final list = List<Song>.of(_localSongs);
    switch (_sortOption) {
      case _SongSortOption.titleAZ:
        list.sort((a, b) => compareTitles(a.title, b.title));
        break;
      case _SongSortOption.titleZA:
        list.sort((a, b) => compareTitles(b.title, a.title));
        break;
      case _SongSortOption.artistAZ:
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case _SongSortOption.dateAddedNewest:
        list.sort((a, b) {
          final da = a.addedAt; final db = b.addedAt;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
        break;
    }
    return list;
  }

  void _jumpToLetter(String letter, List<Song> songs) {
    final index = letter == '#'
        ? songs.indexWhere((s) => !_leadingLetterReg.hasMatch(s.title))
        : songs.indexWhere((s) => s.title.toUpperCase().startsWith(letter));
    if (index == -1) return;
    _scrollController.animateTo(index * _itemHeight,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _scanThisFolder({required bool onlyMissing}) async {
    final targets = onlyMissing
        ? _localSongs.where((s) => !s.metadataScanned).toList()
        : List<Song>.of(_localSongs);
    if (targets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              content: Text(
                  AppLocalizations.of(context)!.foldersAllScanned)),
        );
      }
      return;
    }
    setState(() { _isScanning = true; _scanProgress = 0; });
    const batchSize = 5;
    for (int i = 0; i < targets.length; i += batchSize) {
      final batch = targets.skip(i).take(batchSize);
      await Future.wait(batch.map((s) => MetadataService.instance.enrichSong(s)));
      if (mounted) setState(() => _scanProgress += batch.length);
    }
    if (mounted) {
      final lib = context.read<LibraryProvider>();
      await lib.loadFromDb();
      final updatedIds = _localSongs.map((s) => s.id).toSet();
      setState(() {
        _isScanning = false;
        _localSongs = lib.songs.where((s) => updatedIds.contains(s.id)).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            content:
                Text(AppLocalizations.of(context)!.foldersScanDone)),
      );
    }
  }

  String _sortLabel(_SongSortOption opt) {
    final l = AppLocalizations.of(context)!;
    switch (opt) {
      case _SongSortOption.titleAZ: return l.foldersSortTitleAsc;
      case _SongSortOption.titleZA: return l.foldersSortTitleDesc;
      case _SongSortOption.artistAZ: return l.foldersSortArtistAsc;
      case _SongSortOption.dateAddedNewest: return l.foldersSortDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _localSongs.fold(0, (sum, s) => sum + s.durationMs);
    final displayed = _sorted;
    final showAzBar = _sortOption == _SongSortOption.titleAZ;
    final availableLetters = <String>{
      for (final s in displayed)
        _leadingLetterReg.hasMatch(s.title) ? s.title[0].toUpperCase() : '#'
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folderName),
        actions: [
          PopupMenuButton<_SongSortOption>(
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sort, size: 16),
                const SizedBox(width: 4),
                Text(_sortLabel(_sortOption), style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
              ],
            ),
            onSelected: (v) { setState(() => _sortOption = v); _savePrefs(); },
            itemBuilder: (context) => [
              _sortMenuItem(
                  _SongSortOption.titleAZ,
                  AppLocalizations.of(context)!.foldersSortTitleAsc),
              _sortMenuItem(
                  _SongSortOption.titleZA,
                  AppLocalizations.of(context)!.foldersSortTitleDesc),
              _sortMenuItem(
                  _SongSortOption.artistAZ,
                  AppLocalizations.of(context)!.foldersSortArtistAsc),
              _sortMenuItem(
                  _SongSortOption.dateAddedNewest,
                  AppLocalizations.of(context)!.foldersSortDate),
            ],
          ),
          _isScanning
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.cloud_sync_outlined),
                  onPressed: _localSongs.isEmpty
                      ? null
                      : () => _pickScanMode(),
                ),
        ],
      ),
      body: Column(
        children: [
          if (_isScanning)
            LinearProgressIndicator(
                value: _localSongs.isEmpty ? 0 : _scanProgress / _localSongs.length),
          Expanded(
            child: displayed.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.music_note_outlined,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                            AppLocalizations.of(context)!.foldersNoSongs,
                            textAlign: TextAlign.center),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverToBoxAdapter(
                            child: buildCollectionHeader(
                              context: context,
                              songCount: _localSongs.length,
                              totalMs: totalMs,
                              songs: displayed,
                            ),
                          ),
                          SliverFixedExtentList(
                            itemExtent: _itemHeight,
                            delegate: SliverChildBuilderDelegate(
                              (context, i) => buildSongTile(context, displayed[i], displayed, i),
                              childCount: displayed.length,
                            ),
                          ),
                        ],
                      ),
                      if (showAzBar)
                        Positioned(
                          right: 0, top: 0, bottom: 0,
                          child: AzScrollbar(
                            availableLetters: availableLetters,
                            onLetterSelected: (l) => _jumpToLetter(l, displayed),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  void _pickScanMode() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16),
              leading: const Icon(Icons.cloud_sync_outlined),
              title: Text(AppLocalizations.of(context)!.libraryScanMissing),
              onTap: () { Navigator.pop(ctx); _scanThisFolder(onlyMissing: true); },
            ),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16),
              leading: const Icon(Icons.refresh),
              title: Text(AppLocalizations.of(context)!.libraryRescanAll),
              onTap: () { Navigator.pop(ctx); _scanThisFolder(onlyMissing: false); },
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<_SongSortOption> _sortMenuItem(_SongSortOption value, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (_sortOption == value) ...[
            Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: 24),
          Text(label),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ARTISTS SCREEN
// ─────────────────────────────────────────────────────────────

class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
  // The grouping, the artist keys and the "play all" queue are all derived
  // from the library. They are rebuilt only when LibraryProvider.songsVersion
  // changes, so a notify that does not touch the song list (scan progress,
  // scanning flag) no longer regroups the whole library inside build.
  Map<String, List<Song>> _grouped = const <String, List<Song>>{};
  List<String> _artists = const <String>[];
  List<Song> _queue = const <Song>[];
  int _groupedVersion = -1;

  void _syncGroups(LibraryProvider lib) {
    if (_groupedVersion == lib.songsVersion) return;
    _groupedVersion = lib.songsVersion;
    _grouped = lib.groupedByArtist;
    _artists = _grouped.keys.toList()..sort();
    _queue = buildGroupQueue(_artists, _grouped);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, lib, _) {
        if (lib.songs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_outline, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(AppLocalizations.of(context)!.artistsEmpty,
                    textAlign: TextAlign.center),
              ],
            ),
          );
        }
        _syncGroups(lib);
        final grouped = _grouped;
        final artists = _artists;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(AppLocalizations.of(context)!
                        .artistsCount(artists.length),
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ),
                  // Play all and shuffle the whole artist list.
                  buildGroupPlayActions(context, _queue),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // Fixed extent matches the two line tile height, no visual change.
                itemExtent: 72,
                itemCount: artists.length,
                itemBuilder: (context, i) {
                  final artist = artists[i];
                  final songs = grouped[artist]!;
                  return TweenAnimationBuilder<double>(
                    key: ValueKey('artist_$artist'),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 160 + (i % 10) * 20),
                    curve: Curves.easeOut,
                    builder: (context, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(
                            offset: Offset(0, (1 - v) * 6), child: child)),
                    // Fixed extent row: clamp the text scale of the tile.
                    child: _clampRowText(
                      context,
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            safeInitial(artist),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer),
                          ),
                        ),
                        title: Text(artist,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            AppLocalizations.of(context)!
                                .librarySongCount(songs.length),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                        onTap: () => Navigator.push(
                          context,
                          PageRouteBuilder(
                            transitionDuration: const Duration(milliseconds: 280),
                            pageBuilder: (context, anim, _) =>
                                _ArtistSongsScreen(artist: artist, songs: songs),
                            transitionsBuilder: (context, anim, _, child) =>
                                SlideTransition(
                              position: Tween<Offset>(
                                      begin: const Offset(1, 0), end: Offset.zero)
                                  .animate(CurvedAnimation(
                                      parent: anim, curve: Curves.easeOutCubic)),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ArtistSongsScreen extends StatelessWidget {
  final String artist;
  final List<Song> songs;
  const _ArtistSongsScreen({required this.artist, required this.songs});

  @override
  Widget build(BuildContext context) {
    final totalMs = songs.fold(0, (sum, s) => sum + s.durationMs);
    return Scaffold(
      appBar: AppBar(title: Text(artist)),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: buildCollectionHeader(
              context: context,
              songCount: songs.length,
              totalMs: totalMs,
              songs: songs,
            ),
          ),
          SliverFixedExtentList(
            itemExtent: 72,
            delegate: SliverChildBuilderDelegate(
              (context, i) => buildSongTile(context, songs[i], songs, i),
              childCount: songs.length,
            ),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// GENRES SCREEN
// ─────────────────────────────────────────────────────────────

class GenresScreen extends StatefulWidget {
  const GenresScreen({super.key});

  @override
  State<GenresScreen> createState() => _GenresScreenState();
}

class _GenresScreenState extends State<GenresScreen> {
  // Same memoization as ArtistsScreen: rebuild the grouping, the keys and the
  // play all queue only when the library version changes, not on every
  // provider notify (for example each metadata scan batch).
  Map<String, List<Song>> _grouped = const <String, List<Song>>{};
  List<String> _genres = const <String>[];
  List<Song> _queue = const <Song>[];
  int _groupedVersion = -1;

  void _syncGroups(LibraryProvider lib) {
    if (_groupedVersion == lib.songsVersion) return;
    _groupedVersion = lib.songsVersion;
    _grouped = lib.groupedByGenre;
    _genres = _grouped.keys.toList()..sort();
    _queue = buildGroupQueue(_genres, _grouped);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, lib, _) {
        if (lib.songs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.category_outlined,
                    size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(AppLocalizations.of(context)!.genresEmpty,
                    textAlign: TextAlign.center),
              ],
            ),
          );
        }
        _syncGroups(lib);
        final grouped = _grouped;
        final genres = _genres;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(AppLocalizations.of(context)!
                        .genresCount(genres.length),
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ),
                  // Play all and shuffle the whole genre list.
                  buildGroupPlayActions(context, _queue),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // Fixed extent matches the two line tile height, no visual change.
                itemExtent: 72,
                itemCount: genres.length,
                itemBuilder: (context, i) {
                  final genre = genres[i];
                  final songs = grouped[genre]!;
                  return TweenAnimationBuilder<double>(
                    key: ValueKey('genre_$genre'),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 160 + (i % 10) * 20),
                    curve: Curves.easeOut,
                    builder: (context, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(
                            offset: Offset(0, (1 - v) * 6), child: child)),
                    // Fixed extent row: clamp the text scale of the tile.
                    child: _clampRowText(
                      context,
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.music_note,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                              size: 20),
                        ),
                        title: Text(genre,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            AppLocalizations.of(context)!
                                .librarySongCount(songs.length),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                        onTap: () => Navigator.push(
                          context,
                          PageRouteBuilder(
                            transitionDuration: const Duration(milliseconds: 280),
                            pageBuilder: (context, anim, _) =>
                                _GenreSongsScreen(genre: genre, songs: songs),
                            transitionsBuilder: (context, anim, _, child) =>
                                SlideTransition(
                              position: Tween<Offset>(
                                      begin: const Offset(1, 0), end: Offset.zero)
                                  .animate(CurvedAnimation(
                                      parent: anim, curve: Curves.easeOutCubic)),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GenreSongsScreen extends StatelessWidget {
  final String genre;
  final List<Song> songs;
  const _GenreSongsScreen({required this.genre, required this.songs});

  @override
  Widget build(BuildContext context) {
    final totalMs = songs.fold(0, (sum, s) => sum + s.durationMs);
    return Scaffold(
      appBar: AppBar(title: Text(genre)),
      body: Column(
        children: [
          buildCollectionHeader(
              context: context,
              songCount: songs.length,
              totalMs: totalMs,
              songs: songs),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverFixedExtentList(
                  itemExtent: 72,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => buildSongTile(context, songs[i], songs, i),
                    childCount: songs.length,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FAVORITES SCREEN
// ─────────────────────────────────────────────────────────────

enum _FavSortOption { titleAZ, titleZA, artistAZ, dateAddedNewest }

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  _FavSortOption _sortOption = _FavSortOption.titleAZ;
  final _scrollController = ScrollController();
  static const double _itemHeight = 72;
  static const _kFavSort = 'fav_sort_option';

  // Multi-select state, mirrors library_screen pattern. Session only.
  bool _multiSelectMode = false;
  final Set<int> _selectedIds = {};

  // Derived from the library: the sorted favorite rows, the total duration and
  // the A-Z letter set. Rebuilt only when the library version or the sort
  // changes, so a scan progress notify no longer re-sorts the whole list and
  // rebuilds the letter set inside build.
  List<Song> _favs = const <Song>[];
  int _totalMs = 0;
  Set<String> _letters = const <String>{};
  int _favsVersion = -1;
  _FavSortOption? _favsSort;

  void _syncFavorites(LibraryProvider lib) {
    if (_favsVersion == lib.songsVersion && _favsSort == _sortOption) return;
    _favsVersion = lib.songsVersion;
    _favsSort = _sortOption;
    final allFavs = lib.favorites;
    final sorted = _applySortAndFilter(allFavs);
    _favs = sorted;
    _totalMs = allFavs.fold(0, (sum, s) => sum + s.durationMs);
    _letters = <String>{
      for (final s in sorted)
        _leadingLetterReg.hasMatch(s.title) ? s.title[0].toUpperCase() : '#'
    };
  }

  // Playlists are loaded lazily on first bulk action to keep startup cheap.
  bool _playlistsRequested = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_kFavSort) ?? 0;
    if (mounted) {
      setState(() => _sortOption =
          _FavSortOption.values[idx.clamp(0, _FavSortOption.values.length - 1)]);
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFavSort, _sortOption.index);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Exit multi-select and clear the selection.
  void _exitMultiSelect() => setState(() {
        _multiSelectMode = false;
        _selectedIds.clear();
      });

  // Toggle one song id. Leaving zero selected exits the mode.
  void _toggleSelect(int id) => setState(() {
        if (_selectedIds.contains(id)) {
          _selectedIds.remove(id);
          if (_selectedIds.isEmpty) _multiSelectMode = false;
        } else {
          _selectedIds.add(id);
        }
      });

  // Load playlists once when first needed. Guarded by mounted.
  Future<void> _ensurePlaylistsLoaded() async {
    if (_playlistsRequested) return;
    _playlistsRequested = true;
    if (!mounted) return;
    try {
      await context.read<PlaylistProvider>().load();
    } catch (_) {
      // Picker below handles the empty state, no toast needed here.
    }
  }

  // Bulk add the selected songs to a chosen playlist.
  Future<void> _bulkAddToPlaylist(List<Song> songs) async {
    try {
      await _ensurePlaylistsLoaded();
      if (!mounted) return;
      final provider = context.read<PlaylistProvider>();
      final playlists = provider.playlists;
      if (playlists.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context)!.bulkCreatePlaylistFirst),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.9,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        AppLocalizations.of(context)!.libraryChoosePlaylist,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ...playlists.map((p) => ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        leading: const Icon(Icons.queue_music),
                        title: Text('${p['name']}'),
                        onTap: () async {
                          final name = '${p['name']}';
                          // One transaction for the whole selection. The per
                          // song path re-read the entire playlist every time,
                          // which made a large selection quadratic.
                          var added = 0;
                          var failed = 0;
                          try {
                            added = await provider.addSongs(
                                p['id'], songs.map((s) => s.id).toList());
                          } catch (_) {
                            failed = songs.length;
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (!mounted) return;
                          _exitMultiSelect();
                          // Report the real outcome, never the request count.
                          final partial = AppLocalizations.of(context)!
                              .libraryPartialAddedToPlaylist(
                                  added, songs.length, name, failed);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                              backgroundColor: failed > 0 ? Colors.red : null,
                              content: Text(failed > 0
                                  ? partial
                                  : AppLocalizations.of(context)!
                                      .libraryAddedToPlaylist(added, name)),
                            ),
                          );
                        },
                      )),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(AppLocalizations.of(context)!
              .bulkActionFailed(e.toString())),
        ),
      );
    }
  }

  // Bulk remove the selected songs from favorites.
  Future<void> _bulkRemoveFavorites(
      LibraryProvider lib, List<Song> songs) async {
    try {
      await lib.setFavoritesBulk(songs, false);
      if (!mounted) return;
      _exitMultiSelect();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(AppLocalizations.of(context)!
              .bulkUnfavoriteFailed(e.toString())),
        ),
      );
    }
  }

  // Selection action bar, mirrors library_screen multi-select bar.
  Widget _buildMultiSelectBar(LibraryProvider lib, List<Song> favs) {
    if (!_multiSelectMode) return const SizedBox.shrink();
    final selected =
        favs.where((s) => _selectedIds.contains(s.id)).toList();
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
              AppLocalizations.of(context)!
                  .librarySelectedCount(selected.length),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.playlist_add),
            tooltip:
                AppLocalizations.of(context)!.libraryAddToPlaylist,
            onPressed:
                selected.isEmpty ? null : () => _bulkAddToPlaylist(selected),
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.heart_broken_outlined),
            tooltip:
                AppLocalizations.of(context)!.bulkRemoveFavorite,
            onPressed: selected.isEmpty
                ? null
                : () => _bulkRemoveFavorites(lib, selected),
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.close),
            tooltip: AppLocalizations.of(context)!.cancel,
            onPressed: _exitMultiSelect,
          ),
        ],
      ),
    );
  }

  List<Song> _applySortAndFilter(List<Song> favs) {
    final list = List<Song>.of(favs);
    switch (_sortOption) {
      case _FavSortOption.titleAZ:
        list.sort((a, b) => compareTitles(a.title, b.title));
        break;
      case _FavSortOption.titleZA:
        list.sort((a, b) => compareTitles(b.title, a.title));
        break;
      case _FavSortOption.artistAZ:
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case _FavSortOption.dateAddedNewest:
        list.sort((a, b) {
          final da = a.addedAt; final db = b.addedAt;
          if (da == null && db == null) return 0;
          if (da == null) return 1; if (db == null) return -1;
          return db.compareTo(da);
        });
        break;
    }
    return list;
  }

  void _jumpToLetter(String letter, List<Song> songs) {
    final index = letter == '#'
        ? songs.indexWhere((s) => !_leadingLetterReg.hasMatch(s.title))
        : songs.indexWhere((s) => s.title.toUpperCase().startsWith(letter));
    if (index == -1) return;
    _scrollController.animateTo(index * _itemHeight,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  String _sortLabel(_FavSortOption opt) {
    final l = AppLocalizations.of(context)!;
    switch (opt) {
      case _FavSortOption.titleAZ: return l.foldersSortTitleAsc;
      case _FavSortOption.titleZA: return l.foldersSortTitleDesc;
      case _FavSortOption.artistAZ: return l.foldersSortArtistAsc;
      case _FavSortOption.dateAddedNewest: return l.foldersSortDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, lib, _) {
        // Recomputed only when the library or the sort changed, see
        // _syncFavorites. No favorites means an empty list here too.
        _syncFavorites(lib);
        if (_favs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(AppLocalizations.of(context)!.collectionsFavoritesEmpty,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(AppLocalizations.of(context)!.collectionsFavoritesHint,
                    style: TextStyle(color: Colors.grey[500])),
              ],
            ),
          );
        }
        final favs = _favs;
        final totalMs = _totalMs;
        final showAzBar = _sortOption == _FavSortOption.titleAZ;
        final availableLetters = _letters;

        return Column(
          children: [
            // Sort + total row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  // Shared ripple chip, same label as before.
                  SortChip(
                    label: _sortLabel(_sortOption),
                    onTap: () => _showSortMenu(context),
                  ),
                  const Spacer(),
                  Text(AppLocalizations.of(context)!
                      .librarySongCountDuration(
                          favs.length, formatDurationLong(totalMs)),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: favs.isEmpty
                          ? null
                          : () async {
                              try {
                                await PlayerService.instance.setQueueAndPlay(favs, 0);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        behavior: SnackBarBehavior.floating,
                                        duration:
                                            const Duration(seconds: 5),
                                        content: Text(
                                            AppLocalizations.of(context)!
                                                .libraryPlayFailed('$e'))),
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: Text(AppLocalizations.of(context)!
                          .libraryStartPlaying),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: favs.isEmpty ? null : () async {
                        final r = Random().nextInt(favs.length);
                        await PlayerService.instance.setQueueAndPlay(favs, r);
                        PlayerService.instance.setShuffle(true);
                      },
                      icon: const Icon(Icons.shuffle, size: 18),
                      label: Text(AppLocalizations.of(context)!
                          .libraryShuffle),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                    ),
                  ),
                ],
              ),
            ),
            // Multi-select action bar, mirrors library_screen pattern.
            _buildMultiSelectBar(lib, favs),
            Expanded(
              child: Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: () => lib.loadFromDb(),
                    // No AnimatedBuilder around the scroll view: every row
                    // watches the player on its own, so a track change, a play
                    // or pause toggle, the sleep timer or the crossfade no
                    // longer rebuilds the whole favorites list.
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverFixedExtentList(
                          itemExtent: _itemHeight,
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _FavSongTile(
                              song: favs[i],
                              queue: favs,
                              index: i,
                              isSelected: _selectedIds.contains(favs[i].id),
                              isMultiSelect: _multiSelectMode,
                              onToggleSelect: () => _toggleSelect(favs[i].id),
                              onLongPress: () => setState(() {
                                _multiSelectMode = true;
                                _selectedIds.add(favs[i].id);
                              }),
                            ),
                            childCount: favs.length,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showAzBar && !_multiSelectMode)
                    Positioned(
                      right: 0, top: 0, bottom: 0,
                      child: AzScrollbar(
                        availableLetters: availableLetters,
                        onLetterSelected: (l) => _jumpToLetter(l, favs),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSortMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        // Cap height at 90 percent of the screen and scroll on small phones.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                  AppLocalizations.of(context)!.librarySortBy,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            ..._FavSortOption.values.map((opt) => ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  dense: true,
                  leading: _sortOption == opt
                      ? Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary)
                      : const SizedBox(width: 18),
                  title: Text(_sortLabel(opt)),
                  onTap: () {
                    setState(() => _sortOption = opt);
                    _savePrefs();
                    Navigator.pop(ctx);
                  },
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FAVORITES ROW
// ─────────────────────────────────────────────────────────────

/// One favorites row. Same per row player watching as buildSongTile: only the
/// row whose isCurrent flag flips is rebuilt, and the bars inside it rebuild
/// only on play and pause.
class _FavSongTile extends StatelessWidget {
  final Song song;
  final List<Song> queue;
  final int index;
  final bool isSelected, isMultiSelect;
  final VoidCallback onToggleSelect, onLongPress;

  const _FavSongTile({
    required this.song,
    required this.queue,
    required this.index,
    required this.isSelected,
    required this.isMultiSelect,
    required this.onToggleSelect,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Provide the singleton locally so the Selector works without touching
    // the global provider setup in main.dart.
    return ChangeNotifierProvider.value(
      value: PlayerService.instance,
      child: Selector<PlayerService, bool>(
        selector: (_, ps) => ps.currentSong?.id == song.id,
        builder: (context, isCurrent, _) {
          final cs = Theme.of(context).colorScheme;
          // Row text is clamped: the row keeps a fixed 72 px extent.
          final scaler = _rowTextScaler(context);
          return InkWell(
            onTap: () {
              if (isMultiSelect) {
                onToggleSelect();
                return;
              }
              _playQueue(context, queue, index);
            },
            onLongPress: onLongPress,
            child: Container(
              color: isSelected
                  ? cs.primaryContainer.withValues(alpha: 0.5)
                  : isCurrent
                      ? cs.primaryContainer.withValues(alpha: 0.25)
                      : null,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              height: 72,
              child: Row(
                children: [
                  if (isMultiSelect)
                    Checkbox(
                        value: isSelected, onChanged: (_) => onToggleSelect())
                  else if (isCurrent)
                    const _FavNowPlayingBadge()
                  else
                    const Icon(Icons.favorite, color: Colors.red, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: scaler,
                          style: TextStyle(
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isCurrent ? cs.primary : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: scaler,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(formatDuration(song.durationMs),
                      textScaler: scaler,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[500])),
                  if (!isMultiSelect)
                    IconButton(
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => showSongOptions(context, song),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Circular now playing badge of a favorites row. Inner selector so play and
/// pause only rebuild the bars.
class _FavNowPlayingBadge extends StatelessWidget {
  const _FavNowPlayingBadge();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Selector<PlayerService, bool>(
      selector: (_, ps) => ps.player.playing,
      builder: (context, playing, _) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: PlayingIndicator(isPlaying: playing, color: cs.primary),
      ),
    );
  }
}

/// Play a queue position and surface a playback failure instead of dropping it.
Future<void> _playQueue(BuildContext context, List<Song> queue, int index) async {
  try {
    await PlayerService.instance.setQueueAndPlay(queue, index);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            content: Text(
                AppLocalizations.of(context)!.libraryPlayFailed('$e'))),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────
// PLAYLISTS SCREEN
// ─────────────────────────────────────────────────────────────

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});
  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<PlaylistProvider>().load());
  }

  Future<void> _createPlaylist() async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.collectionsNewPlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l.collectionsPlaylistNameHint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(l.create)),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      if (mounted) context.read<PlaylistProvider>().create(name);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, PlaylistProvider provider, int id, String name) async {
    final l = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.collectionsDeletePlaylist),
        content: Text(l.collectionsDeletePlaylistConfirm(name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.delete)),
        ],
      ),
    );
    if (confirm == true) provider.delete(id);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Consumer<PlaylistProvider>(
      builder: (context, provider, _) {
        if (provider.playlists.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.queue_music_outlined, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(l.collectionsNoPlaylists,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _createPlaylist,
                  icon: const Icon(Icons.add),
                  label: Text(l.collectionsCreatePlaylist),
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l.collectionsPlaylistCountAlt(
                        provider.playlists.length),
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ),
                  IconButton.filled(
                    onPressed: _createPlaylist,
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.add, size: 18),
                    iconSize: 18,
                    style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        tapTargetSize: MaterialTapTargetSize.padded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // Fixed extent matches the single line tile height, no visual change.
                itemExtent: 64,
                itemCount: provider.playlists.length,
                itemBuilder: (context, i) {
                  final p = provider.playlists[i];
                  return TweenAnimationBuilder<double>(
                    key: ValueKey('pl_${p['id']}'),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 180 + (i % 8) * 25),
                    curve: Curves.easeOut,
                    builder: (context, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(
                            offset: Offset(0, (1 - v) * 6), child: child)),
                    // Fixed extent row: clamp the text scale of the tile.
                    child: _clampRowText(
                      context,
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.queue_music,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              size: 20),
                        ),
                        title: Text(p['name'], maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.push(
                          context,
                          PageRouteBuilder(
                            transitionDuration: const Duration(milliseconds: 280),
                            pageBuilder: (context, anim, _) => PlaylistDetailScreen(
                                playlistId: p['id'], playlistName: p['name']),
                            transitionsBuilder: (context, anim, _, child) =>
                                SlideTransition(
                              position: Tween<Offset>(
                                      begin: const Offset(1, 0), end: Offset.zero)
                                  .animate(CurvedAnimation(
                                      parent: anim, curve: Curves.easeOutCubic)),
                              child: child,
                            ),
                          ),
                        ),
                        trailing: IconButton(
                          constraints: const BoxConstraints(
                              minWidth: 48, minHeight: 48),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () =>
                              _confirmDelete(context, provider, p['id'], p['name']),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// RECENTLY ADDED SCREEN
// ─────────────────────────────────────────────────────────────

class RecentlyAddedScreen extends StatefulWidget {
  const RecentlyAddedScreen({super.key});
  @override
  State<RecentlyAddedScreen> createState() => _RecentlyAddedScreenState();
}

class _RecentlyAddedScreenState extends State<RecentlyAddedScreen> {
  List<Song> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final lib = context.read<LibraryProvider>();
    // Full list, no artificial cap: the sliver list builds rows lazily.
    final songs = await lib.getRecentlyAdded(limit: _kFullListLimit);
    if (mounted) setState(() { _songs = songs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _SkeletonList();
    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.new_releases_outlined,
                size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
                AppLocalizations.of(context)!.collectionsRecentlyAddedEmpty,
                textAlign: TextAlign.center),
          ],
        ),
      );
    }
    final totalMs = _songs.fold(0, (sum, s) => sum + s.durationMs);
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          // Header play buttons - collapses on scroll
          SliverToBoxAdapter(
            child: buildCollectionHeader(
                context: context,
                songCount: _songs.length,
                totalMs: totalMs,
                songs: _songs),
          ),
          SliverFixedExtentList(
            itemExtent: 72,
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final song = _songs[i];
                return buildSongTile(context, song, _songs, i,
                    leading: song.albumArtUrl != null
                        // Disk cached artwork with network fallback.
                        ? ClipOval(
                            child: CachedArtImage(
                              url: song.albumArtUrl!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              // Decode thumbnail size only to save image memory.
                              cacheWidth: 88,
                              fallback: const CircleAvatar(
                                child: Icon(Icons.music_note, size: 20),
                              ),
                            ),
                          )
                        : const CircleAvatar(
                            child: Icon(Icons.music_note, size: 20),
                          ));
              },
              childCount: _songs.length,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MOST PLAYED SCREEN
// ─────────────────────────────────────────────────────────────

class MostPlayedScreen extends StatefulWidget {
  const MostPlayedScreen({super.key});
  @override
  State<MostPlayedScreen> createState() => _MostPlayedScreenState();
}

class _MostPlayedScreenState extends State<MostPlayedScreen> {
  List<Song> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final lib = context.read<LibraryProvider>();
    // Full list, no artificial cap: the sliver list builds rows lazily.
    final songs = await lib.getMostPlayed(limit: _kFullListLimit);
    if (mounted) setState(() { _songs = songs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _SkeletonList();
    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.collectionsMostPlayedEmpty,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context)!.collectionsMostPlayedHint,
                style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }
    final totalMs = _songs.fold(0, (sum, s) => sum + s.durationMs);
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: buildCollectionHeader(
                context: context,
                songCount: _songs.length,
                totalMs: totalMs,
                songs: _songs),
          ),
          SliverFixedExtentList(
            itemExtent: 72,
            delegate: SliverChildBuilderDelegate(
              (context, i) => buildSongTile(
                  context, _songs[i], _songs, i,
                  leading: SizedBox(
                    width: 40, height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _songs[i].albumArtUrl != null
                            // Disk cached artwork with network fallback.
                            ? ClipOval(
                                child: CachedArtImage(
                                  url: _songs[i].albumArtUrl!,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  // Decode thumbnail size only to save image memory.
                                  cacheWidth: 88,
                                  fallback: const CircleAvatar(
                                    child: Icon(
                                        Icons.music_note, size: 18),
                                  ),
                                ),
                              )
                            : const CircleAvatar(
                                child:
                                    Icon(Icons.music_note, size: 18),
                              ),
                        if (i < 3)
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              width: 16, height: 16,
                              decoration: BoxDecoration(
                                color: i == 0
                                    ? Colors.amber
                                    : i == 1
                                        ? Colors.grey[400]
                                        : Colors.brown[300],
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                childCount: _songs.length,
              ),
            ),
          ],
        ),
      );
  }
}

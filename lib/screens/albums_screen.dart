import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../widgets/mini_player.dart';
import '../widgets/entrance_fade.dart';
import '../widgets/sort_chip.dart';
import '../widgets/song_art_image.dart';
import '../services/embedded_art_service.dart';
import 'extra_screens.dart';

// Sort mode for the album grid. Session only, no persistence needed.
enum _AlbumSortOption { titleAZ, titleZA, countDesc, countAsc }

// Grid cell has a fixed aspect ratio while the app allows text scales up to
// 2x, so the info text of a card is clamped to stay inside the cell.
const double _kAlbumCardMaxTextScale = 1.5;

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  _AlbumSortOption _sortOption = _AlbumSortOption.titleAZ;

  // Grouping, sorted album keys and the "play all" queue are derived from the
  // library. Rebuilt only when LibraryProvider.songsVersion or the sort
  // changes, so a provider notify that does not touch the song list (scan
  // progress, scanning flag) no longer regroups the whole library in build.
  Map<String, List<Song>> _grouped = const <String, List<Song>>{};
  List<String> _albums = const <String>[];
  List<Song> _queue = const <Song>[];
  int _groupedVersion = -1;
  _AlbumSortOption? _groupedSort;

  void _syncAlbums(LibraryProvider lib) {
    if (_groupedVersion == lib.songsVersion && _groupedSort == _sortOption) {
      return;
    }
    _groupedVersion = lib.songsVersion;
    _groupedSort = _sortOption;
    final grouped = <String, List<Song>>{};
    for (final s in lib.songs) {
      grouped.putIfAbsent(s.album, () => []).add(s);
    }
    _grouped = grouped;
    _albums = _sortedAlbums(grouped.keys.toList(), grouped);
    _queue = buildGroupQueue(_albums, grouped);
  }

  // Short label shown inside the sort chip.
  String _sortChipLabel(AppLocalizations l) {
    switch (_sortOption) {
      case _AlbumSortOption.titleAZ:
        return l.albumSortTitleAZ;
      case _AlbumSortOption.titleZA:
        return l.albumSortTitleZA;
      case _AlbumSortOption.countDesc:
        return l.albumSortCountDesc;
      case _AlbumSortOption.countAsc:
        return l.albumSortCountAsc;
    }
  }

  // Full label shown inside the sort sheet rows.
  String _sortSheetLabel(AppLocalizations l, _AlbumSortOption opt) {
    switch (opt) {
      case _AlbumSortOption.titleAZ:
        return l.albumSortTitleAZ;
      case _AlbumSortOption.titleZA:
        return l.albumSortTitleZA;
      case _AlbumSortOption.countDesc:
        return l.albumSortCountDesc;
      case _AlbumSortOption.countAsc:
        return l.albumSortCountAsc;
    }
  }

  // Order album keys by the current session sort option.
  List<String> _sortedAlbums(
      List<String> keys, Map<String, List<Song>> grouped) {
    final sorted = List<String>.of(keys);
    switch (_sortOption) {
      case _AlbumSortOption.titleAZ:
        sorted.sort(
            (a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        break;
      case _AlbumSortOption.titleZA:
        sorted.sort(
            (a, b) => b.toLowerCase().compareTo(a.toLowerCase()));
        break;
      case _AlbumSortOption.countDesc:
        sorted.sort((a, b) =>
            (grouped[b]?.length ?? 0).compareTo(grouped[a]?.length ?? 0));
        break;
      case _AlbumSortOption.countAsc:
        sorted.sort((a, b) =>
            (grouped[a]?.length ?? 0).compareTo(grouped[b]?.length ?? 0));
        break;
    }
    return sorted;
  }

  // Simple bottom sheet with the four sort choices.
  void _showSortMenu() {
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(l.librarySortBy,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            ..._AlbumSortOption.values.map((opt) => ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  dense: true,
                  leading: _sortOption == opt
                      ? Icon(Icons.check,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary)
                      : const SizedBox(width: 18),
                  title: Text(_sortSheetLabel(l, opt)),
                  onTap: () {
                    setState(() => _sortOption = opt);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(builder: (context, lib, _) {
      final l = AppLocalizations.of(context)!;
      if (lib.songs.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.album_outlined, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(l.albumsEmpty, textAlign: TextAlign.center),
            ],
          ),
        );
      }

      // Grouped by album, memoized per library version and sort option.
      _syncAlbums(lib);
      final Map<String, List<Song>> grouped = _grouped;
      final albums = _albums;

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.albumsCount(albums.length),
                      style:
                          TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                // Play all and shuffle the whole album list.
                buildGroupPlayActions(context, _queue),
                const SizedBox(width: 4),
                // Shared ripple chip, same label as before.
                SortChip(
                  label: _sortChipLabel(l),
                  onTap: _showSortMenu,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemCount: albums.length,
              itemBuilder: (context, i) {
                final album = albums[i];
                final songs = grouped[album]!;
                // Prefer a member with a usable cover: first an already
                // known local (embedded) file, then a remote URL, else any.
                final cover = songs.firstWhere(
                    (s) =>
                        (s.albumArtPath ?? '').trim().isNotEmpty ||
                        EmbeddedArtService.instance.peekSync(s.id) != null,
                    orElse: () => songs.firstWhere(
                        (s) => s.albumArtUrl != null,
                        orElse: () => songs.first));
                return EntranceFade(
                  index: i,
                  key: ValueKey('album_$album'),
                  child: _AlbumCard(
                    album: album,
                    songs: songs,
                    coverSong: cover,
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

class _AlbumCard extends StatelessWidget {
  final String album;
  final List<Song> songs;
  final Song coverSong;

  const _AlbumCard(
      {required this.album, required this.songs, required this.coverSong});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    // Grid cell has a fixed aspect ratio, so clamp the text scale of the two
    // info lines to keep them inside the card at large app text scales.
    final scaler = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: _kAlbumCardMaxTextScale);
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 280),
            pageBuilder: (_, anim, __) =>
                _AlbumSongsScreen(album: album, songs: songs),
            transitionsBuilder: (_, anim, __, child) => SlideTransition(
              position: Tween<Offset>(
                      begin: const Offset(1, 0), end: Offset.zero)
                  .animate(CurvedAnimation(
                      parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover art: local embedded art wins, see the lookup at the
            // call site for the priority order.
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: SongArtImage(
                  song: coverSong,
                  fit: BoxFit.cover,
                  // Match grid column width to limit decoded size.
                  cacheWidth: 400,
                  fallback: _PlaceholderCover(cs: cs),
                ),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: scaler,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(l.librarySongCount(songs.length),
                      textScaler: scaler,
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  final ColorScheme cs;
  const _PlaceholderCover({required this.cs});
  @override
  Widget build(BuildContext context) => Container(
        color: cs.primaryContainer,
        child: Icon(Icons.album_outlined,
            size: 48, color: cs.onPrimaryContainer.withValues(alpha: 0.4)),
      );
}

class _AlbumSongsScreen extends StatelessWidget {
  final String album;
  final List<Song> songs;
  const _AlbumSongsScreen({required this.album, required this.songs});

  @override
  Widget build(BuildContext context) {
    final totalMs = songs.fold(0, (sum, s) => sum + s.durationMs);
    // Album artist (take the first/most common artist)
    final artistMap = <String, int>{};
    for (final s in songs) {
      artistMap[s.artist] = (artistMap[s.artist] ?? 0) + 1;
    }
    final topArtist = artistMap.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    return Scaffold(
      appBar: AppBar(title: Text(album)),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(topArtist,
                      style: TextStyle(
                          fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                buildCollectionHeader(
                    context: context,
                    songCount: songs.length,
                    totalMs: totalMs,
                    songs: songs),
              ],
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

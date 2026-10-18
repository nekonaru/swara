import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../providers/playlist_provider.dart';
import '../services/m3u_service.dart';
import '../services/player_service.dart';
import '../services/playlist_art_service.dart';
import '../utils/format.dart';
import '../utils/song_options.dart';
import '../widgets/az_scrollbar.dart';
import '../widgets/playing_indicator.dart';

enum _PlsSortOption { custom, titleAZ, titleZA, artistAZ }

class PlaylistDetailScreen extends StatefulWidget {
  final int playlistId;
  final String playlistName;
  const PlaylistDetailScreen({super.key, required this.playlistId, required this.playlistName});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<Song> _songs = [];
  _PlsSortOption _sortOption = _PlsSortOption.custom;
  String _query = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  static const double _itemHeight = 72;

  String get _kPlsSort => 'pls_sort_${widget.playlistId}';

  @override
  void initState() {
    super.initState();
    _loadPrefs().catchError((Object _) {}).then((_) => _load());
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_kPlsSort) ?? 0;
    if (!mounted) return;
    setState(() => _sortOption = _PlsSortOption.values[idx.clamp(0, _PlsSortOption.values.length - 1)]);
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlsSort, _sortOption.index);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final songs = await context.read<PlaylistProvider>().songsIn(widget.playlistId);
      if (!mounted) return;
      setState(() => _songs = songs);
      _scheduleArtRefresh();
    } catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            content: Text(l.playlistLoadFailed(e.toString()))),
      );
    }
  }

  // Fire and forget collage rebuild after content changes.
  // Never blocks the UI and never throws: failures keep the fallback.
  void _scheduleArtRefresh() {
    final songs = List<Song>.of(_songs);
    final playlistId = widget.playlistId;
    Future(() async {
      try {
        await PlaylistArtService.buildPlaylistArt(playlistId, songs);
        if (mounted) setState(() {});
      } catch (_) {
        // Keep the fallback art on any failure.
      }
    });
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final previousOrder = List<Song>.of(_songs);
    setState(() {
      final song = _songs.removeAt(oldIndex);
      _songs.insert(newIndex, song);
    });
    try {
      await context.read<PlaylistProvider>().reorder(widget.playlistId, _songs.map((s) => s.id).toList());
      _scheduleArtRefresh();
    } catch (e) {
      if (!mounted) return;
      // DB failed - roll back to the previous order.
      setState(() => _songs = previousOrder);
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            content: Text(l.playlistReorderFailed(e.toString()))),
      );
    }
  }

  Future<void> _removeSong(Song song) async {
    try {
      await context.read<PlaylistProvider>().removeSong(widget.playlistId, song.id);
    } catch (e) {
      if (!mounted) return;
      // Failed - rebuild so the dismissed tile reappears.
      setState(() {});
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            content: Text(l.playlistRemoveFailed(e.toString()))),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _songs.removeWhere((s) => s.id == song.id));
    _scheduleArtRefresh();
  }

  // Export the current playlist songs to an M3U file in Downloads.
  // Shows the saved path on success or the error on failure.
  Future<void> _exportM3u() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final songs = List<Song>.of(_songs);
      if (songs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(l10n.m3uExportEmpty),
          ),
        );
        return;
      }
      final content = M3uService.buildM3uContent(songs);
      final file =
          await M3uService.saveM3uToDownloads(widget.playlistName, content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(l10n.m3uExported(file.path)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(l10n.m3uExportFailed(e.toString())),
        ),
      );
    }
  }

  // Merge songs from another playlist into this one.
  // Only songs not already present are added (checked via songsIn),
  // so the target never gets duplicates. Shows a summary snackbar.
  Future<void> _mergeFromOther() async {
    final prov = context.read<PlaylistProvider>();
    try {
      await prov.load();
    } catch (_) {
      // Fall through and use the cached list on load failure.
    }
    if (!mounted) return;
    final others = prov.playlists
        .where((p) => (p['id'] as int) != widget.playlistId)
        .toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(AppLocalizations.of(context)!.mergeNoOthers),
        ),
      );
      return;
    }
    // Simple source picker dialog: list other playlists by name.
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(AppLocalizations.of(c)!.mergeFrom),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in others)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.queue_music),
                  title: Text((p['name'] as String?) ?? ''),
                  onTap: () => Navigator.pop(c, p),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppLocalizations.of(c)!.cancel),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final sourceId = picked['id'] as int;
    final sourceName = (picked['name'] as String?) ?? '';
    try {
      final current = await prov.songsIn(widget.playlistId);
      final source = await prov.songsIn(sourceId);
      if (!mounted) return;
      final existingIds = current.map((s) => s.id).toSet();
      // Only the songs the target does not have yet. The batch insert
      // re-checks inside its transaction, so a concurrent change cannot
      // create a duplicate, and the count it returns is the real one.
      final toAdd = <int>[];
      for (final s in source) {
        if (existingIds.contains(s.id)) continue;
        existingIds.add(s.id);
        toAdd.add(s.id);
      }
      final skipped = source.length - toAdd.length;
      var added = 0;
      try {
        added = await prov.addSongs(widget.playlistId, toAdd);
      } catch (_) {
        // The insert is atomic, so a failure means nothing was added.
        added = 0;
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(AppLocalizations.of(context)!.mergeSummary(
              added, sourceName, widget.playlistName, skipped)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          content: Text(AppLocalizations.of(context)!
              .mergeFailed(e.toString())),
        ),
      );
    }
  }

  List<Song> get _displayed {
    List<Song> list;
    switch (_sortOption) {
      case _PlsSortOption.custom:
        list = List<Song>.of(_songs);
        break;
      case _PlsSortOption.titleAZ:
        list = List<Song>.of(_songs)..sort((a, b) => compareTitles(a.title, b.title));
        break;
      case _PlsSortOption.titleZA:
        list = List<Song>.of(_songs)..sort((a, b) => compareTitles(b.title, a.title));
        break;
      case _PlsSortOption.artistAZ:
        list = List<Song>.of(_songs)
          ..sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
    }
    if (_query.trim().isEmpty) return list;
    final q = _query.toLowerCase();
    return list.where((s) =>
        s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q)).toList();
  }

  void _jumpToLetter(String letter, List<Song> songs) {
    int index;
    if (letter == '#') {
      index = songs.indexWhere((s) => !RegExp(r'^[a-zA-Z]').hasMatch(s.title));
    } else {
      index = songs.indexWhere((s) => s.title.toUpperCase().startsWith(letter));
    }
    if (index == -1) return;
    _scrollController.animateTo(
      index * _itemHeight,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final displayed = _displayed;
    final totalMs = _songs.fold(0, (sum, s) => sum + s.durationMs);
    final showAzBar = _query.isEmpty && _sortOption == _PlsSortOption.titleAZ;
    final availableLetters = <String>{
      for (final s in displayed)
        RegExp(r'^[a-zA-Z]').hasMatch(s.title) ? s.title[0].toUpperCase() : '#'
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlistName),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.m3uExportMenu,
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _exportM3u,
          ),
          PopupMenuButton<_PlsSortOption>(
            icon: const Icon(Icons.sort),
            onSelected: (v) {
              setState(() => _sortOption = v);
              _savePrefs();
            },
            itemBuilder: (context) => [
              _sortMenuItem(_PlsSortOption.custom, l.playlistSortCustom),
              _sortMenuItem(_PlsSortOption.titleAZ, l.playlistSortTitleAZ),
              _sortMenuItem(_PlsSortOption.titleZA, l.playlistSortTitleZA),
              _sortMenuItem(_PlsSortOption.artistAZ, l.playlistSortArtistAZ),
            ],
          ),
          // Extra actions menu: merge another playlist into this one.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (action) {
              if (action == 'merge') _mergeFromOther();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'merge',
                child:
                    Text(AppLocalizations.of(context)!.mergeMenu),
              ),
            ],
          ),
        ],
      ),
      body: _songs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.queue_music_outlined,
                      size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(l.playlistEmpty, textAlign: TextAlign.center),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Center(
                    child: _PlaylistHeaderArt(
                        playlistId: widget.playlistId),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l.playlistSummary(_songs.length, formatDurationLong(totalMs)),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ),
                ),
                // Search
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: l.playlistSearchHint,
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              constraints: const BoxConstraints(
                                  minWidth: 48, minHeight: 48),
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: displayed.isEmpty ? null : () => PlayerService.instance.setQueueAndPlay(displayed, 0),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l.playlistPlay),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: displayed.isEmpty ? null : () async {
                            final randomStart = Random().nextInt(displayed.length);
                            await PlayerService.instance.setQueueAndPlay(displayed, randomStart);
                            PlayerService.instance.setShuffle(true);
                          },
                          icon: const Icon(Icons.shuffle),
                          label: Text(l.playlistShuffle),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_sortOption == _PlsSortOption.custom && _query.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.drag_handle, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(l.playlistReorderHint,
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                Expanded(
                  child: displayed.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off,
                                  size: 56, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(l.playlistNoResults,
                                  textAlign: TextAlign.center),
                            ],
                          ),
                        )
                      : Stack(
                          children: [
                            AnimatedBuilder(
                              animation: PlayerService.instance,
                              builder: (context, _) =>
                                // Use ReorderableListView only in custom mode without search
                                _sortOption == _PlsSortOption.custom && _query.isEmpty
                                ? ReorderableListView.builder(
                                scrollController: _scrollController,
                                itemCount: displayed.length,
                                onReorderItem: _onReorder,
                                itemBuilder: (context, i) => _buildTile(displayed, i, reorderable: true),
                              )
                                : ListView.builder(
                                controller: _scrollController,
                                itemCount: displayed.length,
                                itemExtent: _itemHeight,
                                itemBuilder: (context, i) => _buildTile(displayed, i, reorderable: false),
                              ),
                            ),
                            if (showAzBar)
                              Positioned(
                                right: 0, top: 0, bottom: 0,
                                child: AzScrollbar(
                                  availableLetters: availableLetters,
                                  onLetterSelected: (letter) => _jumpToLetter(letter, displayed),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildTile(List<Song> songs, int i, {required bool reorderable}) {
    final song = songs[i];
    final currentSong = PlayerService.instance.currentSong;
    final isCurrentlyPlaying = currentSong != null && currentSong.id == song.id;
    final tile = Dismissible(
      key: ValueKey('pls_${song.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _removeSong(song),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        tileColor: isCurrentlyPlaying
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        leading: isCurrentlyPlaying
            ? Container(
                width: 40, height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: PlayingIndicator(
                  isPlaying: PlayerService.instance.player.playing,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : const Icon(Icons.music_note),
        title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: isCurrentlyPlaying ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatDuration(song.durationMs),
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            IconButton(
              constraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.more_vert),
              onPressed: () async {
                await showSongOptions(context, song,
                    showFullDelete: false, playlistId: widget.playlistId);
                _load();
              },
            ),
            if (reorderable) const Icon(Icons.drag_handle, color: Colors.grey),
          ],
        ),
        onTap: () => PlayerService.instance.setQueueAndPlay(songs, i),
      ),
    );

    return TweenAnimationBuilder<double>(
      key: ValueKey('plssong_${song.id}'), // without $i - avoid re-animation on reorder
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 180 + (i % 10) * 20),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 6), child: child),
      ),
      child: tile,
    );
  }

  PopupMenuItem<_PlsSortOption> _sortMenuItem(_PlsSortOption value, String label) {
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

// Large header cover showing the generated collage when cached,
// otherwise the same icon placeholder the empty state uses.
// TODO L10N: no user facing strings here, all literals are debug only.
class _PlaylistHeaderArt extends StatelessWidget {
  final int playlistId;

  const _PlaylistHeaderArt({required this.playlistId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.queue_music,
        color: cs.onPrimaryContainer,
        size: 64,
      ),
    );
    // A fresh future per build keeps the code simple: the parent calls
    // setState after each content change, so new art is picked up.
    return FutureBuilder<File?>(
      future: PlaylistArtService.existingArt(playlistId),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return fallback;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            file,
            width: 160,
            height: 160,
            fit: BoxFit.cover,
            cacheWidth: 320,
            errorBuilder: (_, __, ___) => fallback,
          ),
        );
      },
    );
  }
}

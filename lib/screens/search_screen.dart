import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/player_service.dart';
import '../services/art_cache_service.dart';
import '../utils/format.dart';
import '../utils/search_filter.dart';
import '../utils/song_options.dart';
import '../widgets/playing_indicator.dart';
import '../widgets/mini_player.dart';

enum _SearchFilter { lagu, album, artis, folder, genre }

// Result rows keep a fixed 72 px extent while the app allows text scales up to
// 2x, so the text of a row is clamped to stay inside that box.
const double _kRowMaxTextScale = 1.5;

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  _SearchFilter _filter = _SearchFilter.lagu;
  Timer? _debounce;

  // Search runs without any manual paging: the whole filtered result set is
  // rendered, but every row is still built lazily by ListView.builder.
  // Upper bound for one query run. Purely a safety net against a pathological
  // library, it is never reached in normal use.
  static const int _resultsLimit = 500;

  // Monotonic query token. Bumped for every query text or filter change so a
  // slow lookup started for an older query can never publish over a newer one.
  int _queryGen = 0;

  // Filtered songs for the active query, published from the async search only
  // after the generation check above passes.
  List<Song> _results = const <Song>[];
  // Spelling hint shown when nothing matched at all, for example "fadde".
  String? _suggestion;

  // LibraryProvider.songsVersion used for the last published search. The
  // version changes on content edits too (a metadata scan that renames rows
  // without changing the count), so the results cannot go stale silently.
  int _resultsLibVersion = -1;

  // True while a post frame re-search is already queued, avoids queueing
  // several redundant searches when build runs again first.
  bool _searchScheduled = false;

  // Latest raw text field content. The committed _query lags behind by the
  // debounce delay, filter changes re-filter this pending text so switching
  // tabs never drops what the user typed.
  String _pendingQuery = '';

  // Haystacks for the active library version and filter tab. Rebuilt only
  // when one of those changes, so a keystroke ships cached strings to the
  // isolate instead of rebuilding a string per song on the UI thread.
  List<String> _haystacks = const <String>[];
  List<String> _suggestHaystacks = const <String>[];
  int _haystackLibVersion = -1;
  _SearchFilter? _haystackFilter;
  int _haystackLength = -1;

  // Multi-select state for song results, mirrors library_screen pattern.
  // Session only, cleared when the query or filter changes.
  bool _multiSelectMode = false;
  final Set<int> _selectedIds = {};

  // Last 10 non-empty queries, newest first, persisted in SharedPreferences.
  static const _historyKey = 'search_history';
  static const _historyMax = 10;
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // Read the stored history once. Guarded by mounted.
  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_historyKey) ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _history = stored
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .take(_historyMax)
            .toList();
      });
    } catch (_) {
      // History is optional, ignore load failures.
    }
  }

  // Persist the current history list. Best effort only.
  Future<void> _persistHistory(List<String> value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_historyKey, value);
    } catch (_) {
      // Ignore write failures, the in memory list still renders.
    }
  }

  // Add a query to the top of the history (dedup, newest first, max 10).
  void _addToHistory(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final lowered = trimmed.toLowerCase();
    final updated = <String>[
      trimmed,
      for (final h in _history) if (h.toLowerCase() != lowered) h,
    ];
    if (updated.length > _historyMax) {
      updated.removeRange(_historyMax, updated.length);
    }
    if (!mounted) return;
    setState(() => _history = updated);
    _persistHistory(updated);
  }

  // Remove one history entry by value.
  void _removeHistoryItem(String item) {
    final updated = _history.where((h) => h != item).toList();
    if (!mounted) return;
    setState(() => _history = updated);
    _persistHistory(updated);
  }

  // Clear all stored history entries.
  void _clearHistory() {
    if (!mounted) return;
    setState(() => _history = []);
    _persistHistory([]);
  }

  // Submit a query: fill the field, run the search, remember the history.
  void _submitQuery(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _debounce?.cancel();
    _controller.text = trimmed;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    if (!mounted) return;
    setState(() {
      _query = trimmed;
      _pendingQuery = trimmed;
      _multiSelectMode = false;
      _selectedIds.clear();
    });
    _addToHistory(trimmed);
    _startSearch();
  }

  // Fill the field from a history chip and run the search.
  void _useHistoryItem(String item) => _submitQuery(item);

  // Playlists are loaded lazily on first bulk action to keep startup cheap.
  bool _playlistsRequested = false;

  // Debounce the search itself, the text field stays instant.
  void _onQueryChanged(String v) {
    _debounce?.cancel();
    // Invalidate any in flight search for the previous text right away.
    _pendingQuery = v;
    ++_queryGen;
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = v;
        // New query invalidates the old selection.
        _multiSelectMode = false;
        _selectedIds.clear();
      });
      // Take a fresh generation so this run always owns the latest token.
      _startSearch();
    });
  }

  // Bump the generation and kick off a search for the current pending text.
  void _startSearch() {
    final gen = ++_queryGen;
    _runSearch(gen);
  }

  // Bump the generation and re-run the search after the current frame, used
  // when the library list changed and the published results went stale.
  void _scheduleSearch() {
    final gen = ++_queryGen;
    _searchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchScheduled = false;
      if (!mounted) return;
      _runSearch(gen);
    });
  }

  // Filter the library and publish the result, but only when this run still
  // owns the active generation. Guards against stale async writes.
  Future<void> _runSearch(int gen) async {
    final lib = context.read<LibraryProvider>();
    final source = lib.songs;
    // Same source and version, so the published result is always in sync.
    final version = lib.songsVersion;
    final query = _pendingQuery;
    // Yield one turn so the guard below is meaningful even for small
    // libraries where the filter would otherwise finish synchronously.
    await Future<void>.delayed(Duration.zero);
    final found = await _filterSongs(source, query, version);
    // Guard after the isolate hop: an outdated run must not publish its
    // results or its spelling hint over a newer query.
    if (!mounted || gen != _queryGen) return;
    setState(() {
      _results = found.songs;
      _suggestion = found.suggestion;
      _resultsLibVersion = version;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
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
    } catch (e) {
      if (!mounted) return;
      // Keep silent here, the picker below will show the empty state.
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
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
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
                          final partial =
                              AppLocalizations.of(context)!
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

  // Bulk mark the selected songs as favorites.
  Future<void> _bulkAddToFavorites(List<Song> songs) async {
    final lib = context.read<LibraryProvider>();
    // setFavoritesBulk reports a failure through scanError instead of
    // throwing, so keep the previous value to tell success from failure.
    final previousError = lib.scanError;
    try {
      await lib.setFavoritesBulk(songs, true);
      if (!mounted) return;
      final error = lib.scanError != previousError ? lib.scanError : null;
      _exitMultiSelect();
      final done =
          AppLocalizations.of(context)!.libraryFavoritesAdded(songs.length);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          backgroundColor: error != null ? Colors.red : null,
          content: Text(error != null
              ? AppLocalizations.of(context)!.bulkFavoriteFailed(error)
              : done),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
          content: Text(AppLocalizations.of(context)!
              .bulkFavoriteFailed(e.toString())),
        ),
      );
    }
  }

  // Selection action bar shown under the filter chips in multi-select mode.
  Widget _buildMultiSelectBar(List<Song> results) {
    if (!_multiSelectMode) return const SizedBox.shrink();
    final selected =
        results.where((s) => _selectedIds.contains(s.id)).toList();
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
            icon: const Icon(Icons.favorite_border),
            tooltip:
                AppLocalizations.of(context)!.libraryAddToFavorites,
            onPressed:
                selected.isEmpty ? null : () => _bulkAddToFavorites(selected),
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

  // Rebuild the haystacks only when the library content or the filter tab
  // changed. A new query then reuses them instead of rebuilding a string
  // per song on the UI thread before the isolate hop.
  void _ensureHaystacks(List<Song> songs, int version) {
    if (_haystackLibVersion == version &&
        _haystackFilter == _filter &&
        _haystackLength == songs.length &&
        _suggestHaystacks.length == songs.length) {
      return;
    }
    _haystacks = <String>[for (final s in songs) _haystackFor(s)];
    _suggestHaystacks = <String>[
      for (final s in songs) '${s.title} ${s.artist} ${s.album}'
    ];
    _haystackLibVersion = version;
    _haystackFilter = _filter;
    _haystackLength = songs.length;
  }

  // Filter the library with the given query text and the active filter tab.
  // Returns the full match set plus an optional spelling hint; the caller
  // renders the matches lazily.
  //
  // Matching runs in a background isolate: every haystack is normalized
  // with regular expressions and the typo tolerant pass can run a bounded
  // edit distance against every word of every song, which used to cost a
  // frame per keystroke on a large library.
  Future<({List<Song> songs, String? suggestion})> _filterSongs(
      List<Song> songs, String query, int version) async {
    if (query.trim().isEmpty) {
      return (songs: const <Song>[], suggestion: null);
    }
    _ensureHaystacks(songs, version);
    final res = await compute(filterSongsIsolate, <String, dynamic>{
      'haystacks': _haystacks,
      'suggestHaystacks': _suggestHaystacks,
      'query': query,
      'limit': _resultsLimit,
    });
    final indices = (res['indices'] as List).cast<int>();
    // Map indices back to songs. The bounds check is cheap insurance against
    // the list changing between the haystack build and this await.
    return (
      songs: [
        for (final i in indices)
          if (i >= 0 && i < songs.length) songs[i],
      ],
      suggestion: res['suggestion'] as String?,
    );
  }

  String _haystackFor(Song s) {
    switch (_filter) {
      case _SearchFilter.lagu:
        return '${s.title} ${s.artist}';
      case _SearchFilter.album:
        return s.album;
      case _SearchFilter.artis:
        return s.artist;
      case _SearchFilter.folder:
        final parts = s.filePath.split('/');
        return parts.length > 1 ? parts[parts.length - 2] : '';
      case _SearchFilter.genre:
        return s.genre ?? '';
    }
  }

  // Group results by album/artist/folder/genre for the grouped view
  Map<String, List<Song>> _groupResults(List<Song> results) {
    final l = AppLocalizations.of(context)!;
    final map = <String, List<Song>>{};
    for (final s in results) {
      String key;
      switch (_filter) {
        case _SearchFilter.album:
          key = s.album;
          break;
        case _SearchFilter.artis:
          key = s.artist;
          break;
        case _SearchFilter.folder:
          final parts = s.filePath.split('/');
          key = parts.length > 1 ? parts[parts.length - 2] : l.searchOther;
          break;
        case _SearchFilter.genre:
          key = s.genre ?? l.unknown;
          break;
        default:
          key = '';
      }
      map.putIfAbsent(key, () => []).add(s);
    }
    return map;
  }

  Widget _buildFilterChips() {
    final l = AppLocalizations.of(context)!;
    final filters = [
      (_SearchFilter.lagu, l.searchFilterSong),
      (_SearchFilter.album, l.searchFilterAlbum),
      (_SearchFilter.artis, l.searchFilterArtist),
      (_SearchFilter.folder, l.searchFilterFolder),
      (_SearchFilter.genre, l.searchFilterGenre),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (filter, label) = filters[i];
          final isSelected = _filter == filter;
          return FilterChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) {
              setState(() {
                _filter = filter;
                // Switching filter invalidates the old selection.
                _multiSelectMode = false;
                _selectedIds.clear();
              });
              // Re-run the search for the same text under the new filter.
              _startSearch();
            },
            showCheckmark: false,
          );
        },
      ),
    );
  }

  // Recent queries as chips, shown only while the query is empty.
  // Tap fills the field and searches, X or long-press removes one entry.
  Widget _buildHistoryChips() {
    if (_query.trim().isNotEmpty || _history.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.histRecent,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clearHistory,
                child: Container(
                  alignment: Alignment.centerRight,
                  constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
                  child: Text(
                      AppLocalizations.of(context)!.histClear,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final item in _history)
                GestureDetector(
                  // Long-press removes the entry, same as the X button.
                  onLongPress: () => _removeHistoryItem(item),
                  child: InputChip(
                    label: Text(item,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: () => _useHistoryItem(item),
                    onDeleted: () => _removeHistoryItem(item),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Clamp the text scale of a fixed height row. ListTile has no textScaler
  // parameter, so the whole tile subtree gets a clamped MediaQuery instead.
  Widget _clampRowText(BuildContext context, Widget child) {
    final scaler =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _kRowMaxTextScale);
    final mq = MediaQuery.of(context);
    if (scaler == mq.textScaler) return child;
    return MediaQuery(data: mq.copyWith(textScaler: scaler), child: child);
  }

  // One result row. Mirrors the library_screen tile: the row is wrapped in a
  // per row Selector, so a track change, a play or pause toggle rebuilds only
  // the affected rows instead of the whole result list on every notify.
  Widget _buildSongTile(Song song, List<Song> queue, int index) {
    final isSelected = _selectedIds.contains(song.id);
    return ChangeNotifierProvider.value(
      value: PlayerService.instance,
      child: Selector<PlayerService, bool>(
        selector: (_, ps) => ps.currentSong?.id == song.id,
        builder: (context, isCurrent, _) => _songTileBody(
          song: song,
          queue: queue,
          index: index,
          isCurrent: isCurrent,
          isSelected: isSelected,
        ),
      ),
    );
  }

  Widget _songTileBody({
    required Song song,
    required List<Song> queue,
    required int index,
    required bool isCurrent,
    required bool isSelected,
  }) {
    final cs = Theme.of(context).colorScheme;
    return _clampRowText(
      context,
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        tileColor: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.5)
            : isCurrent
                ? cs.primaryContainer.withValues(alpha: 0.25)
                : null,
        leading: _multiSelectMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSelect(song.id),
              )
            : _SearchNowPlayingIcon(songId: song.id, fallback: _artFallback(song)),
        title: Text(song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text('${song.artist} \u00B7 ${song.album}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatDuration(song.durationMs),
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            if (!_multiSelectMode)
              IconButton(
                constraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.more_vert),
                onPressed: () => showSongOptions(context, song),
              ),
          ],
        ),
        onTap: () async {
          // In multi-select mode a tap toggles the checkbox, no playback.
          if (_multiSelectMode) {
            _toggleSelect(song.id);
            return;
          }
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
        // Long-press enters multi-select, mirrors library_screen pattern.
        // Only the flat song list uses this; grouped views keep normal taps.
        onLongPress: () {
          if (_filter != _SearchFilter.lagu) return;
          setState(() {
            _multiSelectMode = true;
            _selectedIds.add(song.id);
          });
        },
      ),
    );
  }

  // Artwork used when this row is not the current song.
  Widget _artFallback(Song song) => song.albumArtUrl != null
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

  Widget _buildResults(List<Song> results) {
    final l = AppLocalizations.of(context)!;
    if (_query.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              l.searchPromptTitle,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[400]),
            ),
            const SizedBox(height: 8),
            Text(
              l.searchPromptSubtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              l.searchNoResults,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[400]),
            ),
            const SizedBox(height: 8),
            Text(
              l.searchNotFound(_query),
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
            // Spelling hint for a near miss, for example "fadde" when the
            // library has "Faded".
            if (_suggestion != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  final suggestion = _suggestion;
                  if (suggestion == null) return;
                  _controller.text = suggestion;
                  _controller.selection = TextSelection.collapsed(
                      offset: suggestion.length);
                  _pendingQuery = suggestion;
                  _startSearch();
                },
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: Text(
                  AppLocalizations.of(context)!
                      .searchDidYouMean(_suggestion!),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (_filter == _SearchFilter.lagu) {
      // Full flat result set, still built one row at a time by the builder.
      // No AnimatedBuilder here: each row watches the player by itself, so a
      // track change or a play and pause toggle no longer rebuilds the list.
      return ListView.builder(
        itemCount: results.length,
        itemExtent: 72,
        itemBuilder: (context, i) => SizedBox(
            height: 72, child: _buildSongTile(results[i], results, i)),
      );
    }

    // Grouped view for album/artist/folder/genre
    final grouped = _groupResults(results);
    final groups = grouped.keys.toList()..sort();

    // Flatten the groups into a single row list so every header and every
    // song stays lazily built, without a per group eager Column.
    final rows = <_GroupRow>[];
    for (final groupKey in groups) {
      final groupSongs = grouped[groupKey]!;
      rows.add(_GroupRow.header(groupKey, groupSongs.length));
      for (var k = 0; k < groupSongs.length; k++) {
        rows.add(_GroupRow.song(groupSongs[k], groupSongs, k));
      }
    }

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, gi) {
        final row = rows[gi];
        if (row.headerKey != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(row.headerKey!,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                    Text(l.librarySongCount(row.headerCount!),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
          );
        }
        return _buildSongTile(row.song!, row.queue!, row.index);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final lib = context.watch<LibraryProvider>();
    // A library change invalidates the published results, re-run the search.
    // Compared on the version token, not the length: a metadata scan can
    // change every title while the song count stays the same.
    if (!_searchScheduled && lib.songsVersion != _resultsLibVersion) {
      _scheduleSearch();
    }
    // Results live in state, published only by a generation checked search.
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        // In multi-select mode the AppBar shows the count + cancel action.
        title: _multiSelectMode
            ? Text(AppLocalizations.of(context)!
                .librarySelectedCount(_selectedIds.length))
            : TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: l.searchHint,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          constraints: const BoxConstraints(
                              minWidth: 48, minHeight: 48),
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _debounce?.cancel();
                            _controller.clear();
                            setState(() {
                              _query = '';
                              _pendingQuery = '';
                              _multiSelectMode = false;
                              _selectedIds.clear();
                            });
                            _startSearch();
                          },
                        )
                      : null,
                ),
                onChanged: _onQueryChanged,
                onSubmitted: _submitQuery,
                textInputAction: TextInputAction.search,
              ),
        actions: [
          if (_multiSelectMode)
            IconButton(
              constraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.close),
              tooltip: AppLocalizations.of(context)!.cancel,
              onPressed: _exitMultiSelect,
            ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          _buildFilterChips(),
          _buildHistoryChips(),
          const SizedBox(height: 8),
          _buildMultiSelectBar(results),
          if (_query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Align(
                  key: ValueKey(_query + _filter.name),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l.searchResultCount(results.length),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildResults(results),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

/// Leading icon of a search result row. Provides the player singleton locally
/// so the two Selectors work without touching main.dart: the outer one rebuilds
/// only when this row becomes the current song, the inner one only on play and
/// pause.
class _SearchNowPlayingIcon extends StatelessWidget {
  final int songId;
  final Widget fallback;
  const _SearchNowPlayingIcon({required this.songId, required this.fallback});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: PlayerService.instance,
      child: Selector<PlayerService, bool>(
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
            child: Selector<PlayerService, bool>(
              selector: (_, ps) => ps.player.playing,
              builder: (context, playing, _) =>
                  PlayingIndicator(isPlaying: playing, color: cs.primary),
            ),
          );
        },
      ),
    );
  }
}

/// One row of the grouped search result list. Either a group header or a
/// single song. Flattening the groups into rows keeps every element lazily
/// built by ListView.builder instead of building a whole group eagerly.
class _GroupRow {
  /// Group name when this row is a header, otherwise null.
  final String? headerKey;

  /// Song count shown next to the header, otherwise null.
  final int? headerCount;

  /// Song shown when this row is a song, otherwise null.
  final Song? song;

  /// Full group queue so playback covers the whole group.
  final List<Song>? queue;

  /// Position of [song] inside [queue].
  final int index;

  const _GroupRow.header(this.headerKey, this.headerCount)
      : song = null,
        queue = null,
        index = 0;

  const _GroupRow.song(this.song, this.queue, this.index)
      : headerKey = null,
        headerCount = null;
}

import 'package:flutter/foundation.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:swara/providers/language_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/db_helper.dart';
import '../services/library_scanner.dart';
import '../services/metadata_service.dart';
import '../utils/format.dart';

enum SortOption {
  titleAZ,
  titleZA,
  artistAZ,
  artistZA,
  albumAZ,
  albumZA,
  dateAddedNewest,
  dateAddedOldest,
  genre,
}

class LibraryProvider extends ChangeNotifier {
  List<Song> songs = [];
  bool isScanning = false;
  bool isBulkScanningMetadata = false;
  // Private mutex for bulkScanMetadata so overlapping calls return early.
  bool _bulkScanning = false;
  int bulkScanProgress = 0;
  int bulkScanTotal = 0;
  String? scanError;
  SortOption sortOption = SortOption.titleAZ;

  // Monotonic counter bumped every time the song list is replaced, reordered
  // or has a row removed. Consumers use it to invalidate derived caches (A-Z
  // map, id to row index, groupings) with a cheap int compare instead of
  // deep comparing thousands of songs.
  int _songsVersion = 0;

  // True while scanDevice is running, so a second call is ignored.
  bool _scanning = false;

  // Cached sum of every duration, recomputed once per load instead of on
  // every read.
  int _totalDurationMs = 0;

  // Cached favorite rows, rebuilt only when songsVersion changes. The
  // collections screen reads favorites.length on every build, and scanning
  // notifications fire often, so an uncached getter allocated a fresh list
  // thousands of rows long per notification.
  List<Song> _favoritesCache = const <Song>[];
  int _favoritesVersion = -1;

  // Lazily built id to song index, invalidated whenever the list content or
  // order changes. Screens that look up one row per rebuild (the player
  // screen resolves the playing song on every notification) used to scan the
  // whole library for that.
  Map<int, Song>? _byIdCache;
  int _byIdCacheVersion = -1;

  static const _kSortOption = 'lib_sort_option';
  static const _kLastDeviceScan = 'last_device_scan_ms';
  // Auto scan only when more than 30 minutes have passed
  static const _scanIntervalMs = 1800000;

  // Time of the last full loadFromDb, backing the fetchSongsPage fast path.
  DateTime? _lastFullLoadAt;

  // Guard so notifyListeners never runs after dispose.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  LibraryProvider() {
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_kSortOption) ?? 0;
    sortOption = SortOption.values[idx.clamp(0, SortOption.values.length - 1)];
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSortOption, sortOption.index);
  }

  /// Load from DB (instant, no device scan) - called when the app opens
  Future<void> loadFromDb() async {
    final all = await DBHelper.instance.getAllSongs();
    final excluded = await DBHelper.instance.getExcludedFolders();
    songs = excluded.isEmpty
        ? all
        : all.where((s) {
            final folder = folderOf(s.filePath);
            return !excluded.contains(folder);
          }).toList();
    _applySort();
    // Sum the durations once here instead of folding the whole library on
    // every rebuild. The header reads this value on every notification and
    // a metadata scan notifies once per batch, so folding 20k rows there
    // would be tens of millions of iterations per scan.
    var durationMs = 0;
    for (final s in songs) {
      durationMs += s.durationMs;
    }
    _totalDurationMs = durationMs;
    // Content may have changed while the length stayed the same (metadata
    // edits, one file removed and one added), so bump the version.
    _songsVersion++;
    _lastFullLoadAt = DateTime.now();
    notifyListeners();
  }

  /// Load from DB then scan the device in the background only if needed.
  /// Songs appear instantly from the DB, the scan only runs when the last
  /// scan is old enough.
  Future<void> autoLoadAndScanIfNeeded() async {
    // Step 1: load the DB first - music shows up right away
    await loadFromDb();

    // Step 2: check whether a device scan is needed
    int lastMs = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      lastMs = prefs.getInt(_kLastDeviceScan) ?? 0;
    } catch (e) {
      debugPrint('LibraryProvider autoLoadAndScanIfNeeded prefs read failed: $e');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsed = nowMs - lastMs;

    // Skip the scan when songs already exist and the last scan is recent
    if (songs.isNotEmpty && elapsed < _scanIntervalMs) return;

    // Scan the device (no internet) in the background
    await scanDevice();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastDeviceScan, nowMs);
    } catch (e) {
      debugPrint('LibraryProvider autoLoadAndScanIfNeeded prefs write failed: $e');
    }
  }

  /// Scan files from the phone (detect new/removed songs).
  /// Fast path: device read + DB write only, no internet fetch, so the
  /// song list appears instantly at startup.
  Future<void> scanDevice() async {
    // Reentrancy guard. Two overlapping scans compared the songs table against
    // their own device snapshot, so the slower one deleted the songs the
    // faster one had just inserted, together with their playlist entries and
    // listening history.
    if (_scanning) return;
    _scanning = true;
    isScanning = true;
    scanError = null;
    notifyListeners();
    try {
      await LibraryScanner().scanAndSync();
      await loadFromDb();
    } catch (e) {
      scanError = '${lookupAppLocalizations(LanguageProvider.instance.locale).coreScanFailed}: $e';
    }
    _scanning = false;
    isScanning = false;
    notifyListeners();
  }

  /// Force a device scan and refresh the timestamp
  Future<void> forceScanDevice() async {
    await scanDevice();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastDeviceScan, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('LibraryProvider forceScanDevice prefs write failed: $e');
    }
  }

  Future<void> bulkScanMetadata({bool onlyMissing = false}) async {
    // Skip when a bulk scan is already running.
    if (_bulkScanning) return;
    final targets = onlyMissing ? songs.where((s) => !s.metadataScanned).toList() : songs;
    if (targets.isEmpty) return;

    _bulkScanning = true;
    isBulkScanningMetadata = true;
    bulkScanTotal = targets.length;
    bulkScanProgress = 0;
    notifyListeners();

    try {
      const batchSize = 5;
      DateTime? _lastNotify;
      // Throttle notifyListeners: only update at most every 10 songs or
      // every 2 seconds, whichever comes first. The UI only needs coarse
      // progress, not a rebuild per batch of 5.
      void _maybeNotify(int done) {
        final now = DateTime.now();
        final byCount = done % 10 == 0;
        final byTime = _lastNotify == null ||
            now.difference(_lastNotify!).inMilliseconds >= 2000;
        if (byCount || byTime) {
          _lastNotify = now;
          notifyListeners();
        }
      }
      for (int i = 0; i < targets.length; i += batchSize) {
        final batch = targets.skip(i).take(batchSize).toList();
        final results =
            await Future.wait(batch.map((song) => MetadataService.instance.enrichSong(song)));
        bulkScanProgress += batch.length;
        _maybeNotify(bulkScanProgress);
        if (results.any((limited) => limited)) break;
      }

      await loadFromDb();
    } finally {
      _bulkScanning = false;
      isBulkScanningMetadata = false;
      notifyListeners();
    }
  }

  /// Fetch metadata for one song from the internet on purpose.
  ///
  /// Returns true when the fetch was skipped because iTunes is rate limiting
  /// us, so the UI can say so instead of claiming success.
  Future<bool> rescanSingleMetadata(Song song) async {
    final limited =
        await MetadataService.instance.enrichSong(song, bypassCache: true);
    // enrichSong fills the in-memory object but upsertSong keeps the stored
    // rich columns for an existing row, so the new values have to be written
    // explicitly. Without this the button appeared to work and then changed
    // nothing.
    if (!limited) {
      await DBHelper.instance.applyEnrichedMetadata(song);
    }
    // The enrich can rewrite title/artist/album, so re-sort after patching.
    // One row changed: no full table reload for it.
    if (_patchSongInMemory(song)) {
      _applySort();
      _songsVersion++;
      notifyListeners();
    } else {
      await loadFromDb();
    }
    return limited;
  }

  void setSortOption(SortOption option) {
    sortOption = option;
    _applySort();
    // Same rows, different order: derived indexes must be rebuilt.
    _songsVersion++;
    _savePrefs();
    notifyListeners();
  }

  /// Cheap change token for the current [songs] list, content and order.
  int get songsVersion => _songsVersion;

  /// Song stored at [id] in the current library, or null when it is gone.
  ///
  /// Replaces an O(n) scan per lookup. The index is rebuilt only when the
  /// version changed, and dropped by [_patchSongInMemory] when a row object
  /// was swapped in place.
  Song? songById(int id) {
    final cache = _byIdCache;
    if (cache == null ||
        _byIdCacheVersion != _songsVersion ||
        cache.length != songs.length) {
      final rebuilt = <int, Song>{for (final s in songs) s.id: s};
      _byIdCache = rebuilt;
      _byIdCacheVersion = _songsVersion;
      return rebuilt[id];
    }
    return cache[id];
  }

  /// Swap the stored row for [id] with the fresh field values of [source].
  ///
  /// Returns false when the id is not in the current library, so the caller
  /// can fall back to a full reload. Single row actions (rename, one metadata
  /// refresh) used to reload the whole table, re-sort the full list and
  /// rebuild every consumer for one changed row.
  ///
  /// The existing row OBJECT is kept and only its mutable fields are copied
  /// over, so any widget already holding that row sees the update and the id
  /// index stays valid without a rebuild.
  bool _patchSongInMemory(Song source) {
    final list = songs;
    for (var i = 0; i < list.length; i++) {
      final row = list[i];
      if (row.id != source.id) continue;
      if (identical(row, source)) return true;
      row.title = source.title;
      row.artist = source.artist;
      row.album = source.album;
      row.genre = source.genre;
      row.region = source.region;
      row.albumArtPath = source.albumArtPath;
      row.albumArtUrl = source.albumArtUrl;
      row.lyrics = source.lyrics;
      row.durationMs = source.durationMs;
      row.isFavorite = source.isFavorite;
      row.addedAt = source.addedAt;
      row.metadataScanned = source.metadataScanned;
      return true;
    }
    return false;
  }

  /// Flip the favorite flag on one stored row without touching anything else.
  ///
  /// The passed in object may be a copy loaded by another screen, so only the
  /// flag is written and the library row keeps its own field values.
  bool _setFavoriteInMemory(int id, bool value) {
    final list = songs;
    for (var i = 0; i < list.length; i++) {
      final row = list[i];
      if (row.id == id) {
        row.isFavorite = value;
        return true;
      }
    }
    return false;
  }

  /// ORDER BY key matching DBHelper.querySongsPage whitelist for [opt].
  /// Keeps DB paging order consistent with the in memory [_applySort].
  String orderByForSort(SortOption opt) {
    switch (opt) {
      case SortOption.titleAZ:
        return 'title ASC';
      case SortOption.titleZA:
        return 'title DESC';
      case SortOption.artistAZ:
        return 'artist ASC';
      case SortOption.artistZA:
        return 'artist DESC';
      case SortOption.albumAZ:
        return 'album ASC';
      case SortOption.albumZA:
        return 'album DESC';
      case SortOption.dateAddedNewest:
        return 'addedAt DESC';
      case SortOption.dateAddedOldest:
        return 'addedAt ASC';
      case SortOption.genre:
        return 'genre ASC';
    }
  }

  /// Single DB page using querySongsPage with the current sort and the
  /// stored excluded folders. Returns null when the paged query fails so
  /// the caller can fall back to the full in memory list.
  ///
  /// Fast path: when the in memory [songs] list is fresh (a full loadFromDb
  /// less than 60 seconds ago), the query is empty, and the sort is the
  /// default title A-Z, the in memory order already matches the DB order
  /// produced by querySongsPage for orderBy 'title ASC', so a plain slice
  /// is returned with no DB hit. Fallback: any other sort, a non empty
  /// query, stale data, or an out of range page falls through to the DB
  /// query below (and a DB failure still returns null for the caller to
  /// fall back to the full in memory list).
  Future<List<Song>?> fetchSongsPage({
    required int limit,
    required int offset,
    String query = '',
  }) async {
    final lastLoad = _lastFullLoadAt;
    if (query.trim().isEmpty &&
        sortOption == SortOption.titleAZ &&
        lastLoad != null &&
        DateTime.now().difference(lastLoad) < const Duration(seconds: 60)) {
      final safeLimit = limit < 1 ? 50 : limit;
      final safeOffset = offset < 0 ? 0 : offset;
      if (safeOffset >= songs.length) return <Song>[];
      final end = (safeOffset + safeLimit).clamp(0, songs.length);
      return songs.sublist(safeOffset, end);
    }
    try {
      final excluded = await DBHelper.instance.getExcludedFolders();
      final page = await DBHelper.instance.querySongsPage(
        limit: limit,
        offset: offset,
        query: query,
        orderBy: orderByForSort(sortOption),
        excludedFolders: excluded,
      );
      return page;
    } catch (_) {
      return null;
    }
  }

  void _applySort() {
    // Comparison keys are computed ONCE per song. The old comparators
    // lowercased both sides inside every comparison, which for a large
    // library meant hundreds of thousands of string allocations on every
    // load and every sort change.
    switch (sortOption) {
      case SortOption.titleAZ:
        _sortByTitle(descending: false);
        break;
      case SortOption.titleZA:
        _sortByTitle(descending: true);
        break;
      case SortOption.artistAZ:
        _sortByKey((s) => s.artist.toLowerCase(), descending: false);
        break;
      case SortOption.artistZA:
        _sortByKey((s) => s.artist.toLowerCase(), descending: true);
        break;
      case SortOption.albumAZ:
        _sortByKey((s) => s.album.toLowerCase(), descending: false);
        break;
      case SortOption.albumZA:
        _sortByKey((s) => s.album.toLowerCase(), descending: true);
        break;
      case SortOption.dateAddedNewest:
        songs.sort((a, b) {
          final da = a.addedAt;
          final db = b.addedAt;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
        break;
      case SortOption.dateAddedOldest:
        songs.sort((a, b) {
          final da = a.addedAt;
          final db = b.addedAt;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return da.compareTo(db);
        });
        break;
      case SortOption.genre:
        songs.sort((a, b) => (a.genre ?? '').compareTo(b.genre ?? ''));
        break;
    }
  }

  /// Sort titles in tier order (symbols < digits < letters < other scripts),
  /// same result as calling compareTitles per comparison but with the lower
  /// case form and the tier computed once per song.
  void _sortByTitle({required bool descending}) {
    final decorated = <(int, String, Song)>[
      for (final s in songs) (titleSortRank(s.title), s.title.toLowerCase(), s),
    ];
    decorated.sort((a, b) {
      if (a.$1 != b.$1) {
        final cmp = a.$1.compareTo(b.$1);
        return descending ? -cmp : cmp;
      }
      final cmp = a.$2.compareTo(b.$2);
      return descending ? -cmp : cmp;
    });
    songs.setAll(0, [for (final d in decorated) d.$3]);
  }

  /// Sort by a precomputed key string, in place so callers keep the same
  /// list object they already hold.
  void _sortByKey(String Function(Song) keyOf, {required bool descending}) {
    final decorated = <(String, Song)>[for (final s in songs) (keyOf(s), s)];
    decorated.sort((a, b) {
      final cmp = a.$1.compareTo(b.$1);
      return descending ? -cmp : cmp;
    });
    songs.setAll(0, [for (final d in decorated) d.$2]);
  }

  List<Song> filteredSongs(String query) {
    if (query.trim().isEmpty) return songs;
    final q = query.toLowerCase();
    return songs.where((s) =>
        s.title.toLowerCase().contains(q) ||
        s.artist.toLowerCase().contains(q) ||
        s.album.toLowerCase().contains(q)).toList();
  }

  int get totalCount => songs.length;
  int get totalDurationMs => _totalDurationMs;

  List<Song> get favorites {
    if (_favoritesVersion != _songsVersion) {
      _favoritesVersion = _songsVersion;
      _favoritesCache = songs.where((s) => s.isFavorite).toList();
    }
    return _favoritesCache;
  }

  Future<void> toggleFavorite(Song song, bool value) async {
    await DBHelper.instance.setFavorite(song.id, value);
    // Keep the caller's object in sync (it may be a copy held by the player
    // or a playlist screen), then patch the library row in place. A favorite
    // is never a sort key, so no re-sort and no version bump are needed.
    song.isFavorite = value;
    if (!_setFavoriteInMemory(song.id, value)) {
      // Not in the current list (deleted meanwhile): fall back to a reload.
      await loadFromDb();
      return;
    }
    // Version gates every derived cache, including the favorites screen
    // list, so a favorite change must bump it even though the sort keys and
    // the row order stay the same.
    _songsVersion++;
    notifyListeners();
  }

  /// Set favorites for many songs at once: a single batch write to the DB,
  /// then one in memory patch and a single notification. On failure -> scanError.
  Future<void> setFavoritesBulk(List<Song> songs, bool value) async {
    if (songs.isEmpty) return;
    try {
      await DBHelper.instance
          .setFavoritesBulk(songs.map((s) => s.id).toList(), value);
      var patched = 0;
      for (final s in songs) {
        s.isFavorite = value;
        if (_setFavoriteInMemory(s.id, value)) patched++;
      }
      if (patched == songs.length) {
        // Same reason as toggleFavorite: the favorites screen is version
        // gated and must see the new state.
        _songsVersion++;
        notifyListeners();
      } else {
        // Something the list never saw (deleted rows): reload to resync.
        await loadFromDb();
      }
    } catch (e) {
      scanError = '${lookupAppLocalizations(LanguageProvider.instance.locale).coreUpdateFavoritesFailed}: $e';
      notifyListeners();
    }
  }

  Future<void> deleteSong(Song song) async {
    await DBHelper.instance.deleteSong(song.id);
    _removeSongsFromMemory([song]);
  }

  /// Delete many songs with one in memory update.
  ///
  /// [deleteSong] in a loop re-notifies for every row, and each notification
  /// invalidates the row index map and the A-Z map, so removing a few hundred
  /// duplicates rebuilt those maps hundreds of times. This removes them all
  /// at once and bumps the version a single time.
  Future<void> deleteSongs(List<Song> toDelete) async {
    if (toDelete.isEmpty) return;
    for (final song in toDelete) {
      try {
        await DBHelper.instance.deleteSong(song.id);
      } catch (_) {
        // Keep going so one locked row does not abort the whole cleanup.
      }
    }
    _removeSongsFromMemory(toDelete);
  }

  /// Drop deleted songs from the cached lists and bump the version once.
  void _removeSongsFromMemory(List<Song> toRemove) {
    if (toRemove.isEmpty) return;
    final ids = toRemove.map((s) => s.id).toSet();
    var removedDurationMs = 0;
    final kept = <Song>[];
    for (final s in songs) {
      if (ids.contains(s.id)) {
        removedDurationMs += s.durationMs;
      } else {
        kept.add(s);
      }
    }
    songs = kept;
    // The cached total must follow the deletion, otherwise the library header
    // would keep reporting the duration of songs that no longer exist.
    _totalDurationMs =
        _totalDurationMs > removedDurationMs
            ? _totalDurationMs - removedDurationMs
            : 0;
    _songsVersion++;
    notifyListeners();
  }

  Future<void> updateMetadata(Song song) async {
    await DBHelper.instance.updateSongMetadata(song);
    // A rename can change the sort keys, so the stored rows are patched and
    // the list is re-sorted in memory. Reloading the whole table here cost a
    // full query plus a full rebuild for one edited row.
    if (!_patchSongInMemory(song)) {
      await loadFromDb();
      return;
    }
    _applySort();
    _songsVersion++;
    notifyListeners();
  }

  Map<String, List<Song>> get groupedByArtist {
    final Map<String, List<Song>> map = {};
    for (final s in songs) {
      map.putIfAbsent(s.artist, () => []).add(s);
    }
    return map;
  }

  Map<String, List<Song>> get groupedByGenre {
    final unknown =
        lookupAppLocalizations(LanguageProvider.instance.locale).unknown;
    final Map<String, List<Song>> map = {};
    for (final s in songs) {
      final key = s.genre ?? unknown;
      map.putIfAbsent(key, () => []).add(s);
    }
    return map;
  }

  Future<List<Song>> getRecentlyAdded({int limit = 50}) async {
    final all = await DBHelper.instance.getAllSongsByDateAdded();
    final excluded = await DBHelper.instance.getExcludedFolders();
    final filtered = excluded.isEmpty
        ? all
        : all.where((s) => !excluded.contains(folderOf(s.filePath))).toList();
    return filtered.take(limit).toList();
  }

  Future<List<Song>> getMostPlayed({int limit = 50}) async {
    // Hidden folders must not show up here either. The DB query cannot know
    // about them, so filter afterwards and over fetch to still fill the list.
    final all = await DBHelper.instance.getMostPlayedSongs(limit: limit * 4);
    final excluded = await DBHelper.instance.getExcludedFolders();
    if (excluded.isEmpty) return all.take(limit).toList();
    return all
        .where((s) => !excluded.contains(folderOf(s.filePath)))
        .take(limit)
        .toList();
  }
}

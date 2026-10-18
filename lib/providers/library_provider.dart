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
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_kLastDeviceScan) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsed = nowMs - lastMs;

    // Skip the scan when songs already exist and the last scan is recent
    if (songs.isNotEmpty && elapsed < _scanIntervalMs) return;

    // Scan the device (no internet) in the background
    await scanDevice();
    await prefs.setInt(_kLastDeviceScan, nowMs);
  }

  /// Scan files from the phone (detect new/removed songs).
  /// Fast path: device read + DB write only, no internet fetch, so the
  /// song list appears instantly at startup. Pass [autoFetchMetadata] true
  /// only when the caller explicitly wants the slow internet enrich inline.
  Future<void> scanDevice({bool autoFetchMetadata = false}) async {
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
      await LibraryScanner().scanAndSync(autoFetchMetadata: autoFetchMetadata);
      await loadFromDb();
    } catch (e) {
      scanError = '${lookupAppLocalizations(LanguageProvider.instance.locale).coreScanFailed}: $e';
    }
    _scanning = false;
    isScanning = false;
    notifyListeners();
  }

  /// Force a device scan and refresh the timestamp
  Future<void> forceScanDevice({bool autoFetchMetadata = false}) async {
    await scanDevice(autoFetchMetadata: autoFetchMetadata);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastDeviceScan, DateTime.now().millisecondsSinceEpoch);
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
      for (int i = 0; i < targets.length; i += batchSize) {
        final batch = targets.skip(i).take(batchSize).toList();
        // Await the batch and stop at once on iTunes 429: leftovers keep
        // metadataScanned false and are retried on a later scan.
        // Single backoff window lives in MetadataService, no retry loop here.
        final results =
            await Future.wait(batch.map((song) => MetadataService.instance.enrichSong(song)));
        bulkScanProgress += batch.length;
        notifyListeners();
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
    await loadFromDb();
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
    switch (sortOption) {
      case SortOption.titleAZ:
        songs.sort((a, b) => compareTitles(a.title, b.title));
        break;
      case SortOption.titleZA:
        songs.sort((a, b) => compareTitles(b.title, a.title));
        break;
      case SortOption.artistAZ:
        songs.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case SortOption.artistZA:
        songs.sort((a, b) => b.artist.toLowerCase().compareTo(a.artist.toLowerCase()));
        break;
      case SortOption.albumAZ:
        songs.sort((a, b) => (a.album).toLowerCase().compareTo((b.album).toLowerCase()));
        break;
      case SortOption.albumZA:
        songs.sort((a, b) => (b.album).toLowerCase().compareTo((a.album).toLowerCase()));
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

  List<Song> get favorites => songs.where((s) => s.isFavorite).toList();

  Future<void> toggleFavorite(Song song, bool value) async {
    await DBHelper.instance.setFavorite(song.id, value);
    await loadFromDb();
  }

  /// Set favorites for many songs at once: a single batch write to the DB
  /// then ONE reload + notify (via loadFromDb). On failure -> scanError.
  Future<void> setFavoritesBulk(List<Song> songs, bool value) async {
    if (songs.isEmpty) return;
    try {
      await DBHelper.instance
          .setFavoritesBulk(songs.map((s) => s.id).toList(), value);
      await loadFromDb();
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
    await loadFromDb();
  }

  List<Song> get sortedByArtist =>
      [...songs]..sort((a, b) => a.artist.compareTo(b.artist));

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

  Map<String, List<Song>> get groupedByRegion {
    final unknown =
        lookupAppLocalizations(LanguageProvider.instance.locale).unknown;
    final Map<String, List<Song>> map = {};
    for (final s in songs) {
      final key = s.region ?? unknown;
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
    return DBHelper.instance.getMostPlayedSongs(limit: limit);
  }
}

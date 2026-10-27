import 'package:flutter/foundation.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:swara/providers/language_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class DBHelper {
  DBHelper._();
  static final DBHelper instance = DBHelper._();
  Database? _db;

  Future<Database> get db async {
    _db ??= await _init();
    final database = _db;
    if (database == null) {
      throw StateError('Database failed to initialize.');
    }
    return database;
  }

  Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'music_app.db');
    return openDatabase(
      path,
      version: 9,
      onConfigure: (db) async {
        // sqflite calls onConfigure before it opens the migration transaction,
        // which is the only window where the journal mode can still be
        // switched. See _applyPragmas.
        await _applyPragmas(db);
      },
      onOpen: (db) async {
        // onOpen runs after the transaction is committed, so the tables are
        // guaranteed to exist. This is where the indexes are created.
        await _ensureIndexes(db);
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE songs(
            id INTEGER PRIMARY KEY,
            filePath TEXT UNIQUE,
            title TEXT,
            artist TEXT,
            album TEXT,
            genre TEXT,
            region TEXT,
            albumArtPath TEXT,
            albumArtUrl TEXT,
            lyrics TEXT,
            durationMs INTEGER,
            isFavorite INTEGER DEFAULT 0,
            lastPlayedAt TEXT,
            addedAt TEXT,
            metadataScanned INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE listening_entries(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            songId INTEGER,
            timestamp TEXT,
            listenedMs INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE playlists(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE,
            createdAt TEXT,
            folder TEXT DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE playlist_songs(
            playlistId INTEGER,
            songId INTEGER,
            addedAt TEXT,
            position INTEGER DEFAULT 0,
            PRIMARY KEY (playlistId, songId)
          )
        ''');
        await db.execute('''
          CREATE TABLE folders(
            path TEXT PRIMARY KEY,
            includeInLibrary INTEGER DEFAULT 1
          )
        ''');
        // Indexes are deliberately NOT created here: onCreate runs inside the
        // migration transaction, and an index that fails to be created there
        // (for example because the device ran out of space during an upgrade)
        // would stay missing. _ensureIndexes retries them on every open.
        //
        // Disk cache for iTunes search responses so reinstalls do not
        // refetch songs that were already looked up (hits and misses).
        await db.execute('''
          CREATE TABLE metadata_cache(
            query TEXT PRIMARY KEY,
            response TEXT,
            fetchedAt TEXT
          )
        ''');
        // Synced (LRC) lyrics fetched from lrclib, keyed by song id.
        await db.execute('''
          CREATE TABLE synced_lyrics(
            songId INTEGER PRIMARY KEY,
            lrc TEXT,
            fetchedAt TEXT
          )
        ''');
        // No automatic prune of listening_entries here. The dashboard reads it
        // with all time queries that have no date filter (getTotalListeningMs,
        // getHourlyDistribution, getTopSongIds, getMostPlayedSongs), so
        // dropping rows by age would silently change numbers that are still
        // on screen. Pruning is user confirmed only, see pruneListeningEntries.
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // No pragma tuning here: this callback runs inside the migration
        // transaction, where SQLite refuses to change the journal mode.
        // Indexes are created in onOpen as well, see _ensureIndexes.
        if (oldVersion < 2) {
          // Add the position column for the playlist reorder feature
          try {
            await db.execute('ALTER TABLE playlist_songs ADD COLUMN position INTEGER DEFAULT 0');
          } catch (_) {
            // Column may already exist, ignore
          }
        }
        if (oldVersion < 3) {
          // Add the addedAt column so the "Recently added" sort truly reflects
          // insert time instead of just reversing the current list order
          try {
            await db.execute('ALTER TABLE songs ADD COLUMN addedAt TEXT');
          } catch (_) {
            // Column may already exist, ignore
          }
        }
        if (oldVersion < 4) {
          // Explicitly mark songs whose metadata was already scanned,
          // so the "scan only songs missing metadata" feature stays accurate.
          try {
            await db.execute('ALTER TABLE songs ADD COLUMN metadataScanned INTEGER DEFAULT 0');
            // Never mark 'Tidak diketahui' as scanned - that is a fallback
            // value, not a real fetch result. Only genuine genre/lyrics count.
            // Empty strings count as unscanned too, so use NULLIF to treat
            // '' the same as NULL for both genre and lyrics.
            await db.execute(
                "UPDATE songs SET metadataScanned = 1 WHERE (NULLIF(genre, '') IS NOT NULL AND genre != 'Tidak diketahui') OR NULLIF(lyrics, '') IS NOT NULL");
          } catch (_) {
            // Column may already exist, ignore
          }
        }
        if (oldVersion < 5) {
          // Disk cache for iTunes responses (hits and miss markers).
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS metadata_cache(
                query TEXT PRIMARY KEY,
                response TEXT,
                fetchedAt TEXT
              )
            ''');
          } catch (_) {
            // Table may already exist, ignore
          }
        }
        if (oldVersion < 6) {
          // Synced (LRC) lyrics store for the synced lyrics feature.
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS synced_lyrics(
                songId INTEGER PRIMARY KEY,
                lrc TEXT,
                fetchedAt TEXT
              )
            ''');
          } catch (_) {
            // Table may already exist, ignore
          }
        }
        if (oldVersion < 7) {
          // Playlist folder label for the collections grouping feature.
          // Empty string means the playlist is not in any folder.
          try {
            await db.execute(
                "ALTER TABLE playlists ADD COLUMN folder TEXT DEFAULT ''");
          } catch (_) {
            // Column may already exist, ignore
          }
        }
        if (oldVersion < 8) {
          try {
            // Backfill rows whose addedAt is NULL so the Recently Added sort
            // stays stable. Use the earliest known addedAt in the table so
            // backfilled rows sort as the oldest, and fall back to now only
            // when the table has no non-null addedAt at all.
            final minRows = await db.rawQuery(
                'SELECT MIN(addedAt) as m FROM songs WHERE addedAt IS NOT NULL');
            final minAdded = minRows.isNotEmpty
                ? minRows.first['m'] as String?
                : null;
            final fallback = (minAdded != null && minAdded.isNotEmpty)
                ? minAdded
                : DateTime.now().toIso8601String();
            await db.execute(
                'UPDATE songs SET addedAt = ? WHERE addedAt IS NULL',
                [fallback]);
          } catch (_) {
            // Best effort only, the list still renders with NULL addedAt last.
          }
          try {
            // Demote rows that were wrongly marked scanned when genre or
            // lyrics was only an empty string. Empty string means unscanned,
            // same as NULL, so it must not keep the scanned flag.
            await db.execute('''
              UPDATE songs SET metadataScanned = 0
              WHERE metadataScanned = 1
                AND (NULLIF(genre, '') IS NULL OR genre = 'Tidak diketahui')
                AND NULLIF(lyrics, '') IS NULL
            ''');
          } catch (_) {
            // Best effort only, unscanned songs are retried on next scan.
          }
        }
        if (oldVersion < 9) {
          // The v9 indexes for artist and album were created on the bare
          // columns, so they use the BINARY collation, while
          // _sanitizeSongsOrderBy always sorts artist and album COLLATE
          // NOCASE. SQLite refuses to use such an index for a COLLATE NOCASE
          // sort, so the sort still full scans. Drop them and let
          // _ensureIndexes create the matching NOCASE ones on every open.
          // Only installs that still upgrade through v9 run this, devices that
          // already reached v9 keep the unused indexes until reinstall.
          try {
            await db.execute('DROP INDEX IF EXISTS idx_songs_artist');
            await db.execute('DROP INDEX IF EXISTS idx_songs_album');
          } catch (e) {
            debugPrint('DBHelper: dropping the unused v9 indexes failed: $e');
          }
        }
        // No automatic prune of listening_entries here. Besides deleting
        // numbers the dashboard still shows (see the note in onCreate), any
        // statement issued while the migration transaction is open joins that
        // transaction, so a DELETE sent from this callback would block
        // openDatabase() until it finished. Pruning is user confirmed only,
        // see pruneListeningEntries.
      },
    );
  }

  // ---------- SQLite tuning ----------
  /// Apply the SQLite pragmas on every open.
  ///
  /// Called from onConfigure, which sqflite runs before it opens the
  /// migration transaction. That placement is required for journal_mode:
  /// SQLite cannot switch journal mode while a transaction is active, so
  /// running this from onCreate or onUpgrade (both inside the exclusive
  /// transaction) always failed and left the database in DELETE mode.
  ///
  /// Nothing is trusted blindly: journal_mode is read back and the real mode
  /// is logged when it is not WAL, and every other failing pragma is logged
  /// too instead of being swallowed.
  static Future<void> _applyPragmas(Database db) async {
    try {
      // setJournalMode hides the Android quirk where the pragma only takes
      // effect through rawQuery when WAL is not enabled in the manifest.
      await db.setJournalMode('wal');
    } catch (e) {
      debugPrint('DBHelper: setJournalMode(wal) failed: $e');
    }
    try {
      final rows = await db.rawQuery('PRAGMA journal_mode');
      final actual =
          rows.isEmpty ? null : rows.first.values.first?.toString().toLowerCase();
      if (actual != 'wal') {
        debugPrint('DBHelper: journal_mode is "$actual" instead of "wal" '
            'after configuring the database.');
      }
    } catch (e) {
      debugPrint('DBHelper: could not read back PRAGMA journal_mode: $e');
    }

    const pragmas = <String>[
      'PRAGMA synchronous=NORMAL',
      'PRAGMA cache_size=-8000', // 8 MB page cache
      'PRAGMA temp_store=MEMORY',
    ];
    for (final sql in pragmas) {
      try {
        await db.execute(sql);
      } catch (e) {
        debugPrint('DBHelper: "$sql" failed: $e');
      }
    }

    // mmap_size answers with a row, so it needs rawQuery instead of execute.
    try {
      await db.rawQuery('PRAGMA mmap_size=134217728'); // 128 MB
    } catch (e) {
      debugPrint('DBHelper: PRAGMA mmap_size failed: $e');
    }
  }

  /// Index name to CREATE statement for every index the app relies on.
  ///
  /// The NOCASE variants exist because _sanitizeSongsOrderBy sorts title,
  /// artist and album with COLLATE NOCASE. An index on the bare column keeps
  /// the BINARY collation of that column and SQLite will not use it to
  /// satisfy a COLLATE NOCASE sort, so the sort would still full scan.
  /// idx_songs_title stays BINARY because getAllSongs, getFavorites and
  /// getNeverPlayedSongs sort title without COLLATE.
  static const Map<String, String> _indexStatements = <String, String>{
    'idx_songs_title':
        'CREATE INDEX IF NOT EXISTS idx_songs_title ON songs(title)',
    'idx_songs_lastPlayedAt': 'CREATE INDEX IF NOT EXISTS '
        'idx_songs_lastPlayedAt ON songs(lastPlayedAt)',
    'idx_songs_addedAt':
        'CREATE INDEX IF NOT EXISTS idx_songs_addedAt ON songs(addedAt)',
    'idx_songs_title_nocase': 'CREATE INDEX IF NOT EXISTS '
        'idx_songs_title_nocase ON songs(title COLLATE NOCASE)',
    'idx_songs_artist_nocase': 'CREATE INDEX IF NOT EXISTS '
        'idx_songs_artist_nocase ON songs(artist COLLATE NOCASE)',
    'idx_songs_album_nocase': 'CREATE INDEX IF NOT EXISTS '
        'idx_songs_album_nocase ON songs(album COLLATE NOCASE)',
    'idx_listening_song_ts': 'CREATE INDEX IF NOT EXISTS '
        'idx_listening_song_ts ON listening_entries(songId, timestamp)',
    'idx_listening_ts': 'CREATE INDEX IF NOT EXISTS '
        'idx_listening_ts ON listening_entries(timestamp)',
    'idx_playlist_songs_pid_pos': 'CREATE INDEX IF NOT EXISTS '
        'idx_playlist_songs_pid_pos ON playlist_songs(playlistId, position)',
  };

  /// Make sure every index exists. Called from onOpen, which sqflite runs after
  /// the migration transaction is committed, so the tables are guaranteed to
  /// exist by then (a fresh install creates them in onCreate first).
  ///
  /// CREATE INDEX IF NOT EXISTS is idempotent and cheap, so this also repairs
  /// an upgrade that failed halfway, for example because the device ran out
  /// of storage: the missing indexes are created on the next open. There is no
  /// heavy await here, only one statement per missing index, so it does not
  /// hold up startup.
  static Future<void> _ensureIndexes(Database db) async {
    for (final entry in _indexStatements.entries) {
      try {
        await db.execute(entry.value);
      } catch (e) {
        debugPrint('DBHelper: index ${entry.key} could not be created: $e');
      }
    }
  }

  /// Drop listening history rows, never called automatically.
  ///
  /// The dashboard reads listening_entries with all time queries that have no
  /// date filter (getTotalListeningMs, getHourlyDistribution,
  /// getTopSongIds, getMostPlayedSongs), so deleting rows by age would remove
  /// numbers that are still shown to the user. This runs only when the user
  /// explicitly confirmed it, through pruneListeningEntries.
  ///
  /// Three passes: corrupt timestamps first, then rows older than [keepDays],
  /// then, when the table is still bigger than [keepMaxRows], the oldest rows
  /// until the row count fits. Returns the total number of deleted rows.
  static Future<int> _pruneListeningEntriesOn(
    Database database, {
    int keepDays = 365,
    int keepMaxRows = 200000,
  }) async {
    var deleted = 0;

    // Pass 1: corrupt rows on their own. A NULL or empty timestamp cannot be
    // ordered or age compared, so it would otherwise survive and still take
    // up part of the row budget below.
    deleted += await database.delete(
      'listening_entries',
      where: 'timestamp IS NULL OR TRIM(timestamp) = ?',
      whereArgs: [''],
    );

    // Pass 2: age. The comparison goes through julianday() and never through
    // a raw string compare, because backup_service stores the timestamp string
    // exactly as it appears in the backup: short forms (2024-01-02) or
    // timezone offsets (...+07:00) sit in the table next to full local
    // ISO8601 strings, and a lexicographic compare would drop the wrong rows.
    // julianday() is not indexable, so this pass scans the table; that is why
    // it must stay off the startup path.
    final safeDays = keepDays < 0 ? 0 : keepDays;
    final cutoff = DateTime.now().subtract(Duration(days: safeDays));
    deleted += await database.rawDelete(
      'DELETE FROM listening_entries WHERE julianday(timestamp) < julianday(?)',
      [cutoff.toIso8601String()],
    );

    // Pass 3: row cap, in chunks so no single statement has to materialize
    // hundreds of thousands of ids at once. ORDER BY timestamp ASC, id ASC
    // keeps the selection deterministic across chunks, and the yield between
    // chunks stops one long run from holding the write lock throughout.
    final safeMaxRows = keepMaxRows < 1 ? 1 : keepMaxRows;
    const chunkSize = 20000;
    final total = Sqflite.firstIntValue(await database
            .rawQuery('SELECT COUNT(*) FROM listening_entries')) ??
        0;
    var overflow = total - safeMaxRows;
    while (overflow > 0) {
      final chunk = overflow < chunkSize ? overflow : chunkSize;
      deleted += await database.rawDelete(
        'DELETE FROM listening_entries WHERE id IN ('
        'SELECT id FROM listening_entries ORDER BY timestamp ASC, id ASC LIMIT ?)',
        [chunk],
      );
      overflow -= chunk;
      if (overflow > 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return deleted;
  }

  /// Public entry point: prune [listening_entries] to [keepDays] of history
  /// and at most [keepMaxRows] rows. Returns the number of deleted rows.
  ///
  /// Never called on startup or during a migration: several dashboard queries
  /// read listening_entries without a date filter, so rows deleted here change
  /// totals the user can still see. Only call this from UI code, after the
  /// user explicitly confirmed the deletion.
  Future<int> pruneListeningEntries({
    int keepDays = 365,
    int keepMaxRows = 200000,
  }) async {
    final database = await db;
    final deleted = await _pruneListeningEntriesOn(
      database,
      keepDays: keepDays,
      keepMaxRows: keepMaxRows,
    );
    // The dashboard caches its summary numbers for 10 minutes and they come
    // from this table, so the cache must go or the summary would contradict
    // the fresh detail lists on the same screen.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_dashboardCacheKey);
    } catch (_) {
      // Best effort: the numbers self heal on the next full reload.
    }
    return deleted;
  }

  /// Prefs key of the dashboard aggregate cache. Owned here because a history
  /// prune changes those numbers from outside the dashboard screen.
  static const String _dashboardCacheKey = 'dashboard_aggregate_cache_v1';

  // ---------- Songs ----------
  Future<void> upsertSong(Song s) async {
    final database = await db;
    // Rescans must never wipe enrich results or manual edits. When the row
    // already exists, only file facts are refreshed (filePath and
    // durationMs). Title, artist, album, genre, region, art, lyrics,
    // favorite, lastPlayed, addedAt, and scanned flags stay as stored.
    // Tradeoff: changed tags inside the audio file itself are not adopted
    // automatically on rescan. Users pick them up via manual edit or a
    // deliberate metadata refresh, which keeps the 30 minute scan from
    // deleting enriched data.
    final existing = await database.query('songs', columns: ['id'], where: 'id = ?', whereArgs: [s.id], limit: 1);
    if (existing.isNotEmpty) {
      await database.update(
        'songs',
        {'filePath': s.filePath, 'durationMs': s.durationMs},
        where: 'id = ?',
        whereArgs: [s.id],
      );
      return;
    }
    final map = s.toMap();
    map['addedAt'] = DateTime.now().toIso8601String();
    await database.insert('songs', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Song>> getAllSongs() async {
    final database = await db;
    final rows = await database.query('songs', orderBy: 'title ASC');
    return rows.map((r) => Song.fromMap(r)).toList();
  }

  /// Delete from the DB the songs whose original files no longer exist on the
  /// phone (deleted/moved by the user outside the app). [existingIds] holds
  /// ALL ids that are still truly detected on the device (including ones in
  /// hidden folders - so songs in hidden folders are NOT deleted).
  /// Song count in the DB - used by the safety guard in scanAndSync()
  /// to detect when querySongs() returns a suspicious result.
  Future<int> getSongCount() async {
    final database = await db;
    final result = await database.rawQuery('SELECT COUNT(*) as count FROM songs');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> deleteSongsMissingFromDevice(
    Set<int> existingIds, {
    /// Ids that were already stored when the scan started. Passing them keeps
    /// the delete from touching rows another scan inserted meanwhile.
    Set<int>? knownDbIds,
  }) async {
    final database = await db;
    // Use the caller snapshot when provided. A live read of the songs table
    // would also see rows written by a scan running in parallel, and those
    // rows would look like files that disappeared.
    final allDbIds = knownDbIds ??
        (await database.query('songs', columns: ['id']))
            .map((r) => (r['id'] as num?)?.toInt())
            .whereType<int>()
            .toSet();
    final ghostIds = allDbIds.difference(existingIds);
    if (ghostIds.isEmpty) return 0;

    final batch = database.batch();
    for (final id in ghostIds) {
      batch.delete('songs', where: 'id = ?', whereArgs: [id]);
      batch.delete('playlist_songs', where: 'songId = ?', whereArgs: [id]);
      batch.delete('listening_entries', where: 'songId = ?', whereArgs: [id]);
      batch.delete('synced_lyrics', where: 'songId = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    return ghostIds.length;
  }

  /// IDs of songs whose metadata was already scanned (so the app does not
  /// re-fetch from the internet for the same song over and over).
  Future<Set<int>> getScannedSongIds() async {
    final database = await db;
    final rows = await database.query('songs', where: 'metadataScanned = 1', columns: ['id']);
    return rows
        .map((r) => (r['id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();
  }

  /// Songs ordered by the time they were actually added to the library,
  /// not just by reversing the current list order.
  Future<List<Song>> getAllSongsByDateAdded() async {
    final database = await db;
    final rows = await database.query('songs', orderBy: 'addedAt DESC');
    return rows.map((r) => Song.fromMap(r)).toList();
  }

  Future<void> deleteSong(int id) async {
    final database = await db;
    await database.delete('songs', where: 'id = ?', whereArgs: [id]);
    await database
        .delete('playlist_songs', where: 'songId = ?', whereArgs: [id]);
    await database
        .delete('listening_entries', where: 'songId = ?', whereArgs: [id]);
    await database
        .delete('synced_lyrics', where: 'songId = ?', whereArgs: [id]);
  }

  Future<void> updateSongMetadata(Song s) async {
    final database = await db;
    // Read isFavorite from the DB first so it is not reset by a stale Song object.
    // Same protection as in upsertSong() - the user may have favorited the song
    // in another tab while the Edit Metadata screen was still open.
    final existing = await database.query('songs', columns: ['isFavorite'], where: 'id = ?', whereArgs: [s.id], limit: 1);
    final map = s.toMap();
    if (existing.isNotEmpty) {
      map['isFavorite'] = existing.first['isFavorite'];
    }
    await database.update('songs', map, where: 'id = ?', whereArgs: [s.id]);
  }

  /// Update the metadata of many songs in one transaction.
  ///
  /// The single row path reads isFavorite per row and the caller reloads the
  /// whole library per row, so a 500 song bulk edit ran 500 full table reads.
  /// Here the favorite flags are read once for the whole batch and every
  /// update commits together.
  Future<void> updateSongMetadataBulk(List<Song> songs) async {
    if (songs.isEmpty) return;
    final database = await db;
    final ids = songs.map((s) => s.id).toSet().toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final favoriteRows = await database.rawQuery(
      'SELECT id, isFavorite FROM songs WHERE id IN ($placeholders)',
      ids,
    );
    final favorites = {
      for (final row in favoriteRows) row['id'] as int: row['isFavorite'],
    };
    final batch = database.batch();
    for (final s in songs) {
      final map = s.toMap();
      if (favorites.containsKey(s.id)) map['isFavorite'] = favorites[s.id];
      batch.update('songs', map, where: 'id = ?', whereArgs: [s.id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> setFavorite(int songId, bool value) async {
    final database = await db;
    await database.update('songs', {'isFavorite': value ? 1 : 0},
        where: 'id = ?', whereArgs: [songId]);
  }

  /// Set favorites for many songs at once in a single batch + single commit.
  Future<void> setFavoritesBulk(List<int> songIds, bool value) async {
    if (songIds.isEmpty) return;
    try {
      final database = await db;
      final batch = database.batch();
      for (final id in songIds) {
        batch.update('songs', {'isFavorite': value ? 1 : 0},
            where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      throw StateError('${lookupAppLocalizations(LanguageProvider.instance.locale).coreUpdateFavoritesFailed} ${songIds.length} ${lookupAppLocalizations(LanguageProvider.instance.locale).coreSongs}: $e');
    }
  }

  Future<List<Song>> getFavorites() async {
    final database = await db;
    final rows =
        await database.query('songs', where: 'isFavorite = 1', orderBy: 'title ASC');
    return rows.map((r) => Song.fromMap(r)).toList();
  }

  Future<void> markPlayed(int songId) async {
    final database = await db;
    await database.update(
        'songs', {'lastPlayedAt': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [songId]);
  }

  Future<List<Song>> getRecentlyPlayed({int limit = 50}) async {
    final database = await db;
    final rows = await database.query('songs',
        where: 'lastPlayedAt IS NOT NULL',
        orderBy: 'lastPlayedAt DESC',
        limit: limit);
    return rows.map((r) => Song.fromMap(r)).toList();
  }

  // ---------- Listening history (for the dashboard) ----------
  Future<void> addListeningEntry(ListeningEntry e) async {
    final database = await db;
    await database.insert('listening_entries', e.toMap());
  }

  /// Last heard moment per song, newest first, capped at [limit] songs.
  ///
  /// Smart shuffle needs the last play time of every song for its staleness
  /// weight. That used to live only in memory in PlayerService, so a restart
  /// left every song with a null stamp, every song scored 1.0 staleness, and
  /// 40 percent of the weight became a no-op. Reading it back here keeps the
  /// feature working on the very first shuffle after a launch.
  ///
  /// Details that matter for restored backups:
  /// - ordering goes through julianday(), never a string compare, because the
  ///   table can hold short forms (2024-01-02) and timezone offsets
  ///   (...+07:00) next to full local ISO8601 strings. This is the same
  ///   reasoning as the age pass of pruneListeningEntries.
  /// - the value is converted from the Julian day number in Dart with a
  ///   tryParse style guard on the numeric result, so a corrupt row is skipped
  ///   instead of failing the whole load.
  ///
  /// [limit] defaults to 500 to match the cap used for the play counts in
  /// PlayerService.refreshSmartShuffleStats: on a large library both maps are
  /// built from the same 500 songs, so the weighting stays consistent.
  Future<Map<int, DateTime>> getLastPlayedStamps({int limit = 500}) async {
    final safeLimit = limit < 1 ? 500 : limit;
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT songId, MAX(julianday(timestamp)) AS latest
      FROM listening_entries
      WHERE songId IS NOT NULL AND julianday(timestamp) IS NOT NULL
      GROUP BY songId
      ORDER BY latest DESC
      LIMIT ?
    ''', [safeLimit]);

    // 2440587.5 is the Julian day number of 1970-01-01T00:00:00Z, the Unix
    // epoch, so this is the standard day number to millisecond conversion.
    const epochJulianDay = 2440587.5;
    const msPerDay = 86400000.0;

    final result = <int, DateTime>{};
    for (final r in rows) {
      final songId = (r['songId'] as num?)?.toInt();
      if (songId == null) continue;
      final latest = (r['latest'] as num?)?.toDouble();
      if (latest == null) continue;
      if (latest.isNaN || latest.isInfinite) continue;
      final stamp = DateTime.fromMillisecondsSinceEpoch(
        ((latest - epochJulianDay) * msPerDay).round(),
        isUtc: true,
      ).toLocal();
      if (stamp.millisecondsSinceEpoch <= 0) continue;
      result[songId] = stamp;
    }
    return result;
  }

  /// Total ms listened per day for the last 7 days (for the dashboard chart)
  Future<Map<DateTime, int>> getDailyListeningLast7Days() async {
    final database = await db;
    final since = DateTime.now().subtract(const Duration(days: 6));
    final sinceStr =
        DateTime(since.year, since.month, since.day).toIso8601String();
    // julianday() instead of a string compare: a restored backup can hold short
    // forms (2024-01-02) or timezone offsets (...+07:00) next to full local
    // ISO8601 strings, and those do not sort correctly as plain text. This is
    // the same comparison pruneListeningEntries uses, see pass 2 there.
    // The cost is that idx_listening_ts cannot serve this range scan; the
    // window is seven days, so the scan stays small. The schema is unchanged.
    final rows = await database.rawQuery(
      'SELECT timestamp, listenedMs FROM listening_entries '
      'WHERE julianday(timestamp) >= julianday(?)',
      [sinceStr],
    );

    final Map<DateTime, int> result = {};
    for (int i = 0; i < 7; i++) {
      final d = DateTime.now().subtract(Duration(days: 6 - i));
      result[DateTime(d.year, d.month, d.day)] = 0;
    }
    for (final r in rows) {
      // Skip corrupt rows instead of throwing, so one bad timestamp
      // never breaks the whole dashboard chart.
      final rawTs = r['timestamp'];
      if (rawTs is! String) continue;
      final ts = DateTime.tryParse(rawTs);
      if (ts == null) continue;
      final key = DateTime(ts.year, ts.month, ts.day);
      if (result.containsKey(key)) {
        result[key] = (result[key] ?? 0) + ((r['listenedMs'] as num?)?.toInt() ?? 0);
      }
    }
    return result;
  }

  /// Top songs by listening_entries count
  Future<List<MapEntry<int, int>>> getTopSongIds({int limit = 10}) async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT songId, COUNT(*) as playCount
      FROM listening_entries
      GROUP BY songId
      ORDER BY playCount DESC
      LIMIT ?
    ''', [limit]);
    return rows
        .map((r) => MapEntry(
            (r['songId'] as num?)?.toInt() ?? 0,
            (r['playCount'] as num?)?.toInt() ?? 0,
          ))
        .toList();
  }

  /// Top artists by total listening_entries joined against the songs table
  Future<List<MapEntry<String, int>>> getTopArtists({int limit = 10}) async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT s.artist as artist, COUNT(*) as playCount
      FROM listening_entries le
      JOIN songs s ON s.id = le.songId
      GROUP BY s.artist
      ORDER BY playCount DESC
      LIMIT ?
    ''', [limit]);
    return rows
        .map((r) => MapEntry(
            (r['artist'] as String?) ?? 'Unknown Artist',
            (r['playCount'] as num?)?.toInt() ?? 0,
          ))
        .toList();
  }

  /// Genre distribution (song count per genre)
  Future<Map<String, int>> getGenreDistribution() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT COALESCE(genre, 'Tidak diketahui') as genre, COUNT(*) as cnt
      FROM songs GROUP BY genre ORDER BY cnt DESC
    ''');
    return {
      for (final r in rows)
        if (r['genre'] is String)
          r['genre'] as String: (r['cnt'] as num?)?.toInt() ?? 0,
    };
  }

  /// Song origin-region distribution
  Future<Map<String, int>> getRegionDistribution() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT COALESCE(region, 'Tidak diketahui') as region, COUNT(*) as cnt
      FROM songs GROUP BY region ORDER BY cnt DESC
    ''');
    return {
      for (final r in rows)
        if (r['region'] is String)
          r['region'] as String: (r['cnt'] as num?)?.toInt() ?? 0,
    };
  }

  /// Total listening time (ms) per hour of day (0-23).
  /// No schema change: groups listening_entries by strftime hour.
  /// Missing hours are returned as 0.
  Future<Map<int, int>> getHourlyDistribution() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT CAST(strftime('%H', timestamp) AS INTEGER) as hour,
             COALESCE(SUM(listenedMs), 0) as total
      FROM listening_entries
      GROUP BY hour
    ''');
    final result = <int, int>{for (int h = 0; h < 24; h++) h: 0};
    for (final r in rows) {
      final hour = (r['hour'] as num?)?.toInt();
      if (hour == null || hour < 0 || hour > 23) continue;
      result[hour] = (r['total'] as num?)?.toInt() ?? 0;
    }
    return result;
  }

  // ---------- Playlists ----------
  Future<int> createPlaylist(String name) async {
    final database = await db;
    return database.insert('playlists', {
      'name': name,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPlaylists() async {
    final database = await db;
    return database.query('playlists', orderBy: 'createdAt DESC');
  }

  Future<void> deletePlaylist(int id) async {
    final database = await db;
    await database.delete('playlists', where: 'id = ?', whereArgs: [id]);
    await database
        .delete('playlist_songs', where: 'playlistId = ?', whereArgs: [id]);
  }

  // ---------- Playlist folders ----------
  // Optional label stored per playlist. Empty string means ungrouped.

  /// Move one playlist into [folder]. Pass '' to remove it from any folder.
  ///
  /// Errors are deliberately not swallowed: the folder move is a user action,
  /// so a failure has to surface as an error in the caller instead of looking
  /// like the move silently worked. The signature is unchanged.
  Future<void> setPlaylistFolder(int playlistId, String folder) async {
    final database = await db;
    await database.update(
      'playlists',
      {'folder': folder.trim()},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  /// Distinct non-empty folder names, sorted A to Z.
  Future<List<String>> getPlaylistFolders() async {
    try {
      final database = await db;
      final rows = await database.rawQuery(
        "SELECT DISTINCT folder FROM playlists "
        "WHERE folder IS NOT NULL AND TRIM(folder) != '' "
        "ORDER BY folder COLLATE NOCASE ASC",
      );
      return rows
          .map((r) => ((r['folder'] as String?) ?? '').trim())
          .where((f) => f.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// All playlists stored in [folder], newest first like [getPlaylists].
  Future<List<Map<String, dynamic>>> getPlaylistsInFolder(String folder) async {
    try {
      final database = await db;
      return await database.query(
        'playlists',
        where: 'folder = ?',
        whereArgs: [folder.trim()],
        orderBy: 'createdAt DESC',
      );
    } catch (_) {
      return [];
    }
  }

  /// Rename [oldName] to [newName] for every playlist in that folder.
  /// Pass '' as [newName] to ungroup all playlists in the folder.
  Future<void> renamePlaylistFolder(String oldName, String newName) async {
    try {
      final oldTrimmed = oldName.trim();
      if (oldTrimmed.isEmpty) return;
      final database = await db;
      await database.update(
        'playlists',
        {'folder': newName.trim()},
        where: 'folder = ?',
        whereArgs: [oldTrimmed],
      );
    } catch (_) {
      // Best effort only, folders still render with the old name.
    }
  }

  /// Write the enriched fields of an existing song to the DB.
  ///
  /// [upsertSong] deliberately refuses to overwrite the rich columns of an
  /// existing row so a rescan cannot wipe them. That is correct for the
  /// scanner but wrong for a deliberate "fetch from the internet", which is
  /// exactly the case where the new values should win.
  Future<void> applyEnrichedMetadata(Song s) async {
    final database = await db;
    await database.update(
      'songs',
      {
        'title': s.title,
        'artist': s.artist,
        'album': s.album,
        'genre': s.genre,
        'region': s.region,
        'albumArtPath': s.albumArtPath,
        'albumArtUrl': s.albumArtUrl,
        'lyrics': encodeLyricsForDb(s.lyrics),
        'metadataScanned': s.metadataScanned ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [s.id],
    );
  }

  /// Add many songs to a playlist in one transaction.
  ///
  /// [addSongToPlaylist] needs a MAX(position) query per song, and the
  /// provider used to re-read the whole playlist per song to detect a
  /// duplicate. Doing that per row made a playlist merge or a bulk add
  /// quadratic: n songs meant n full playlist reads. Here the existing ids
  /// are read once, the new rows are inserted with one batch inside a single
  /// transaction, and the positions are assigned from one starting value.
  ///
  /// Returns how many rows were actually inserted, so the caller can report
  /// the real result instead of the requested count.
  Future<int> addSongsToPlaylist(int playlistId, List<int> songIds) async {
    if (songIds.isEmpty) return 0;
    final database = await db;
    // Preserve the order of the incoming list and drop repeated ids so the
    // same song cannot be inserted twice by one call.
    final unique = <int>[];
    final seen = <int>{};
    for (final id in songIds) {
      if (seen.add(id)) unique.add(id);
    }
    if (unique.isEmpty) return 0;

    return database.transaction<int>((txn) async {
      final existingRows = await txn.rawQuery(
        'SELECT songId FROM playlist_songs WHERE playlistId = ?',
        [playlistId],
      );
      final existing = existingRows
          .map((r) => r['songId'])
          .whereType<int>()
          .toSet();
      final toInsert = unique.where((id) => !existing.contains(id)).toList();
      if (toInsert.isEmpty) return 0;

      final maxPos = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT MAX(position) as m FROM playlist_songs WHERE playlistId = ?',
        [playlistId],
      ));
      var nextPos = (maxPos ?? 0) + 1;
      final now = DateTime.now().toIso8601String();
      final batch = txn.batch();
      for (final id in toInsert) {
        batch.insert('playlist_songs', {
          'playlistId': playlistId,
          'songId': id,
          'addedAt': now,
          'position': nextPos++,
        });
      }
      await batch.commit(noResult: true);
      return toInsert.length;
    });
  }

  Future<void> addSongToPlaylist(int playlistId, int songId) async {
    final database = await db;
    final maxPos = Sqflite.firstIntValue(await database.rawQuery(
        'SELECT MAX(position) as m FROM playlist_songs WHERE playlistId = ?', [playlistId])) ?? 0;
    await database.insert(
      'playlist_songs',
      {
        'playlistId': playlistId,
        'songId': songId,
        'addedAt': DateTime.now().toIso8601String(),
        'position': maxPos + 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    final database = await db;
    await database.delete('playlist_songs',
        where: 'playlistId = ? AND songId = ?', whereArgs: [playlistId, songId]);
  }

  Future<List<Song>> getSongsInPlaylist(int playlistId) async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT s.* FROM songs s
      JOIN playlist_songs ps ON ps.songId = s.id
      WHERE ps.playlistId = ?
      ORDER BY ps.position ASC, ps.addedAt ASC
    ''', [playlistId]);
    return rows.map((r) => Song.fromMap(r)).toList();
  }

  /// Re-save the song order inside a playlist (called after a drag reorder)
  Future<void> reorderPlaylistSongs(int playlistId, List<int> songIdsInOrder) async {
    final database = await db;
    final batch = database.batch();
    for (int i = 0; i < songIdsInOrder.length; i++) {
      batch.update(
        'playlist_songs',
        {'position': i},
        where: 'playlistId = ? AND songId = ?',
        whereArgs: [playlistId, songIdsInOrder[i]],
      );
    }
    await batch.commit(noResult: true);
  }

  // ---------- Folders ----------
  Future<void> setFolderIncluded(String path, bool included) async {
    final database = await db;
    await database.insert(
      'folders',
      {'path': path, 'includeInLibrary': included ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Set<String>> getExcludedFolders() async {
    final database = await db;
    final rows = await database.query('folders', where: 'includeInLibrary = 0');
    return rows.map((r) => r['path'] as String).toSet();
  }

  /// Songs ordered by play count (most played first).
  /// A single JOIN query - no longer loads the whole songs table into memory.
  Future<List<Song>> getMostPlayedSongs({int limit = 50}) async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT s.*, COUNT(le.id) as playCount
      FROM songs s
      JOIN listening_entries le ON le.songId = s.id
      GROUP BY s.id
      ORDER BY playCount DESC
      LIMIT ?
    ''', [limit]);
    return rows.map((r) => Song.fromMap(r)).toList();
  }

  /// Songs that were never played at all
  Future<List<Song>> getNeverPlayedSongs() async {
    final database = await db;
    final rows = await database.query(
      'songs',
      where: 'lastPlayedAt IS NULL',
      orderBy: 'title ASC',
    );
    return rows.map((r) => Song.fromMap(r)).toList();
  }

  /// Total all-time listening time (ms)
  Future<int> getTotalListeningMs() async {
    final database = await db;
    final result = await database.rawQuery(
        'SELECT COALESCE(SUM(listenedMs), 0) as total FROM listening_entries');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Total listening time this month (ms)
  Future<int> getThisMonthListeningMs() async {
    final database = await db;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1).toIso8601String();
    final result = await database.rawQuery(
        'SELECT COALESCE(SUM(listenedMs), 0) as total FROM listening_entries '
        'WHERE julianday(timestamp) >= julianday(?)',
        [start]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Top songs listened to at or after [isoStart].
  /// Same shape as [getTopSongIds], no schema change.
  /// The date filter compares with julianday(), never as text, for the same
  /// reason getDailyListeningLast7Days does.
  Future<List<MapEntry<int, int>>> getTopSongIdsSince(String isoStart,
      {int limit = 10}) async {
    final database = await db;
    final safeLimit = limit < 1 ? 10 : limit;
    final rows = await database.rawQuery('''
      SELECT songId, COUNT(*) as playCount
      FROM listening_entries
      WHERE julianday(timestamp) >= julianday(?)
      GROUP BY songId
      ORDER BY playCount DESC
      LIMIT ?
    ''', [isoStart, safeLimit]);
    return rows
        .map((r) => MapEntry((r['songId'] as num).toInt(),
            (r['playCount'] as num).toInt()))
        .toList();
  }

  /// Top artists listened to at or after [isoStart].
  /// Same shape as [getTopArtists], no schema change.
  /// The date filter compares with julianday(), never as text.
  Future<List<MapEntry<String, int>>> getTopArtistsSince(String isoStart,
      {int limit = 10}) async {
    final database = await db;
    final safeLimit = limit < 1 ? 10 : limit;
    final rows = await database.rawQuery('''
      SELECT s.artist as artist, COUNT(*) as playCount
      FROM listening_entries le
      JOIN songs s ON s.id = le.songId
      WHERE julianday(le.timestamp) >= julianday(?)
      GROUP BY s.artist
      ORDER BY playCount DESC
      LIMIT ?
    ''', [isoStart, safeLimit]);
    return rows
        .map((r) => MapEntry(
            (r['artist'] as String?) ?? 'Unknown Artist',
            (r['playCount'] as num).toInt()))
        .toList();
  }

  /// Total listening time (ms) from [isoStart] onwards.
  /// Same shape as [getTotalListeningMs], no schema change.
  /// The date filter compares with julianday(), never as text.
  Future<int> getListeningMsSince(String isoStart) async {
    final database = await db;
    final result = await database.rawQuery(
        'SELECT COALESCE(SUM(listenedMs), 0) as total FROM listening_entries '
        'WHERE julianday(timestamp) >= julianday(?)',
        [isoStart]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Escape the LIKE wildcards in a user supplied search string.
  String _escapeLike(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  /// Hoisted so the whitespace pattern is compiled once instead of once per
  /// query. Every song list read goes through the sanitizer.
  static final RegExp _orderByWsReg = RegExp(r'\s+');

  /// Map a caller supplied order key to a safe ORDER BY fragment.
  /// Unknown values are ignored and fall back to title ASC.
  String _sanitizeSongsOrderBy(String? orderBy) {
    final normalized =
        (orderBy ?? '').trim().replaceAll(_orderByWsReg, ' ').toUpperCase();
    switch (normalized) {
      case 'TITLE ASC':
        return 'title COLLATE NOCASE ASC';
      case 'TITLE DESC':
        return 'title COLLATE NOCASE DESC';
      case 'ARTIST ASC':
        return 'artist COLLATE NOCASE ASC';
      case 'ARTIST DESC':
        return 'artist COLLATE NOCASE DESC';
      case 'ALBUM ASC':
        return 'album COLLATE NOCASE ASC';
      case 'ALBUM DESC':
        return 'album COLLATE NOCASE DESC';
      case 'ADDEDAT DESC':
      case 'ADDED_AT DESC':
        return 'addedAt DESC';
      case 'ADDEDAT ASC':
      case 'ADDED_AT ASC':
        // Keep NULL addedAt last, same as the in memory sort.
        return 'CASE WHEN addedAt IS NULL THEN 1 ELSE 0 END, addedAt ASC';
      case 'GENRE ASC':
        return 'genre COLLATE NOCASE ASC';
      case 'GENRE DESC':
        return 'genre COLLATE NOCASE DESC';
      default:
        return 'title COLLATE NOCASE ASC';
    }
  }

  /// Paged song query with search, sort, and excluded folder filtering.
  /// No schema change. [orderBy] is strictly whitelisted, unknown values
  /// fall back to title ASC. Each excluded folder becomes a
  /// filePath NOT LIKE 'prefix/%' clause so the whole subtree is skipped.
  Future<List<Song>> querySongsPage({
    required int limit,
    required int offset,
    String? query,
    String? orderBy,
    Set<String>? excludedFolders,
  }) async {
    final database = await db;
    final safeLimit = limit < 1 ? 50 : limit;
    final safeOffset = offset < 0 ? 0 : offset;
    final where = <String>[];
    final args = <Object?>[];
    final trimmed = (query ?? '').trim();
    if (trimmed.isNotEmpty) {
      final pattern = '%${_escapeLike(trimmed)}%';
      where.add(
          "(title LIKE ? ESCAPE '\\' OR artist LIKE ? ESCAPE '\\' OR album LIKE ? ESCAPE '\\')");
      args.addAll([pattern, pattern, pattern]);
    }
    final excluded = (excludedFolders ?? const <String>{})
        .map((e) => e.replaceAll('\\', '/'))
        .map((e) => e.endsWith('/') ? e.substring(0, e.length - 1) : e)
        .where((e) => e.isNotEmpty)
        .toList();
    for (final folder in excluded) {
      final pattern = '${_escapeLike(folder)}/%';
      where.add("filePath NOT LIKE ? ESCAPE '\\'");
      args.add(pattern);
    }
    final orderClause = _sanitizeSongsOrderBy(orderBy);
    final sql = StringBuffer('SELECT * FROM songs');
    if (where.isNotEmpty) {
      sql.write(' WHERE ');
      sql.write(where.join(' AND '));
    }
    sql.write(' ORDER BY $orderClause LIMIT ? OFFSET ?');
    args.addAll([safeLimit, safeOffset]);
    final rows = await database.rawQuery(sql.toString(), args);
    return rows.map((r) => Song.fromMap(r)).toList();
  }

  /// Consecutive days with at least one listening entry, ending today
  /// or yesterday. Returns 0 when there is no recent activity.
  /// No schema change: reads distinct calendar days from listening_entries.
  Future<int> getListeningStreak() async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT DISTINCT substr(timestamp, 1, 10) as day '
      'FROM listening_entries ORDER BY day DESC',
    );
    if (rows.isEmpty) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // The streak stays alive when the latest entry is from today or yesterday.
    // Corrupt day strings are skipped so one bad row never breaks the streak.
    DateTime? latest;
    for (final r in rows) {
      final raw = r['day']?.toString() ?? '';
      if (raw.isEmpty) continue;
      latest = DateTime.tryParse('${raw}T00:00:00');
      if (latest != null) break;
    }
    if (latest == null) return 0;
    // Calendar day difference, NOT 24-hour difference. subtract(Duration(days:1))
    // can land at 23:00 on DST transition nights and break the streak one day
    // early.
    final latestDay = DateTime(latest.year, latest.month, latest.day);
    final gap = today.difference(latestDay).inDays;
    if (gap > 1) return 0;
    var cursor = gap == 1
        ? DateTime(today.year, today.month, today.day - 1)
        : today;
    var streak = 0;
    for (final r in rows) {
      final raw = r['day']?.toString() ?? '';
      if (raw.isEmpty) continue;
      final day = DateTime.tryParse('${raw}T00:00:00');
      if (day == null) continue;
      final dayOnly = DateTime(day.year, day.month, day.day);
      if (dayOnly == cursor) {
        streak++;
        cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
      } else if (dayOnly.isBefore(cursor)) {
        break;
      }
    }
    return streak;
  }

  /// Most played genre this month, or null when there is no history yet.
  /// No schema change: joins listening_entries against songs.
  /// The date filter compares with julianday(), never as text.
  Future<String?> getTopGenreThisMonth() async {
    final database = await db;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1).toIso8601String();
    final rows = await database.rawQuery('''
      SELECT s.genre as genre, COUNT(*) as cnt
      FROM listening_entries le
      JOIN songs s ON s.id = le.songId
      WHERE julianday(le.timestamp) >= julianday(?) AND s.genre IS NOT NULL AND s.genre != ''
      GROUP BY s.genre
      ORDER BY cnt DESC
      LIMIT 1
    ''', [start]);
    if (rows.isEmpty) return null;
    return rows.first['genre'] as String?;
  }

  // ---------- iTunes metadata disk cache ----------
  /// Raw cached iTunes response for [query], or null when absent.
  /// The returned map holds 'response' and 'fetchedAt' strings.
  /// TTL checks are done by the caller so hit and miss markers can
  /// use different lifetimes.
  Future<Map<String, String>?> getMetadataCache(String query) async {
    final database = await db;
    final rows = await database.query('metadata_cache',
        columns: ['response', 'fetchedAt'],
        where: 'query = ?',
        whereArgs: [query],
        limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'response': (row['response'] ?? '').toString(),
      'fetchedAt': (row['fetchedAt'] ?? '').toString(),
    };
  }

  /// Insert or replace the cached iTunes response for [query].
  Future<void> putMetadataCache(String query, String response) async {
    final database = await db;
    await database.insert(
      'metadata_cache',
      {
        'query': query,
        'response': response,
        'fetchedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Delete stale iTunes metadata cache rows older than [maxAgeDays].
  /// Only the metadata_cache table is pruned. Listening history in
  /// listening_entries is product data and is never deleted here.
  /// Returns the number of cache rows removed.
  Future<int> pruneMetadataCache({int maxAgeDays = 90}) async {
    final database = await db;
    final cutoff = DateTime.now()
        .subtract(Duration(days: maxAgeDays))
        .toIso8601String();
    return database.delete(
      'metadata_cache',
      where: 'fetchedAt < ?',
      whereArgs: [cutoff],
    );
  }

  // ---------- Synced (LRC) lyrics ----------
  /// Raw synced lyrics (LRC text) stored for [songId], or null when absent.
  Future<String?> getSyncedLyrics(int songId) async {
    final database = await db;
    final rows = await database.query('synced_lyrics',
        columns: ['lrc'],
        where: 'songId = ?',
        whereArgs: [songId],
        limit: 1);
    if (rows.isEmpty) return null;
    final lrc = rows.first['lrc'] as String?;
    if (lrc == null || lrc.isEmpty) return null;
    return lrc;
  }

  /// Insert or replace the synced lyrics (LRC text) for [songId].
  Future<void> setSyncedLyrics(int songId, String lrc) async {
    final database = await db;
    await database.insert(
      'synced_lyrics',
      {
        'songId': songId,
        'lrc': lrc,
        'fetchedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

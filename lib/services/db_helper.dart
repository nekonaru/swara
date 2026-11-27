import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:swara/providers/language_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../utils/backup_paths.dart';
import '../utils/format.dart';

class DBHelper {
  // True when [table] already has [column]. Used by the migrations to
  // avoid relying on try/catch for idempotency: a swallowed ALTER inside
  // the migration transaction would commit a half-upgraded schema.
  static Future<bool> _hasColumn(
      DatabaseExecutor db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((r) =>
        (r['name'] as String?)?.toLowerCase() == column.toLowerCase());
  }

  DBHelper._();
  static final DBHelper instance = DBHelper._();
  // Memoize the in-flight Future, not the completed Database. Cold-start
  // callers race here; without this they each run a full open and migration.
  Future<Database>? _dbFuture;

  Future<Database> get db {
    final pending = _dbFuture;
    if (pending != null) return pending;
    // A failed open must not poison every later call until restart.
    final created = _init().catchError((Object e) {
      _dbFuture = null;
      throw e;
    });
    return _dbFuture = created;
  }

  Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'music_app.db');
    return openDatabase(
      path,
      version: 18,
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
            metadataScanned INTEGER DEFAULT 0,
            rating INTEGER DEFAULT 0
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
            folder TEXT DEFAULT '',
            isAuto INTEGER DEFAULT 0,
            rule TEXT
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
            fetchedAt TEXT,
            offsetMs INTEGER DEFAULT 0
          )
        ''');
        // Persistent playhead bookmarks, created with the table so a fresh
        // install never has to wait for the v14 migration branch.
        await db.execute('''
          CREATE TABLE song_bookmarks(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            songId INTEGER,
            positionMs INTEGER,
            label TEXT DEFAULT '',
            createdAt TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_bookmarks_song ON song_bookmarks(songId)');
        // Old paths kept after a real file rename, so backups exported before
        // the rename can still remap the song on import.
        await db.execute('''
          CREATE TABLE song_path_aliases(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            songId INTEGER,
            path TEXT,
            basename TEXT,
            changedAt TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_path_aliases_song ON song_path_aliases(songId)');
        await db.execute('''
          CREATE TABLE song_labels(
            songId INTEGER PRIMARY KEY,
            label TEXT DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE trash_songs(
            songId INTEGER PRIMARY KEY,
            payload TEXT,
            deletedAt TEXT
          )
        ''');
        // Per-track and per-folder playback overrides. Separate tables keep
        // rescans from overwriting user settings on the songs table.
        await db.execute('''
          CREATE TABLE song_playback_settings(
            songId INTEGER PRIMARY KEY,
            gainDb REAL DEFAULT 0,
            skipStartMs INTEGER DEFAULT 0,
            skipEndMs INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE folder_playback_settings(
            folderPath TEXT PRIMARY KEY,
            gainDb REAL DEFAULT 0,
            skipStartMs INTEGER DEFAULT 0,
            skipEndMs INTEGER DEFAULT 0
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
          if (!await _hasColumn(db, 'playlist_songs', 'position')) {
            await db.execute('ALTER TABLE playlist_songs ADD COLUMN position INTEGER DEFAULT 0');
          }
        }
        if (oldVersion < 3) {
          // Add the addedAt column so the "Recently added" sort truly reflects
          // insert time instead of just reversing the current list order
          if (!await _hasColumn(db, 'songs', 'addedAt')) {
            await db.execute('ALTER TABLE songs ADD COLUMN addedAt TEXT');
          }
        }
        if (oldVersion < 4) {
          // Explicitly mark songs whose metadata was already scanned,
          // so the "scan only songs missing metadata" feature stays accurate.
          if (!await _hasColumn(db, 'songs', 'metadataScanned')) {
            await db.execute('ALTER TABLE songs ADD COLUMN metadataScanned INTEGER DEFAULT 0');
            // Never mark 'Unknown' as scanned - that is a fallback
            // value, not a real fetch result. Only genuine genre/lyrics count.
            // Empty strings count as unscanned too, so use NULLIF to treat
            // '' the same as NULL for both genre and lyrics.
            await db.execute(
                "UPDATE songs SET metadataScanned = 1 WHERE (NULLIF(genre, '') IS NOT NULL AND genre != 'Unknown') OR NULLIF(lyrics, '') IS NOT NULL");
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
          if (!await _hasColumn(db, 'playlists', 'folder')) {
            await db.execute(
                "ALTER TABLE playlists ADD COLUMN folder TEXT DEFAULT ''");
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
                AND (NULLIF(genre, '') IS NULL OR genre = 'Unknown')
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
        if (oldVersion < 10) {
          // v10 replaces the Indonesian placeholder 'Tidak diketahui' with the
          // language-neutral 'Unknown'. Rewrite stored values so charts and
          // grouping keep working for existing installs.
          try {
            await db.execute(
                "UPDATE songs SET genre = 'Unknown' WHERE genre = 'Tidak diketahui'");
            await db.execute(
                "UPDATE songs SET region = 'Unknown' WHERE region = 'Tidak diketahui'");
          } catch (e) {
            debugPrint('DBHelper: v10 Unknown migration failed: $e');
          }
        }
        if (oldVersion < 11) {
          // v11 localizes the region labels to English (English is the
          // source), matching what metadata_service stores from now on.
          const renames = <List<String>>[
            ['Amerika Serikat', 'United States'],
            ['Inggris', 'United Kingdom'],
            ['Korea Selatan', 'South Korea'],
            ['Jepang', 'Japan'],
            ['Kanada', 'Canada'],
          ];
          for (final pair in renames) {
            try {
              await db.execute('UPDATE songs SET region = ? WHERE region = ?',
                  [pair[1], pair[0]]);
            } catch (e) {
              debugPrint('DBHelper: v11 region rename failed for ${pair[0]}: $e');
            }
          }
        }
        if (oldVersion < 12) {
          // Mark the built-in automatic playlists with an explicit flag
          // instead of matching their hard-coded names. An explicit flag
          // survives a user renaming the playlist.
          if (!await _hasColumn(db, 'playlists', 'isAuto')) {
            await db.execute(
                'ALTER TABLE playlists ADD COLUMN isAuto INTEGER DEFAULT 0');
            await db.execute(
                "UPDATE playlists SET isAuto = 1 WHERE name IN ('Daily Mix', 'Unplayed')");
          }
        }
        if (oldVersion < 13) {
          for (final sql in <String>[
            '''CREATE TABLE IF NOT EXISTS song_playback_settings(
              songId INTEGER PRIMARY KEY,
              gainDb REAL DEFAULT 0,
              skipStartMs INTEGER DEFAULT 0,
              skipEndMs INTEGER DEFAULT 0
            )''',
            '''CREATE TABLE IF NOT EXISTS folder_playback_settings(
              folderPath TEXT PRIMARY KEY,
              gainDb REAL DEFAULT 0,
              skipStartMs INTEGER DEFAULT 0,
              skipEndMs INTEGER DEFAULT 0
            )''',
          ]) {
            try {
              await db.execute(sql);
            } catch (e) {
              debugPrint('DBHelper: v13 table migration failed: $e');
            }
          }
        }
        if (oldVersion < 14) {
          // Synced lyric timing correction and persistent song bookmarks.
          if (!await _hasColumn(db, 'synced_lyrics', 'offsetMs')) {
            try {
              await db.execute(
                  'ALTER TABLE synced_lyrics ADD COLUMN offsetMs INTEGER DEFAULT 0');
            } catch (e) {
              debugPrint('DBHelper: v14 offset column migration failed: $e');
            }
          }
          for (final sql in <String>[
            '''CREATE TABLE IF NOT EXISTS song_bookmarks(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              songId INTEGER,
              positionMs INTEGER,
              label TEXT DEFAULT '',
              createdAt TEXT
            )''',
            'CREATE INDEX IF NOT EXISTS idx_bookmarks_song ON song_bookmarks(songId)',
          ]) {
            try {
              await db.execute(sql);
            } catch (e) {
              debugPrint('DBHelper: v14 bookmark migration failed: $e');
            }
          }
        }
        if (oldVersion < 15) {
          for (final sql in <String>[
            '''CREATE TABLE IF NOT EXISTS song_path_aliases(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              songId INTEGER,
              path TEXT,
              basename TEXT,
              changedAt TEXT
            )''',
            'CREATE INDEX IF NOT EXISTS idx_path_aliases_song ON song_path_aliases(songId)',
          ]) {
            try {
              await db.execute(sql);
            } catch (e) {
              debugPrint('DBHelper: v15 path alias migration failed: $e');
            }
          }
        }
        if (oldVersion < 16) {
          if (!await _hasColumn(db, 'playlists', 'rule')) {
            try {
              await db.execute('ALTER TABLE playlists ADD COLUMN rule TEXT');
            } catch (e) {
              debugPrint('DBHelper: v16 rule column migration failed: $e');
            }
          }
          // Give the existing auto playlists real rules so they can be
          // edited and rebuilt by the generic smart playlist engine.
          const seedRules = <(String, String)>[
            (
              'Unplayed',
              '{"schema":1,"match":"all","criteria":[{"field":"lastPlayed","op":"isNull","value":null}],"order":"title_asc","limit":null,"salt":0}',
            ),
            (
              'Forgotten Favorites',
              '{"schema":1,"match":"all","criteria":[{"field":"favorite","op":"isTrue","value":null},{"field":"lastPlayed","op":"beforeDays","value":90}],"order":"lastPlayed_asc","limit":null,"salt":0}',
            ),
            (
              'Daily Mix',
              '{"schema":1,"match":"all","criteria":[],"order":"random_daily","limit":25,"salt":0}',
            ),
          ];
          for (final (name, rule) in seedRules) {
            try {
              await db.execute(
                'UPDATE playlists SET rule = ?, isAuto = 1 '
                'WHERE name = ? AND rule IS NULL',
                [rule, name],
              );
            } catch (e) {
              debugPrint('DBHelper: v16 rule seed failed for $name: $e');
            }
          }
        }
        if (oldVersion < 18) {
          if (!await _hasColumn(db, 'songs', 'rating')) {
            try {
              await db.execute(
                  'ALTER TABLE songs ADD COLUMN rating INTEGER DEFAULT 0');
            } catch (e) {
              debugPrint('DBHelper: v18 rating migration failed: $e');
            }
          }
        }
        if (oldVersion < 17) {
          for (final sql in <String>[
            '''CREATE TABLE IF NOT EXISTS song_labels(
              songId INTEGER PRIMARY KEY,
              label TEXT DEFAULT ''
            )''',
            '''CREATE TABLE IF NOT EXISTS trash_songs(
              songId INTEGER PRIMARY KEY,
              payload TEXT,
              deletedAt TEXT
            )''',
          ]) {
            try {
              await db.execute(sql);
            } catch (e) {
              debugPrint('DBHelper: v17 migration failed: $e');
            }
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
    // Dashboard range queries compare julianday(timestamp); a plain timestamp
    // index cannot serve that expression and forces a full history scan.
    'idx_listening_julianday': 'CREATE INDEX IF NOT EXISTS '
        'idx_listening_julianday ON listening_entries(julianday(timestamp))',
    'idx_playlist_songs_pid_pos': 'CREATE INDEX IF NOT EXISTS '
        'idx_playlist_songs_pid_pos ON playlist_songs(playlistId, position)',
    // Partial indexes for the flag columns used by the favorites view and
    // the metadata-scan bookkeeping; tiny, only matching rows are indexed.
    'idx_songs_favorite': 'CREATE INDEX IF NOT EXISTS '
        'idx_songs_favorite ON songs(isFavorite) WHERE isFavorite = 1',
    'idx_songs_scanned': 'CREATE INDEX IF NOT EXISTS '
        'idx_songs_scanned ON songs(metadataScanned) WHERE metadataScanned = 1',
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
    // Every DB caller awaits onOpen. Issuing 11 CREATE INDEX statements on a
    // warm start is pure overhead, so skip the ones already in the schema.
    final existing = <String>{};
    try {
      final rows = await db.query('sqlite_master',
          columns: ['name'], where: "type = 'index'");
      existing.addAll(rows.map((r) => (r['name'] as String?) ?? ''));
    } catch (_) {
      // If the catalog read fails, fall through to the idempotent statements.
    }
    for (final entry in _indexStatements.entries) {
      if (existing.contains(entry.key)) continue;
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
    await invalidateDashboardCache();
    return deleted;
  }

  /// Prefs key of the dashboard aggregate cache. Owned here because a history
  /// prune changes those numbers from outside the dashboard screen.
  static const String _dashboardCacheKey = 'dashboard_aggregate_cache_v1';
  static const String dashboardCacheEpochKey = 'dashboard_cache_epoch_v1';

  /// Drop the dashboard summary cache when a new listening entry changes it.
  static Future<void> invalidateDashboardCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(dashboardCacheEpochKey,
          (prefs.getInt(dashboardCacheEpochKey) ?? 0) + 1);
      await prefs.remove(_dashboardCacheKey);
    } catch (_) {
      // Best effort: the numbers self heal on the next full reload.
    }
  }

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

  /// Lightweight song rows for screens that only need identity, folder and
  /// a count. Skips the lyrics column entirely, so no isolate round trip is
  /// paid to decompress lyrics that will never be displayed.
  Future<List<Song>> getSongSummaries() async {
    final database = await db;
    final rows = await database.query('songs',
        columns: ['id', 'filePath', 'title', 'artist', 'durationMs']);
    final out = <Song>[];
    for (final r in rows) {
      final id = (r['id'] as num?)?.toInt() ?? 0;
      final path = r['filePath'] is String ? r['filePath'] as String : '';
      if (id <= 0 || path.isEmpty) continue;
      out.add(Song(
        id: id,
        filePath: path,
        album: '',
        title: r['title'] is String ? r['title'] as String : '',
        artist: r['artist'] is String ? r['artist'] as String : '',
        durationMs: (r['durationMs'] as num?)?.toInt() ?? 0,
      ));
    }
    return out;
  }

  Future<List<Song>> getAllSongs() async {
    final database = await db;
    final rows = await database.query('songs', orderBy: 'title ASC');
    return await _songsFromRows(rows);
  }

  /// Distinct non-empty cover paths. Art cache maintenance only needs these
  /// paths, so it avoids reading and decompressing every song's lyrics.
  Future<List<String>> getAlbumArtPaths() async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT DISTINCT albumArtPath FROM songs '
      "WHERE albumArtPath IS NOT NULL AND albumArtPath != ''",
    );
    return rows
        .map((r) => r['albumArtPath']?.toString().trim() ?? '')
        .where((path) => path.isNotEmpty)
        .toList();
  }

  /// Convert raw DB rows into Songs, skipping any corrupt row instead of
  /// throwing. A single row with an empty or invalid filePath used to make
  /// the whole map() call throw a FormatException, which blanked the entire
  /// library even though every other song was fine.
  ///
  /// Decoding gzipped lyrics happens in a background isolate: decoding every
  /// row inline used to stall the UI thread for a full second or more on
  /// libraries with tens of thousands of lyrics. Rows without compressed
  /// lyrics are converted inline, no isolate is spawned for them.
  static Future<List<Song>> _songsFromRows(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return const <Song>[];
    var hasCompressedLyrics = false;
    for (final row in rows) {
      final raw = row['lyrics'];
      if (raw is String && raw.startsWith('gz:')) {
        hasCompressedLyrics = true;
        break;
      }
    }
    // Only the compressed lyric strings cross the isolate boundary. Sending
    // every full row (title, tags, paths...) across and back doubled peak
    // memory on large libraries at startup and after every scan.
    Map<int, String?>? decoded;
    if (hasCompressedLyrics) {
      final payload = <int, String>{};
      for (final row in rows) {
        final raw = row['lyrics'];
        if (raw is String && raw.startsWith('gz:')) {
          payload[(row['id'] as num?)?.toInt() ?? -1] = raw;
        }
      }
      decoded = await compute(_decodeLyricsInIsolate, payload);
    }
    final songs = <Song>[];
    for (final row in rows) {
      Map<String, Object?> effective = row;
      final raw = row['lyrics'];
      if (decoded != null && raw is String && raw.startsWith('gz:')) {
        final id = (row['id'] as num?)?.toInt() ?? -1;
        effective = <String, Object?>{...row, 'lyrics': decoded[id]};
      }
      try {
        songs.add(Song.fromMap(effective));
      } catch (e) {
        debugPrint('DBHelper: skipping corrupt songs row ${row['id']}: $e');
      }
    }
    return songs;
  }

  /// Decode only the `gz:` lyric values in a background isolate. The input
  /// and output are small id-to-string maps, so the whole song table is not
  /// copied across the boundary.
  static Map<int, String?> _decodeLyricsInIsolate(Map<int, String> encoded) =>
      encoded.map((id, raw) => MapEntry(id, decodeLyricsFromDb(raw)));

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
      batch.delete('song_bookmarks', where: 'songId = ?', whereArgs: [id]);
      batch.delete('song_playback_settings', where: 'songId = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    return ghostIds.length;
  }

  // ---------- Playback settings ----------
  Future<Map<int, Map<String, num>>> getAllSongPlaybackSettings() async {
    final database = await db;
    final rows = await database.query('song_playback_settings');
    return {
      for (final r in rows)
        (r['songId'] as num).toInt(): {
          'gainDb': (r['gainDb'] as num?) ?? 0,
          'skipStartMs': (r['skipStartMs'] as num?) ?? 0,
          'skipEndMs': (r['skipEndMs'] as num?) ?? 0,
        },
    };
  }

  Future<Map<String, Map<String, num>>> getAllFolderPlaybackSettings() async {
    final database = await db;
    final rows = await database.query('folder_playback_settings');
    return {
      for (final r in rows)
        r['folderPath'] as String: {
          'gainDb': (r['gainDb'] as num?) ?? 0,
          'skipStartMs': (r['skipStartMs'] as num?) ?? 0,
          'skipEndMs': (r['skipEndMs'] as num?) ?? 0,
        },
    };
  }

  Future<void> setSongPlaybackSettings(
    int songId, {
    required double gainDb,
    required int skipStartMs,
    required int skipEndMs,
  }) async {
    final database = await db;
    await database.insert(
      'song_playback_settings',
      {
        'songId': songId,
        'gainDb': gainDb,
        'skipStartMs': skipStartMs,
        'skipEndMs': skipEndMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setFolderPlaybackSettings(
    String folderPath, {
    required double gainDb,
    required int skipStartMs,
    required int skipEndMs,
  }) async {
    final database = await db;
    await database.insert(
      'folder_playback_settings',
      {
        'folderPath': folderPath,
        'gainDb': gainDb,
        'skipStartMs': skipStartMs,
        'skipEndMs': skipEndMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearSongPlaybackSettings(int songId) async {
    final database = await db;
    await database.delete('song_playback_settings',
        where: 'songId = ?', whereArgs: [songId]);
  }

  Future<void> clearFolderPlaybackSettings(String folderPath) async {
    final database = await db;
    await database.delete('folder_playback_settings',
        where: 'folderPath = ?', whereArgs: [folderPath]);
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
  ///
  /// [limit] pushes the cap into SQL so a small request never reads the
  /// whole table. Callers that filter by hidden folders afterwards should
  /// pass an over fetched limit.
  Future<List<Song>> getAllSongsByDateAdded({int? limit}) async {
    final database = await db;
    final rows = await database.query('songs', orderBy: 'addedAt DESC', limit: limit);
    return await _songsFromRows(rows);
  }

  /// Replace a playlist's membership in one transaction so a failed insert
  /// never leaves an auto playlist empty.
  Future<void> replacePlaylistSongs(
      int playlistId, List<int> songIds) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('playlist_songs',
          where: 'playlistId = ?', whereArgs: [playlistId]);
      final seen = <int>{};
      var position = 0;
      final now = DateTime.now().toIso8601String();
      for (final id in songIds) {
        if (!seen.add(id)) continue;
        await txn.insert('playlist_songs', {
          'playlistId': playlistId,
          'songId': id,
          'addedAt': now,
          'position': position++,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> clearPlaylistSongs(int playlistId) async {
    final database = await db;
    await database.delete('playlist_songs',
        where: 'playlistId = ?', whereArgs: [playlistId]);
  }

  Future<void> deleteSong(int id) async {
    final database = await db;
    // One transaction so a crash between deletes cannot leave a half-deleted
    // song behind (favorites/history gone but playlist links surviving).
    await database.transaction((txn) async {
      await txn.delete('songs', where: 'id = ?', whereArgs: [id]);
      await txn
          .delete('playlist_songs', where: 'songId = ?', whereArgs: [id]);
      await txn
          .delete('listening_entries', where: 'songId = ?', whereArgs: [id]);
      await txn.delete('synced_lyrics', where: 'songId = ?', whereArgs: [id]);
      await txn.delete('song_bookmarks', where: 'songId = ?', whereArgs: [id]);
      await txn.delete('song_playback_settings',
          where: 'songId = ?', whereArgs: [id]);
    });
  }

  Future<void> updateSongMetadata(Song s) async {
    invalidateDashboardCache();
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
    invalidateDashboardCache();
    if (songs.isEmpty) return;
    final database = await db;
    final ids = songs.map((s) => s.id).toSet().toList();
    final favorites = <int, Object?>{};
    // Chunked: Android 8/9 bundle SQLite with a 999 variable limit.
    const chunk = 400;
    for (var off = 0; off < ids.length; off += chunk) {
      final end = off + chunk > ids.length ? ids.length : off + chunk;
      final slice = ids.sublist(off, end);
      final placeholders = List.filled(slice.length, '?').join(',');
      final rows = await database.rawQuery(
        'SELECT id, isFavorite FROM songs WHERE id IN ($placeholders)',
        slice,
      );
      for (final row in rows) {
        favorites[row['id'] as int] = row['isFavorite'];
      }
    }
    final batch = database.batch();
    for (final s in songs) {
      final map = s.toMap();
      if (favorites.containsKey(s.id)) map['isFavorite'] = favorites[s.id];
      batch.update('songs', map, where: 'id = ?', whereArgs: [s.id]);
    }
    await batch.commit(noResult: true);
  }

  /// Look up songs by their ids, returning them in the order of [ids].
  /// Missing rows are dropped. Used by the playback resume restore, which
  /// stores the play order of the queue as song ids.
  Future<List<Song>> getSongsByIds(List<int> ids) async {
    if (ids.isEmpty) return const <Song>[];
    final database = await db;
    final rows = <Map<String, Object?>>[];
    const chunk = 400;
    for (var off = 0; off < ids.length; off += chunk) {
      final end = off + chunk > ids.length ? ids.length : off + chunk;
      final slice = ids.sublist(off, end);
      final placeholders = List.filled(slice.length, '?').join(',');
      rows.addAll(await database.rawQuery(
        'SELECT * FROM songs WHERE id IN ($placeholders)',
        slice,
      ));
    }
    final byId = <int, Song>{};
    for (final song in await _songsFromRows(rows)) {
      byId[song.id] = song;
    }
    final out = <Song>[];
    for (final id in ids) {
      final song = byId[id];
      if (song != null) out.add(song);
    }
    return out;
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
    return await _songsFromRows(rows);
  }

  /// Restore a backed-up last-played stamp only when this device has none.
  /// Falls back to the newest listening entry when the export has no stamp.
  Future<void> restoreLastPlayedAt(int songId, String? backedUp) async {
    try {
      final database = await db;
      if (backedUp != null && backedUp.isNotEmpty) {
        await database.rawUpdate(
          'UPDATE songs SET lastPlayedAt = ? '
          'WHERE id = ? AND lastPlayedAt IS NULL',
          [backedUp, songId],
        );
      } else {
        await database.rawUpdate(
          'UPDATE songs SET lastPlayedAt = '
          '(SELECT MAX(timestamp) FROM listening_entries '
          'WHERE songId = songs.id) '
          'WHERE id = ? AND lastPlayedAt IS NULL',
          [songId],
        );
      }
    } catch (_) {
      // Best effort: a history entry is enough to reconstruct recency.
    }
  }

  /// Mark many songs played in one transaction and invalidate the dashboard
  /// cache once. The bulk selection path used to call markPlayed per row,
  /// which did a SharedPreferences round trip for every song.
  Future<int> markPlayedBulk(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final database = await db;
    final stamp = DateTime.now().toIso8601String();
    var updated = 0;
    try {
      await database.transaction((txn) async {
        for (final id in ids) {
          updated += await txn.update(
            'songs',
            {'lastPlayedAt': stamp},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      });
      await invalidateDashboardCache();
    } catch (_) {}
    return updated;
  }

  Future<void> markPlayed(int songId) async {
    try {
      final database = await db;
      await database.update(
          'songs', {'lastPlayedAt': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [songId]);
      // Invalidate only after the write it invalidates.
      await invalidateDashboardCache();
    } catch (e) {
      // A failed marker write must never abort a track change: playback
      // depends on this being best-effort.
      debugPrint('DBHelper: markPlayed failed for $songId: $e');
    }
  }

  Future<List<Song>> getRecentlyPlayed({
    int limit = 50,
    int offset = 0,
    Set<String>? excludedFolders,
  }) async {
    final database = await db;
    final where = <String>['lastPlayedAt IS NOT NULL'];
    final args = <Object?>[];
    for (final folder in excludedFolders ?? const <String>{}) {
      final normalized = folder.replaceAll('\\', '/').replaceAll(RegExp(r'/$'), '');
      if (normalized.isEmpty) continue;
      where.add("filePath NOT LIKE ? ESCAPE '\\'");
      args.add('${_escapeLike(normalized)}/%');
    }
    args.addAll([limit, offset < 0 ? 0 : offset]);
    final rows = await database.rawQuery(
      'SELECT * FROM songs WHERE ${where.join(' AND ')} '
      'ORDER BY lastPlayedAt DESC LIMIT ? OFFSET ?',
      args,
    );
    return await _songsFromRows(rows);
  }

  Future<List<Map<String, dynamic>>> getPlaylistsPage({
    required int limit,
    required int offset,
  }) async {
    final database = await db;
    return database.rawQuery(
      'SELECT * FROM playlists ORDER BY createdAt DESC LIMIT ? OFFSET ?',
      [limit, offset < 0 ? 0 : offset],
    );
  }

  Future<List<Song>> getSongsInPlaylistPage(int playlistId,
      {required int limit, required int offset}) async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT s.* FROM songs s
      JOIN playlist_songs ps ON ps.songId = s.id
      WHERE ps.playlistId = ?
      ORDER BY ps.position ASC, ps.addedAt ASC
      LIMIT ? OFFSET ?
    ''', [playlistId, limit, offset < 0 ? 0 : offset]);
    return await _songsFromRows(rows);
  }

  Future<List<String>> getMusicFoldersPage({
    required int limit,
    required int offset,
    required Set<String> excludedFolders,
  }) async {
    final folders = <String>{};
    for (final song in await getSongSummaries()) {
      final folder = folderOf(song.filePath);
      if (folder.isEmpty || isHiddenPath(song.filePath, excludedFolders)) continue;
      folders.add(folder);
    }
    final sorted = folders.toList()..sort();
    final safeOffset = offset < 0 ? 0 : offset;
    if (safeOffset >= sorted.length) return const <String>[];
    final end = (safeOffset + limit).clamp(0, sorted.length).toInt();
    return sorted.sublist(safeOffset, end);
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
  /// Total times [songId] appears in the listening history.
  Future<int> getPlayCountForSong(int songId) async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) FROM listening_entries WHERE songId = ?',
      [songId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

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

  /// Albums ranked by listening time in the last 30 days. Reads only the
  /// existing history and song tables, with no new schema or dependency.
  Future<List<Map<String, Object?>>> getTopAlbums({int limit = 5}) async {
    final database = await db;
    final since = DateTime.now()
        .subtract(const Duration(days: 29))
        .toIso8601String();
    return database.rawQuery(
      'SELECT COALESCE(NULLIF(s.album, \'\'), ?) AS album, '
      'SUM(l.listenedMs) AS totalMs, COUNT(*) AS plays '
      'FROM listening_entries l JOIN songs s ON s.id = l.songId '
      'WHERE julianday(l.timestamp) >= julianday(?) '
      'GROUP BY album ORDER BY totalMs DESC LIMIT ?',
      ['Unknown Album', since, limit],
    );
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
      SELECT COALESCE(genre, 'Unknown') as genre, COUNT(*) as cnt
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
      SELECT COALESCE(region, 'Unknown') as region, COUNT(*) as cnt
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
  /// Listening milliseconds grouped by weekday (1 = Monday, 7 = Sunday).
  Future<Map<int, int>> getWeekdayDistribution() async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT CAST(strftime("%w", timestamp) AS INTEGER) AS weekday, '
      'SUM(listenedMs) AS ms FROM listening_entries GROUP BY weekday',
    );
    final out = <int, int>{};
    for (final row in rows) {
      final day = (row['weekday'] as num?)?.toInt();
      final ms = (row['ms'] as num?)?.toInt();
      if (day == null || ms == null) continue;
      // strftime gives 0 for Sunday, map it to 7.
      out[day == 0 ? 7 : day] = ms;
    }
    return out;
  }

  /// One row per day for the last [days] days, including days with no play.
  Future<List<Map<String, Object?>>> getDailyListeningSeries(int days) async {
    final database = await db;
    final start = DateTime.now()
        .subtract(Duration(days: days > 0 ? days - 1 : 0))
        .toIso8601String()
        .substring(0, 10);
    final rows = await database.rawQuery(
      'SELECT substr(timestamp, 1, 10) AS day, SUM(listenedMs) AS ms '
      'FROM listening_entries WHERE substr(timestamp, 1, 10) >= ? '
      'GROUP BY day ORDER BY day ASC',
      [start],
    );
    return rows;
  }

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
  Future<int> createPlaylist(String name,
      {bool isAuto = false, String? rule}) async {
    final database = await db;
    return database.insert('playlists', {
      'name': name,
      'createdAt': DateTime.now().toIso8601String(),
      'isAuto': isAuto || rule != null ? 1 : 0,
      'rule': rule,
    });
  }

  Future<void> setPlaylistAuto(int playlistId, bool value) async {
    final database = await db;
    await database.update('playlists', {'isAuto': value ? 1 : 0},
        where: 'id = ?', whereArgs: [playlistId]);
  }

  /// Create a playlist dated [createdAt] instead of now. Used by the backup
  /// restore to keep the original ordering of playlists across devices.
  Future<int> createPlaylistWithDate(String name, String createdAt,
      {String? rule}) async {
    final database = await db;
    return database.insert('playlists', {
      'name': name,
      'createdAt': createdAt,
      'rule': rule,
      'isAuto': rule != null ? 1 : 0,
    });
  }

  Future<void> setPlaylistRule(int playlistId, String? rule,
      {bool updateAuto = true}) async {
    final database = await db;
    await database.update(
      'playlists',
      {
        'rule': rule,
        if (updateAuto) 'isAuto': rule != null ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [playlistId],
    );
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
        'SELECT DISTINCT folder FROM playlists '
        "WHERE folder IS NOT NULL AND TRIM(folder) != '' "
        'ORDER BY folder COLLATE NOCASE ASC',
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
    invalidateDashboardCache();
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
    return await _songsFromRows(rows);
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
    // Every reader re-fetches this from the DB per call otherwise; drop the
    // cache so a hidden folder is invisible immediately.
    _excludedFoldersCache = null;
    invalidateDashboardCache();
  }

  // Memo of the excluded folder set. Read repeatedly by the library, the
  // dashboard and the paged query; invalidated by setFolderIncluded.
  Set<String>? _excludedFoldersCache;

  Future<Set<String>> getExcludedFolders() async {
    final cached = _excludedFoldersCache;
    if (cached != null) return cached;
    final database = await db;
    final rows = await database.query('folders', where: 'includeInLibrary = 0');
    final result = rows.map((r) => r['path'] as String).toSet();
    _excludedFoldersCache = result;
    return result;
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
    return await _songsFromRows(rows);
  }

  /// Songs that were never played at all
  Future<List<Song>> getNeverPlayedSongs() async {
    final database = await db;
    final rows = await database.query(
      'songs',
      where: 'lastPlayedAt IS NULL',
      orderBy: 'title ASC',
    );
    return await _songsFromRows(rows);
  }

  /// Favorite songs whose last play is older than [days] ago (or that were
  /// never played). Least recently played first, so the result starts with
  /// the songs most overdue for a replay.
  ///
  /// lastPlayedAt is stored as an ISO 8601 string, so a lexicographic
  /// comparison against the cutoff is chronological.
  Future<List<Song>> getForgottenFavorites({int days = 90}) async {
    final safeDays = days < 1 ? 90 : days;
    final cutoff = DateTime.now()
        .subtract(Duration(days: safeDays))
        .toIso8601String();
    final database = await db;
    final rows = await database.query(
      'songs',
      where: 'isFavorite = 1 AND (lastPlayedAt IS NULL OR lastPlayedAt < ?)',
      whereArgs: [cutoff],
      orderBy: "COALESCE(lastPlayedAt, '') ASC",
    );
    return await _songsFromRows(rows);
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
        AND songId IS NOT NULL
      GROUP BY songId
      ORDER BY playCount DESC
      LIMIT ?
    ''', [isoStart, safeLimit]);
    return rows
        .map((r) => MapEntry(
            (r['songId'] as num?)?.toInt() ?? -1,
            (r['playCount'] as num?)?.toInt() ?? 0))
        .where((e) => e.key != -1)
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

  /// Normalize excluded folder paths before building LIKE clauses.
  List<String> _normalizedFolders(Set<String>? folders) => (folders ?? const <String>{})
      .map((e) => e.replaceAll('\\', '/'))
      .map((e) => e.endsWith('/') ? e.substring(0, e.length - 1) : e)
      .where((e) => e.isNotEmpty)
      .toList();

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

  Future<List<String>> getDistinctGenres() async {
    final database = await db;
    final rows = await database.rawQuery(
      "SELECT DISTINCT genre FROM songs WHERE genre IS NOT NULL AND genre != '' "
      'ORDER BY genre ASC LIMIT 100',
    );
    return rows
        .map((r) => r['genre'] as String?)
        .whereType<String>()
        .toList();
  }

  Future<List<Song>> getSongsByGenre(
    String genre, {
    required int limit,
    required int offset,
    Set<String>? excludedFolders,
  }) async {
    final database = await db;
    final where = <String>['genre = ?'];
    final args = <Object?>[genre];
    for (final folder in _normalizedFolders(excludedFolders)) {
      where.add("filePath NOT LIKE ? ESCAPE '\\'");
      args.add('${_escapeLike(folder)}/%');
    }
    final rows = await database.rawQuery(
      'SELECT * FROM songs WHERE ${where.join(' AND ')} '
      'ORDER BY title COLLATE NOCASE ASC LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return _songsFromRows(rows);
  }

  Future<List<Song>> getRecentlyAddedSongs({
    required int limit,
    required int offset,
    Set<String>? excludedFolders,
  }) async {
    final database = await db;
    final excluded = (excludedFolders ?? const <String>{})
        .map((e) => e.replaceAll('\\', '/'))
        .map((e) => e.endsWith('/') ? e.substring(0, e.length - 1) : e)
        .where((e) => e.isNotEmpty)
        .toList();
    final where = <String>['addedAt IS NOT NULL'];
    final args = <Object?>[];
    for (final folder in excluded) {
      where.add("filePath NOT LIKE ? ESCAPE '\\'");
      args.add('${_escapeLike(folder)}/%');
    }
    final rows = await database.rawQuery(
      'SELECT * FROM songs WHERE ${where.join(' AND ')} '
      'ORDER BY addedAt DESC LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return _songsFromRows(rows);
  }

  Future<List<Song>> getUnplayedSongs({
    required int limit,
    required int offset,
    Set<String>? excludedFolders,
  }) async {
    final database = await db;
    final where = <String>['lastPlayedAt IS NULL'];
    final args = <Object?>[];
    for (final folder in _normalizedFolders(excludedFolders)) {
      where.add("filePath NOT LIKE ? ESCAPE '\\'");
      args.add('${_escapeLike(folder)}/%');
    }
    final rows = await database.rawQuery(
      'SELECT * FROM songs WHERE ${where.join(' AND ')} '
      'ORDER BY title COLLATE NOCASE ASC LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return _songsFromRows(rows);
  }

  /// Search both title and artist in the same row. Used by voice playback
  /// where the spoken query is ambiguous but the metadata extras are precise.
  Future<List<Song>> querySongsByTitleAndArtist(
    String title,
    String artist, {
    int limit = 20,
    Set<String>? excludedFolders,
  }) async {
    final database = await db;
    final titlePattern = '%${_escapeLike(title)}%';
    final artistPattern = '%${_escapeLike(artist)}%';
    final where = <String>[
      "lower(title) LIKE lower(?) ESCAPE '\\'",
      "lower(artist) LIKE lower(?) ESCAPE '\\'",
    ];
    final args = <Object?>[titlePattern, artistPattern];
    // Exclude hidden folders in SQL, before LIMIT, so a full page of matches
    // in hidden folders cannot push visible songs out of the result.
    final excluded = (excludedFolders ?? const <String>{})
        .map((e) => e.replaceAll('\\', '/'))
        .map((e) => e.endsWith('/') ? e.substring(0, e.length - 1) : e)
        .where((e) => e.isNotEmpty)
        .toList();
    for (final folder in excluded) {
      where.add("filePath NOT LIKE ? ESCAPE '\\'");
      args.add('${_escapeLike(folder)}/%');
    }
    final rows = await database.rawQuery(
      'SELECT * FROM songs WHERE ${where.join(' AND ')} '
      'ORDER BY title ASC LIMIT ?',
      [...args, limit],
    );
    return await _songsFromRows(rows);
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
    return await _songsFromRows(rows);
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
  Future<void> setSyncedLyrics(int songId, String lrc,
      {int offsetMs = 0}) async {
    final database = await db;
    await database.insert(
      'synced_lyrics',
      {
        'songId': songId,
        'lrc': lrc,
        'fetchedAt': DateTime.now().toIso8601String(),
        'offsetMs': offsetMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Saved user timing correction in milliseconds for [songId].
  Future<int> getSyncedLyricOffset(int songId) async {
    final database = await db;
    final rows = await database.query('synced_lyrics',
        columns: ['offsetMs'],
        where: 'songId = ?',
        whereArgs: [songId],
        limit: 1);
    if (rows.isEmpty) return 0;
    return (rows.first['offsetMs'] as num?)?.toInt() ?? 0;
  }

  /// Persist a timing correction without changing the stored LRC text or
  /// pretending it was fetched again.
  Future<void> setSyncedLyricOffset(int songId, int offsetMs) async {
    final database = await db;
    await database.update(
      'synced_lyrics',
      {'offsetMs': offsetMs},
      where: 'songId = ?',
      whereArgs: [songId],
    );
  }

  /// One batched read for all per-song extras used by backup export. Three
  /// queries per song used to mean thousands of awaits on a large library.
  Future<Map<int, Map<String, Object?>>> getBackupSongExtras(
      List<int> songIds) async {
    final database = await db;
    final result = <int, Map<String, Object?>>{};
    const chunk = 400;
    for (var off = 0; off < songIds.length; off += chunk) {
      final end = off + chunk > songIds.length ? songIds.length : off + chunk;
      final slice = songIds.sublist(off, end);
      final placeholders = List.filled(slice.length, '?').join(',');
      final lrcRows = await database.rawQuery(
          'SELECT songId, lrc, offsetMs FROM synced_lyrics '
          'WHERE songId IN ($placeholders)', slice);
      for (final row in lrcRows) {
        final id = (row['songId'] as num?)?.toInt();
        if (id == null) continue;
        result.putIfAbsent(id, () => {});
        result[id]!['lrc'] = row['lrc'];
        result[id]!['offsetMs'] = row['offsetMs'];
      }
      final playedRows = await database.rawQuery(
          'SELECT id, lastPlayedAt FROM songs '
          'WHERE id IN ($placeholders)', slice);
      for (final row in playedRows) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        result.putIfAbsent(id, () => {});
        result[id]!['lastPlayedAt'] = row['lastPlayedAt'];
      }
      final bookmarkRows = await database.rawQuery(
          'SELECT id, songId, positionMs, label, createdAt FROM song_bookmarks '
          'WHERE songId IN ($placeholders) ORDER BY positionMs ASC', slice);
      for (final row in bookmarkRows) {
        final id = (row['songId'] as num?)?.toInt();
        if (id == null) continue;
        result.putIfAbsent(id, () => {});
        final list = (result[id]!['bookmarks'] as List<Object?>?)?.toList() ??
            <Object?>[];
        list.add(row);
        result[id]!['bookmarks'] = list;
      }
    }
    return result;
  }

  /// Previous normalized paths for songs that were renamed on disk.
  Future<Map<int, List<String>>> getPathAliases() async {
    final result = <int, List<String>>{};
    try {
      final database = await db;
      final rows = await database.query('song_path_aliases',
          columns: ['songId', 'path']);
      for (final row in rows) {
        final id = (row['songId'] as num?)?.toInt();
        final path = row['path'] as String?;
        if (id == null || path == null || path.isEmpty) continue;
        result.putIfAbsent(id, () => <String>[]).add(normalizeBackupPath(path));
      }
    } catch (_) {
      // A failed v15 migration must not break backup export.
    }
    return result;
  }

  // ---------- Backup identity helpers ----------
  /// Change a song's stored path and title only when the row still matches
  /// [oldPath] and no other row already uses [newPath].
  Future<bool> updateSongFilePath(
    int id, {
    required String oldPath,
    required String newPath,
    required String newTitle,
  }) async {
    final database = await db;
    try {
      return await database.transaction((txn) async {
        final rows = await txn.query('songs',
            columns: ['filePath'], where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty || rows.first['filePath'] != oldPath) return false;
        final colliding = await txn.query('songs',
            columns: ['id'],
            where: 'filePath = ? COLLATE NOCASE AND id != ?',
            whereArgs: [newPath, id],
            limit: 1);
        if (colliding.isNotEmpty) return false;
        await txn.update(
          'songs',
          {'filePath': newPath, 'title': newTitle},
          where: 'id = ?',
          whereArgs: [id],
        );
        // Keep the previous identity so a backup exported before this rename
        // can still find the row on import.
        await txn.insert('song_path_aliases', {
          'songId': id,
          'path': oldPath,
          'basename': p.basenameWithoutExtension(oldPath),
          'changedAt': DateTime.now().toIso8601String(),
        });
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  Future<Song?> getSongByFilePath(String filePath) async {
    final database = await db;
    final rows = await database.query('songs',
        where: 'filePath = ?', whereArgs: [filePath], limit: 1);
    if (rows.isEmpty) return null;
    final songs = await _songsFromRows(rows);
    return songs.isEmpty ? null : songs.first;
  }

  Future<Map<String, Object?>?> querySongById(int id) async {
    final database = await db;
    final rows = await database.query('songs',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> getSongIdentityRows() async {
    final database = await db;
    return database.query('songs', columns: ['id', 'filePath', 'durationMs']);
  }

  /// Update only the fields a user may legitimately restore from a backup.
  /// Never touches filePath, durationMs, isFavorite or addedAt.
  Future<void> applyBackupSongMetadata(
    int songId, {
    String? title,
    String? artist,
    String? album,
    String? genre,
    String? region,
    String? lyrics,
    bool? metadataScanned,
  }) async {
    final values = <String, Object?>{};
    if (title != null) values['title'] = title;
    if (artist != null) values['artist'] = artist;
    if (album != null) values['album'] = album;
    if (genre != null) values['genre'] = genre;
    if (region != null) values['region'] = region;
    if (lyrics != null) values['lyrics'] = encodeLyricsForDb(lyrics);
    if (metadataScanned != null) values['metadataScanned'] = metadataScanned ? 1 : 0;
    if (values.isEmpty) return;
    final database = await db;
    await database.update('songs', values,
        where: 'id = ?', whereArgs: [songId]);
  }

  // ---------- Song bookmarks ----------
  static const int maxBookmarksPerSong = 20;

  Future<List<Map<String, Object?>>> getBookmarks(int songId) async {
    final database = await db;
    return database.query('song_bookmarks',
        where: 'songId = ?',
        whereArgs: [songId],
        orderBy: 'positionMs ASC');
  }

  Future<bool> addBookmark(int songId, int positionMs, String label) async {
    final database = await db;
    final existing = await database.query('song_bookmarks',
        columns: ['id'],
        where: 'songId = ?',
        whereArgs: [songId]);
    if (existing.length >= maxBookmarksPerSong) return false;
    await database.insert('song_bookmarks', {
      'songId': songId,
      'positionMs': positionMs,
      'label': label.trim(),
      'createdAt': DateTime.now().toIso8601String(),
    });
    return true;
  }

  /// Restore a bookmark with its original timestamp, deduped and capped at
  /// [maxBookmarksPerSong]. Returns true when a row was inserted.
  Future<bool> insertBookmarkWithDate(
      int songId, int positionMs, String label, String createdAt) async {
    final database = await db;
    final existing = await database.query('song_bookmarks',
        where: 'songId = ? AND positionMs = ? AND label = ?',
        whereArgs: [songId, positionMs, label],
        limit: 1);
    if (existing.isNotEmpty) return false;
    final count = Sqflite.firstIntValue(await database.rawQuery(
            'SELECT COUNT(*) FROM song_bookmarks WHERE songId = ?',
            [songId])) ??
        0;
    if (count >= maxBookmarksPerSong) return false;
    await database.insert('song_bookmarks', {
      'songId': songId,
      'positionMs': positionMs,
      'label': label,
      'createdAt': createdAt,
    });
    return true;
  }

  Future<void> updateBookmarkLabel(int bookmarkId, String label) async {
    final database = await db;
    await database.update('song_bookmarks', {'label': label.trim()},
        where: 'id = ?', whereArgs: [bookmarkId]);
  }

  Future<void> deleteBookmark(int bookmarkId) async {
    final database = await db;
    await database.delete('song_bookmarks',
        where: 'id = ?', whereArgs: [bookmarkId]);
  }

  // ---------- Ratings and v6 helpers ----------

  Future<void> setRating(int songId, int rating) async {
    final database = await db;
    final value = rating.clamp(0, 5);
    await database.update('songs', {'rating': value},
        where: 'id = ?', whereArgs: [songId]);
  }

  Future<List<String>> getDistinctLabels() async {
    final database = await db;
    final rows = await database.rawQuery(
      "SELECT DISTINCT label FROM song_labels WHERE label IS NOT NULL AND label != '' "
      'ORDER BY label ASC',
    );
    return rows.map((r) => r['label'] as String?).whereType<String>().toList();
  }

  Future<void> renameLabel(String from, String to) async {
    final database = await db;
    await database.update('song_labels', {'label': to.trim()},
        where: 'label = ?', whereArgs: [from]);
  }

  Future<void> mergeLabels(String from, String into) async {
    final database = await db;
    await database.transaction((txn) async {
      final rows = await txn.query('song_labels',
          columns: ['songId', 'label'], where: 'label = ?', whereArgs: [from]);
      for (final row in rows) {
        final id = row['songId'];
        if (id == null) continue;
        await txn.insert(
          'song_labels',
          {'songId': id, 'label': into},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.delete('song_labels', where: 'label = ?', whereArgs: [from]);
    });
  }

  Future<void> deleteLabel(String label) async {
    final database = await db;
    await database.delete('song_labels', where: 'label = ?', whereArgs: [label]);
  }

  Future<void> movePlaylistToFolder(int playlistId, String folder) async {
    final database = await db;
    await database.update('playlists', {'folder': folder.trim()},
        where: 'id = ?', whereArgs: [playlistId]);
  }

  Future<List<(String, int)>> getArtistCounts() async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT artist, COUNT(*) AS n FROM songs GROUP BY artist ORDER BY n DESC',
    );
    return [
      for (final row in rows)
        ((row['artist'] as String?) ?? '', (row['n'] as num?)?.toInt() ?? 0),
    ];
  }

  Future<List<(String, int)>> getGenreCounts() async {
    final database = await db;
    final rows = await database.rawQuery(
      "SELECT genre, COUNT(*) AS n FROM songs WHERE genre IS NOT NULL AND genre != '' "
      'GROUP BY genre ORDER BY n DESC',
    );
    return [
      for (final row in rows)
        ((row['genre'] as String?) ?? '', (row['n'] as num?)?.toInt() ?? 0),
    ];
  }

  Future<List<Song>> getRatedSongs({
    required int minRating,
    required int limit,
    required int offset,
  }) async {
    final database = await db;
    final rows = await database.query(
      'songs',
      where: 'rating >= ?',
      whereArgs: [minRating],
      orderBy: 'rating DESC, title COLLATE NOCASE ASC',
      limit: limit,
      offset: offset,
    );
    return _songsFromRows(rows);
  }

  Future<List<Song>> getSongsByLabel(
    String label, {
    required int limit,
    required int offset,
  }) async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT s.* FROM songs s JOIN song_labels l ON l.songId = s.id '
      'WHERE l.label = ? ORDER BY s.title COLLATE NOCASE ASC LIMIT ? OFFSET ?',
      [label, limit, offset],
    );
    return _songsFromRows(rows);
  }

  Future<List<Song>> getListeningHistoryPage({
    required int limit,
    required int offset,
  }) async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT s.* FROM listening_entries e JOIN songs s ON s.id = e.songId '
      'ORDER BY e.timestamp DESC LIMIT ? OFFSET ?',
      [limit, offset],
    );
    return _songsFromRows(rows);
  }

  // ---------- Labels (v17) ----------

  Future<Map<int, String>> getSongLabels() async {
    final database = await db;
    final rows = await database.query('song_labels');
    return {
      for (final row in rows)
        if (row['songId'] is int && (row['label'] as String?)?.isNotEmpty == true)
          (row['songId'] as int): row['label'] as String,
    };
  }

  Future<void> setAlbumArtPath(int songId, String path) async {
    final database = await db;
    await database.update('songs', {'albumArtPath': path},
        where: 'id = ?', whereArgs: [songId]);
  }

  /// Write many labels in one batch. The bulk UI path used one transaction
  /// per song even though it rebuilt the UI only once.
  Future<void> setSongLabelsBulk(Map<int, String> values) async {
    if (values.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final entry in values.entries) {
      final value = entry.value.trim();
      if (value.isEmpty) {
        batch.delete('song_labels',
            where: 'songId = ?', whereArgs: [entry.key]);
      } else {
        batch.insert(
          'song_labels',
          {'songId': entry.key, 'label': value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> setSongLabel(int songId, String label) async {
    final database = await db;
    final value = label.trim();
    if (value.isEmpty) {
      await database.delete('song_labels',
          where: 'songId = ?', whereArgs: [songId]);
    } else {
      await database.insert(
        'song_labels',
        {'songId': songId, 'label': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ---------- Library trash (v17) ----------

  /// Paths of songs in the trash. The scanner must not resurrect them on
  /// the next device scan while their trash entry still exists.
  Future<Set<String>> getTrashedPaths() async {
    final database = await db;
    final rows = await database.query('trash_songs', columns: ['payload']);
    final out = <String>{};
    for (final row in rows) {
      final raw = row['payload'] as String?;
      if (raw == null) continue;
      try {
        final song = (jsonDecode(raw) as Map)['song'] as Map?;
        final path = song?['filePath'] as String?;
        if (path != null && path.isNotEmpty) out.add(path);
      } catch (_) {}
    }
    return out;
  }

  Future<List<Map<String, Object?>>> getTrashEntries() async {
    final database = await db;
    final rows = await database.query('trash_songs',
        columns: ['songId', 'payload', 'deletedAt'],
        orderBy: 'deletedAt DESC');
    final out = <Map<String, Object?>>[];
    for (final row in rows) {
      final raw = row['payload'] as String?;
      String title = '';
      String path = '';
      if (raw != null) {
        try {
          final song = (jsonDecode(raw) as Map)['song'] as Map?;
          title = song?['title'] as String? ?? '';
          path = song?['filePath'] as String? ?? '';
        } catch (_) {}
      }
      out.add({
        'songId': row['songId'],
        'deletedAt': row['deletedAt'],
        'title': title,
        'path': path,
      });
    }
    return out;
  }

  Future<bool> moveSongToTrash(int songId) async {
    final database = await db;
    try {
      return await database.transaction((txn) async {
        final songRows = await txn.query('songs',
            where: 'id = ?', whereArgs: [songId], limit: 1);
        if (songRows.isEmpty) return false;
        final labelRows = await txn.query('song_labels',
            where: 'songId = ?', whereArgs: [songId], limit: 1);
        final payload = <String, Object?>{
          'song': songRows.first,
          'label': labelRows.isEmpty ? '' : labelRows.first['label'],
          'playlistSongs': await txn.query('playlist_songs',
              where: 'songId = ?', whereArgs: [songId]),
          'listening': await txn.query('listening_entries',
              where: 'songId = ?', whereArgs: [songId]),
          'lyrics': await txn.query('synced_lyrics',
              where: 'songId = ?', whereArgs: [songId], limit: 1),
          'bookmarks': await txn.query('song_bookmarks',
              where: 'songId = ?', whereArgs: [songId]),
          'playback': await txn.query('song_playback_settings',
              where: 'songId = ?', whereArgs: [songId], limit: 1),
        };
        await txn.insert('trash_songs', {
          'songId': songId,
          'payload': jsonEncode(payload),
          'deletedAt': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn
            .delete('songs', where: 'id = ?', whereArgs: [songId]);
        await txn.delete('playlist_songs',
            where: 'songId = ?', whereArgs: [songId]);
        await txn.delete('listening_entries',
            where: 'songId = ?', whereArgs: [songId]);
        await txn.delete('synced_lyrics',
            where: 'songId = ?', whereArgs: [songId]);
        await txn.delete('song_bookmarks',
            where: 'songId = ?', whereArgs: [songId]);
        await txn.delete('song_playback_settings',
            where: 'songId = ?', whereArgs: [songId]);
        await txn.delete('song_labels',
            where: 'songId = ?', whereArgs: [songId]);
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  Future<bool> restoreFromTrash(int songId) async {
    final database = await db;
    try {
      return await database.transaction((txn) async {
        final rows = await txn.query('trash_songs',
            where: 'songId = ?', whereArgs: [songId], limit: 1);
        if (rows.isEmpty) return false;
        final raw = rows.first['payload'] as String?;
        if (raw == null) return false;
        final payload = jsonDecode(raw) as Map<String, dynamic>;
        final song = Map<String, dynamic>.from(payload['song'] as Map);
        // filePath is UNIQUE. A scan may have re-added this file with a new
        // MediaStore id while it was in the trash. Bind user data to the row
        // that actually exists, never to a dead id.
        int? resolvedId;
        final byId = await txn.query('songs',
            columns: ['id'], where: 'id = ?', whereArgs: [songId], limit: 1);
        if (byId.isNotEmpty) {
          resolvedId = songId;
        } else {
          final path = song['filePath'] as String?;
          if (path != null) {
            final byPath = await txn.query('songs',
                columns: ['id'],
                where: 'filePath = ?',
                whereArgs: [path],
                limit: 1);
            if (byPath.isNotEmpty) {
              resolvedId = (byPath.first['id'] as num).toInt();
            }
          }
          if (resolvedId == null) {
            final inserted = await txn.insert('songs', song,
                conflictAlgorithm: ConflictAlgorithm.ignore);
            if (inserted <= 0) return false;
            resolvedId = songId;
          }
        }
        final target = resolvedId;
        Map<String, dynamic> remap(Map item) {
          final out = Map<String, dynamic>.from(item);
          if (out['songId'] == songId) out['songId'] = target;
          return out;
        }
        for (final table in const [
          'playlist_songs',
          'listening_entries',
          'song_bookmarks',
        ]) {
          for (final item in (payload[table == 'playlist_songs'
                      ? 'playlistSongs'
                      : table == 'listening_entries'
                          ? 'listening'
                          : 'bookmarks'] as List?) ??
              const []) {
            if (item is! Map) continue;
            await txn.insert(table, remap(item),
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        for (final entry in const [
          ('synced_lyrics', 'lyrics'),
          ('song_playback_settings', 'playback'),
        ]) {
          final item = payload[entry.$2];
          if (item is Map) {
            await txn.insert(entry.$1, remap(item),
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        final label = payload['label'] as String?;
        if (label != null && label.isNotEmpty) {
          await txn.insert('song_labels',
              {'songId': target, 'label': label},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await txn.delete('trash_songs',
            where: 'songId = ?', whereArgs: [songId]);
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteTrashEntry(int songId) async {
    final database = await db;
    await database.delete('trash_songs',
        where: 'songId = ?', whereArgs: [songId]);
  }

  Future<void> clearTrash() async {
    final database = await db;
    await database.delete('trash_songs');
  }
}

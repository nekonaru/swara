import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'db_helper.dart';

// ── Isolate entry points ──────────────────────────────────────────────
// Top-level functions used by compute(). They receive plain serialisable
// data and return plain results so the isolate never touches the
// singleton's state or sqflite. A fresh http.Client is created inside
// each entry because it is not transferable across isolate boundaries.

/// iTunes lookup isolate entry point: only HTTP, no sqflite.
///
/// Return contract (kept explicit because a wrong guess poisons the cache):
///   {'body': <raw 200 body>}  definitive hit, safe to apply and cache
///   {'miss': true}            definitive miss, cache the MISS marker
///   {'rateLimited': true}     HTTP 429, start the backoff window
///   {}                        transient failure (offline, 5xx, captive
///                             portal HTML), retry on a later scan
Future<Map<String, dynamic>> _itunesLookupIsolate(Map<String, dynamic> params) async {
  final artist = params['artist'] as String;
  final title = params['title'] as String;
  final client = http.Client();
  try {
    final url = Uri.https('itunes.apple.com', '/search', {
      'term': '$artist $title'.trim(),
      'entity': 'song',
      'limit': '1',
    });
    final resp = await client
        .get(url, headers: {'User-Agent': 'Swara/1.0'})
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode == 200) {
      // A captive portal (hotel, airport, campus WiFi) can return 200 with
      // an HTML body. Only an iTunes shaped payload counts as an answer.
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data.containsKey('resultCount')) {
          final count = data['resultCount'];
          if (count is num && count > 0) {
            return <String, dynamic>{'body': resp.body};
          }
          return <String, dynamic>{'miss': true};
        }
      } catch (_) {
        // Not JSON: fall through as a transient failure below.
      }
      return <String, dynamic>{};
    }
    if (resp.statusCode == 429) return <String, dynamic>{'rateLimited': true};
    if (resp.statusCode == 404) {
      // Commit a miss only when the body actually looks like iTunes,
      // otherwise a captive portal 404 would lock the song for 90 days.
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data.containsKey('resultCount')) {
          return <String, dynamic>{'miss': true};
        }
      } catch (_) {
        // HTML or truncated body: treat as transient below.
      }
      return <String, dynamic>{};
    }
    // Any other status (5xx and friends): transient, never cached.
    return <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  } finally {
    client.close();
  }
}

/// Lyrics fetch isolate entry point: only HTTP, no sqflite.
///
/// Same contract as the iTunes entry: {'lyrics': ...} on hit,
/// {'miss': true} on a definitive miss, {'rateLimited': true} on 429,
/// and {} for anything transient that must not poison the cache.
Future<Map<String, dynamic>> _lyricsFetchIsolate(Map<String, dynamic> params) async {
  final artist = params['artist'] as String;
  final title = params['title'] as String;
  if (artist.isEmpty || title.isEmpty) return <String, dynamic>{};
  final client = http.Client();
  try {
    final url = Uri.https(
      'api.lyrics.ovh',
      '/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}',
    );
    final resp = await client
        .get(url, headers: {'User-Agent': 'Swara/1.0'})
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode == 200) {
      try {
        final data = jsonDecode(resp.body);
        if (data is Map) {
          final lyrics = data['lyrics']?.toString().trim() ?? '';
          if (lyrics.isNotEmpty) {
            final capped =
                lyrics.length > 100 * 1024 ? lyrics.substring(0, 100 * 1024) : lyrics;
            return <String, dynamic>{'lyrics': capped};
          }
          // 200 with valid JSON and no lyrics: the song has none.
          return <String, dynamic>{'miss': true};
        }
      } catch (_) {
        // Not JSON (captive portal page): transient below.
      }
      return <String, dynamic>{};
    }
    if (resp.statusCode == 429) return <String, dynamic>{'rateLimited': true};
    if (resp.statusCode == 404) return <String, dynamic>{'miss': true};
    // 5xx and friends: transient, never cached.
    return <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  } finally {
    client.close();
  }
}

/// Hoisted so the timestamp pattern is compiled once per isolate run instead
/// of once per line. LRC lines look like "[00:12.34]Some words".
final RegExp _lrcLineTimeReg =
    RegExp(r'^\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

/// Convert LRC text into plain lyrics by dropping the timestamps. Used when
/// a source returned synced lyrics but no plain lyrics, so the plain view
/// still has something to show. Metadata tags such as "[ar:Artist]" carry no
/// digits in the first field, so the pattern never matches them.
String _plainLyricsFromLrc(String lrc) {
  final out = <String>[];
  for (final line in lrc.split('\n')) {
    final m = _lrcLineTimeReg.firstMatch(line);
    if (m == null) continue;
    final text = line.substring(m.end).trim();
    if (text.isEmpty) continue;
    if (out.length >= 2000) break;
    out.add(text);
  }
  return out.join('\n');
}

/// Cap any lyrics payload at 100KB so an anomalous response cannot bloat
/// the DB. Shared by the plain and the synced path so both behave the same.
String _capLyrics(String text) =>
    text.length > 100 * 1024 ? text.substring(0, 100 * 1024) : text;

/// lrclib fetch isolate entry point: only HTTP, no sqflite.
///
/// One request returns both the plain and the synced lyrics, which replaces
/// the old pair of separate requests (lrclib for synced, lyrics.ovh for
/// plain) with a single round trip in the common case.
///
/// Contract: {'lyrics': ..., 'synced': ...} on a hit, {'miss': true} when
/// lrclib has no entry for the track, and {} for anything transient that
/// must not poison the cache. 'synced' is null when the entry only carries
/// plain lyrics.
Future<Map<String, dynamic>> _lrclibFetchIsolate(
    Map<String, dynamic> params) async {
  final artist = params['artist'] as String;
  final title = params['title'] as String;
  if (artist.isEmpty || title.isEmpty) return <String, dynamic>{};
  final album = (params['album'] as String?)?.trim() ?? '';
  final client = http.Client();
  try {
    // Album is optional. Leaving it out makes lrclib fall back to matching by
    // artist and title alone, which is what we want when the album tag is
    // missing or unknown.
    final query = <String, String>{
      'artist_name': artist,
      'track_name': title,
    };
    if (album.isNotEmpty) query['album_name'] = album;
    final url = Uri.https('lrclib.net', '/api/get', query);
    final res = await client
        .get(url, headers: {'User-Agent': 'Swara/1.0'})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 429) return <String, dynamic>{'rateLimited': true};
    if (res.statusCode != 200) {
      // 404 is a definitive miss. 5xx and friends are transient.
      return res.statusCode == 404
          ? <String, dynamic>{'miss': true}
          : <String, dynamic>{};
    }
    dynamic data;
    try {
      data = jsonDecode(res.body);
    } catch (_) {
      // Not JSON (captive portal page): transient below.
      return <String, dynamic>{};
    }
    if (data is! Map) return <String, dynamic>{};
    final plain = (data['plainLyrics'] as String?)?.trim() ?? '';
    final synced = (data['syncedLyrics'] as String?)?.trim() ?? '';
    if (plain.isEmpty && synced.isEmpty) return <String, dynamic>{'miss': true};
    return <String, dynamic>{
      if (plain.isNotEmpty) 'lyrics': plain,
      if (synced.isNotEmpty) 'synced': synced,
    };
  } catch (_) {
    return <String, dynamic>{};
  } finally {
    client.close();
  }
}

/// Guesses and completes song metadata from the title/file name:
/// - Album art via the iTunes Search API (free, no API key)
/// - Lyrics via lyrics.ovh (free, no API key)
/// - Genre via the iTunes Search API
/// - Region guessed from the artist's home country (simple heuristic, manually editable)
class MetadataService {
  MetadataService._();
  static final MetadataService instance = MetadataService._();

  // Every metadata request (iTunes and lyrics) now runs inside an isolate
  // through compute(), and each isolate owns its own http.Client. That leaves
  // this class with no HTTP work of its own, so the shared client that used
  // to live here is gone. Each isolate closes its client when it finishes.

  /// Start of the 429 backoff window. While now is before this value,
  /// enrich calls skip the network so a burst of 429s does not repeat.
  /// Single 30 second window, no retry loop. Leftovers are retried on
  /// a later scan because they keep metadataScanned false.
  DateTime? _rateLimitUntil;

  static const _rateLimitBackoff = Duration(seconds: 30);

  /// Disk cache lifetimes for iTunes responses.
  static const _cacheHitTtl = Duration(days: 30);
  static const _cacheMissTtl = Duration(days: 90);

  /// Marker stored when iTunes has no result for a query, so later scans
  /// skip the network instead of refetching the same unknown song.
  static const _cacheMissMarker = 'MISS';

  /// Hoisted so the filename patterns are compiled once instead of twice per
  /// parsed file. A full rescan parses every file in the library.
  static final RegExp _filenameExtReg =
      RegExp(r'\.(mp3|flac|wav|m4a|ogg)$', caseSensitive: false);
  static final RegExp _leadingTrackNoReg = RegExp(r'^\d+[\.\-_\s]*');

  /// True while inside the 429 backoff window.
  bool get isRateLimited =>
      _rateLimitUntil != null && DateTime.now().isBefore(_rateLimitUntil!);

  /// Cleans the title from the file name, stripping track numbers, underscores, etc,
  /// and tries to split an "Artist - Title.mp3" pattern
  Map<String, String> parseFromFilename(String filePath) {
    String name = filePath.substring(filePath.lastIndexOf('/') + 1);
    name = name.replaceAll(_filenameExtReg, '');
    name = name.replaceAll(_leadingTrackNoReg, ''); // drop a leading track number
    name = name.replaceAll('_', ' ').trim();

    if (name.contains(' - ')) {
      final parts = name.split(' - ');
      return {'artist': parts[0].trim(), 'title': parts.sublist(1).join(' - ').trim()};
    }
    return {'artist': '', 'title': name};
  }

  /// Enrich one song from iTunes + lyrics.
  /// Returns true when iTunes rate limited the request (HTTP 429) or the
  /// backoff window is still active, so batch callers can stop at once.
  /// Returns false otherwise. Success behavior is unchanged.
  /// The iTunes HTTP call is dispatched to an isolate via compute() so
  /// network I/O does not hold the main thread.
  Future<bool> enrichSong(Song song, {bool bypassCache = false}) async {
    // Inside the backoff window: skip the network and leave the song
    // unscanned so a later scan retries it. No retry loop here.
    if (isRateLimited) {
      debugPrint('iTunes backoff active, skip enrich ${song.title}');
      return true;
    }
    // Serve a fresh disk cache entry before touching the network.
    // A cache hit applies the same fields as a live 200 response, and a
    // miss marker follows the same path as a live empty result.
    final cacheKey = _cacheKeyFor(song);
    // A manual "scan from the internet" must actually reach the network,
    // otherwise it silently replays a cache entry up to 30 days old.
    final cachedResponse =
        bypassCache ? null : await _readValidCache(cacheKey);
    if (cachedResponse != null) {
      if (cachedResponse != _cacheMissMarker) {
        // Corrupt cache entries return false and fall through to network.
        final applied = _applyItunesResponseBody(song, cachedResponse);
        if (applied) {
          song.region ??= 'Tidak diketahui';
          song.genre ??= 'Tidak diketahui';
          await fetchLyricsOnly(song, bypassCache: bypassCache);
          song.metadataScanned = true;
          await DBHelper.instance.upsertSong(song);
          return false;
        }
      } else {
        song.region ??= 'Tidak diketahui';
        song.genre ??= 'Tidak diketahui';
        await fetchLyricsOnly(song, bypassCache: bypassCache);
        song.metadataScanned = true;
        await DBHelper.instance.upsertSong(song);
        return false;
      }
    }
    bool rateLimited = false;
    bool itunesFailed = false;
    // Dispatch the iTunes HTTP call to an isolate so the main thread stays
    // responsive during network I/O. Cache/DB reads happen on the main
    // thread; only the HTTP round-trip moves off-thread.
    Map<String, dynamic>? itunesResult;
    try {
      itunesResult = await compute(
        _itunesLookupIsolate,
        <String, dynamic>{
          'artist': song.artist,
          'title': song.title,
        },
      );
    } catch (_) {
      itunesFailed = true;
    }
    if (itunesResult == null) {
      // compute() itself threw: transient, no MISS marker.
      itunesFailed = true;
    } else if (itunesResult['rateLimited'] == true) {
      rateLimited = true;
      _rateLimitUntil = DateTime.now().add(_rateLimitBackoff);
      debugPrint('iTunes rate-limit (429), skip enrich ${song.title}');
    } else if (itunesResult['miss'] == true) {
      // Definitive miss confirmed by the isolate (iTunes shaped answer
      // with no result). Cache it so later scans skip the network.
      try {
        await DBHelper.instance.putMetadataCache(cacheKey, _cacheMissMarker);
      } catch (_) {}
    } else {
      final body = itunesResult['body'] as String?;
      if (body == null || !_applyItunesResponseBody(song, body)) {
        // Empty map or an answer that does not apply: transient failure,
        // keep the song retryable instead of locking it as missing.
        itunesFailed = true;
      } else {
        // Cache the raw body so reinstalls and later scans reuse it in the
        // same format _applyItunesResponseBody already understands.
        try {
          await DBHelper.instance.putMetadataCache(cacheKey, body);
        } catch (_) {}
      }
    }
    if (rateLimited) {
      song.region ??= 'Tidak diketahui';
      song.genre ??= 'Tidak diketahui';
      song.metadataScanned = false;
      await DBHelper.instance.upsertSong(song);
      return true;
    }
    if (itunesFailed) {
      song.region ??= 'Tidak diketahui';
      song.genre ??= 'Tidak diketahui';
      await fetchLyricsOnly(song, bypassCache: bypassCache);
      song.metadataScanned = false;
      await DBHelper.instance.upsertSong(song);
      return false;
    }
    song.region ??= 'Tidak diketahui';
    song.genre ??= 'Tidak diketahui';

    // Fetch lyrics separately (small response, stays on main thread).
    await fetchLyricsOnly(song, bypassCache: bypassCache);

    song.metadataScanned = true;
    await DBHelper.instance.upsertSong(song);
    return false;
  }

  /// Enrich [songs] in order and stop at the first 429 or backoff hit.
  /// Returns true when the batch stopped early because of rate limiting.
  /// Remaining songs keep metadataScanned false and are retried on a
  /// later scan. There is no retry loop here by design.
  Future<bool> enrichBatch(List<Song> songs) async {
    for (final song in songs) {
      final limited = await enrichSong(song);
      if (limited) return true;
    }
    return false;
  }

  /// Fetch lyrics only WITHOUT overwriting title/artist/album - used by the
  /// PlayerScreen auto-fetch so manual user edits are never clobbered.
  /// Uses the shared metadata_cache table with a "lyrics|" key prefix:
  /// a MISS marker hit returns false without HTTP (90 day TTL, same as
  /// iTunes misses), a valid hit applies the cached lyrics directly.
  Future<bool> fetchLyricsOnly(Song song, {bool bypassCache = false}) async {
    // Never call the API with empty/unknown fields - guaranteed 404 + wasted quota.
    if (song.artist.isEmpty ||
        song.title.isEmpty ||
        song.artist == 'Unknown Artist' ||
        song.title == 'Unknown Title') {
      return false;
    }
    final lyricsKey = _lyricsCacheKeyFor(song);
    // Serve a fresh disk cache entry before touching the network, unless
    // the caller explicitly wants to bypass it (manual rescan).
    final cachedLyrics =
        bypassCache ? null : await _readValidCache(lyricsKey);
    if (cachedLyrics != null) {
      if (cachedLyrics == _cacheMissMarker) {
        // The plain lyrics are known absent, but the synced lyrics may still
        // be worth one lookup, so keep going instead of returning here.
        return await _fillSyncedFromLrclib(song);
      }
      if (cachedLyrics.isNotEmpty) {
        song.lyrics = cachedLyrics;
        // lrclib returns plain and synced together, so a song whose plain
        // lyrics came from cache has usually never been looked up there.
        // One lrclib request completes both at once instead of leaving the
        // synced view permanently empty. The plain lyrics stay as stored.
        await _fillSyncedFromLrclib(song);
        return true;
      }
      // Empty cached body should behave like a miss.
      return false;
    }
    // One lrclib request returns both the plain and the synced lyrics, so the
    // old pair of separate requests (lrclib then lyrics.ovh) collapses into a
    // single round trip whenever lrclib has the track.
    final lrclib = await _fetchFromLrclib(song);
    final plain = lrclib['lyrics'] as String?;
    final synced = lrclib['synced'] as String?;
    if (plain != null && plain.isNotEmpty) {
      song.lyrics = plain;
      await _cacheLyrics(lyricsKey, plain);
      return true;
    }
    if (lrclib['rateLimited'] == true) {
      // Transient: do not poison cache, retry later.
      return false;
    }
    if (plain == null && synced != null && synced.isNotEmpty) {
      // lrclib has only the synced form. Derive the plain view from it so the
      // song still reads as lyrics, and store the synced text alongside.
      final derived = _plainLyricsFromLrc(synced);
      if (derived.isNotEmpty) {
        song.lyrics = derived;
        await _cacheLyrics(lyricsKey, derived);
        return true;
      }
    }
    // lrclib has nothing for this track. Fall back to lyrics.ovh for the
    // plain lyrics, which is a different database and still worth asking.
    return await _fetchPlainFromLyricsOvh(song, lyricsKey);
  }

  /// One lrclib request for both lyric forms. Runs in an isolate so the
  /// network I/O does not hold the main thread.
  ///
  /// Returns {'lyrics': plain?, 'synced': lrc?} on a hit, {'miss': true}
  /// when lrclib has no entry, or {} on a transient failure.
  Future<Map<String, dynamic>> _fetchFromLrclib(Song song) async {
    try {
      final album = song.album.trim();
      return await compute(
        _lrclibFetchIsolate,
        <String, dynamic>{
          'artist': song.artist,
          'title': song.title,
          'album':
              (album.isEmpty || album == 'Unknown Album') ? '' : album,
        },
      );
    } catch (_) {
      // Transient (isolate or network failure): no MISS marker, retry later.
      return <String, dynamic>{};
    }
  }

  /// Store the synced lyrics for [song] when there are some, and report
  /// whether synced lyrics now exist. Never throws, so a DB write failure
  /// cannot break a lyric fetch that already succeeded.
  Future<bool> _cacheSynced(Song song, String? synced) async {
    if (synced == null || synced.isEmpty) return false;
    try {
      await applySyncedLyrics(song, synced);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fall back to lyrics.ovh for the plain lyrics only. Kept as a separate
  /// isolate entry because it cannot supply synced lyrics at all.
  Future<bool> _fetchPlainFromLyricsOvh(Song song, String lyricsKey) async {
    Map<String, dynamic> result;
    try {
      result = await compute(
        _lyricsFetchIsolate,
        <String, dynamic>{
          'artist': song.artist,
          'title': song.title,
        },
      );
    } catch (_) {
      // Transient (isolate or network failure): no MISS marker, retry later.
      return false;
    }
    final lyrics = result['lyrics'] as String?;
    if (lyrics != null && lyrics.isNotEmpty) {
      song.lyrics = lyrics;
      try {
        await DBHelper.instance.putMetadataCache(lyricsKey, lyrics);
      } catch (_) {}
      return true;
    }
    if (result['rateLimited'] == true) {
      // Transient: do not poison cache, retry later.
      return false;
    }
    if (result['miss'] == true) {
      // Definitive miss (404 or 200 with empty lyrics): remember so later
      // scans skip the network for 90 days. Anything else stays uncached
      // so a captive portal or a 5xx cannot lock the lyrics out.
      try {
        await DBHelper.instance.putMetadataCache(lyricsKey, _cacheMissMarker);
      } catch (_) {}
    }
    return false;
  }

  /// Make one lrclib request to complete the synced lyrics for a song whose
  /// plain lyrics are already known. Returns true when synced lyrics exist
  /// afterwards, from the DB or from lrclib.
  ///
  /// A stored lrclib entry is never refreshed here: the plain lyrics are
  /// already fixed by whatever stored them, and mixing two sources on one
  /// song would leave the two views out of step.
  Future<bool> _fillSyncedFromLrclib(Song song) async {
    final stored = await _readSynced(song);
    if (stored) return true;
    final lrclib = await _fetchFromLrclib(song);
    return _cacheSynced(song, lrclib['synced'] as String?);
  }

  /// Persist [lrc] for [song] as its synced lyrics and return it, mirroring
  /// what ensureSyncedLyrics returns. Never throws.
  Future<String?> applySyncedLyrics(Song song, String lrc) async {
    final capped = _capLyrics(lrc);
    try {
      await DBHelper.instance.setSyncedLyrics(song.id, capped);
    } catch (_) {
      // Cache write failure must never break the fetch.
    }
    return capped;
  }

  /// Whether synced lyrics are already stored for [song]. Never throws.
  Future<bool> _readSynced(Song song) async {
    try {
      final stored = await DBHelper.instance.getSyncedLyrics(song.id);
      return stored != null && stored.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Write one plain lyrics cache entry, capped, best effort. A cache failure
  /// never fails the fetch that already succeeded. The synced lyrics are
  /// stored in their own table by applySyncedLyrics, not here.
  Future<void> _cacheLyrics(String lyricsKey, String plain) async {
    try {
      await DBHelper.instance.putMetadataCache(lyricsKey, _capLyrics(plain));
    } catch (_) {}
  }

  /// Cache key for a song: "artist|title", lowercase and trimmed.
  String _cacheKeyFor(Song song) {
    return '${song.artist.trim().toLowerCase()}|${song.title.trim().toLowerCase()}';
  }

  /// Return stored synced (LRC) lyrics for [song], fetching them from
  /// lrclib.net when none is stored yet. Never throws and never touches
  /// the plain lyrics field, so plain lyric behavior stays unchanged.
  /// Returns the LRC text, or null when unavailable.
  ///
  /// The request runs in an isolate, matching the plain lyrics fetch, so the
  /// network never holds the main thread.
  Future<String?> ensureSyncedLyrics(Song song) async {
    try {
      final stored = await DBHelper.instance.getSyncedLyrics(song.id);
      if (stored != null && stored.trim().isNotEmpty) return stored;
    } catch (_) {
      // A DB read failure falls through to the network attempt below.
    }
    // Same guard as the plain lyric fetch: unknown fields always miss.
    if (song.artist.isEmpty ||
        song.title.isEmpty ||
        song.artist == 'Unknown Artist' ||
        song.title == 'Unknown Title') {
      return null;
    }
    final lrclib = await _fetchFromLrclib(song);
    final lrc = lrclib['synced'] as String?;
    if (lrc == null || lrc.isEmpty) return null;
    return applySyncedLyrics(song, lrc);
  }

  /// Lyrics cache key: "lyrics|artist|title", lowercase and trimmed, so
  /// lyric entries never collide with iTunes entries in the same table.
  String _lyricsCacheKeyFor(Song song) {
    return 'lyrics|${song.artist.trim().toLowerCase()}|${song.title.trim().toLowerCase()}';
  }

  /// Fresh cached iTunes body for [cacheKey], or null when absent/expired.
  /// Hits live 30 days, miss markers live 90 days. Cache read problems
  /// return null so enrichment falls back to the network.
  Future<String?> _readValidCache(String cacheKey) async {
    try {
      final cached = await DBHelper.instance.getMetadataCache(cacheKey);
      if (cached == null) return null;
      final response = cached['response'] ?? '';
      final fetchedAt = DateTime.tryParse(cached['fetchedAt'] ?? '');
      if (fetchedAt == null) return null;
      final ttl =
          response == _cacheMissMarker ? _cacheMissTtl : _cacheHitTtl;
      if (DateTime.now().difference(fetchedAt) > ttl) return null;
      return response;
    } catch (_) {
      return null;
    }
  }

  /// Apply a cached iTunes JSON body to [song] using the same field
  /// mapping as a live 200 response. Returns false when the body is
  /// corrupt so the caller can fall back to the network.
  bool _applyItunesResponseBody(Song song, String body) {
    try {
      final data = jsonDecode(body);
      if (data['resultCount'] == null || data['resultCount'] <= 0) {
        return false;
      }
      final track = data['results'][0];
      song.title = _sanitizeField(track['trackName'], song.title);
      song.artist = _sanitizeField(track['artistName'], song.artist);
      song.album = _sanitizeField(track['collectionName'], song.album);
      final genre = track['primaryGenreName']?.toString();
      song.genre = genre != null ? _sanitizeField(genre, genre) : song.genre;
      song.albumArtUrl =
          (track['artworkUrl100'] as String?)?.replaceAll('100x100', '600x600');
      song.region = _guessRegion(track['country']?.toString(), song.artist);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Limit metadata field length (keep giant HTML out of the DB) + trim.
  String _sanitizeField(dynamic raw, String fallback) {
    final s = (raw ?? fallback).toString().trim();
    if (s.isEmpty) return fallback;
    return s.length > 300 ? s.substring(0, 300) : s;
  }

  String _guessRegion(String? countryCode, String artist) {
    if (countryCode == null || countryCode.isEmpty) return 'Tidak diketahui';
    const map = {
      'IDN': 'Indonesia',
      'USA': 'Amerika Serikat',
      'GBR': 'Inggris',
      'KOR': 'Korea Selatan',
      'JPN': 'Jepang',
      'CAN': 'Kanada',
      'AUS': 'Australia',
    };
    return map[countryCode] ?? countryCode;
  }
}

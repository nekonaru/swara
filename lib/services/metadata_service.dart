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

/// Guesses and completes song metadata from the title/file name:
/// - Album art via the iTunes Search API (free, no API key)
/// - Lyrics via lyrics.ovh (free, no API key)
/// - Genre via the iTunes Search API
/// - Region guessed from the artist's home country (simple heuristic, manually editable)
class MetadataService {
  MetadataService._();
  static final MetadataService instance = MetadataService._();

  /// Single shared HTTP client for all metadata requests (iTunes + lyrics).
  /// Created once and never closed because this singleton lives for the
  /// whole app lifetime, which avoids socket churn from one-shot http.get.
  final http.Client _client = http.Client();

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

  /// True while inside the 429 backoff window.
  bool get isRateLimited =>
      _rateLimitUntil != null && DateTime.now().isBefore(_rateLimitUntil!);

  /// Cleans the title from the file name, stripping track numbers, underscores, etc,
  /// and tries to split an "Artist - Title.mp3" pattern
  Map<String, String> parseFromFilename(String filePath) {
    String name = filePath.substring(filePath.lastIndexOf('/') + 1);
    name = name.replaceAll(RegExp(r'\.(mp3|flac|wav|m4a|ogg)$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'^\d+[\.\-_\s]*'), ''); // drop a leading track number
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
    // Best effort synced lyrics fetch (lrclib). Runs regardless of the
    // plain lyric outcome below and never changes its return value.
    try {
      await ensureSyncedLyrics(song);
    } catch (_) {
      // Synced fetch must never break the plain lyric fetch.
    }
    final lyricsKey = _lyricsCacheKeyFor(song);
    // Serve a fresh disk cache entry before touching the network, unless
    // the caller explicitly wants to bypass it (manual rescan).
    final cachedLyrics =
        bypassCache ? null : await _readValidCache(lyricsKey);
    if (cachedLyrics != null) {
      if (cachedLyrics == _cacheMissMarker) {
        return false;
      }
      if (cachedLyrics.isNotEmpty) {
        song.lyrics = cachedLyrics;
        return true;
      }
      // Empty cached body should behave like a miss.
      return false;
    }
    // Dispatch the lyrics HTTP call to an isolate so the main thread stays
    // responsive during network I/O. Cache/DB reads/writes stay on main.
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

  /// Cache key for a song: "artist|title", lowercase and trimmed.
  String _cacheKeyFor(Song song) {
    return '${song.artist.trim().toLowerCase()}|${song.title.trim().toLowerCase()}';
  }

  /// Return stored synced (LRC) lyrics for [song], fetching them from
  /// lrclib.net when none is stored yet. Never throws and never touches
  /// the plain lyrics field, so plain lyric behavior stays unchanged.
  /// Returns the LRC text, or null when unavailable.
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
    try {
      final params = {
        'artist_name': song.artist,
        'track_name': song.title,
      };
      final album = song.album.trim();
      if (album.isNotEmpty && album != 'Unknown Album') {
        params['album_name'] = album;
      }
      final url = Uri.https('lrclib.net', '/api/get', params);
      final res = await _client
          .get(url, headers: {'User-Agent': 'Swara/1.0'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final lrc = data is Map ? data['syncedLyrics']?.toString().trim() : null;
      if (lrc == null || lrc.isEmpty) return null;
      // Cap at 100KB so the DB does not bloat on anomalous responses.
      final capped = lrc.length > 100 * 1024 ? lrc.substring(0, 100 * 1024) : lrc;
      try {
        await DBHelper.instance.setSyncedLyrics(song.id, capped);
      } catch (_) {
        // Cache write failure must never break the fetch.
      }
      return capped;
    } catch (_) {
      return null;
    }
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

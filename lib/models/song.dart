import 'dart:convert';
import 'dart:io';

/// Prefix marking a lyrics DB value as gzip + base64 compressed.
const String _lyricsGzipPrefix = 'gz:';

/// Encodes lyrics for DB storage using gzip + base64 with a 'gz:' marker.
///
/// Null stays null and empty stays empty so those cheap cases
/// never pay the compression cost.
String? encodeLyricsForDb(String? lyrics) {
  // Keep null and empty untouched for cheap storage and simple checks.
  if (lyrics == null || lyrics.isEmpty) {
    return lyrics;
  }
  final List<int> gzipped = gzip.encode(utf8.encode(lyrics));
  return '$_lyricsGzipPrefix${base64Encode(gzipped)}';
}

/// Decodes a lyrics DB value, accepting both new and legacy formats.
///
/// Plaintext rows written before compression pass through unchanged.
/// Values with the 'gz:' marker are decoded, and a corrupt payload
/// returns the original string instead of throwing.
/// Non-string values return null so callers never hit a cast error.
String? decodeLyricsFromDb(dynamic value) {
  // Legacy plaintext (or null) passes through unchanged.
  if (value == null) {
    return null;
  }
  // Guard against corrupt column types (for example an int left by a bad
  // write). Null is safer than echoing a non-string back to a String field.
  if (value is! String) {
    return null;
  }
  if (!value.startsWith(_lyricsGzipPrefix)) {
    return value;
  }
  try {
    final String payload = value.substring(_lyricsGzipPrefix.length);
    final List<int> gzipped = base64Decode(payload);
    final List<int> raw = gzip.decode(gzipped);
    return utf8.decode(raw);
  } catch (_) {
    // Corrupt data must never break song loading, keep the raw string.
    return value;
  }
}

class Song {
  final int id;
  final String filePath;
  String title;
  String artist;
  String album;
  String? genre;
  String? region; // song origin country/area, detected from artist/metadata
  String? albumArtPath; // local path to the cached cover
  String? albumArtUrl; // remote URL from the API when not cached yet
  String? lyrics;
  int durationMs;
  bool isFavorite;
  DateTime? addedAt;
  bool metadataScanned;

  Song({
    required this.id,
    required this.filePath,
    required this.title,
    required this.artist,
    required this.album,
    this.genre,
    this.region,
    this.albumArtPath,
    this.albumArtUrl,
    this.lyrics,
    this.durationMs = 0,
    this.isFavorite = false,
    this.addedAt,
    this.metadataScanned = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'filePath': filePath,
        'title': title,
        'artist': artist,
        'album': album,
        'genre': genre,
        'region': region,
        'albumArtPath': albumArtPath,
        'albumArtUrl': albumArtUrl,
        'lyrics': encodeLyricsForDb(lyrics),
        'durationMs': durationMs,
        'isFavorite': isFavorite ? 1 : 0,
        'addedAt': addedAt?.toIso8601String(),
        'metadataScanned': metadataScanned ? 1 : 0,
      };

  factory Song.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    final rawPath = map['filePath'];
    if (rawId is! int || rawPath is! String || rawPath.isEmpty) {
      throw const FormatException('Corrupt songs row: id/filePath is not valid');
    }
    DateTime? parsedAddedAt;
    final rawAdded = map['addedAt'];
    if (rawAdded is String && rawAdded.isNotEmpty) {
      parsedAddedAt = DateTime.tryParse(rawAdded);
    }
    return Song(
      id: rawId,
      filePath: rawPath,
      title: (map['title'] as String?)?.isNotEmpty == true
          ? map['title'] as String
          : 'Unknown Title',
      artist: (map['artist'] as String?)?.isNotEmpty == true
          ? map['artist'] as String
          : 'Unknown Artist',
      album: (map['album'] as String?)?.isNotEmpty == true
          ? map['album'] as String
          : 'Unknown Album',
        genre: map['genre'] as String?,
        region: map['region'] as String?,
        albumArtPath: map['albumArtPath'] as String?,
        albumArtUrl: map['albumArtUrl'] as String?,
        lyrics: decodeLyricsFromDb(map['lyrics']),
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        isFavorite: (map['isFavorite'] ?? 0) == 1,
        addedAt: parsedAddedAt,
        metadataScanned: (map['metadataScanned'] ?? 0) == 1,
      );
  }
}

/// One listening-history row, recorded each time a song play session ends/stops.
class ListeningEntry {
  final int? id;
  final int songId;
  final DateTime timestamp;
  final int listenedMs; // how long was actually listened

  ListeningEntry({
    this.id,
    required this.songId,
    required this.timestamp,
    required this.listenedMs,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'songId': songId,
        'timestamp': timestamp.toIso8601String(),
        'listenedMs': listenedMs,
      };

  factory ListeningEntry.fromMap(Map<String, dynamic> map) {
    final rawTs = map['timestamp'];
    final parsedTs = rawTs is String ? DateTime.tryParse(rawTs) : null;
    return ListeningEntry(
      id: map['id'] as int?,
      songId: (map['songId'] as num?)?.toInt() ?? 0,
      timestamp: parsedTs ?? DateTime.fromMillisecondsSinceEpoch(0),
      listenedMs: (map['listenedMs'] as num?)?.toInt() ?? 0,
    );
  }
}

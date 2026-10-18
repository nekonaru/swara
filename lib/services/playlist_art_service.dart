import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

// Automatic playlist cover art built as a small collage.
//
// Picks up to 4 songs that have a local cover file in [Song.albumArtPath],
// composes a 400x400 grid, and stores it under the app documents directory
// as playlist_art_<id>.jpg. All failures return null and never throw, so
// callers can always fall back to an icon.
//
// The decode and resize run in a background isolate. A 2000x2000 cover
// decodes to roughly 16 MB of pixels, and doing that for four images on the
// UI isolate froze the app for seconds whenever a playlist changed.
class PlaylistArtService {
  PlaylistArtService._();

  static const int artSize = 400;
  static const int cellSize = 200;
  static const int maxSources = 4;

  // Content fingerprint per playlist: which songs and which covers went into
  // the stored collage. The old guard compared the song COUNT only, so
  // removing one song and adding another kept the stale collage forever.
  static final Map<int, String> _builtFingerprints = <int, String>{};

  static String? _docsPath;

  /// Stable fingerprint of the songs and the covers they contribute.
  static String fingerprintOf(List<Song> songs) {
    final parts = <String>[];
    for (final s in songs) {
      final art = s.albumArtPath;
      if (art == null || art.isEmpty) continue;
      parts.add('${s.id}@$art');
      if (parts.length >= maxSources) break;
    }
    if (parts.isEmpty) return 'empty';
    parts.sort();
    return parts.join(',');
  }

  static String _fileName(int playlistId) => 'playlist_art_$playlistId.jpg';

  static Future<Directory?> _artDir() async {
    try {
      var base = _docsPath;
      if (base == null) {
        final docs = await getApplicationDocumentsDirectory();
        base = docs.path;
        _docsPath = base;
      }
      final dir = Directory(p.join(base, 'playlist_art'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  // File location for a playlist cover, or null when none is cached.
  // Read only, never builds. Used by UI tiles and headers.
  static Future<File?> existingArt(int playlistId) async {
    try {
      final dir = await _artDir();
      if (dir == null) return null;
      final file = File(p.join(dir.path, _fileName(playlistId)));
      if (await file.exists() && await file.length() > 0) {
        return file;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Build (or reuse) the collage for [playlistId] from [songs].
  // Returns the art file, or null when there is nothing to show
  // or any step fails. Never throws.
  static Future<File?> buildPlaylistArt(
      int playlistId, List<Song> songs) async {
    try {
      final dir = await _artDir();
      if (dir == null) return null;
      final outFile = File(p.join(dir.path, _fileName(playlistId)));

      // Collect up to 4 songs with a readable local cover file.
      final sources = <Song>[];
      final sourceFiles = <String>[];
      for (final song in songs) {
        if (sources.length >= maxSources) break;
        final artPath = song.albumArtPath;
        if (artPath == null || artPath.isEmpty) continue;
        try {
          final f = File(artPath);
          if (f.existsSync() && f.lengthSync() > 0) {
            sources.add(song);
            sourceFiles.add(f.path);
          }
        } catch (_) {
          // Skip unreadable entries, keep scanning the rest.
        }
      }

      // No local covers: drop any stale collage so the UI shows fallback.
      if (sources.isEmpty) {
        try {
          if (await outFile.exists()) {
            await outFile.delete();
          }
        } catch (_) {
          // Best effort only.
        }
        _builtFingerprints.remove(playlistId);
        return null;
      }

      // Reuse the stored collage only when the same songs contributed the
      // same covers. Comparing the song count alone kept a stale collage
      // whenever one song was swapped for another of equal length.
      final fingerprint = fingerprintOf(sources);
      try {
        if (_builtFingerprints[playlistId] == fingerprint &&
            await outFile.exists() &&
            await outFile.length() > 0) {
          return outFile;
        }
      } catch (_) {
        // Fall through to rebuild on any stat failure.
      }

      // Compose off the UI isolate: decoding a full resolution cover is the
      // expensive part and it must never block a frame.
      final sourcePaths = sourceFiles.take(maxSources).toList();
      final Uint8List? jpg = await Isolate.run(() => _compose(sourcePaths));
      if (jpg == null || jpg.isEmpty) return null;
      // Write through a temp file and rename, so a kill in the middle of the
      // write cannot leave a half written collage that then looks valid.
      final tempFile = File('${outFile.path}.part');
      try {
        await tempFile.writeAsBytes(jpg, flush: true);
        await tempFile.rename(outFile.path);
      } catch (_) {
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {
          // Best effort cleanup only.
        }
        return null;
      }
      _builtFingerprints[playlistId] = fingerprint;
      return outFile;
    } catch (_) {
      return null;
    }
  }

  /// Build the collage bytes. Runs in a background isolate, so it may only
  /// use top level functions and plain data.
  static Uint8List? _compose(List<String> paths) {
    final canvas = img.Image(width: artSize, height: artSize);
    img.fill(canvas, color: img.ColorRgb8(158, 158, 158));
    if (paths.length == 1) {
      final full = _decodeSized(File(paths.first), artSize, artSize);
      if (full != null) {
        img.compositeImage(canvas, full, dstX: 0, dstY: 0);
      }
    } else {
      for (var i = 0; i < paths.length && i < maxSources; i++) {
        final cell = _decodeSized(File(paths[i]), cellSize, cellSize);
        if (cell == null) continue;
        img.compositeImage(canvas, cell,
            dstX: (i % 2) * cellSize, dstY: (i ~/ 2) * cellSize);
      }
    }
    return img.encodeJpg(canvas, quality: 85);
  }

  // Delete the cached collage for [playlistId]. Never throws.
  static Future<void> clearPlaylistArt(int playlistId) async {
    _builtFingerprints.remove(playlistId);
    try {
      final dir = await _artDir();
      if (dir == null) return;
      final file = File(p.join(dir.path, _fileName(playlistId)));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best effort only.
    }
  }

  // Decode [file] and scale it to exactly [width]x[height] for the grid.
  // Returns null when decoding or resizing fails.
  static img.Image? _decodeSized(File file, int width, int height) {
    try {
      final bytes = file.readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      return img.copyResize(decoded, width: width, height: height);
    } catch (_) {
      return null;
    }
  }
}

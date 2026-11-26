import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Disk cache for cover art that is embedded in the audio files themselves.
///
/// Remote covers are handled by [ArtCacheService]; this service handles the
/// covers that never reach the network: songs whose artwork is stored inside
/// the file (ID3 APIC, FLAC picture blocks, MP4 covr). The artwork is
/// extracted lazily on first display, written under the app documents dir as
/// `embedded_art/<songId>.jpg`, and reused forever after.
///
/// All failures resolve to null and never throw, so callers can fall back to
/// the network cover or an icon.
class EmbeddedArtService {
  EmbeddedArtService._();
  static final EmbeddedArtService instance = EmbeddedArtService._();

  // Extracted files are cached forever: they only change when the user
  // edits a file's tags, and a stale thumbnail is harmless.
  static const String _dirName = 'embedded_art';
  // One platform client for the whole app. Constructing it per artwork probe
  // made the first scroll through a large library pay a setup cost per row.
  static final OnAudioQuery _query = OnAudioQuery();
  static const MethodChannel _channel = MethodChannel('swara/file_rename');

  String? _dirPath;
  // Memory first answer for already resolved files, so the build path
  // never touches the disk. Bounded by the library size, like ArtCache.
  final Map<int, String> _knownPaths = {};
  // Song ids we already tried and found no embedded art for, so an icon is
  // not re-queried on every rebuild.
  final Set<int> _missing = {};
  // Concurrent calls for the same id share one MediaStore query.
  final Map<int, Future<String?>> _inFlight = {};
  // A folder that reported no sidecar once will not be probed again during
  // the same session. The first fling through an untagged album otherwise
  // issues one native call per row.
  final Set<String> _noSidecarFolders = <String>{};
  bool _indexPrimed = false;

  // Sync fast path: only the in memory index, safe to call from build.
  String? peekSync(int songId) {
    if (songId <= 0) return null;
    return _knownPaths[songId];
  }

  // True when we already know this song has no embedded art after a probe.
  bool isKnownMissing(int songId) => _missing.contains(songId);

  Future<String?> _dir() async {
    try {
      if (_dirPath != null) return _dirPath;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, _dirName));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _dirPath = dir.path;
      await _preloadIndex(dir);
      return dir.path;
    } catch (_) {
      return null;
    }
  }

  // List the cache dir once per run so peekSync can answer without the disk.
  Future<void> _preloadIndex(Directory dir) async {
    if (_indexPrimed) return;
    _indexPrimed = true;
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('embedded_') || !name.endsWith('.jpg')) continue;
        final id = int.tryParse(name.substring(9, name.length - 4));
        if (id == null || id <= 0) continue;
        // Only paths are cached here; content validity is confirmed when
        // the file is read or rewritten.
        _knownPaths[id] = entity.path;
      }
    } catch (_) {
      // Best effort index only.
    }
  }

  /// Resolve the cached embedded cover for [songId], extracting and caching
  /// it on first use. Returns the absolute file path, or null when the song
  /// has no embedded artwork or anything failed.
  Future<String?> resolveArtFile(int songId, {String? filePath}) {
    if (songId <= 0) return Future.value(null);
    final hit = peekSync(songId);
    if (hit != null) return Future.value(hit);
    if (_missing.contains(songId)) return Future.value(null);
    final pending = _inFlight[songId];
    if (pending != null) return pending;
    final task = _resolveInner(songId, filePath);
    _inFlight[songId] = task;
    task.whenComplete(() => _inFlight.remove(songId));
    return task;
  }

  Future<String?> _resolveInner(int songId, String? filePath) async {
    try {
      final dirPath = await _dir();
      if (dirPath == null) return null;
      final file = File(p.join(dirPath, 'embedded_$songId.jpg'));
      if (await file.exists() && await file.length() > 0) {
        final head = await _header(file);
        if (head != null && _looksLikeImage(head)) {
          _knownPaths[songId] = file.path;
          return file.path;
        }
        // A truncated file from an interrupted copy must not be served.
        try {
          await file.delete();
        } catch (_) {}
      }
      List<int>? bytes;
      try {
        bytes = await _query.queryArtwork(
          songId,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: 200,
        );
      } catch (_) {
        // A MediaStore failure must not hide a valid folder sidecar.
        bytes = null;
      }
      if (bytes == null || bytes.isEmpty) {
        // No embedded tag: look for a sidecar in the song's own folder. This
        // keeps untagged collections offline through MediaStore.
        final folderArt = await _folderArt(songId, filePath, file);
        if (folderArt != null) return folderArt;
        _missing.add(songId);
        return null;
      }
      // No flush: a thumbnail is rebuilt from the audio file if a crash
      // loses it, while an fsync per cover stalled the first scroll.
      await file.writeAsBytes(bytes);
      _knownPaths[songId] = file.path;
      return file.path;
    } catch (_) {
      _missing.add(songId);
      return null;
    }
  }

  /// Look for cover.jpg / folder.jpg in the song's folder through the native
  /// MediaStore helper and copy it into the private art cache. Dart never
  /// touches a raw image path, so scoped storage rules are respected.
  Future<String?> _folderArt(
    int songId,
    String? filePath,
    File cacheFile,
  ) async {
    if (filePath == null || filePath.isEmpty) return null;
    final folder = p.dirname(filePath);
    if (_noSidecarFolders.contains(folder)) return null;
    String? path;
    try {
      path = await _channel.invokeMethod<String>('folderArt', {
        'folderPath': folder,
        'names': const [
          'cover.jpg',
          'folder.jpg',
          'Cover.jpg',
          'Folder.jpg',
          'cover.png',
          'folder.png',
        ],
        'cachePath': cacheFile.path,
      });
    } catch (_) {
      _noSidecarFolders.add(folder);
      await _discard(cacheFile);
      return null;
    }
    if (path == null || path.isEmpty) {
      _noSidecarFolders.add(folder);
      await _discard(cacheFile);
      return null;
    }
    // A corrupt or non-image sidecar must not enter the index, otherwise the
    // decode fails on every rebuild. Check the header before caching.
    final head = await _header(cacheFile);
    if (head == null || !_looksLikeImage(head)) {
      _noSidecarFolders.add(folder);
      await _discard(cacheFile);
      return null;
    }
    _knownPaths[songId] = cacheFile.path;
    return cacheFile.path;
  }

  static Future<List<int>?> _header(File file) async {
    try {
      return await file.openRead().expand((c) => c).take(12).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _discard(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static bool _looksLikeImage(List<int> h) {
    if (h.length < 4) return false;
    if (h[0] == 0xFF && h[1] == 0xD8 && h[2] == 0xFF) return true; // JPEG
    if (h[0] == 0x89 && h[1] == 0x50 && h[2] == 0x4E && h[3] == 0x47) {
      return true; // PNG
    }
    if (h.length >= 12 &&
        h[0] == 0x52 && h[1] == 0x49 && h[2] == 0x46 && h[3] == 0x46 &&
        h[8] == 0x57 && h[9] == 0x45 && h[10] == 0x42 && h[11] == 0x50) {
      return true; // WebP
    }
    return false;
  }

  // Drop a song's embedded cover from every index. Used after a metadata
  // edit that could have changed the embedded artwork.
  void evict(int songId) {
    _knownPaths.remove(songId);
    _missing.remove(songId);
    // A tag edit could replace the cover, so re-probe sidecars too.
    _noSidecarFolders.clear();
  }

  /// Total bytes and file count of the extracted embedded art cache.
  static Future<int> totalBytes() async {
    var bytes = 0;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, _dirName));
      if (!await dir.exists()) return 0;
      await for (final e in dir.list()) {
        if (e is File) bytes += await e.length();
      }
    } catch (_) {
      // Report 0 rather than throw.
    }
    return bytes;
  }

  static Future<int> totalFiles() async {
    var count = 0;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, _dirName));
      if (!await dir.exists()) return 0;
      await for (final e in dir.list()) {
        if (e is File) count++;
      }
    } catch (_) {
      // Report 0 rather than throw.
    }
    return count;
  }

  /// Delete every extracted embedded cover and reset the in memory indexes,
  /// so the next display re-probes the files. Used by Clear art cache.
  static Future<int> clearCache() async {
    var deleted = 0;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, _dirName));
      if (await dir.exists()) {
        await for (final e in dir.list()) {
          if (e is File) {
            try {
              await e.delete();
              deleted++;
            } catch (_) {
              // Keep going when one file cannot be deleted.
            }
          }
        }
      }
    } catch (_) {
      // Partial progress is reported, not thrown.
    }
    instance._knownPaths.clear();
    instance._missing.clear();
    instance._inFlight.clear();
    instance._noSidecarFolders.clear();
    instance._indexPrimed = false;
    instance._dirPath = null;
    return deleted;
  }
}

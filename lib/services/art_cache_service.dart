import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Disk cache for remote album art.
//
// Remote covers are downloaded once into the app temp dir and reused
// across launches, so lists and players do not refetch them every time.
// All failures return null and never throw, so callers can fall back
// to Image.network or an icon.
class ArtCacheService {
  ArtCacheService._();
  static final ArtCacheService instance = ArtCacheService._();

  // Total cache budget. Oldest files are evicted first (best effort).
  static const int maxTotalBytes = 100 * 1024 * 1024;

  String? _dirPath;
  final Map<String, Future<File?>> _inflight = {};
  final Map<String, String> _knownPaths = {};
  // Last time each cache file's modified time was refreshed, to throttle the
  // setLastModified syscall in _touch. Bounded by the cache file count.
  final Map<String, DateTime> _lastTouchedAt = {};
  static const _touchInterval = Duration(minutes: 10);
  // Hash to path index built once from the cache directory listing, so the
  // synchronous build path can answer without touching the disk.
  final Map<String, String> _knownPathsByHash = {};
  bool _indexPreloaded = false;

  // The hash portion of the cache file name, used as the index key.
  String _hashOf(String url) {
    final name = _fileNameFor(url);
    return name.substring(4, name.length - 4);
  }

  // Simple non crypto hash of the URL, stable across launches.
  // Two 32 bit lanes are combined to keep collision risk low.
  String _fileNameFor(String url) {
    var h1 = 0x811c9dc5;
    var h2 = 0x811c9dc5 ^ 0x5bd1e995;
    for (final c in url.codeUnits) {
      h1 ^= c;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
      h2 ^= c;
      h2 = ((h2 << 5) + h2 + (c ^ 0x9e3779b9)) & 0xFFFFFFFF;
    }
    final a = h1.toRadixString(16).padLeft(8, '0');
    final b = h2.toRadixString(16).padLeft(8, '0');
    return 'art_${a}_$b.jpg';
  }

  Future<Directory?> _cacheDir() async {
    try {
      if (_dirPath != null) {
        final dir = Directory(_dirPath!);
        if (await dir.exists()) {
          await _preloadIndex(dir);
          return dir;
        }
      }
      final tmp = await getTemporaryDirectory();
      final dir = Directory(p.join(tmp.path, 'art_cache'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _dirPath = dir.path;
      await _preloadIndex(dir);
      return dir;
    } catch (_) {
      return null;
    }
  }

  // Fill the url to path index once, so peekSync can stay memory only.
  // Runs a single time per app run; a failure just means the async resolve
  // path does the work per cover.
  Future<void> _preloadIndex(Directory dir) async {
    if (_indexPreloaded) return;
    _indexPreloaded = true;
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('art_') || !name.endsWith('.jpg')) continue;
        final hash = name.substring(4, name.length - 4);
        if (!hash.contains('_')) continue;
        // Only the path is cached here. Whether the file has content is
        // confirmed by the async path, so a truncated file is never shown as
        // a valid image.
        _knownPathsByHash[hash] = entity.path;
      }
    } catch (_) {
      // Best effort index only.
    }
  }

  // Sync fast path for already resolved files. Memory only on purpose: this
  // runs from build(), so touching the disk here meant two syscalls per cover
  // per frame while scrolling. Disk confirmation happens in the async resolve
  // path, and _cacheDir preloads the index once at startup.
  File? peekSync(String url) {
    final path = _knownPaths[url];
    if (path != null) return File(path);
    final indexed = _knownPathsByHash[_hashOf(url)];
    if (indexed == null) return null;
    _knownPaths[url] = indexed;
    return File(indexed);
  }

  // Resolve the cached file for [url], downloading it once on a miss.
  // Returns the file when it exists or the download succeeds,
  // otherwise null. Concurrent calls for the same URL share one task.
  Future<File?> resolveArtFile(String url) {
    if (url.isEmpty) return Future.value(null);
    final hit = peekSync(url);
    if (hit != null) {
      // Refresh recency in the background for LRU eviction.
      _touch(hit);
      return Future.value(hit);
    }
    final pending = _inflight[url];
    if (pending != null) return pending;
    final task = _resolveInner(url);
    _inflight[url] = task;
    task.whenComplete(() => _inflight.remove(url));
    return task;
  }

  Future<File?> _resolveInner(String url) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return null;
      final file = File(p.join(dir.path, _fileNameFor(url)));
      if (await file.exists()) {
        if (await file.length() > 0) {
          _knownPaths[url] = file.path;
          _touch(file);
          return file;
        } else {
          await file.delete();
        }
      }
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) return null;
      final res = await http
          .get(uri, headers: const {'Accept': 'image/*'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    final contentType = res.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().startsWith('image/')) return null;
    if (res.bodyBytes.length > 5 * 1024 * 1024) return null;
    final b = res.bodyBytes;
    final isJpeg = b.length >= 2 && b[0] == 0xFF && b[1] == 0xD8;
    final isPng = b.length >= 8 &&
        b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    if (!isJpeg && !isPng) return null;
    await file.writeAsBytes(res.bodyBytes, flush: true);
      _knownPaths[url] = file.path;
      await _enforceCap(dir);
      return file;
    } catch (_) {
      return null;
    }
  }

  // Best effort LRU touch. Never throws.
  void _touch(File file) {
    // Updating the modified time is what keeps a file from being evicted, but
    // it is a filesystem syscall per tile init, and scrolling inits hundreds
    // of tiles per minute for the same covers. One touch per file every 10
    // minutes keeps the LRU order fresh at a fraction of the syscalls.
    final now = DateTime.now();
    final last = _lastTouchedAt[file.path];
    if (last != null && now.difference(last) < _touchInterval) return;
    _lastTouchedAt[file.path] = now;
    try {
      file.setLastModified(now);
    } catch (_) {
      // Ignore.
    }
  }

  // Delete oldest files until the folder fits the budget. Best effort.
  Future<void> _enforceCap(Directory dir) async {
    try {
      final entries = await dir.list().toList();
      final files = <File>[];
      for (final e in entries) {
        if (e is File &&
            p.basename(e.path).startsWith('art_') &&
            p.basename(e.path).endsWith('.jpg')) {
          files.add(e);
        }
      }
      var total = 0;
      final sizes = <String, int>{};
      final times = <String, DateTime>{};
      for (final f in files) {
        try {
          final stat = await f.stat();
          sizes[f.path] = stat.size;
          times[f.path] = stat.modified;
          total += stat.size;
        } catch (_) {
          // Skip unreadable entries.
        }
      }
      if (total <= maxTotalBytes) return;
      files.sort((a, b) {
        final ta = times[a.path] ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = times[b.path] ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ta.compareTo(tb);
      });
      for (final f in files) {
        if (total <= maxTotalBytes) break;
        try {
          await f.delete();
          total -= sizes[f.path] ?? 0;
          // Both indexes must drop the evicted file, otherwise the sync
          // build path would keep handing out a deleted file.
          _knownPaths.removeWhere((_, v) => v == f.path);
          _lastTouchedAt.remove(f.path);
          final base = p.basename(f.path);
          if (base.startsWith('art_') && base.endsWith('.jpg')) {
            _knownPathsByHash.remove(base.substring(4, base.length - 4));
          }
        } catch (_) {
          // Keep going with the next file.
        }
      }
    } catch (_) {
      // Cache eviction must never break the UI.
    }
  }
}

// Small cover widget backed by [ArtCacheService].
//
// Shows the disk file when available, otherwise the plain network image
// (so behavior and look stay the same as before), and [fallback] when
// both fail. The future is stored in state, so parent rebuilds do not
// restart the lookup and FutureBuilder needs no manual dispose.
class CachedArtImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget fallback;
  final Widget? loading;
  final bool gaplessPlayback;

  const CachedArtImage({
    super.key,
    required this.url,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.loading,
    this.gaplessPlayback = true,
  });

  @override
  State<CachedArtImage> createState() => _CachedArtImageState();
}

class _CachedArtImageState extends State<CachedArtImage> {
  late Future<File?> _future;

  @override
  void initState() {
    super.initState();
    _future = ArtCacheService.instance.resolveArtFile(widget.url);
  }

  @override
  void didUpdateWidget(CachedArtImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = ArtCacheService.instance.resolveArtFile(widget.url);
    }
  }

  Widget _networkFallback() {
    return Image.network(
      widget.url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: widget.gaplessPlayback,
      loadingBuilder: widget.loading == null
          ? null
          : (context, child, progress) {
              if (progress == null) return child;
              return widget.loading!;
            },
      errorBuilder: (_, __, ___) => widget.fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sync fast path avoids any flicker for files already on disk.
    final hit = ArtCacheService.instance.peekSync(widget.url);
    if (hit != null) {
      return Image.file(
        hit,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        gaplessPlayback: widget.gaplessPlayback,
        errorBuilder: (_, __, ___) => _networkFallback(),
      );
    }
    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            widget.loading != null) {
          return widget.loading!;
        }
        final file = snapshot.data;
        if (file != null) {
          return Image.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            cacheWidth: widget.cacheWidth,
            gaplessPlayback: widget.gaplessPlayback,
            errorBuilder: (_, __, ___) => _networkFallback(),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _networkFallback();
        }
        return _networkFallback();
      },
    );
  }
}

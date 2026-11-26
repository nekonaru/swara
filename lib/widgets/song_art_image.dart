import 'dart:io';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/art_cache_service.dart';
import '../services/embedded_art_service.dart';

/// Shared cover art widget with a single resolver for every screen.
///
/// Resolution order, per display:
/// 1. [Song.albumArtPath] when it points at a readable local file (already
///    downloaded art kept by earlier versions of the app),
/// 2. embedded cover art stored inside the audio file, extracted and cached
///    under app documents (falling back to this even when albumArtUrl is
///    set, so embedded art always wins over network fetch),
/// 3. the remote cover via [CachedArtImage] with disk caching and an
///    optional fallback chain,
/// 4. [fallback] when none of the above produced anything.
class SongArtImage extends StatefulWidget {
  final Song song;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget fallback;
  final bool gaplessPlayback;

  const SongArtImage({
    super.key,
    required this.song,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.gaplessPlayback = true,
  });

  // Paths that were seen to decode successfully. Bounded, because a long
  // session can visit far more covers than the art cache keeps on disk.
  static final Set<String> _validCoverPaths = <String>{};
  static const int _maxValidPaths = 4096;

  static void noteValidCover(String path) {
    if (_validCoverPaths.length >= _maxValidPaths) _validCoverPaths.clear();
    _validCoverPaths.add(path);
  }

  /// Forget remembered paths after the art cache is cleared, so rows probe
  /// again instead of trusting a path that no longer exists.
  static void clearCoverCache() => _validCoverPaths.clear();

  @override
  State<SongArtImage> createState() => _SongArtImageState();
}

class _SongArtImageState extends State<SongArtImage> {
  // Resolved embedded path for this song, or null while unresolved/missing.
  String? _embeddedPath;
  // True once we know this song has no embedded art (checked on disk).
  bool _embeddedChecked = false;
  // A referenced local file failed to decode. Do not retry it every frame.
  bool _localArtFailed = false;

  @override
  void didUpdateWidget(covariant SongArtImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _localArtFailed = false;
      _embeddedChecked = false;
      _embeddedPath = EmbeddedArtService.instance.peekSync(widget.song.id);
    } else if (oldWidget.song.albumArtPath != widget.song.albumArtPath) {
      _localArtFailed = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _embeddedPath = EmbeddedArtService.instance.peekSync(widget.song.id);
    _embeddedChecked = _embeddedPath != null ||
        EmbeddedArtService.instance.isKnownMissing(widget.song.id);
    // A usable local or cached remote cover is displayed without the
    // embedded probe. Avoiding that MediaStore query per visible row is the
    // difference between a smooth first fling and hundreds of disk writes.
    final localPath = (widget.song.albumArtPath ?? '').trim();
    // Only a real on-disk cover can replace the embedded-art fallback. A
    // stale path or a remote URL must still let the embedded probe run.
    // Never stat a path on the UI isolate. Image.file already decodes
    // off-isolate and reports a bad path through errorBuilder; remembering
    // decoded paths avoids repeating the work for duplicated album art.
    final hasRealCover = localPath.isNotEmpty;
    // A file existing does not prove it decodes. Keep the embedded probe
    // available as a fallback until an image actually renders.
    if (!_embeddedChecked && !hasRealCover) {
      _loadEmbedded();
    }
  }

  Future<void> _loadEmbedded() async {
    final path = await EmbeddedArtService.instance.resolveArtFile(
      widget.song.id,
      filePath: widget.song.filePath,
    );
    if (!mounted) return;
    setState(() {
      _embeddedPath = path;
      _embeddedChecked = true;
    });
  }

  Widget _localImage(String path) {
    return Image.file(
      File(path),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: widget.gaplessPlayback,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null) SongArtImage.noteValidCover(path);
        return child;
      },
      errorBuilder: (_, __, ___) {
        // The file may have been cleared or re-extracted since it was last
        // decoded. Forget it and retry the embedded art.
        SongArtImage._validCoverPaths.remove(path);
        _localArtFailed = true;
        _embeddedChecked = false;
        if (_embeddedPath == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadEmbedded();
          });
        }
        // A referenced local file that fails to decode must not strand the
        // row on a placeholder while embedded or network art is available.
        if (path != _embeddedPath && _embeddedPath != null) {
          return _localImage(_embeddedPath!);
        }
        return _networkOrIcon();
      },
    );
  }

  Widget _networkOrIcon() {
    final url = (widget.song.albumArtUrl ?? '').trim();
    if (url.isEmpty) return widget.fallback;
    return CachedArtImage(
      url: url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: widget.gaplessPlayback,
      fallback: widget.fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final localPath = (widget.song.albumArtPath ?? '').trim();
    if (localPath.isNotEmpty && !_localArtFailed) {
      return _localImage(localPath);
    }
    final embedded = _embeddedPath;
    if (embedded != null) {
      return _localImage(embedded);
    }
    // Embedded check still running: never flash the network cover and then
    // swap, which would pop on every first sight of a song. Fall back to
    // the fallback until the probe answers, then show embedded or network.
    if (!_embeddedChecked) {
      return widget.fallback;
    }
    return _networkOrIcon();
  }
}

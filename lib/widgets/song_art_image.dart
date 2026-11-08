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

  @override
  State<SongArtImage> createState() => _SongArtImageState();
}

class _SongArtImageState extends State<SongArtImage> {
  // Resolved embedded path for this song, or null while unresolved/missing.
  String? _embeddedPath;
  // True once we know this song has no embedded art (checked on disk).
  bool _embeddedChecked = false;

  @override
  void initState() {
    super.initState();
    _embeddedPath = EmbeddedArtService.instance.peekSync(widget.song.id);
    _embeddedChecked = _embeddedPath != null ||
        EmbeddedArtService.instance.isKnownMissing(widget.song.id);
    if (!_embeddedChecked) {
      _loadEmbedded();
    }
  }

  Future<void> _loadEmbedded() async {
    final path =
        await EmbeddedArtService.instance.resolveArtFile(widget.song.id);
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
      errorBuilder: (_, __, ___) =>
          _embeddedPath != null && path == _embeddedPath ? _networkOrIcon() : widget.fallback,
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
    if (localPath.isNotEmpty) {
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

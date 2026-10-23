import 'dart:io';

import 'package:path_provider/path_provider.dart';

// Requires the `file_picker` package (to be added to pubspec.yaml
// separately). Standard async picker pattern is used below.
import 'package:file_picker/file_picker.dart';

import '../models/song.dart';

// Result of matching M3U entries against the in-memory library.
class M3uMatch {
  final List<Song> matched;
  final int missing;

  /// Entries whose file name matches more than one library song, so no safe
  /// match was possible and they were skipped instead of guessing.
  final int ambiguous;

  const M3uMatch({
    required this.matched,
    required this.missing,
    this.ambiguous = 0,
  });

  /// Entries that could not be matched, for any reason.
  int get unresolved => missing + ambiguous;
}

// Picked M3U file together with its library match result.
class M3uPicked {
  final String playlistName;
  final M3uMatch match;

  const M3uPicked({required this.playlistName, required this.match});
}

// Parses .m3u/.m3u8 playlist files and matches entries to library songs.
// Pure matching logic lives in [matchContent] so it can be tested
// without the file picker. Only existing model types are used.
class M3uService {
  M3uService._();

  // Parse M3U [content] and match each entry against [library].
  // Lines starting with '#' are skipped, except that '#EXTINF' title
  // lines are simply ignored (the following path line is what matters).
  // Relative paths resolve against [baseDir] (the M3U file folder).
  // Matching is exact on normalized filePath first, then falls back
  // to comparing file names with endsWith semantics.
  static M3uMatch matchContent({
    required String content,
    required String baseDir,
    required List<Song> library,
  }) {
    final entries = _parseEntries(content);
    final byPath = <String, Song>{};
    for (final song in library) {
      byPath.putIfAbsent(
        _normalizePath(song.filePath),
        () => song,
      );
    }

    final matched = <Song>[];
    final seenIds = <int>{};
    var missing = 0;
    var ambiguous = 0;
    for (final entry in entries) {
      final resolved = _resolveEntry(entry, baseDir);
      final normalized = _normalizePath(resolved);
      Song? hit = byPath[normalized];
      hit ??= _matchByFileName(normalized, library);
      if (hit == null) {
        // No path match and no single file name match: either the file is
        // gone or the name is shared by several songs. Either way guessing
        // would silently add the wrong track, so report it instead.
        if (_countByFileName(normalized, library) > 1) {
          ambiguous++;
        } else {
          missing++;
        }
      } else if (seenIds.add(hit.id)) {
        matched.add(hit);
      }
    }
    return M3uMatch(matched: matched, missing: missing, ambiguous: ambiguous);
  }

  // Open the system file picker, read the chosen .m3u/.m3u8 file,
  // and match it against [library]. Returns null when the user
  // cancels or the picked file has no readable path.
  static Future<M3uPicked?> pickAndMatch(List<Song> library) async {
    final files = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['m3u', 'm3u8'],
    );
    if (files.isEmpty) return null;
    final path = files.first.path;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    final content = await file.readAsString();
    final match = matchContent(
      content: content,
      baseDir: _dirnameOf(path),
      library: library,
    );
    return M3uPicked(
      playlistName: _playlistNameFromPath(path),
      match: match,
    );
  }

  // Split raw M3U text into candidate path lines.
  static List<String> _parseEntries(String content) {
    final entries = <String>[];
    for (final rawLine in content.split('\n')) {
      var line = rawLine.trim();
      // Strip a UTF-8 BOM when the file starts with one.
      if (entries.isEmpty && line.startsWith('\uFEFF')) {
        line = line.substring(1);
      }
      if (line.isEmpty) continue;
      // Skip comments and directives; #EXTINF only carries a
      // display title, the path on the next line is what we need.
      if (line.startsWith('#')) continue;
      entries.add(line);
    }
    return entries;
  }

  // Resolve one M3U entry to an absolute path string.
  // file:// URIs are decoded, absolute paths pass through,
  // anything else is treated as relative to [baseDir].
  static String _resolveEntry(String entry, String baseDir) {
    final trimmed = entry.trim().replaceAll('\\', '/');
    if (trimmed.startsWith('file://')) {
      try {
        return Uri.parse(trimmed).toFilePath().replaceAll('\\', '/');
      } catch (_) {
        return trimmed;
      }
    }
    if (_isAbsolutePath(trimmed)) return trimmed;
    final base = baseDir.replaceAll('\\', '/');
    final sep = base.endsWith('/') ? '' : '/';
    return '$base$sep$trimmed';
  }

  static bool _isAbsolutePath(String value) {
    if (value.startsWith('/')) return true;
    // Windows drive letter, e.g. C:/Music/song.mp3
    if (value.length >= 3 &&
        RegExp(r'^[A-Za-z]:/').hasMatch(value)) {
      return true;
    }
    // UNC path, e.g. //server/share/song.mp3
    if (value.startsWith('//')) return true;
    return false;
  }

  // Lowercase with forward slashes and no trailing slash so
  // comparisons work across Windows and POSIX style paths.
  static String _normalizePath(String value) {
    var out = value.replaceAll('\\', '/');
    while (out.endsWith('/') && out.length > 1) {
      out = out.substring(0, out.length - 1);
    }
    return out.toLowerCase();
  }

  // Fallback match on the file name only: entry matches when the
  // library path ends with the entry file name. First hit wins.
  static Song? _matchByFileName(String normalizedEntry, List<Song> library) {
    final name = _basenameOf(normalizedEntry);
    if (name.isEmpty) return null;
    // Prefer an exact normalized path or a path ending in the same
    // directory plus name.
    final exact = library.cast<Song?>().firstWhere(
          (s) => _normalizePath(s!.filePath) == normalizedEntry,
          orElse: () => null,
        );
    if (exact != null) return exact;
    // Fall back to the file name only when it is UNIQUE in the library.
    // Returning the first of several same named files would silently add the
    // wrong song to the playlist.
    final byName = _allByFileName(normalizedEntry, library);
    if (byName.length == 1) return byName.first;
    return null;
  }

  /// Every library song whose path ends with the same file name.
  static List<Song> _allByFileName(
      String normalizedEntry, List<Song> library) {
    final name = _basenameOf(normalizedEntry);
    if (name.isEmpty) return const [];
    final hits = <Song>[];
    for (final song in library) {
      final libPath = _normalizePath(song.filePath);
      if (libPath == name ||
          libPath.endsWith('/$name') ||
          _basenameOf(libPath) == name) {
        hits.add(song);
      }
    }
    return hits;
  }

  /// How many library songs share this entry's file name.
  static int _countByFileName(String normalizedEntry, List<Song> library) =>
      _allByFileName(normalizedEntry, library).length;

  static String _basenameOf(String path) {
    final value = path.replaceAll('\\', '/');
    final idx = value.lastIndexOf('/');
    return idx < 0 ? value : value.substring(idx + 1);
  }

  // Folder of a picked file path without extra dependencies.
  static String _dirnameOf(String path) {
    final value = path.replaceAll('\\', '/');
    final idx = value.lastIndexOf('/');
    if (idx <= 0) return value;
    return value.substring(0, idx);
  }

  // Playlist default name: file name without its extension.
  static String _playlistNameFromPath(String path) {
    final base = _basenameOf(path);
    final dot = base.lastIndexOf('.');
    if (dot <= 0) return base;
    return base.substring(0, dot);
  }

  // Build extended M3U text for [songs]: one #EXTM3U header followed
  // by an #EXTINF line plus the file path per song. Duration is in
  // whole seconds, or -1 when unknown. Pure function, never touches
  // the file system.
  static String buildM3uContent(List<Song> songs) {
    final buf = StringBuffer()..writeln('#EXTM3U');
    for (final song in songs) {
      final seconds = song.durationMs > 0 ? song.durationMs ~/ 1000 : -1;
      // Commas and newlines would break the EXTINF format, so flatten them.
      final title = '${song.artist} - ${song.title}'
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ')
          .replaceAll(',', ' ');
      buf.writeln('#EXTINF:$seconds,$title');
      buf.writeln(song.filePath);
    }
    return buf.toString();
  }

  // Write M3U [content] into the Downloads folder and return the file.
  // Prefers getDownloadsDirectory, then getExternalStorageDirectory,
  // then the temp dir as a last resort. Wraps any failure in a plain
  // Exception so callers only need a generic catch.
  static Future<File> saveM3uToDownloads(
      String playlistName, String content) async {
    try {
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {
        dir = null;
      }
      if (dir == null) {
        try {
          dir = await getExternalStorageDirectory();
        } catch (_) {
          dir = null;
        }
      }
      dir ??= await getTemporaryDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final safeName = _sanitizeFileName(playlistName);
      final file = File('${dir.path}${Platform.pathSeparator}$safeName.m3u');
      await file.writeAsString(content);
      return file;
    } catch (e) {
      throw Exception('Failed to save M3U file: $e');
    }
  }

  // Strip characters that are illegal in file names on common platforms.
  // Falls back to a generic name when nothing usable remains.
  static String _sanitizeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\.+$'), '')
        .trim();
    return cleaned.isEmpty ? 'playlist' : cleaned;
  }
}

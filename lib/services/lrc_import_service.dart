import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/song.dart';
import '../utils/lrc.dart';
import 'db_helper.dart';

/// Fully offline `.lrc` sidecar import and export. No network call, no new
/// permission, and no new dependency: file_picker and share_plus are already
/// part of the app.
class LrcImportService {
  LrcImportService._();

  static const int maxBytes = 100 * 1024;

  /// Pick a `.lrc` file and attach it to [song]. Returns the number of timed
  /// lines, `0` on cancel or an unusable file, and `-1` when the file is too
  /// large to store safely.
  static Future<int> pickAndApply(Song song) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['lrc'],
    );
    if (picked.isEmpty) return 0;
    final file = picked.first;
    int? length;
    List<int> bytes;
    try {
      length = await file.length();
      if (length == null || length <= 0 || length > maxBytes) return -1;
      bytes = await file.readAsBytes();
    } catch (_) {
      return 0;
    }
    if (bytes.isEmpty || bytes.length > maxBytes) return -1;
    final text = utf8.decode(bytes, allowMalformed: true);
    final lines = parseLrc(text);
    if (lines.isEmpty) return 0;
    // An imported LRC must not wipe the user's saved timing correction.
    final offset = await DBHelper.instance.getSyncedLyricOffset(song.id);
    await DBHelper.instance.setSyncedLyrics(song.id, text, offsetMs: offset);
    // Keep the plain text view in step with the imported timed view.
    song.lyrics = lines.map((line) => line.text).join('\n');
    return lines.length;
  }

  /// Share the stored LRC as a real `.lrc` file the user can save anywhere.
  static Future<void> share(Song song) async {
    final lrc = await DBHelper.instance.getSyncedLyrics(song.id);
    if (lrc == null || lrc.isEmpty) return;
    final dir = await getTemporaryDirectory();
    final safe = song.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}${Platform.pathSeparator}$safe.lrc');
    await file.writeAsString(lrc);
    await SharePlus.instance
        .share(ShareParams(files: [XFile(file.path)], text: song.title));
  }
}

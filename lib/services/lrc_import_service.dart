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

  /// A parsed LRC that has not been written to the database yet.
  static Future<({int count, String plain, String text, int offsetMs})> pick(
      Song song) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['lrc'],
    );
    if (picked.isEmpty) return (count: 0, plain: '', text: '', offsetMs: 0);
    final file = picked.first;
    List<int> bytes;
    try {
      final length = await file.length();
      if (length == null || length <= 0 || length > maxBytes) {
        return (count: -1, plain: '', text: '', offsetMs: 0);
      }
      bytes = await file.readAsBytes();
    } catch (_) {
      return (count: 0, plain: '', text: '', offsetMs: 0);
    }
    if (bytes.isEmpty || bytes.length > maxBytes) {
      return (count: -1, plain: '', text: '', offsetMs: 0);
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    final lines = parseLrc(text);
    if (lines.isEmpty) {
      return (count: 0, plain: '', text: '', offsetMs: 0);
    }
    // An imported LRC must not wipe the user's saved timing correction.
    final offset = await DBHelper.instance.getSyncedLyricOffset(song.id);
    return (
      count: lines.length,
      plain: lines.map((line) => line.text).join('\n'),
      text: text,
      offsetMs: offset,
    );
  }

  /// Write a parsed LRC. Called only after the UI has asked for consent.
  static Future<void> apply(Song song,
      ({int count, String plain, String text, int offsetMs}) imported) async {
    final offset = imported.offsetMs;
    await DBHelper.instance.setSyncedLyrics(song.id, imported.text,
        offsetMs: offset);
  }

  /// Convenience path for callers without a confirmation step.
  static Future<({int count, String plain})> pickAndApply(Song song) async {
    final imported = await pick(song);
    if (imported.count <= 0) {
      return (count: imported.count, plain: imported.plain);
    }
    await apply(song, imported);
    return (count: imported.count, plain: imported.plain);
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

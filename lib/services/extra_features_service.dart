import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

/// Recent search queries, kept only on this device.
class SearchHistoryService {
  SearchHistoryService._();
  static const _key = 'search_history_v5';
  static const int maxEntries = 10;

  static Future<List<String>> recent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<void> add(String query) async {
    final value = query.trim();
    if (value.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (prefs.getStringList(_key) ?? <String>[])
          .where((q) => q.toLowerCase() != value.toLowerCase())
          .toList();
      list.insert(0, value);
      if (list.length > maxEntries) list.removeRange(maxEntries, list.length);
      await prefs.setStringList(_key, list);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}

/// A daily listening target. Progress comes from listening history, not a
/// separate counter, so it cannot drift from the dashboard.
class ListeningGoalService {
  ListeningGoalService._();
  static const _key = 'listening_goal_minutes_v5';

  static Future<int> targetMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_key) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> setTargetMinutes(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (minutes <= 0) {
        await prefs.remove(_key);
      } else {
        await prefs.setInt(_key, minutes);
      }
    } catch (_) {}
  }
}

/// Home widget layout settings read by the native side at push time.
class WidgetSettingsService {
  WidgetSettingsService._();
  static const _queueKey = 'widget_queue_len_v5';
  static const _styleKey = 'widget_compact_v5';

  static Future<int> queueLength() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(_queueKey) ?? 5;
      return value == 3 || value == 8 ? value : 5;
    } catch (_) {
      return 5;
    }
  }

  static Future<void> setQueueLength(int length) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_queueKey, length == 3 || length == 8 ? length : 5);
    } catch (_) {}
  }

  static Future<bool> compact() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_styleKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setCompact(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_styleKey, value);
    } catch (_) {}
  }
}

/// Small in-memory log of playback and scan failures, useful when the user
/// reports that something did not work. Never leaves the app unless shared.
class DiagnosticsService {
  DiagnosticsService._();
  static final DiagnosticsService instance = DiagnosticsService._();
  static const int maxLines = 200;
  final List<String> _lines = <String>[];

  void add(String tag, String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    _lines.add('$stamp $tag: $message');
    if (_lines.length > maxLines) _lines.removeAt(0);
  }

  List<String> get lines => List<String>.unmodifiable(_lines);

  String exportText() => _lines.isEmpty ? 'No diagnostics' : _lines.join('\n');

  void clear() => _lines.clear();
}

/// Parse a filename into title and artist without touching the file.
class FilenameTagService {
  FilenameTagService._();

  static ({String title, String artist}) parse(String fileName) {
    var name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '').trim();
    name = name.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ');
    // Leading track numbers are not part of the title.
    name = name.replaceFirst(RegExp(r'^\d{1,3}[\s.\-]+'), '');
    final parts = name.split(RegExp(r'\s+[-–]\s+'));
    if (parts.length >= 2) {
      final first = parts.first.trim();
      final second = parts.skip(1).join(' - ').trim();
      // Most libraries use "Artist - Title"; keep that when both are useful.
      if (first.isNotEmpty && second.isNotEmpty) {
        return (title: second, artist: first);
      }
    }
    return (title: name, artist: '');
  }
}

/// Per-folder library counts for the storage screen. Uses only data already
/// in memory, so it costs one pass and no disk access.
Map<String, int> folderCounts(List<Song> songs) {
  final out = <String, int>{};
  for (final song in songs) {
    final folder = p.dirname(song.filePath);
    out[folder] = (out[folder] ?? 0) + 1;
  }
  return out;
}

// Sort-tier category: symbols/icons first, then digits, then latin letters,
// finally other scripts (Korean/Chinese/Japanese/etc).

int _sortRank(String s) {
  if (s.isEmpty) return 0;
  final c = s.codeUnitAt(0);
  // ASCII ranges checked directly: identical to the old [a-zA-Z] and [0-9]
  // regex tests, but without running the regex engine on every comparison.
  if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) {
    return 2; // latin letter
  }
  if (c >= 0x30 && c <= 0x39) return 1; // digit
  if (c > 127) return 3; // non-latin script (CJK, etc)
  return 0; // symbol/icon (#, [, etc)
}

/// Sort tier for one title, exposed so callers can precompute a sort key per
/// song instead of calling [compareTitles] inside every comparison.
int titleSortRank(String s) => _sortRank(s);

/// Compare two titles in tier order: symbols < digits < letters < other scripts.
int compareTitles(String a, String b) {
  final rankA = _sortRank(a);
  final rankB = _sortRank(b);
  if (rankA != rankB) return rankA.compareTo(rankB);
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// Safely extract the folder path from a file path - supports both '/' (Android/Linux)
/// and '\' (Windows). When there is no separator at all (edge case),
/// return an empty string instead of crashing with a RangeError.
String folderOf(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final idx = normalized.lastIndexOf('/');
  if (idx == -1) return '';
  // Return the folder in normalized (slash) form so the
  // excluded.contains(folder) comparison stays consistent on every platform.
  return normalized.substring(0, idx);
}

/// True when [filePath] is inside [folder] or the folder itself. Hidden
/// folders exclude their descendants, matching querySongsPage's LIKE rule.
bool isHiddenPath(String filePath, Set<String> excluded) {
  if (excluded.isEmpty) return false;
  // SQLite LIKE is case-insensitive here, so the in-memory check must be too.
  final normalized = filePath.replaceAll('\\', '/').toLowerCase();
  for (final raw in excluded) {
    final folder = raw
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/$'), '')
        .toLowerCase();
    if (folder.isEmpty) continue;
    if (normalized == folder || normalized.startsWith('$folder/')) return true;
  }
  return false;
}

/// First letter that is safe for avatar/A-Z - never throws RangeError.
String safeInitial(String s) => s.isEmpty ? '#' : s[0].toUpperCase();
String formatDuration(int ms) {
  final totalSeconds = (ms / 1000).round();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${two(minutes)}:${two(seconds)}';
  }
  return '${two(minutes)}:${two(seconds)}';
}

/// Format a total duration as a compact text such as "2h 15m" or "45m".
/// Units follow [indonesian]; default is English. (This used to always
/// print jam/menit regardless of locale.)
String formatDurationLong(int ms, {bool indonesian = false}) {
  final totalMinutes = (ms / 60000).round();
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (indonesian) {
    if (hours > 0 && minutes > 0) return '$hours jam $minutes menit';
    if (hours > 0) return '$hours jam';
    return '$minutes menit';
  }
  if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h';
  return '${minutes}m';
}

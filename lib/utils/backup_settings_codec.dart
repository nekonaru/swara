import 'dart:convert';

/// Decode the backup settings section defensively. Only whitelisted keys and
/// primitive values are accepted so a corrupt section cannot poison prefs.
Map<String, Object> decodeBackupSettings(dynamic raw) {
  final result = <String, Object>{};
  if (raw is! Map) return result;
  const keys = <String>{
    'equalizerPreset',
    'custom_eq_gains',
    'custom_eq_presets',
    'textScale',
    'themeMode',
    'accentColorIndex',
    'amoledBlack',
    'dynamicColor',
    'loudness_enabled',
    'crossfadeSeconds',
    'crossfadeEnabled',
    'smartShuffle',
    'fairShuffleV6',
    'playbackSpeed',
    'playbackPitch',
    'sleepScheduleEnabled',
    'sleepScheduleHour',
    'sleepScheduleMinute',
    'shuffle',
    'repeatMode',
    'language_code',
  };
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || !keys.contains(key)) continue;
    if (value is String || value is bool || value is num || value is List<String>) {
      result[key] = value;
    }
  }
  return result;
}

String encodeBackupSettings(Map<String, Object> settings) => jsonEncode(settings);

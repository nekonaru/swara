import 'dart:convert';

/// A user-named 5-band EQ curve, persisted as JSON by ThemeProvider.
class EqPreset {
  final String id;
  final String name;
  final List<double> gains;

  const EqPreset({
    required this.id,
    required this.name,
    required this.gains,
  });

  static const int bandCount = 5;
  static const double minGain = -6;
  static const double maxGain = 6;

  static List<double> clampGains(List<dynamic> raw) => List<double>.generate(
        bandCount,
        (i) {
          final value = i < raw.length ? raw[i] : null;
          final number = value is num ? value.toDouble() : 0.0;
          if (!number.isFinite) return 0;
          return number.clamp(minGain, maxGain).toDouble();
        },
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'gains': gains,
      };

  static EqPreset? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'] is String ? raw['id'] as String : '';
    final name = raw['name'] is String ? raw['name'] as String : '';
    if (id.isEmpty || name.isEmpty) return null;
    final gainsRaw = raw['gains'];
    if (gainsRaw is! List) return null;
    return EqPreset(id: id, name: name, gains: clampGains(gainsRaw));
  }
}

/// Decode a stored preset list defensively: malformed JSON or bad rows are
/// dropped instead of crashing startup.
List<EqPreset> decodeEqPresets(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <EqPreset>[];
    return decoded
        .map((e) => EqPreset.fromJson(e))
        .whereType<EqPreset>()
        .toList();
  } catch (_) {
    return const <EqPreset>[];
  }
}

String encodeEqPresets(List<EqPreset> presets) => jsonEncode(
      presets.map((p) => p.toJson()).toList(),
    );

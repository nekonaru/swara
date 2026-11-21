import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/eq_preset.dart';
import '../theme/app_theme.dart';

const List<Color> kAccentColors = [
  Color(0xFF6750A4), // Deep Purple (default)
  Color(0xFF0066CC), // Blue
  Color(0xFF00897B), // Teal
  Color(0xFF2E7D32), // Green
  Color(0xFFE65100), // Orange
  Color(0xFFC62828), // Red
  Color(0xFF6A1B9A), // Purple
  Color(0xFFAD1457), // Pink
  Color(0xFF00838F), // Cyan
  Color(0xFF558B2F), // Light Green
];

// Allowed app text scale factors shown in Settings.
// 0.8 is the smallest (a bit smaller than normal), 0.85 is the default
// "normal" size, 1.0 is "large". Extra-large is intentionally gone.
const List<double> kTextScales = [0.8, 0.85, 1.0];

class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'themeMode';
  static const _accentKey = 'accentColorIndex';
  static const _equalizerPresetKey = 'equalizerPreset';
  static const _textScaleKey = 'textScale';
  static const _customEqGainsKey = 'custom_eq_gains';
  static const _eqPresetsKey = 'custom_eq_presets';
  static const _amoledBlackKey = 'amoledBlack';
  static const _dynamicColorKey = 'dynamicColor';

  ThemeMode themeMode = ThemeMode.system;
  int accentColorIndex = 0;
  String equalizerPreset = 'Flat';
  // App text scale factor. 0.85 (small) is the default so the app feels
  // lighter on screen and fits more rows without scrolling.
  double textScale = 0.85;
  // Custom 5-band EQ gains (low to high). Used only with the Custom preset.
  List<double> customEqGains = [0, 0, 0, 0, 0];
  // Named user EQ curves, persisted independently of the one Custom buffer.
  List<EqPreset> eqPresets = const <EqPreset>[];
  static const int maxEqPresets = 12;

  // Pitch black background for the dark theme. Wired in main by someone else.
  bool amoledBlack = false;
  // Material You: follow the Android 12+ system accent colors instead of the
  // built-in seed palette. Falls back to the seed when unavailable.
  bool dynamicColor = false;

  Color get accentColor => kAccentColors[accentColorIndex];

  // Write chain serializes SharedPreferences writes so two quick taps cannot
  // land out of order. Each setter awaits the chain before starting its own
  // write, so a slower write cannot overtake a faster one.
  Future<void> _writeChain = Future<void>.value();

  Future<void> _write(Future<void> Function(SharedPreferences) op) async {
    // Chain through the previous write so two quick taps cannot land out of
    // order and a slower earlier write can never win the race.
    final future = _writeChain.then((_) => _doWrite(op));
    _writeChain = future.catchError((Object e) {
      // Keep the chain alive even when one write fails.
      debugPrint('ThemeProvider write chain error: $e');
    });
    return future;
  }

  Future<void> _doWrite(Future<void> Function(SharedPreferences) op) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await op(prefs);
    } catch (e) {
      debugPrint('ThemeProvider write failed: $e');
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        themeMode = ThemeMode.values.firstWhere(
          (e) => e.name == saved,
          orElse: () => ThemeMode.system,
        );
      }
      accentColorIndex = (prefs.getInt(_accentKey) ?? 0)
          .clamp(0, kAccentColors.length - 1);
      equalizerPreset = prefs.getString(_equalizerPresetKey) ?? 'Flat';
      // Fall back to normal (0.85) when nothing is stored or the value is unknown.
      final savedScale = prefs.getDouble(_textScaleKey) ?? 0.85;
      textScale = kTextScales.contains(savedScale) ? savedScale : 0.85;
      customEqGains = _readCustomGains(prefs);
      final storedPresets = prefs.getString(_eqPresetsKey);
      if (storedPresets != null) eqPresets = decodeEqPresets(storedPresets);
      amoledBlack = prefs.getBool(_amoledBlackKey) ?? false;
      dynamicColor = prefs.getBool(_dynamicColorKey) ?? false;
    } catch (e) {
      // Keep defaults if storage is unavailable.
      debugPrint('ThemeProvider load failed: $e');
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _write((prefs) => prefs.setString(_prefsKey, mode.name));
  }

  Future<void> setAccentColor(int index) async {
    accentColorIndex = index.clamp(0, kAccentColors.length - 1);
    notifyListeners();
    await _write((prefs) => prefs.setInt(_accentKey, accentColorIndex));
  }

  Future<void> setEqualizerPreset(String preset) async {
    equalizerPreset = preset;
    notifyListeners();
    await _write((prefs) => prefs.setString(_equalizerPresetKey, preset));
  }

  // Persist the selected text scale and notify listeners at once.
  Future<void> setTextScale(double scale) async {
    // Validate against the same whitelist load() uses, so a value that is
    // not an offered option cannot be stored and then silently reset later.
    textScale = kTextScales.contains(scale) ? scale : 0.85;
    notifyListeners();
    await _write((prefs) => prefs.setDouble(_textScaleKey, textScale));
  }

  // Read the stored custom gains, falling back to flat on bad data.
  static List<double> _readCustomGains(SharedPreferences prefs) {
    const flat = [0.0, 0.0, 0.0, 0.0, 0.0];
    final stored = prefs.getStringList(_customEqGainsKey);
    if (stored == null || stored.length != 5) return List.of(flat);
    try {
      return stored.map(double.parse).toList();
    } catch (_) {
      return List.of(flat);
    }
  }

  // Save the Custom preset slider values and notify listeners at once.
  Future<void> setCustomEqGains(List<double> gains) async {
    final fixed = List<double>.generate(
        5, (i) => i < gains.length ? gains[i].clamp(-6.0, 6.0) : 0.0);
    customEqGains = fixed;
    notifyListeners();
    await _write((prefs) => prefs.setStringList(
        _customEqGainsKey, fixed.map((g) => g.toString()).toList()));
  }

  Future<int> saveEqPreset(String name, List<double> gains) async {
    if (eqPresets.length >= maxEqPresets) return -1;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final preset = EqPreset(
      id: id,
      name: name.trim(),
      gains: EqPreset.clampGains(gains),
    );
    eqPresets = [...eqPresets, preset];
    // Selecting a saved curve reuses the existing "Custom" DSP path.
    equalizerPreset = 'user:$id';
    customEqGains = List.of(preset.gains);
    notifyListeners();
    await _write((prefs) async {
      await prefs.setString(_eqPresetsKey, encodeEqPresets(eqPresets));
      await prefs.setString(_equalizerPresetKey, equalizerPreset);
      await prefs.setStringList(
          _customEqGainsKey, customEqGains.map((g) => g.toString()).toList());
    });
    return eqPresets.length - 1;
  }

  void selectEqPreset(EqPreset preset) {
    equalizerPreset = 'user:${preset.id}';
    customEqGains = List.of(preset.gains);
    notifyListeners();
    unawaited(_write((prefs) async {
      await prefs.setString(_equalizerPresetKey, equalizerPreset);
      await prefs.setStringList(
          _customEqGainsKey, customEqGains.map((g) => g.toString()).toList());
    }));
  }

  Future<void> renameEqPreset(int index, String name) async {
    if (index < 0 || index >= eqPresets.length || name.trim().isEmpty) return;
    final updated = List<EqPreset>.of(eqPresets);
    final old = updated[index];
    updated[index] =
        EqPreset(id: old.id, name: name.trim(), gains: List.of(old.gains));
    eqPresets = updated;
    notifyListeners();
    await _write((prefs) =>
        prefs.setString(_eqPresetsKey, encodeEqPresets(eqPresets)));
  }

  Future<void> deleteEqPreset(int index) async {
    if (index < 0 || index >= eqPresets.length) return;
    final removed = eqPresets[index];
    eqPresets = List<EqPreset>.of(eqPresets)..removeAt(index);
    if (equalizerPreset == 'user:${removed.id}') {
      equalizerPreset = 'Flat';
      customEqGains = const [0, 0, 0, 0, 0];
    }
    notifyListeners();
    await _write((prefs) async {
      await prefs.setString(_eqPresetsKey, encodeEqPresets(eqPresets));
      await prefs.setString(_equalizerPresetKey, equalizerPreset);
    });
  }

  /// Gains for the active preset token, or null for a factory preset.
  List<double>? gainsForActivePreset() {
    if (!equalizerPreset.startsWith('user:')) return null;
    final id = equalizerPreset.substring(5);
    for (final preset in eqPresets) {
      if (preset.id == id) return List.of(preset.gains);
    }
    return null;
  }

  // Toggle the pitch black dark theme variant and persist it.
  Future<void> setAmoledBlack(bool value) async {
    amoledBlack = value;
    notifyListeners();
    await _write((prefs) => prefs.setBool(_amoledBlackKey, value));
  }

  // Toggle Material You (system accent colors) and persist it.
  Future<void> setDynamicColor(bool value) async {
    dynamicColor = value;
    notifyListeners();
    await _write((prefs) => prefs.setBool(_dynamicColorKey, value));
  }

  // Dark theme for main to use. The plain dark theme normally, or the pitch
  // black variant when amoledBlack is on. Same seed either way; every visual
  // default comes from the shared buildSwaraTheme so the light and the dark
  // side cannot drift apart.
  ThemeData buildDarkTheme({ColorScheme? dynamicScheme}) => buildSwaraTheme(
        seed: accentColor,
        brightness: Brightness.dark,
        amoledBlack: amoledBlack,
        dynamicScheme: dynamicScheme,
      );
}

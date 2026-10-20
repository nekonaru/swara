import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Manages the app display language (English default, Indonesian optional).
// Persists the selection so it survives app restarts.
class LanguageProvider extends ChangeNotifier {
  // Shared singleton instance used across the app.
  static final LanguageProvider instance = LanguageProvider._internal();

  // Private constructor for the singleton.
  LanguageProvider._internal();

  // Storage key for the persisted language code.
  static const _prefsKey = 'language_code';

  // Currently active locale. English is the default.
  Locale locale = const Locale('en');

  // True when the current locale is Indonesian.
  bool get isIndonesian => locale.languageCode == 'id';

  // Loads the saved language code from disk, if any.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == 'id') {
        locale = const Locale('id');
      } else {
        // Fall back to English for missing or unrecognized values.
        locale = const Locale('en');
      }
    } catch (e) {
      debugPrint('LanguageProvider load failed: $e');
      locale = const Locale('en');
    }
    notifyListeners();
  }

  // Sets a new locale and persists it.
  Future<void> setLocale(Locale value) async {
    // Only English and Indonesian are supported.
    final code = value.languageCode == 'id' ? 'id' : 'en';
    locale = Locale(code);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, code);
    } catch (e) {
      debugPrint('LanguageProvider setLocale failed: $e');
    }
  }
}

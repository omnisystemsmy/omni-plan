import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _boxName = 'app_settings';
  static const String _themeModeKey = 'theme_mode';
  static const String _legacyDarkModeKey = 'dark_mode';

  ThemeMode _themeMode = ThemeMode.light;
  Box? _settingsBox;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  bool get isSystem => _themeMode == ThemeMode.system;

  Future<void> init() async {
    _settingsBox ??= await Hive.openBox(_boxName);

    final savedMode = _settingsBox!.get(_themeModeKey);
    if (savedMode is String) {
      _themeMode = _parseThemeMode(savedMode);
      notifyListeners();
      return;
    }

    // Backward compatibility with older boolean storage.
    final legacyIsDark = _settingsBox!.get(_legacyDarkModeKey);
    if (legacyIsDark is bool) {
      _themeMode = legacyIsDark ? ThemeMode.dark : ThemeMode.light;
      await _persistThemeMode(_themeMode);
      notifyListeners();
      return;
    }

    // First launch: light, not the phone's setting.
    _themeMode = ThemeMode.light;
    await _persistThemeMode(_themeMode);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _persistThemeMode(mode);
    notifyListeners();
  }

  Future<void> toggleTheme(bool isDark) async {
    await setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  ThemeMode _parseThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToStorageValue(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> _persistThemeMode(ThemeMode mode) async {
    _settingsBox ??= await Hive.openBox(_boxName);
    await _settingsBox!.put(_themeModeKey, _themeModeToStorageValue(mode));
    await _settingsBox!.put(_legacyDarkModeKey, mode == ThemeMode.dark);
  }
}

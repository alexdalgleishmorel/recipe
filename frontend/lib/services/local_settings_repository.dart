import 'package:shared_preferences/shared_preferences.dart';

import 'repositories.dart';

class LocalSettingsRepository implements SettingsRepository {
  static const _themeKey = 'settings.theme.dark';

  @override
  Future<bool> isDark() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_themeKey) ?? false;
  }

  @override
  Future<void> setDark(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, value);
  }
}

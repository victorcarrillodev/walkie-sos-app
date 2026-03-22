import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark; 
  Color _primaryColor = const Color(0xFF00E676);

  ThemeProvider({ThemeMode? initialThemeMode, Color? initialPrimaryColor}) {
    if (initialThemeMode != null) _themeMode = initialThemeMode;
    if (initialPrimaryColor != null) _primaryColor = initialPrimaryColor;
  }

  ThemeMode get themeMode => _themeMode;
  Color get primaryColor => _primaryColor;

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> setPrimaryColor(Color color) async {
    _primaryColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('primaryColor', color.value);
  }
}
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark; 
  Color _primaryColor = const Color(0xFF00E676);
  List<Color>? _primaryGradientColors;

  ThemeProvider({
    ThemeMode? initialThemeMode, 
    Color? initialPrimaryColor,
    List<Color>? initialPrimaryGradientColors,
  }) {
    if (initialThemeMode != null) _themeMode = initialThemeMode;
    if (initialPrimaryColor != null) _primaryColor = initialPrimaryColor;
    if (initialPrimaryGradientColors != null) _primaryGradientColors = initialPrimaryGradientColors;
  }

  ThemeMode get themeMode => _themeMode;
  Color get primaryColor => _primaryColor;
  
  Gradient? get primaryGradient {
    if (_primaryGradientColors == null || _primaryGradientColors!.isEmpty) return null;
    return LinearGradient(
      colors: _primaryGradientColors!,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> setPrimaryColor(Color color) async {
    _primaryColor = color;
    _primaryGradientColors = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('primaryColor', color.value);
    await prefs.remove('primaryGradient');
  }

  Future<void> setPrimaryGradient(List<Color> colors) async {
    if (colors.isEmpty) return;
    _primaryGradientColors = colors;
    _primaryColor = colors.first;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('primaryGradient', colors.map((c) => c.value.toString()).join(','));
    await prefs.setInt('primaryColor', _primaryColor.value);
  }
}
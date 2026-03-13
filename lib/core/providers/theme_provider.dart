import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  // Inicia en modo oscuro y verde por defecto
  ThemeMode _themeMode = ThemeMode.dark; 
  Color _primaryColor = const Color(0xFF00E676);

  ThemeMode get themeMode => _themeMode;
  Color get primaryColor => _primaryColor;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void setPrimaryColor(Color color) {
    _primaryColor = color;
    notifyListeners();
  }
}
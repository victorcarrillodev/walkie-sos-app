import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final authProvider = context.read<AuthProvider>();

    String themeName = 'Sistema';
    if (themeProvider.themeMode == ThemeMode.light) themeName = 'Claro';
    if (themeProvider.themeMode == ThemeMode.dark) themeName = 'Oscuro';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Tema de la Aplicación'),
            subtitle: Text(themeName),
            onTap: () => _showThemeDialog(context, themeProvider),
          ),
          ListTile(
            leading: const Icon(Icons.color_lens),
            title: const Text('Color Principal'),
            trailing: CircleAvatar(
              backgroundColor: themeProvider.primaryColor,
              radius: 12,
            ),
            onTap: () => _showColorDialog(context, themeProvider),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onTap: () {
              authProvider.logout();
              // Retorna a la raíz de la app (lo que automáticamente mostrará el Login)
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context, ThemeProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Seleccionar Tema'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _themeRadioTile(context, 'Sistema', ThemeMode.system, provider),
            _themeRadioTile(context, 'Claro', ThemeMode.light, provider),
            _themeRadioTile(context, 'Oscuro', ThemeMode.dark, provider),
          ],
        ),
      ),
    );
  }

  Widget _themeRadioTile(BuildContext context, String title, ThemeMode mode, ThemeProvider provider) {
    return ListTile(
      title: Text(title),
      leading: Radio<ThemeMode>(
        value: mode,
        groupValue: provider.themeMode,
        activeColor: provider.primaryColor,
        onChanged: (val) {
          provider.setThemeMode(val!);
          Navigator.pop(context);
        },
      ),
      onTap: () {
        provider.setThemeMode(mode);
        Navigator.pop(context);
      },
    );
  }

  void _showColorDialog(BuildContext context, ThemeProvider provider) {
    final colors = [
      const Color(0xFF00E676), // Verde original
      const Color(0xFF2196F3), // Azul
      const Color(0xFFF44336), // Rojo
      const Color(0xFFFF9800), // Naranja
      const Color(0xFF9C27B0), // Morado
      const Color(0xFF00BCD4), // Teal (Turquesa)
      const Color(0xFFE91E63), // Rosa
      const Color(0xFF3F51B5), // Indigo
    ];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Seleccionar Color'),
        content: Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: colors.map((color) {
            final isSelected = provider.primaryColor.value == color.value;
            return GestureDetector(
              onTap: () {
                provider.setPrimaryColor(color);
                Navigator.pop(context);
              },
              child: CircleAvatar(
                backgroundColor: color,
                radius: 24,
                child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
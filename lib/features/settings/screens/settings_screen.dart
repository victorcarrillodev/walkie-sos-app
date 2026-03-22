import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/emergency_service.dart';
import '../../../core/providers/contact_provider.dart';
import '../../../core/providers/channel_provider.dart';
import 'alerts_history_screen.dart';

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
        title: const Text('Configuración'),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Emergencia', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ListTile(
            leading: const Icon(Icons.settings_voice, color: Colors.orange),
            title: const Text('Configurar Alerta por Voz'),
            subtitle: Text('Frase: ${context.watch<EmergencyService>().keyPhrase}'),
            onTap: () => _showEmergencyDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.blue),
            title: const Text('Historial de Alertas'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertsHistoryScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onTap: () {
              authProvider.logout();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context, ThemeProvider provider) {
// ... existing theme dialog ...
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
// ... existing color dialog ...
    final colors = [
      const Color(0xFF00E676),
      const Color(0xFF2196F3),
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

  void _showEmergencyDialog(BuildContext context) async {
    final emergency = context.read<EmergencyService>();
    final contactsProvider = context.read<ContactProvider>();
    final channelsProvider = context.read<ChannelProvider>();

    if (contactsProvider.contacts.isEmpty) await contactsProvider.loadContacts();
    if (channelsProvider.myChannels.isEmpty) await channelsProvider.loadMyChannels();

    String currentPhrase = emergency.keyPhrase;
    String? currentTargetId;
    if (emergency.targetId != null) {
      currentTargetId = emergency.isGroupTarget ? 'G_${emergency.targetId}' : 'C_${emergency.targetId}';
    }
    bool currentIsGroup = emergency.isGroupTarget;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Configuración de Emergencia'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: currentPhrase,
                      decoration: const InputDecoration(labelText: 'Frase Clave (Ej: ayuda por favor)'),
                      onChanged: (val) => currentPhrase = val,
                    ),
                    const SizedBox(height: 16),
                    const Text('Destinatario de la alerta:', style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text('Selecciona un contacto o grupo'),
                      value: currentTargetId,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Ninguno (Desactivado)'),
                        ),
                        ...contactsProvider.contacts.map((c) => DropdownMenuItem(
                          value: 'C_${c.contactId}',
                          child: Text('👤 ${c.alias} / ${c.name}'),
                        )),
                        ...channelsProvider.myChannels.map((c) => DropdownMenuItem(
                          value: 'G_${c.id}',
                          child: Text('👥 ${c.name}'),
                        )),
                      ],
                      onChanged: (val) {
                        setState(() {
                          currentTargetId = val;
                          if (val != null) {
                            currentIsGroup = val.startsWith('G_');
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    String? finalTarget = currentTargetId;
                    if (finalTarget != null) {
                      finalTarget = finalTarget.substring(2); // Quitar prefijo C_ o G_
                    }
                    emergency.saveSettings(currentPhrase, finalTarget, currentIsGroup);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Guardar'),
                )
              ],
            );
          }
        );
      }
    );
  }
}
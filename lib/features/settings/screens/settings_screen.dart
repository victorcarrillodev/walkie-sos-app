import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

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

    final user = authProvider.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Cuenta', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          // Perfil del Usuario
          if (user != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: themeProvider.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: themeProvider.primaryColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: themeProvider.primaryGradient == null ? themeProvider.primaryColor : null,
                      gradient: themeProvider.primaryGradient,
                    ),
                    child: Center(
                      child: Text(
                        user.firstName.isNotEmpty ? user.firstName[0].toUpperCase() : 'U',
                        style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${user.firstName} ${user.lastName}'.trim(),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: themeProvider.primaryColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '@${user.alias}',
                            style: TextStyle(
                              fontSize: 14,
                              color: themeProvider.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.email,
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ListTile(
            leading: Icon(Icons.lock, color: themeProvider.primaryColor),
            title: const Text('Cambiar Contraseña'),
            onTap: () => _showChangePasswordDialog(context),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Apariencia', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Tema de la Aplicación'),
            subtitle: Text(themeName),
            onTap: () => _showThemeDialog(context, themeProvider),
          ),
          ListTile(
            leading: const Icon(Icons.color_lens),
            title: const Text('Color Principal'),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: themeProvider.primaryGradient == null ? themeProvider.primaryColor : null,
                gradient: themeProvider.primaryGradient,
              ),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Botón Flotante', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ListTile(
            leading: const Icon(Icons.picture_in_picture_alt, color: Colors.purple),
            title: const Text('Tamaño del botón'),
            onTap: () => _showBubbleSizeDialog(context),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Pantalla de Canal', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          _EqualizerToggleTile(),
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
    final solidColors = [
      const Color(0xFFEF4444), // Rojo Vibrante
      const Color(0xFFF97316), // Naranja Llamativo
      const Color(0xFFF59E0B), // Ámbar
      const Color(0xFFEAB308), // Amarillo
      const Color(0xFF84CC16), // Lima
      const Color(0xFF22C55E), // Verde Brillante
      const Color(0xFF10B981), // Esmeralda
      const Color(0xFF14B8A6), // Teal
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFF0EA5E9), // Azul Claro
      const Color(0xFF3B82F6), // Azul Océano
      const Color(0xFF6366F1), // Índigo
      const Color(0xFF8B5CF6), // Violeta
      const Color(0xFFA855F7), // Morado
      const Color(0xFFD946EF), // Fucsia
      const Color(0xFFEC4899), // Rosa Fuerte
      const Color(0xFFF43F5E), // Rosa Claro
      const Color(0xFFFF0055), // Neón Rosa
      const Color(0xFF00FFCC), // Neón Menta
      const Color(0xFFFFD700), // Dorado Puro
    ];

    final gradients = [
      [const Color(0xFFFF416C), const Color(0xFFFF4B2B)], // Atardecer Naranja
      [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)], // Lluvia Morada
      [const Color(0xFFFC466B), const Color(0xFF3F5EFB)], // Amanecer Rosa
      [const Color(0xFF11998E), const Color(0xFF38EF7D)], // Verde Fresco
      [const Color(0xFF2193B0), const Color(0xFF6DD5ED)], // Brisa Azul
      [const Color(0xFFFF512F), const Color(0xFFF09819)], // Naranja Quemado
      [const Color(0xFF00C6FF), const Color(0xFF0072FF)], // Vista Oceánica
      [const Color(0xFFD38312), const Color(0xFFA83279)], // Caramelo
      [const Color(0xFF00B09B), const Color(0xFF96C93D)], // Neón Cibernético
      [const Color(0xFFFF512F), const Color(0xFFDD2476)], // Bloody Mary
      [const Color(0xFF0CEBEB), const Color(0xFF20E3B2)], // Bajo Cero
      [const Color(0xFF654EA3), const Color(0xFFEAAFC8)], // Púrpura Real
      [const Color(0xFFF09819), const Color(0xFFEDDE5D)], // Pulpa de Mango
      [const Color(0xFFE1EEC3), const Color(0xFFF05053)], // Sol de Terciopelo
      [const Color(0xFF4776E6), const Color(0xFF8E54E9)], // Violeta Eléctrico
      [const Color(0xFFF12711), const Color(0xFFF5AF19)], // Ladrillo de Fuego
      [const Color(0xFFB20A2C), const Color(0xFFFFFBD5)], // Frambuesa Majestuosa
      [const Color(0xFF348F50), const Color(0xFF56B4D3)], // Agua Esmeralda
      [const Color(0xFF232526), const Color(0xFF414345)], // Caballero de la Noche
      [const Color(0xFF141E30), const Color(0xFF243B55)], // Ciudad de Medianoche
    ];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Color Principal'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sólidos', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.start,
                children: solidColors.map((color) {
                  final isSelected = provider.primaryGradient == null && provider.primaryColor.value == color.value;
                  return GestureDetector(
                    onTap: () {
                      provider.setPrimaryColor(color);
                      Navigator.pop(context);
                    },
                    child: CircleAvatar(
                      backgroundColor: color,
                      radius: 20,
                      child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              const Text('Degradados', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.start,
                children: gradients.map((gradColors) {
                  final isSelected = provider.primaryGradient != null && provider.primaryColor.value == gradColors.first.value;
                  return GestureDetector(
                    onTap: () {
                      provider.setPrimaryGradient(gradColors);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: gradColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
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
    final Set<String> currentTargetIds = Set.from(emergency.targetIds);
    
    // Lista de id posibles (Contactos y Grupos)
    final allContactsIds = contactsProvider.contacts.map((c) => 'C_${c.contactId}').toList();
    final allGroupsIds = channelsProvider.myChannels.map((g) => 'G_${g.id}').toList();
    final allPossibleIds = [...allContactsIds, ...allGroupsIds];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final isAllSelected = currentTargetIds.length == allPossibleIds.length && allPossibleIds.isNotEmpty;

            return AlertDialog(
              title: const Text('Configuración de Emergencia'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: currentPhrase,
                      decoration: const InputDecoration(labelText: 'Frase Clave (Ej: ayuda por favor)'),
                      onChanged: (val) => currentPhrase = val,
                    ),
                    const SizedBox(height: 16),
                    const Text('Destinatarios de la alerta:', style: TextStyle(fontWeight: FontWeight.bold)),
                    CheckboxListTile(
                      title: const Text('Seleccionar todos', style: TextStyle(fontWeight: FontWeight.bold)),
                      value: isAllSelected,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            currentTargetIds.addAll(allPossibleIds);
                          } else {
                            currentTargetIds.clear();
                          }
                        });
                      },
                      dense: true,
                    ),
                    const Divider(),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (contactsProvider.contacts.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                              child: Text('Contactos', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            ),
                            ...contactsProvider.contacts.map((c) {
                              final id = 'C_${c.contactId}';
                              return CheckboxListTile(
                                title: Text('👤 ${c.alias} / ${c.name}'),
                                value: currentTargetIds.contains(id),
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      currentTargetIds.add(id);
                                    } else {
                                      currentTargetIds.remove(id);
                                    }
                                  });
                                },
                                dense: true,
                              );
                            }),
                          ],
                          if (channelsProvider.myChannels.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                              child: Text('Grupos', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            ),
                            ...channelsProvider.myChannels.map((g) {
                              final id = 'G_${g.id}';
                              return CheckboxListTile(
                                title: Text('👥 ${g.name}'),
                                value: currentTargetIds.contains(id),
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      currentTargetIds.add(id);
                                    } else {
                                      currentTargetIds.remove(id);
                                    }
                                  });
                                },
                                dense: true,
                              );
                            }),
                          ],
                        ]
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    emergency.saveSettings(currentPhrase, currentTargetIds.toList());
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

  void _showBubbleSizeDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    String currentSize = prefs.getString('bubble_size') ?? 'medium';
    
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Tamaño del botón'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: const Text('Chico'),
                    value: 'small',
                    groupValue: currentSize,
                    onChanged: (val) {
                      setState(() => currentSize = val!);
                      prefs.setString('bubble_size', currentSize);
                      FlutterOverlayWindow.shareData('SIZE:$currentSize');
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('Mediano'),
                    value: 'medium',
                    groupValue: currentSize,
                    onChanged: (val) {
                      setState(() => currentSize = val!);
                      prefs.setString('bubble_size', currentSize);
                      FlutterOverlayWindow.shareData('SIZE:$currentSize');
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('Grande'),
                     value: 'large',
                     groupValue: currentSize,
                     onChanged: (val) {
                       setState(() => currentSize = val!);
                       prefs.setString('bubble_size', currentSize);
                       FlutterOverlayWindow.shareData('SIZE:$currentSize');
                     },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    bool isLoading = false;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Cambiar Contraseña'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(errorMessage!, style: const TextStyle(color: Colors.red)),
                      ),
                    TextField(
                      controller: currentPasswordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Contraseña Actual'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: newPasswordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Nueva Contraseña'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: confirmPasswordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Confirmar Nueva Contraseña'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final currentPass = currentPasswordCtrl.text.trim();
                          final newPass = newPasswordCtrl.text.trim();
                          final confirmPass = confirmPasswordCtrl.text.trim();

                          if (currentPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
                            setState(() => errorMessage = 'Todos los campos son obligatorios');
                            return;
                          }

                          if (newPass != confirmPass) {
                            setState(() => errorMessage = 'Las nuevas contraseñas no coinciden');
                            return;
                          }

                          if (newPass.length < 6) {
                            setState(() => errorMessage = 'La nueva contraseña debe tener al menos 6 caracteres');
                            return;
                          }

                          setState(() {
                            isLoading = true;
                            errorMessage = null;
                          });

                          final authProvider = context.read<AuthProvider>();
                          final success = await authProvider.changePassword(currentPass, newPass);

                          if (!ctx.mounted) return;

                          if (success) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Contraseña cambiada exitosamente'), backgroundColor: Colors.green),
                            );
                          } else {
                            setState(() {
                              isLoading = false;
                              errorMessage = authProvider.error ?? 'Error al cambiar la contraseña';
                            });
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Cambiar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ─── Toggle para mostrar/ocultar el ecualizador ───────────────────────────
class _EqualizerToggleTile extends StatefulWidget {
  @override
  State<_EqualizerToggleTile> createState() => _EqualizerToggleTileState();
}

class _EqualizerToggleTileState extends State<_EqualizerToggleTile> {
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _enabled = prefs.getBool('show_equalizer') ?? true);
  }

  Future<void> _toggle(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_equalizer', val);
    if (mounted) setState(() => _enabled = val);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.equalizer, color: Colors.teal),
      title: const Text('Barras de Ecualizador'),
      subtitle: const Text('Mostrar animación al hablar en el canal'),
      value: _enabled,
      onChanged: _toggle,
    );
  }
}
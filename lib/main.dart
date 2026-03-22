import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/providers/auth_provider.dart';
import 'core/providers/channel_provider.dart';
import 'core/providers/contact_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/presence_provider.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/groups/screens/groups_screen.dart';
import 'features/contacts/screens/contacts_screen.dart';
import 'features/recents/screens/recents_screen.dart';
import 'core/services/bubble_service.dart';
import 'core/services/socket_service.dart';
import 'core/services/emergency_service.dart';

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    color: Colors.transparent,
    home: OverlayWidget(),
  ));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WalkieSosApp());
}

class WalkieSosApp extends StatelessWidget {
  const WalkieSosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChannelProvider()),
        ChangeNotifierProvider(create: (_) => ContactProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) {
          final p = PresenceProvider();
          p.startListening();
          return p;
        }),
        ChangeNotifierProvider(
          create: (_) {
            final e = EmergencyService();
            e.init();
            return e;
          },
          lazy: false,
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'WalkieSOS',
            debugShowCheckedModeBanner: false,
            // Aplicamos el modo seleccionado (Claro/Oscuro/Sistema)
            themeMode: themeProvider.themeMode, 
            
            // CONFIGURACIÓN TEMA CLARO
            theme: ThemeData.light().copyWith(
              colorScheme: ColorScheme.light(primary: themeProvider.primaryColor),
              scaffoldBackgroundColor: const Color(0xFFF5F5F5),
              appBarTheme: AppBarTheme(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
                iconTheme: const IconThemeData(color: Colors.black),
                titleTextStyle: TextStyle(
                  color: themeProvider.primaryColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
            // CONFIGURACIÓN TEMA OSCURO
            darkTheme: ThemeData.dark().copyWith(
              colorScheme: ColorScheme.dark(primary: themeProvider.primaryColor),
              scaffoldBackgroundColor: const Color(0xFF0A0A0A),
              appBarTheme: AppBarTheme(
                backgroundColor: const Color(0xFF0A0A0A),
                foregroundColor: Colors.white,
                elevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
                titleTextStyle: TextStyle(
                  color: themeProvider.primaryColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            home: const AppRoot(),
          );
        }
      ),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    await context.read<AuthProvider>().tryAutoLogin();
    if (mounted) setState(() => _checked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary, // Color dinámico
          ),
        ),
      );
    }
    final isLoggedIn = context.watch<AuthProvider>().isLoggedIn;
    return isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0; 

  bool _isAlertActive = false;
  bool _isAlertExpanded = false;
  Map<String, dynamic>? _activeAlertData;

  final List<Widget> _screens = const [
    RecentsScreen(),
    ContactsScreen(),
    GroupsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _registerEmergencyListener();
  }

  void _registerEmergencyListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SocketService().socket?.on('emergency-alert', _onEmergencyAlert);
      SocketService().socket?.on('alert-resolved', _onAlertResolved);
      SocketService().onOnlineStatus((_) {
        SocketService().socket?.off('emergency-alert', _onEmergencyAlert);
        SocketService().socket?.on('emergency-alert', _onEmergencyAlert);
        SocketService().socket?.off('alert-resolved', _onAlertResolved);
        SocketService().socket?.on('alert-resolved', _onAlertResolved);
      });
    });
  }

  @override
  void dispose() {
    SocketService().socket?.off('emergency-alert', _onEmergencyAlert);
    SocketService().socket?.off('alert-resolved', _onAlertResolved);
    super.dispose();
  }

  void _onEmergencyAlert(dynamic data) {
    if (!mounted) return;
    debugPrint('¡ALERTA RECIBIDA!: $data');
    
    setState(() {
      _isAlertActive = true;
      _isAlertExpanded = true;
      _activeAlertData = data;
    });
  }

  void _onAlertResolved(dynamic data) {
    if (!mounted) return;
    final alertId = data['alertId'];
    if (_activeAlertData != null && _activeAlertData!['id'] == alertId) {
      setState(() {
        _isAlertActive = false;
        _isAlertExpanded = false;
        _activeAlertData = null;
      });
    }
  }

  void _confirmTerminateAlert(String alertId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Terminar Alerta?'),
        content: const Text('Esto cancelará la alerta para todos los participantes. ¿Deseas continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              final channelId = _activeAlertData?['channelId'] ?? '';
              SocketService().socket?.emit('resolve-alert', { 'alertId': alertId, 'channelId': channelId });
              setState(() {
                _isAlertActive = false;
                _isAlertExpanded = false;
                _activeAlertData = null;
              });
            },
            child: const Text('Terminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Detectamos si el fondo general debe ser oscuro o claro
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          
          // --- BANNER DE ALERTA MINIMIZADA ---
          if (_isAlertActive && !_isAlertExpanded && _activeAlertData != null)
             Positioned(
               bottom: 16,
               left: 16,
               right: 16,
               child: GestureDetector(
                 onTap: () => setState(() => _isAlertExpanded = true),
                 child: Material(
                   elevation: 10,
                   borderRadius: BorderRadius.circular(12),
                   child: Container(
                     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                     decoration: BoxDecoration(
                       color: Colors.red.shade700,
                       borderRadius: BorderRadius.circular(12),
                     ),
                     child: Row(
                       children: [
                         const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                         const SizedBox(width: 12),
                         Expanded(
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               const Text('ALERTA ACTIVA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                               Text('De @${_activeAlertData!['user']?['alias'] ?? 'Desconocido'}', style: const TextStyle(color: Colors.white70)),
                             ],
                           )
                         ),
                         const Icon(Icons.open_in_full, color: Colors.white),
                       ],
                     )
                   ),
                 ),
               ),
             ),

          // --- OVERLAY DE ALERTA EXPANDIDA (PANTALLA COMPLETA) ---
          if (_isAlertActive && _isAlertExpanded && _activeAlertData != null)
             Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.85),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, -5))],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                          child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning, color: Colors.red, size: 32),
                                const SizedBox(width: 12),
                                const Expanded(child: Text('¡ALERTA DE EMERGENCIA!', style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text('El usuario @${_activeAlertData!['user']?['alias'] ?? 'Desconocido'} activó un código de pánico. Ubicación en tiempo real:', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 280,
                              width: double.maxFinite,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: FlutterMap(
                                  options: MapOptions(
                                    initialCenter: LatLng(
                                      (_activeAlertData!['location']?['lat'] ?? 0.0).toDouble(),
                                      (_activeAlertData!['location']?['lng'] ?? 0.0).toDouble()
                                    ),
                                    initialZoom: 16.0,
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName: 'com.walkiesos.app',
                                    ),
                                    MarkerLayer(
                                      markers: [
                                        Marker(
                                          point: LatLng(
                                            (_activeAlertData!['location']?['lat'] ?? 0.0).toDouble(),
                                            (_activeAlertData!['location']?['lng'] ?? 0.0).toDouble()
                                          ),
                                          width: 40,
                                          height: 40,
                                          child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.close_fullscreen),
                                    label: const Text('Minimizar'),
                                    onPressed: () => setState(() => _isAlertExpanded = false),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                    icon: const Icon(Icons.stop_circle),
                                    label: const Text('Terminar'),
                                    onPressed: () {
                                       if (_activeAlertData != null) {
                                          _confirmTerminateAlert(_activeAlertData!['id']);
                                       }
                                    },
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                    ),
                  )
                )
             ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2), width: 0.5)),
        ),
        child: BottomNavigationBar(
          // Se adapta al modo claro y oscuro
          backgroundColor: isDark ? const Color(0xFF0F0F0F) : Colors.white,
          selectedItemColor: primaryColor,
          unselectedItemColor: Colors.grey,
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed, 
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Recientes'),
            BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Contactos'),
            BottomNavigationBarItem(icon: Icon(Icons.groups), label: 'Grupos'),
          ],
        ),
      ),
    );
  }
}
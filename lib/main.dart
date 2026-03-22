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
        ChangeNotifierProvider(create: (_) {
          final e = EmergencyService();
          e.init();
          return e;
        }),
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

  final List<Widget> _screens = const [
    RecentsScreen(),
    ContactsScreen(),
    GroupsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Registramos el listener de emergencias del mapa cuando entramos a la app
    _registerEmergencyListener();
  }

  void _registerEmergencyListener() {
    // Es posible que el socket no esté listo enseguida, esperamos frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SocketService().socket?.on('emergency-alert', _onEmergencyAlert);
      SocketService().onOnlineStatus((_) {
        // En caso de que se reconecte el socket, volvemos a registrar
        SocketService().socket?.off('emergency-alert', _onEmergencyAlert);
        SocketService().socket?.on('emergency-alert', _onEmergencyAlert);
      });
    });
  }

  @override
  void dispose() {
    SocketService().socket?.off('emergency-alert', _onEmergencyAlert);
    super.dispose();
  }

  void _onEmergencyAlert(dynamic data) {
    if (!mounted) return;
    debugPrint('¡ALERTA RECIBIDA!: $data');
    
    final lat = data['location']?['lat'] ?? 0.0;
    final lng = data['location']?['lng'] ?? 0.0;
    final alias = data['user']?['alias'] ?? 'Desconocido';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            const Expanded(child: Text('¡ALERTA DE EMERGENCIA!', style: TextStyle(color: Colors.red))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('El usuario @$alias activó un código de pánico. Ubicación en tiempo real:', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              width: double.maxFinite,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lng),
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
                          point: LatLng(lat, lng),
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
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Cerrar Mapeo', style: TextStyle(color: Colors.white)),
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
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
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
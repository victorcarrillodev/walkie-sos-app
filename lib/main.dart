import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers/auth_provider.dart';
import 'core/providers/channel_provider.dart';
import 'core/providers/contact_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/presence_provider.dart';

import 'features/auth/screens/login_screen.dart';
import 'features/groups/screens/groups_screen.dart';
import 'features/contacts/screens/contacts_screen.dart';
import 'features/recents/screens/recents_screen.dart';
import 'core/services/bubble_service.dart';
import 'core/services/emergency_service.dart';
import 'core/widgets/global_emergency_overlay.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

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
  
  final prefs = await SharedPreferences.getInstance();
  final themeModeIndex = prefs.getInt('themeMode') ?? ThemeMode.dark.index;
  final primaryColorValue = prefs.getInt('primaryColor') ?? 0xFF00E676;
  
  List<Color>? primaryGradientColors;
  final gradientString = prefs.getString('primaryGradient');
  if (gradientString != null && gradientString.isNotEmpty) {
    try {
      primaryGradientColors = gradientString.split(',').map((s) => Color(int.parse(s))).toList();
    } catch (_) {}
  }

  runApp(WalkieSosApp(
    initialThemeMode: ThemeMode.values[themeModeIndex],
    initialPrimaryColor: Color(primaryColorValue),
    initialPrimaryGradientColors: primaryGradientColors,
  ));
}

class WalkieSosApp extends StatelessWidget {
  final ThemeMode initialThemeMode;
  final Color initialPrimaryColor;
  final List<Color>? initialPrimaryGradientColors;

  const WalkieSosApp({
    super.key,
    required this.initialThemeMode,
    required this.initialPrimaryColor,
    this.initialPrimaryGradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChannelProvider()),
        ChangeNotifierProvider(create: (_) => ContactProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider(
          initialThemeMode: initialThemeMode,
          initialPrimaryColor: initialPrimaryColor,
          initialPrimaryGradientColors: initialPrimaryGradientColors,
        )),
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
            navigatorKey: GlobalEmergencyOverlay.navigatorKey,
            builder: (context, child) {
              return GlobalEmergencyOverlay(child: child!);
            },
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
    _initialize();
  }

  Future<void> _initialize() async {
    // 1. Continuar y checar sesión primero para no bloquear la pantalla de carga
    await context.read<AuthProvider>().tryAutoLogin();
    if (mounted) setState(() => _checked = true);

    // 2. Pedir permisos principales
    try {
      await [
        Permission.microphone,
        Permission.location,
        Permission.notification,
      ].request();

      // 3. Pedir permiso de superposición si falta (sin await para no congelar la UI)
      final isOverlayGranted = await FlutterOverlayWindow.isPermissionGranted();
      if (isOverlayGranted == false) {
        FlutterOverlayWindow.requestPermission();
      }
    } catch (_) {}
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
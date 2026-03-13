import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/providers/auth_provider.dart';
import 'core/providers/channel_provider.dart';
import 'core/providers/contact_provider.dart';
import 'core/providers/theme_provider.dart'; // <-- IMPORTADO

import 'features/auth/screens/login_screen.dart';
import 'features/channels/screens/channels_screen.dart';
import 'features/contacts/screens/contacts_screen.dart';
import 'features/recents/screens/recents_screen.dart';

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
        ChangeNotifierProvider(create: (_) => ThemeProvider()), // <-- REGISTRADO
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
    ChannelsScreen(),
  ];

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
            BottomNavigationBarItem(icon: Icon(Icons.radio), label: 'Canales'),
          ],
        ),
      ),
    );
  }
}
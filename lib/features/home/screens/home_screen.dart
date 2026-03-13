import 'package:flutter/material.dart';

import '../../channels/screens/channels_screen.dart';
import '../../contacts/screens/contacts_screen.dart';
import '../../recents/screens/recents_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Iniciar en la pestaña 0 (Recientes)
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const RecentsScreen(),
    const ContactsScreen(),
    const ChannelsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      // IndexedStack mantiene vivas las pantallas al cambiar de pestaña
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2), width: 0.5)),
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF0F0F0F),
          selectedItemColor: const Color(0xFF00E676),
          unselectedItemColor: Colors.grey,
          currentIndex: _selectedIndex,
          type: BottomNavigationBarType.fixed,
          onTap: (index) => setState(() => _selectedIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'Recientes',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Contactos',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.group),
              label: 'Canales',
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'contacts_screen.dart';
import 'channels_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Creamos un controlador para 2 pestañas: Contactos y Canales
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Walkie SOS'),
        centerTitle: true,
        // Aquí definimos las pestañas visuales
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orange,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.person), text: 'Contactos'),
            Tab(icon: Icon(Icons.radio), text: 'Canales'),
          ],
        ),
      ),
      // El TabBarView muestra la pantalla correspondiente a la pestaña seleccionada
      body: TabBarView(
        controller: _tabController,
        children: const [
          ContactsScreen(), // Tu pantalla de contactos
          ChannelsScreen(), // Tu pantalla de canales
        ],
      ),
    );
  }
}
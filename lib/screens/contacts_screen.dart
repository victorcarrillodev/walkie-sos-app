import 'package:flutter/material.dart';
import '../core/socket_client.dart';
import '../core/contacts_service.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  _ContactsScreenState createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<dynamic> _contactos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    SocketClient.connect();
    _cargarContactos();
  }

  Future<void> _cargarContactos() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final contactos = await ContactsService.getContacts();
    if (mounted) {
      setState(() {
        _contactos = contactos;
        _isLoading = false;
      });
    }
  }

  void _mostrarDialogoAgregar() {
    final TextEditingController aliasController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Contacto'),
        content: TextField(
          controller: aliasController,
          decoration: const InputDecoration(
            labelText: 'Alias del compa',
            hintText: 'Ej. JuanPerez',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final alias = aliasController.text.trim();
              if (alias.isNotEmpty) {
                Navigator.pop(context);
                bool exito = await ContactsService.addContact(alias);
                if (exito) {
                  _cargarContactos();
                }
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  void _iniciarLlamada(dynamic contacto) {
    String? contactId = contacto['contactId']?.toString() ?? contacto['id']?.toString();
    String alias = contacto['alias']?.toString() ?? 
                 contacto['contactUser']?['alias']?.toString() ?? 'Contacto';

    if (contactId != null) {
      SocketClient.joinChannel(contactId);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(contactId: contactId, alias: alias),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold sin AppBar para que no se duplique con la HomeScreen
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _cargarContactos,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _contactos.isEmpty
                ? const Center(child: Text('No tienes contactos aún.'))
                : ListView.builder(
                    itemCount: _contactos.length,
                    itemBuilder: (context, index) {
                      final contacto = _contactos[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(contacto['alias'] ?? 'Sin alias'),
                        subtitle: const Text('Toca para hablar'),
                        trailing: const Icon(Icons.settings_voice, color: Colors.blue),
                        onTap: () => _iniciarLlamada(contacto),
                      );
                    },
                  ),
      ),
      // Mantenemos el botón flotante aquí
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarDialogoAgregar,
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
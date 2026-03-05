import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/channel_model.dart';
import '../../../core/models/contact_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/contact_provider.dart';
import '../../../core/services/api_service.dart';
import '../../call/screens/call_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final ApiService _api = ApiService();
  String? _loadingContactId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactProvider>().loadContacts();
    });
  }

  void _showAddContactDialog() {
    final aliasCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Agregar Contacto',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: aliasCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Alias del contacto',
            labelStyle: TextStyle(color: Colors.grey),
            prefixIcon: Icon(Icons.alternate_email, color: Colors.grey),
            filled: true,
            fillColor: Color(0xFF2A2A2A),
            border: OutlineInputBorder(borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676)),
            onPressed: () async {
              if (aliasCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              final ok = await context
                  .read<ContactProvider>()
                  .addContact(aliasCtrl.text.trim());
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? '¡Contacto agregado!'
                      : context.read<ContactProvider>().error ?? 'Error'),
                  backgroundColor:
                      ok ? const Color(0xFF00E676) : Colors.red,
                ));
              }
            },
            child:
                const Text('Agregar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> _openDirectCall(ContactModel contact) async {
    final myUserId = context.read<AuthProvider>().user!.id;

    setState(() => _loadingContactId = contact.contactId);

    try {
      final channelData = await _api.createDirectChannel(
        myUserId,
        contact.contactId,
      );

      if (!mounted) return;

      // Construimos el canal con los datos disponibles
      final channel = ChannelModel(
        id: channelData['id'] ?? '',
        name: contact.name,
        description: 'Chat directo con @${contact.alias}',
        isPrivate: true,
        isGroup: false,
      );

      if (channel.id.isEmpty) {
        throw Exception('No se pudo obtener el canal');
      }

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CallScreen(channel: channel)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir canal: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingContactId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Contactos',
            style: TextStyle(color: Colors.white, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined, color: Color(0xFF00E676)),
            onPressed: _showAddContactDialog,
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E676)))
          : provider.contacts.isEmpty
              ? _emptyState()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: provider.contacts.length,
                  separatorBuilder: (_, __) => const Divider(
                    color: Color(0xFF1A1A1A),
                    height: 1,
                    indent: 72,
                  ),
                  itemBuilder: (_, i) =>
                      _contactTile(provider.contacts[i]),
                ),
      floatingActionButton: provider.contacts.isNotEmpty
          ? FloatingActionButton(
              onPressed: _showAddContactDialog,
              backgroundColor: const Color(0xFF00E676),
              child: const Icon(Icons.person_add, color: Colors.black),
            )
          : null,
    );
  }

  Widget _contactTile(ContactModel contact) {
    final isLoading = _loadingContactId == contact.contactId;

    return ListTile(
      onTap: isLoading ? null : () => _openDirectCall(contact),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFF1A1A1A),
        child: Text(
          contact.alias[0].toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF00E676),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      title: Text(contact.name,
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: Text(
        '@${contact.alias}',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      trailing: isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Color(0xFF00E676),
                strokeWidth: 2,
              ),
            )
          : Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF00E676).withOpacity(0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic, size: 14, color: Color(0xFF00E676)),
                  SizedBox(width: 4),
                  Text('Hablar',
                      style: TextStyle(
                          color: Color(0xFF00E676), fontSize: 12)),
                ],
              ),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No tienes contactos aún',
              style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 6),
          const Text('Agrega a alguien por su alias',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _showAddContactDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.person_add, color: Colors.black),
            label: const Text('Agregar contacto',
                style:
                    TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/channel_model.dart';
import '../../../core/models/contact_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/contact_provider.dart';
import '../../../core/providers/presence_provider.dart';
import '../../../core/services/api_service.dart';
import '../../call/screens/call_screen.dart';

import '../../settings/screens/settings_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ContactProvider>().loadContacts();
      if (!mounted) return;
      final ids = context.read<ContactProvider>().contacts.map((c) => c.contactId).toList();
      context.read<PresenceProvider>().checkPresence(ids);
    });
  }

  void _showAddContactDialog() {
    final aliasCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        title: Text('Agregar Contacto',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: TextField(
          controller: aliasCtrl,
          autofocus: true,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            labelText: 'Alias del contacto',
            labelStyle: const TextStyle(color: Colors.grey),
            prefixIcon: const Icon(Icons.alternate_email, color: Colors.grey),
            filled: true,
            fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
            border: const OutlineInputBorder(borderSide: BorderSide.none),
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
                backgroundColor: Theme.of(context).colorScheme.primary),
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
                      ok ? Theme.of(context).colorScheme.primary : Colors.red,
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
        MaterialPageRoute(builder: (_) => CallScreen(
          channel: channel,
          targetUserId: contact.contactId,
        )),
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
      appBar: AppBar(
        title: const Text('Contactos'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: provider.isLoading
          ? Center(
              child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
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
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.person_add, color: Colors.black),
            )
          : null,
    );
  }

  Widget _contactTile(ContactModel contact) {
    final isLoading = _loadingContactId == contact.contactId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = context.watch<PresenceProvider>().isOnline(contact.contactId);

    return ListTile(
      onTap: isLoading ? null : () => _openDirectCall(contact),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade300,
            child: Text(
              contact.alias[0].toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF0A0A0A) : Colors.white,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(contact.name,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.w600)),
      subtitle: Text(
        '@${contact.alias}',
        style: const TextStyle(color: Colors.grey, fontSize: 13),
      ),
      trailing: isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 2,
              ),
            )
          : Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Text('Hablar',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary, fontSize: 12)),
                ],
              ),
            ),
    );
  }

  Widget _emptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          Text('No tienes contactos aún',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 18)),
          const SizedBox(height: 6),
          const Text('Agrega a alguien por su alias',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _showAddContactDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/channel_model.dart';
import '../../../core/providers/channel_provider.dart';
import '../../../core/providers/auth_provider.dart';

class GroupSettingsScreen extends StatefulWidget {
  final ChannelModel channel;

  const GroupSettingsScreen({super.key, required this.channel});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  bool _isLoading = true;
  bool _isMuted = false;
  List<dynamic> _members = [];
  late String _myUserId;

  @override
  void initState() {
    super.initState();
    _myUserId = context.read<AuthProvider>().user!.id;
    // Forzamos el estado de isMuted para que coincida con el canal por defecto
    // aunque un fetch reciente de la info del canal de la API sería mejor,
    // usaremos el de local, y mutamos asumiendo true/false basados en DB
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final provider = context.read<ChannelProvider>();
    // Necesitamos que el canal tenga la prop isMuted, pero el modelo ChannelModel 
    // en el frontend quizás no la tenga mapeada. Lo simplificamos o asumiendo _isMuted.
    try {
      final members = await provider.getChannelMembers(widget.channel.id);
      if (mounted) {
        setState(() {
          _members = members;
          _isLoading = false;
          // Actualizar isMuted si logramos agregarlo al modelo o leerlo después
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleMute(bool value) async {
    setState(() => _isMuted = value);
    final ok = await context.read<ChannelProvider>().toggleMuteChannel(widget.channel.id, value);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error al cambiar configuración del canal'),
        backgroundColor: Colors.red,
      ));
      setState(() => _isMuted = !value); // Revertir visualmente
    }
  }

  void _showPenalizeDialog(Map<String, dynamic> member) {
    if (member['role'] == 'ADMIN' || member['userId'] == _myUserId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No puedes penalizar a este usuario'),
      ));
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String alias = member['user']['alias'];
    final bool isPunished = member['mutedUntil'] != null && DateTime.parse(member['mutedUntil']).isAfter(DateTime.now());

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Administrar a @$alias', 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            if (isPunished)
              ListTile(
                leading: const Icon(Icons.volume_up, color: Colors.green),
                title: const Text('Quitar penalización'),
                onTap: () async {
                  Navigator.pop(context);
                  await context.read<ChannelProvider>().penalizeMember(widget.channel.id, member['userId'], null);
                  _loadData();
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('Silenciar por 1 día'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, member['userId'], 1440);
                _loadData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('Silenciar por 1 semana'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, member['userId'], 10080);
                _loadData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('Silenciar por 1 mes'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, member['userId'], 43200);
                _loadData();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Eliminar grupo?'),
        content: const Text('Esta acción no se puede deshacer. Se eliminará el grupo y todos sus mensajes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              final ok = await context.read<ChannelProvider>().deleteChannel(widget.channel.id);
              if (ok && mounted) {
                // Volver hasta Home
                Navigator.popUntil(context, (r) => r.isFirst);
              }
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuración del grupo')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes (Admin)'),
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          SwitchListTile(
            title: const Text('Silenciar a todos', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Solo tú y otros administradores podrán enviar audios.'),
            value: _isMuted,
            secondary: const Icon(Icons.volume_off),
            activeThumbColor: Theme.of(context).colorScheme.primary,
            onChanged: _toggleMute,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: Text('MIEMBROS DEL GRUPO (${_members.length})', 
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          ..._members.map((member) {
            final String alias = member['user']['alias'];
            final String role = member['role'];
            final bool isPunished = member['mutedUntil'] != null && DateTime.parse(member['mutedUntil']).isAfter(DateTime.now());
            
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: role == 'ADMIN' ? Theme.of(context).colorScheme.primary : (isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade300),
                child: Icon(role == 'ADMIN' ? Icons.star : Icons.person, color: role == 'ADMIN' ? Colors.black : Colors.grey),
              ),
              title: Text('@$alias', style: TextStyle(fontWeight: role == 'ADMIN' ? FontWeight.bold : FontWeight.normal)),
              subtitle: isPunished 
                  ? Text('Silenciado hasta: ${DateTime.parse(member['mutedUntil']).toLocal().toString().substring(0, 16)}', style: const TextStyle(color: Colors.red, fontSize: 11))
                  : Text(role == 'ADMIN' ? 'Administrador' : 'Miembro', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              trailing: role != 'ADMIN' ? const Icon(Icons.more_vert, color: Colors.grey) : null,
              onTap: () => _showPenalizeDialog(member),
            );
          }),
          const SizedBox(height: 32),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever, color: Colors.white),
              label: const Text('ELIMINAR GRUPO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _confirmDelete,
            ),
          )
        ],
      ),
    );
  }
}

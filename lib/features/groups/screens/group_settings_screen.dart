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
  String _myRole = 'USER';

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
      final me = members.firstWhere((m) => m['userId'] == _myUserId, orElse: () => null);
      if (mounted) {
        setState(() {
          _members = members;
          _myRole = me?['role'] ?? 'USER';
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
    if (member['userId'] == _myUserId) return;
    
    // Reglas de jerarquía
    if (member['role'] == 'ADMIN') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No puedes modificar a un Administrador.'),
      ));
      return;
    }
    
    if (_myRole == 'MODERATOR' && member['role'] == 'MODERATOR') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Un moderador no puede modificar a otro moderador.'),
      ));
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String alias = member['user']['alias'];
    final bool isPunished = member['mutedUntil'] != null && DateTime.parse(member['mutedUntil']).isAfter(DateTime.now());
    final bool isAdmin = _myRole == 'ADMIN';
    final bool isMemberModerator = member['role'] == 'MODERATOR';

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
            if (isAdmin && !isMemberModerator)
              ListTile(
                leading: const Icon(Icons.shield, color: Colors.blue),
                title: const Text('Hacer Moderador'),
                onTap: () async {
                  Navigator.pop(context);
                  await context.read<ChannelProvider>().changeMemberRole(widget.channel.id, member['userId'], 'MODERATOR');
                  _loadData();
                },
              ),
            if (isAdmin && isMemberModerator)
              ListTile(
                leading: const Icon(Icons.remove_moderator, color: Colors.grey),
                title: const Text('Quitar Moderador'),
                onTap: () async {
                  Navigator.pop(context);
                  await context.read<ChannelProvider>().changeMemberRole(widget.channel.id, member['userId'], 'USER');
                  _loadData();
                },
              ),
            if (isAdmin) const Divider(),
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
              title: const Text('Silenciar por 5 minutos'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, member['userId'], 5);
                _loadData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('Silenciar por 10 minutos'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, member['userId'], 10);
                _loadData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('Silenciar por 15 minutos'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, member['userId'], 15);
                _loadData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('Silenciar por 20 minutos'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, member['userId'], 20);
                _loadData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('Silenciar por 30 minutos'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, member['userId'], 30);
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

  void _showEditSettingsDialog() {
    final pwdCtrl = TextEditingController();
    double durationVal = widget.channel.maxMessageDuration.toDouble();
    if (durationVal < 5) durationVal = 5;
    if (durationVal > 60) durationVal = 60;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context, 
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          title: Text('Ajustes del grupo', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pwdCtrl,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Nueva contraseña (opcional)',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              Text('Duración máx. mensajes: ${durationVal.toInt()}s', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              Slider(
                value: durationVal,
                min: 5,
                max: 60,
                divisions: 11, // Saltos de 5 segundos
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (v) => setDlg(() => durationVal = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
              onPressed: () async {
                Navigator.pop(ctx);
                final pwd = pwdCtrl.text.trim();
                final ok = await context.read<ChannelProvider>().updateChannelSettings(
                  widget.channel.id, 
                  password: pwd.isNotEmpty ? pwd : null,
                  maxMessageDuration: durationVal.toInt(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'Ajustes actualizados con éxito' : 'Error al actualizar'),
                      backgroundColor: ok ? Colors.green : Colors.red,
                    )
                  );
                }
              },
              child: const Text('Guardar', style: TextStyle(color: Colors.black)),
            )
          ]
        ),
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
          if (_myRole == 'ADMIN') ...[
            SwitchListTile(
              title: const Text('Silenciar a todos', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Solo tú y otros administradores podrán enviar audios.'),
              value: _isMuted,
              secondary: const Icon(Icons.volume_off),
              activeThumbColor: Theme.of(context).colorScheme.primary,
              onChanged: _toggleMute,
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Configuración avanzada', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Cambiar contraseña y duración de audio.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showEditSettingsDialog,
            ),
            const Divider(),
          ],
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: Text('MIEMBROS DEL GRUPO (${_members.length})', 
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          ..._members.map((member) {
            final String alias = member['user']['alias'];
            final String role = member['role'];
            final bool isPunished = member['mutedUntil'] != null && DateTime.parse(member['mutedUntil']).isAfter(DateTime.now());
            
            Color avatarColor = isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade300;
            IconData avatarIcon = Icons.person;
            Color iconColor = Colors.grey;
            
            if (role == 'ADMIN') {
              avatarColor = Theme.of(context).colorScheme.primary;
              avatarIcon = Icons.star;
              iconColor = Colors.black;
            } else if (role == 'MODERATOR') {
              avatarColor = Colors.orange.withOpacity(0.2);
              avatarIcon = Icons.shield;
              iconColor = Colors.orange;
            }

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: avatarColor,
                child: Icon(avatarIcon, color: iconColor),
              ),
              title: Text('@$alias', style: TextStyle(fontWeight: role == 'ADMIN' ? FontWeight.bold : FontWeight.normal)),
              subtitle: isPunished 
                  ? Text('Silenciado hasta: ${DateTime.parse(member['mutedUntil']).toLocal().toString().substring(0, 16)}', style: const TextStyle(color: Colors.red, fontSize: 11))
                  : Text(role == 'ADMIN' ? 'Administrador' : (role == 'MODERATOR' ? 'Moderador' : 'Miembro'), style: TextStyle(color: role == 'MODERATOR' ? Colors.orange : Colors.grey.shade500, fontSize: 12)),
              trailing: (role != 'ADMIN' && member['userId'] != _myUserId) ? const Icon(Icons.more_vert, color: Colors.grey) : null,
              onTap: () => _showPenalizeDialog(member),
            );
          }),
          if (_myRole == 'ADMIN') ...[
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
          ]
        ],
      ),
    );
  }
}

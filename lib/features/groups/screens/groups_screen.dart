import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/channel_provider.dart';
import '../../../core/models/channel_model.dart';
import '../../call/screens/call_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../../core/utils/gradient_extension.dart';
import '../../../core/providers/theme_provider.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ChannelProvider>().loadMyChannels();
    });
  }

  // Solo canales grupales (isGroup: true y nombre no empieza con "direct_")
  List<ChannelModel> _filterGroups(List<ChannelModel> channels) {
    return channels
        .where((c) => c.isGroup && !c.name.startsWith('direct_'))
        .toList();
  }

  void _showJoinOrCreateDialog() {
    final nameCtrl = TextEditingController();
    final pwdCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    double durationVal = 60.0;
    
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          title: Text('Crear o Unirse a un Grupo',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Si el grupo existe, ingresarás usando la contraseña. Si no existe, se creará.', 
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: const InputDecoration(
                    labelText: 'Nombre del grupo (Obligatorio)',
                    labelStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.group, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pwdCtrl,
                  obscureText: true,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: const InputDecoration(
                    labelText: 'Contraseña (Obligatorio)',
                    labelStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.lock, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const Text('Opciones (solo si se crea el grupo)', 
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    labelStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.description_outlined, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.timer, color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Text('Duración máx. mensajes: ${durationVal.toInt()}s',
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13)),
                  ],
                ),
                Slider(
                  value: durationVal,
                  min: 5,
                  max: 60,
                  divisions: 11, // Saltos de 5 segundos
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (val) => setDlg(() => durationVal = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary),
              icon: const Icon(Icons.login, color: Colors.black, size: 18),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final password = pwdCtrl.text.trim();
                if (name.isEmpty || password.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('El nombre y contraseña son requeridos.'), backgroundColor: Colors.red),
                  );
                  return;
                }
                
                Navigator.pop(ctx);
                final ok = await context.read<ChannelProvider>().joinOrCreateGroup(
                  name,
                  password,
                  description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  maxMessageDuration: durationVal.toInt(),
                );
                
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.read<ChannelProvider>().error ?? 'No se pudo acceder o crear el grupo.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              label: const Text('Aceptar', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  void _openGroup(ChannelModel channel) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CallScreen(channel: channel)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final channels = context.watch<ChannelProvider>();
    final myGroups = _filterGroups(channels.myChannels);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mis Grupos',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            Text('@${auth.user?.alias ?? ''}',
                style: const TextStyle(fontSize: 12)),
          ],
        ).withPrimaryGradient(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings).withPrimaryGradient(context),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: channels.isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary))
          : myGroups.isEmpty
              ? _emptyState(
                  'No perteneces a ningún grupo',
                  'Crea uno nuevo o únete a uno existente',
                )
              : ListView.builder(
                  itemCount: myGroups.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (_, i) => _groupTile(myGroups[i]),
                ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: context.watch<ThemeProvider>().primaryGradient,
        ),
        child: FloatingActionButton.extended(
          heroTag: 'join_or_create_group',
          onPressed: _showJoinOrCreateDialog,
          backgroundColor: context.watch<ThemeProvider>().primaryGradient == null ? Theme.of(context).colorScheme.primary : Colors.transparent,
          elevation: context.watch<ThemeProvider>().primaryGradient == null ? null : 0,
          icon: const Icon(Icons.group_add, color: Colors.white, size: 18),
          label: const Text('Crear/Unirse',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _groupTile(ChannelModel group) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      onTap: () => _openGroup(group),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade300,
        child: Icon(
          Icons.lock,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(group.name,
          style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600)),
      subtitle: Text(
        group.description ?? 'Sin descripción',
        style: const TextStyle(color: Colors.grey, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: group.memberCount != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text('${group.memberCount}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            )
          : null,
    );
  }

  Widget _emptyState(String title, String subtitle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.group_outlined, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87, fontSize: 18),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _showJoinOrCreateDialog,
            icon: const Icon(Icons.group_add, size: 16, color: Colors.black),
            label: const Text('Comenzar',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

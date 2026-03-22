import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/channel_provider.dart';
import '../../../core/models/channel_model.dart';
import '../../call/screens/call_screen.dart';

import '../../settings/screens/settings_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ChannelProvider>().loadMyChannels();
      await context.read<ChannelProvider>().loadPublicChannels();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Solo canales grupales (isGroup: true y nombre no empieza con "direct_")
  List<ChannelModel> _filterGroups(List<ChannelModel> channels) {
    return channels
        .where((c) => c.isGroup && !c.name.startsWith('direct_'))
        .toList();
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool isPrivate = false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          title: Text('Nuevo Grupo',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Nombre del grupo',
                  labelStyle: TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.group, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  labelStyle: TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.description_outlined, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                title: Text('Grupo privado',
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14)),
                subtitle: const Text('Solo por invitación', style: TextStyle(color: Colors.grey, fontSize: 12)),
                contentPadding: EdgeInsets.zero,
                value: isPrivate,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (v) => setDlg(() => isPrivate = v),
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
              icon: const Icon(Icons.group_add, color: Colors.black, size: 18),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final ok = await context.read<ChannelProvider>().createChannel(
                  nameCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                );
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.read<ChannelProvider>().error ?? 'Error al crear grupo'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              label: const Text('Crear', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  void _showJoinDialog() {
    final nameCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        title: Text('Unirse a Grupo',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: SingleChildScrollView(
          child: TextField(
            controller: nameCtrl,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: const InputDecoration(
              labelText: 'Nombre exacto del grupo',
              labelStyle: TextStyle(color: Colors.grey),
              prefixIcon: Icon(Icons.search, color: Colors.grey),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary),
            icon: const Icon(Icons.login, color: Colors.black, size: 18),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              final ok = await context
                  .read<ChannelProvider>()
                  .joinChannel(nameCtrl.text.trim());
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? '¡Te uniste al grupo!'
                      : context.read<ChannelProvider>().error ?? 'No se encontró el grupo'),
                  backgroundColor: ok
                      ? Theme.of(context).colorScheme.primary
                      : Colors.red,
                ));
              }
            },
            label: const Text('Unirse', style: TextStyle(color: Colors.black)),
          ),
        ],
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
    final publicGroups = _filterGroups(channels.publicChannels);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Grupos',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            Text('@${auth.user?.alias ?? ''}',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary, fontSize: 12)),
          ],
        ),
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Mis Grupos'),
            Tab(text: 'Explorar'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: MIS GRUPOS
          channels.isLoading
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

          // TAB 2: EXPLORAR
          channels.isLoading
              ? Center(
                  child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary))
              : publicGroups.isEmpty
                  ? _emptyState(
                      'No hay grupos públicos',
                      'Sé el primero en crear uno',
                    )
                  : ListView.builder(
                      itemCount: publicGroups.length,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemBuilder: (_, i) => _groupTile(publicGroups[i]),
                    ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'join_group',
            onPressed: _showJoinDialog,
            backgroundColor: const Color(0xFF1A1A1A),
            icon: const Icon(Icons.search, color: Colors.white, size: 18),
            label: const Text('Unirse', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'create_group',
            onPressed: _showCreateDialog,
            backgroundColor: Theme.of(context).colorScheme.primary,
            icon: const Icon(Icons.group_add, color: Colors.black, size: 18),
            label: const Text('Crear grupo',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _groupTile(ChannelModel group) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      onTap: () => _openGroup(group),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade300,
        child: Icon(
          group.isPrivate ? Icons.lock : Icons.group,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(group.name,
          style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600)),
      subtitle: Text(
        group.description ?? 'Sin descripción',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _showJoinDialog,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Unirse'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(color: Theme.of(context).colorScheme.primary)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.group_add, size: 16, color: Colors.black),
                label: const Text('Crear grupo',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

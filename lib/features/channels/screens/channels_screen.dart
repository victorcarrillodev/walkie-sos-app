import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/channel_provider.dart';
import '../../../core/models/channel_model.dart';
import '../../call/screens/call_screen.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChannelProvider>().loadMyChannels();
      context.read<ChannelProvider>().loadPublicChannels();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Nuevo Canal', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nombre del canal',
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
            TextField(
              controller: descCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              await context.read<ChannelProvider>().createChannel(
                    nameCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                  );
            },
            child: const Text('Crear', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showJoinDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Unirse a Canal', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Nombre exacto del canal',
            labelStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              final ok = await context
                  .read<ChannelProvider>()
                  .joinChannel(nameCtrl.text.trim());
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No se encontró el canal')),
                );
              }
            },
            child: const Text('Unirse', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _openChannel(ChannelModel channel) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CallScreen(channel: channel)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final channels = context.watch<ChannelProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('WalkieSOS', style: TextStyle(color: Colors.white, fontSize: 20)),
            Text(
              '@${auth.user?.alias ?? ''}',
              style: const TextStyle(color: Color(0xFF00E676), fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.grey),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00E676),
          labelColor: const Color(0xFF00E676),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Mis Canales'),
            Tab(text: 'Explorar'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: MIS CANALES
          channels.isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
              : channels.myChannels.isEmpty
                  ? _emptyState('No tienes canales aún', 'Crea uno o únete a uno existente')
                  : ListView.builder(
                      itemCount: channels.myChannels.length,
                      itemBuilder: (_, i) => _channelTile(channels.myChannels[i]),
                    ),

          // TAB 2: EXPLORAR
          channels.isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
              : channels.publicChannels.isEmpty
                  ? _emptyState('No hay canales públicos', 'Sé el primero en crear uno')
                  : ListView.builder(
                      itemCount: channels.publicChannels.length,
                      itemBuilder: (_, i) => _channelTile(channels.publicChannels[i]),
                    ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'join',
            onPressed: _showJoinDialog,
            backgroundColor: const Color(0xFF1A1A1A),
            child: const Icon(Icons.search, color: Colors.white),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'create',
            onPressed: _showCreateDialog,
            backgroundColor: const Color(0xFF00E676),
            child: const Icon(Icons.add, color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _channelTile(ChannelModel channel) {
    return ListTile(
      onTap: () => _openChannel(channel),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF1A1A1A),
        child: Icon(
          channel.isPrivate ? Icons.lock : Icons.radio,
          color: const Color(0xFF00E676),
        ),
      ),
      title: Text(channel.name, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        channel.description ?? 'Sin descripción',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      trailing: channel.memberCount != null
          ? Text(
              '${channel.memberCount} miembros',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            )
          : null,
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.radio, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}
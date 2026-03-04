import 'package:flutter/material.dart';
import '../core/socket_client.dart';
import '../core/channels_service.dart';
import 'chat_screen.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  _ChannelsScreenState createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<dynamic> _canales = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarCanales();
  }

  Future<void> _cargarCanales() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final canales = await ChannelsService.getMyChannels();
    if (mounted) {
      setState(() {
        _canales = canales;
        _isLoading = false;
      });
    }
  }

  void _mostrarDialogoUnirse() {
    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sintonizar Canal'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Nombre del canal',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final nombre = nameController.text.trim();
              if (nombre.isNotEmpty) {
                Navigator.pop(context);
                final resultado = await ChannelsService.joinChannel(nombre);
                if (resultado['success']) _cargarCanales();
              }
            },
            child: const Text('Unirse'),
          ),
        ],
      ),
    );
  }

  void _entrarAlCanal(dynamic canal) {
    final channelId = canal['id'].toString();
    final nombreCanal = canal['name'].toString();

    SocketClient.joinChannel(channelId);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(contactId: channelId, alias: nombreCanal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold sin AppBar para que no se duplique con la HomeScreen
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _cargarCanales,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _canales.isEmpty
                ? const Center(child: Text('No estás en ningún canal.'))
                : ListView.builder(
                    itemCount: _canales.length,
                    itemBuilder: (context, index) {
                      final canal = _canales[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Icon(Icons.radio, color: Colors.white),
                        ),
                        title: Text(canal['name'] ?? 'Canal'),
                        subtitle: Text('${canal['_count']?['members'] ?? 1} miembros'),
                        trailing: const Icon(Icons.settings_voice, color: Colors.orange),
                        onTap: () => _entrarAlCanal(canal),
                      );
                    },
                  ),
      ),
      // Botón flotante para canales
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarDialogoUnirse,
        icon: const Icon(Icons.cell_tower),
        label: const Text('Sintonizar'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}
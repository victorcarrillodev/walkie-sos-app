import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/channel_model.dart';
import '../../../core/models/message_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/channel_provider.dart';
import '../../../core/providers/presence_provider.dart';
import '../../../core/services/database_service.dart';
import '../../call/screens/call_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../../core/utils/gradient_extension.dart';

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  final DatabaseService _db = DatabaseService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _recentItems = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecents();
    });
  }

  Future<void> _loadRecents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final channelProvider = context.read<ChannelProvider>();
      final currentUser = context.read<AuthProvider>().user;
      
      await channelProvider.loadMyChannels();
      final channels = channelProvider.myChannels;
      List<Map<String, dynamic>> temp = [];

      for (var channel in channels) {
        final msgs = await _db.getMessagesByChannel(channel.id);
        if (msgs.isNotEmpty) {
          msgs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          
          String displayTitle = channel.name;
          final uuidRegExp = RegExp(r'^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$');
          
          if (uuidRegExp.hasMatch(channel.name) || (channel.name.length >= 20 && !channel.name.contains(' '))) {
             try {
               final otherUserMsg = msgs.firstWhere((m) => m.userId != currentUser?.id);
               displayTitle = otherUserMsg.alias;
             } catch (e) {
               displayTitle = 'Chat Privado'; 
             }
          }

          temp.add({
            'channel': channel,
            'lastMessage': msgs.first,
            'displayTitle': displayTitle, 
          });
        }
      }

      temp.sort((a, b) {
        final msgA = a['lastMessage'] as MessageModel;
        final msgB = b['lastMessage'] as MessageModel;
        return msgB.createdAt.compareTo(msgA.createdAt);
      });

      if (mounted) {
        setState(() {
          _recentItems = temp;
          _isLoading = false;
        });

        // Solicitamos el estado en línea de los usuarios de canales directos
        final myUserId = context.read<AuthProvider>().user?.id ?? '';
        final directIds = temp
            .map((item) {
              final ch = item['channel'] as ChannelModel;
              if (!ch.name.startsWith('direct_')) return null;
              final parts = ch.name.split('_');
              if (parts.length >= 3) {
                return parts[1] == myUserId ? parts[2] : parts[1];
              }
              return null;
            })
            .whereType<String>()
            .toSet()
            .toList();
        if (directIds.isNotEmpty) {
          context.read<PresenceProvider>().checkPresence(directIds);
        }
      }
    } catch (e) {
      debugPrint('Error cargando recientes: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (time.year == now.year && time.month == now.month && time.day == now.day) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.read<AuthProvider>().user;
    
    // Obtenemos colores globales dinámicos
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recientes',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold)).withPrimaryGradient(context),
        // BOTÓN DE CONFIGURACIÓN EN LA PARTE SUPERIOR DERECHA
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
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : _recentItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 80, color: Colors.grey.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      const Text(
                        'No hay conversaciones recientes',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Entra a un canal y envía un mensaje',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: primaryColor,
                  backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  onRefresh: _loadRecents,
                  child: ListView.builder(
                    itemCount: _recentItems.length,
                    itemBuilder: (context, index) {
                      final item = _recentItems[index];
                      final ChannelModel channel = item['channel'];
                      final MessageModel lastMsg = item['lastMessage'];
                      final String displayTitle = item['displayTitle']; 
                      final isMe = lastMsg.userId == currentUser?.id;

                      // Calcular online status si es canal directo
                      String? directTargetId;
                      if (channel.name.startsWith('direct_')) {
                        final myId = currentUser?.id ?? '';
                        final parts = channel.name.split('_');
                        if (parts.length >= 3) {
                          directTargetId = parts[1] == myId ? parts[2] : parts[1];
                        }
                      }
                      final isOnline = directTargetId != null
                          ? context.watch<PresenceProvider>().isOnline(directTargetId)
                          : false;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade300,
                              child: Text(
                                displayTitle.isNotEmpty ? displayTitle[0].toUpperCase() : '?',
                                style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ),
                            if (directTargetId != null)
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
                        title: Text(
                          displayTitle, 
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87, 
                            fontWeight: FontWeight.w600, 
                            fontSize: 16
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              Icon(
                                isMe ? Icons.mic : Icons.mic_none, 
                                color: isMe ? primaryColor : Colors.grey, 
                                size: 16
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isMe ? 'Tú enviaste un audio' : '${lastMsg.alias} envió un audio',
                                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: Text(
                          _formatTime(lastMsg.createdAt),
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CallScreen(channel: channel),
                            ),
                          );
                          _loadRecents();
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
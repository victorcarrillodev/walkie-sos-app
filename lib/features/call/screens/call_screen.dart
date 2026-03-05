import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../../../core/models/channel_model.dart';
import '../../../core/models/message_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/socket_service.dart';

class CallScreen extends StatefulWidget {
  final ChannelModel channel;
  const CallScreen({super.key, required this.channel});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final SocketService _socket = SocketService();
  final DatabaseService _db = DatabaseService();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  // Estado UI
  bool _isTalking = false;
  bool _isConnected = false;
  bool _isInitializing = true;
  String? _whoIsTalking;
  String? _initError;
  List<MessageModel> _messages = [];

  late String _myUserId;
  late String _myAlias;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user!;
    _myUserId = user.id;
    _myAlias = user.alias;
    _init();
  }

  Future<void> _init() async {
    try {
      // 1. Pedir permisos
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        setState(() {
          _initError = 'Se necesita permiso de micrófono.';
          _isInitializing = false;
        });
        return;
      }

      // 2. FORZAR AUDIO POR EL ALTAVOZ 🔊 (Con la corrección exacta para iOS)
      await _player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: AudioContextIOS(
          // Obligatorio para poder usar defaultToSpeaker en iOS
          category: AVAudioSessionCategory.playAndRecord,
          options: const {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      ));

      // 3. Conectar Socket
      if (!_socket.isConnected) await _socket.connect();
      _socket.joinChannel(widget.channel.id);

      // 4. Cargar BD y Listeners
      await _loadMessages();
      _setupSocketListeners();

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = 'Error al conectar: $e';
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _loadMessages() async {
    final msgs = await _db.getMessagesByChannel(widget.channel.id);
    if (mounted) setState(() => _messages = msgs);
  }

  void _setupSocketListeners() {
    _socket.onPttStatus((data) {
      if (mounted) {
        setState(() {
          _whoIsTalking = (data['isTalking'] == true) ? data['alias'] : null;
        });
      }
    });

    _socket.onReceiveAudio((data) async {
      await _saveAndPlayReceivedAudio(data);
    });

    _socket.onChannelEvent((data) {
      if (mounted && data['type'] == 'JOINED') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${data['message']}'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1A1A1A),
        ));
      }
    });
  }

  Future<void> _startTalking() async {
    if (_isTalking) return;
    setState(() => _isTalking = true);

    _socket.sendPttStart(widget.channel.id);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/ptt_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      // El micrófono ya está libre, esto funcionará perfecto
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (e) {
      debugPrint('Error iniciando grabación: $e');
      setState(() => _isTalking = false);
    }
  }

  Future<void> _stopTalking() async {
    if (!_isTalking) return;
    setState(() => _isTalking = false);

    _socket.sendPttEnd(widget.channel.id);

    try {
      final path = await _recorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final base64Audio = base64Encode(bytes);
          
          // 🚀 ENVIAR AL SERVIDOR
          _socket.sendAudio(widget.channel.id, base64Audio);

          // GUARDAR EN HISTORIAL LOCAL
          final message = MessageModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            channelId: widget.channel.id,
            userId: _myUserId,
            alias: _myAlias,
            audioPath: path,
            createdAt: DateTime.now(),
          );
          await _db.saveMessage(message);
          if (mounted) setState(() => _messages.add(message));
        }
      }
    } catch (e) {
      debugPrint('Error deteniendo grabación: $e');
    }
  }

  Future<void> _saveAndPlayReceivedAudio(Map<String, dynamic> data) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'recv_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final filePath = '${dir.path}/$fileName';

      if (data['audioData'] != null) {
        final audioBytes = base64Decode(data['audioData']);
        await File(filePath).writeAsBytes(audioBytes);
        
        // 🔊 REPRODUCIR AL INSTANTE
        await _player.play(DeviceFileSource(filePath));
      }

      // GUARDAR EN HISTORIAL
      final message = MessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        channelId: widget.channel.id,
        userId: data['userId'] ?? '',
        alias: data['alias'] ?? 'Desconocido',
        audioPath: filePath,
        createdAt: DateTime.now(),
      );
      await _db.saveMessage(message);
      if (mounted) setState(() => _messages.add(message));
    } catch (e) {
      debugPrint('Error guardando audio: $e');
    }
  }

  @override
  void dispose() {
    _socket.leaveChannel(widget.channel.id);
    _socket.removeChannelListeners();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.channel.name, style: const TextStyle(color: Colors.white, fontSize: 18)),
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? Colors.orange : Colors.red,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _isInitializing ? 'Conectando...' : _isConnected ? 'Socket conectado' : 'Sin conexión',
                  style: TextStyle(color: _isConnected ? Colors.orange : Colors.red, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator(color: Colors.orange));
    }

    if (_initError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(_initError!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() { _initError = null; _isInitializing = true; });
                _init();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Reintentar', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _whoIsTalking != null ? 44 : 0,
          color: Colors.orange.withOpacity(0.12),
          child: _whoIsTalking != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.graphic_eq, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Text('$_whoIsTalking está hablando...', style: const TextStyle(color: Colors.orange, fontSize: 14)),
                  ],
                )
              : null,
        ),
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic_none, size: 72, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Mantén el botón para hablar', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _messageTile(_messages[i]),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 44),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, -2))],
          ),
          child: Column(
            children: [
              GestureDetector(
                onTapDown: (_) => _startTalking(),
                onTapUp: (_) => _stopTalking(),
                onTapCancel: () => _stopTalking(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _isTalking ? 130 : 110,
                  height: _isTalking ? 130 : 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isTalking ? Colors.orange : const Color(0xFF1C1C1C),
                    border: Border.all(color: _isTalking ? Colors.orange : const Color(0xFF333333), width: 2),
                    boxShadow: _isTalking ? [BoxShadow(color: Colors.orange.withOpacity(0.45), blurRadius: 35, spreadRadius: 10)] : [],
                  ),
                  child: Icon(_isTalking ? Icons.mic : Icons.mic_none, size: 52, color: _isTalking ? Colors.black : Colors.grey),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _isTalking ? '🔴 Transmitiendo...' : 'Mantén para hablar',
                style: TextStyle(color: _isTalking ? Colors.orange : Colors.grey, fontSize: 14, fontWeight: _isTalking ? FontWeight.bold : FontWeight.normal),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _messageTile(MessageModel msg) {
    final isMe = msg.userId == _myUserId;
    final time = '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _player.play(DeviceFileSource(msg.audioPath)),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
          decoration: BoxDecoration(
            color: isMe ? Colors.orange.withOpacity(0.12) : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isMe ? Colors.orange.withOpacity(0.25) : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_fill, size: 28, color: isMe ? Colors.orange : Colors.grey),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isMe ? 'Tú' : msg.alias, style: TextStyle(color: isMe ? Colors.orange : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                    const Text('Audio (Toca para oír)', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(time, style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}
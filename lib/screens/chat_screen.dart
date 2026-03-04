import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/socket_client.dart';
import '../core/database_service.dart';

class ChatScreen extends StatefulWidget {
  final String contactId;
  final String alias;

  const ChatScreen({super.key, required this.contactId, required this.alias});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool _isRecording = false;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _historyPlayer = AudioPlayer();
  List<Map<String, dynamic>> _historial = [];

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
    // Escuchar actualizaciones de la base de datos
    SocketClient.socket?.on('receive-audio', (_) => _cargarHistorial());
  }

  Future<void> _cargarHistorial() async {
    final mensajes = await DatabaseService.getMessages(widget.contactId);
    if (mounted) setState(() => _historial = mensajes);
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      setState(() => _isRecording = true);
      SocketClient.socket?.emit('ptt-start', widget.contactId);
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/envio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(const RecordConfig(), path: path);
    }
  }

  Future<void> _stopRecording() async {
    setState(() => _isRecording = false);
    SocketClient.socket?.emit('ptt-end', widget.contactId);
    final path = await _audioRecorder.stop();

    if (path != null) {
      final bytes = await File(path).readAsBytes();
      SocketClient.socket?.emit('send-audio', {
        'channelId': widget.contactId,
        'audioData': base64Encode(bytes),
      });

      // GUARDAR MI PROPIO AUDIO EN EL HISTORIAL
      await DatabaseService.saveMessage({
        'contactId': widget.contactId,
        'alias': 'Yo',
        'filePath': path,
        'isMe': 1,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _cargarHistorial();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.alias)),
      body: Column(
        children: [
          // LISTA DE AUDIOS GUARDADOS
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _historial.length,
              itemBuilder: (context, index) {
                final msg = _historial[index];
                bool esMio = msg['isMe'] == 1;
                return Align(
                  alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: esMio ? Colors.blue[100] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(esMio ? "Yo" : msg['alias']),
                        IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () => _historyPlayer.play(DeviceFileSource(msg['filePath'])),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // BOTÓN PTT (PUSH TO TALK)
          Padding(
            padding: const EdgeInsets.all(30.0),
            child: GestureDetector(
              onTapDown: (_) => _startRecording(),
              onTapUp: (_) => _stopRecording(),
              child: CircleAvatar(
                radius: 50,
                backgroundColor: _isRecording ? Colors.red : Colors.blue,
                child: Icon(_isRecording ? Icons.mic : Icons.mic_none, color: Colors.white, size: 40),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
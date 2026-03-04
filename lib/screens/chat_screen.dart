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
    
    // Escuchar el evento solo para refrescar la lista visual, no para procesar el audio
    SocketClient.socket?.on('receive-audio', _onAudioReceivedRefresh);
  }

  void _onAudioReceivedRefresh(data) {
    if (mounted) _cargarHistorial();
  }

  @override
  void dispose() {
    // IMPORTANTE: Quitar el listener específico de esta pantalla al salir
    SocketClient.socket?.off('receive-audio', _onAudioReceivedRefresh);
    _audioRecorder.dispose();
    _historyPlayer.dispose();
    super.dispose();
  }

  Future<void> _cargarHistorial() async {
    final mensajes = await DatabaseService.getMessages(widget.contactId);
    if (mounted) setState(() => _historial = mensajes);
  }

  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) return;

    // Verificar conexión antes de grabar
    if (SocketClient.socket == null || !SocketClient.socket!.connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sin conexión al servidor")));
      return;
    }

    setState(() => _isRecording = true);
    SocketClient.socket?.emit('ptt-start', widget.contactId);
    
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/envio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    
    await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    
    setState(() => _isRecording = false);
    SocketClient.socket?.emit('ptt-end', widget.contactId);
    
    final path = await _audioRecorder.stop();
    if (path != null) {
      final bytes = await File(path).readAsBytes();
      
      // Enviar al servidor
      SocketClient.socket?.emit('send-audio', {
        'channelId': widget.contactId,
        'audioData': base64Encode(bytes),
      });

      // Guardar mi propio audio en BD local
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
      appBar: AppBar(title: Text("Canal: ${widget.alias}"), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(15),
              itemCount: _historial.length,
              itemBuilder: (context, index) {
                final msg = _historial[index];
                bool esMio = msg['isMe'] == 1;
                return Align(
                  alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
                  child: Card(
                    color: esMio ? Colors.blue[50] : Colors.grey[100],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(esMio ? "Yo" : msg['alias'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.play_circle_fill, color: Colors.blue, size: 30),
                            onPressed: () => _historyPlayer.play(DeviceFileSource(msg['filePath'])),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
            child: Center(
              child: GestureDetector(
                onTapDown: (_) => _startRecording(),
                onTapUp: (_) => _stopRecording(),
                onTapCancel: () => _stopRecording(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  padding: EdgeInsets.all(_isRecording ? 25 : 20),
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.red : Colors.blue,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: _isRecording ? 5 : 0)]
                  ),
                  child: Icon(_isRecording ? Icons.mic : Icons.mic_none, color: Colors.white, size: 45),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
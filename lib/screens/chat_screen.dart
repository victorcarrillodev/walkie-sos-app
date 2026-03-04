import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../core/socket_client.dart';

class ChatScreen extends StatefulWidget {
  final String contactId;
  final String alias;

  const ChatScreen({super.key, required this.contactId, required this.alias});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool _isRecording = false;
  bool _isContactTalking = false;

  // Solo necesitamos la grabadora aquí
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _rutaAudioGrabado;

  @override
  void initState() {
    super.initState();
    _configurarSockets();
  }

  void _configurarSockets() {
    // Escuchar si el otro está grabando (Para cambiar el color del texto)
    SocketClient.socket?.on('ptt-status', (data) {
      if (data['userId'] == widget.contactId || data['alias'] == widget.alias) {
        if (mounted) setState(() => _isContactTalking = data['isTalking']);
      }
    });
  }

  // --- LÓGICA DE GRABACIÓN ---
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        if (mounted) setState(() => _isRecording = true);
        SocketClient.socket?.emit('ptt-start', widget.contactId);

        final directorioTemp = await getTemporaryDirectory();
        _rutaAudioGrabado =
            '${directorioTemp.path}/mi_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: _rutaAudioGrabado!,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Necesitas dar permisos de micrófono')),
        );
      }
    } catch (e) {
      print("Error al iniciar grabación: $e");
    }
  }

  Future<void> _stopRecording() async {
    try {
      if (mounted) setState(() => _isRecording = false);
      SocketClient.socket?.emit('ptt-end', widget.contactId);

      final path = await _audioRecorder.stop();

      if (path != null) {
        final bytes = await File(path).readAsBytes();
        final audioBase64 = base64Encode(bytes);

        SocketClient.socket?.emit('send-audio', {
          'channelId': widget.contactId,
          'audioData': audioBase64,
        });

        print("✅ Audio enviado correctamente");
      }
    } catch (e) {
      print("Error al detener grabación: $e");
    }
  }

  @override
  void dispose() {
    SocketClient.socket?.emit('leave-channel', widget.contactId);
    SocketClient.socket?.off('ptt-status');
    // Ya no apagamos receive-audio para que el oído global siga escuchando
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.alias), centerTitle: true),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _isContactTalking
                ? '${widget.alias} está hablando...'
                : 'Conectado y listo',
            style: TextStyle(
              fontSize: 22,
              color: _isContactTalking ? Colors.green : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 80),
          Center(
            child: GestureDetector(
              onTapDown: (_) => _startRecording(),
              onTapUp: (_) => _stopRecording(),
              onTapCancel: () => _stopRecording(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isRecording ? 220 : 200,
                height: _isRecording ? 220 : 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording ? Colors.red : Colors.blue,
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.red : Colors.blue)
                          .withOpacity(0.5),
                      spreadRadius: _isRecording ? 20 : 5,
                      blurRadius: 15,
                    ),
                  ],
                ),
                child: Icon(
                  _isRecording ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: 80,
                ),
              ),
            ),
          ),
          const SizedBox(height: 60),
          Text(
            _isRecording
                ? 'Grabando... Suelta para enviar'
                : 'Mantén presionado para hablar',
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }
}
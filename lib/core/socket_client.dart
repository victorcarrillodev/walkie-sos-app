import 'dart:io';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';

class SocketClient {
  static IO.Socket? socket;
  static final AudioPlayer _audioPlayer = AudioPlayer();

  static Future<void> connect() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;

    socket = IO.io('https://walkiesos.jegode.com', IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setAuth({'token': token})
        .build());

    socket!.connect();

    // ESCUCHAR AUDIOS ENTRANTES
    socket!.on('receive-audio', (data) async {
      print("📥 Recibiendo audio de ${data['alias']}");
      await _procesarYGuardarAudio(data);
    });
  }

  static Future<void> _procesarYGuardarAudio(Map<String, dynamic> data) async {
    try {
      final bytes = base64Decode(data['audioData']);
      
      // Guardar en carpeta de Documentos (Permanente)
      final directorio = await getApplicationDocumentsDirectory();
      final pathFinal = '${directorio.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      final archivo = File(pathFinal);
      await archivo.writeAsBytes(bytes);

      // REGISTRAR EN LA BASE DE DATOS LOCAL
      await DatabaseService.saveMessage({
        'contactId': data['userId'] ?? data['channelId'], 
        'alias': data['alias'],
        'filePath': pathFinal,
        'isMe': 0, // 0 = Recibido
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Reproducir
      await _audioPlayer.play(DeviceFileSource(pathFinal));
    } catch (e) {
      print("Error procesando audio recibido: $e");
    }
  }

  static void joinChannel(String channelId) {
    socket?.emit('join-channel', channelId);
  }
}
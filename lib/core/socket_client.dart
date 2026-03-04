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
    // 1. Evitar duplicar la conexión
    if (socket != null && socket!.connected) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;

    socket = IO.io('https://walkiesos.jegode.com', IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setAuth({'token': token})
        .build());

    socket!.connect();

    // Limpiamos oídos viejos antes de poner los nuevos
    socket!.off('receive-audio');

    socket!.onConnect((_) => print('✅ SOCKET CONECTADO EXITOSAMENTE'));

    // OÍDO GLOBAL ÚNICO
    socket!.on('receive-audio', (data) async {
      print("📥 Audio entrante de: ${data['alias']}");
      await _procesarYGuardarAudio(data);
    });

    socket!.onConnectError((err) => print('❌ ERROR DE CONEXIÓN: $err'));
  }

  static Future<void> _procesarYGuardarAudio(Map<String, dynamic> data) async {
    try {
      if (data['audioData'] == null) return;
      
      final bytes = base64Decode(data['audioData']);
      final directorio = await getApplicationDocumentsDirectory();
      final pathFinal = '${directorio.path}/recibido_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      await File(pathFinal).writeAsBytes(bytes);

      // GUARDAR EN BD LOCAL
      await DatabaseService.saveMessage({
        'contactId': data['userId'].toString(), 
        'alias': data['alias'].toString(),
        'filePath': pathFinal,
        'isMe': 0,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // 2. FORZAR SALIDA POR ALTAVOZ (IMPORTANTE)
      await _audioPlayer.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
      ));

      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(DeviceFileSource(pathFinal));
      print("▶️ Reproduciendo audio por altavoz...");
    } catch (e) {
      print("❌ Error procesando audio: $e");
    }
  }

  static void joinChannel(String channelId) {
    if (socket?.connected ?? false) {
      print("📻 Sintonizando canal en servidor: $channelId");
      socket?.emit('join-channel', channelId);
    }
  }
}
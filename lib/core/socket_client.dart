import 'dart:io';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class SocketClient {
  static IO.Socket? socket;
  // Instanciamos el reproductor a nivel global
  static final AudioPlayer _audioPlayer = AudioPlayer();

  static Future<void> connect() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) return;

    // IMPORTANTE: Asegúrate de que esta IP sea la misma que tu computadora (ej. 192.168.1.75)
    socket = IO.io('https://walkiesos.jegode.com', IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setAuth({'token': token})
        .build());

    socket!.connect();

    socket!.onConnect((_) {
      print('✅ Conectado al Socket del servidor Zello');
    });

    // EL OÍDO GLOBAL: Escucha audios en cualquier pantalla
    socket!.on('receive-audio', (data) async {
      print("📥 ¡Audio entrante de ${data['alias']}!");
      await _reproducirAudioRecibido(data['audioData']);
    });

    socket!.onConnectError((err) => print('❌ Error de conexión de socket: $err'));
    socket!.onError((err) => print('❌ Error en socket: $err'));
  }

  // Función global para reproducir
  static Future<void> _reproducirAudioRecibido(String audioBase64) async {
    try {
      final bytes = base64Decode(audioBase64);
      final directorioTemp = await getTemporaryDirectory();
      final archivo = File('${directorioTemp.path}/audio_recibido_${DateTime.now().millisecondsSinceEpoch}.m4a');
      
      await archivo.writeAsBytes(bytes);
      await _audioPlayer.play(DeviceFileSource(archivo.path));
      print("▶️ Audio reproducido con éxito");
    } catch (e) {
      print("❌ Error al reproducir audio: $e");
    }
  }

  static void joinChannel(String channelId) {
    socket?.emit('join-channel', channelId);
  }

  static void disconnect() {
    socket?.disconnect();
  }
}
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';

class SocketService {
  // SINGLETON - una sola instancia en toda la app
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  static const String baseUrl = 'https://walkiesos.jegode.com';
  IO.Socket? _socket;

  bool get isConnected => _socket?.connected ?? false;
  IO.Socket? get socket => _socket;

  Future<void> connect() async {
    // Si ya está conectado, no reconectar
    if (_socket != null && _socket!.connected) {
      debugPrint('✅ Socket ya conectado, reutilizando');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      debugPrint('❌ No hay token guardado');
      return;
    }

    debugPrint('🔌 Conectando socket...');

    // Si existe pero desconectado, limpiar
    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .setTimeout(10000)
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      debugPrint('✅ Socket conectado - ID: ${_socket!.id}');
    });

    _socket!.onDisconnect((reason) {
      debugPrint('🔌 Socket desconectado: $reason');
    });

    _socket!.onConnectError((data) {
      debugPrint('❌ Error conexión socket: $data');
    });

    _socket!.onReconnect((_) {
      debugPrint('🔄 Socket reconectado');
    });

    // Esperar a que conecte
    await Future.delayed(const Duration(milliseconds: 1500));
  }

  void joinChannel(String channelId) {
    debugPrint('📻 Uniéndose al canal: $channelId');
    _socket?.emit('join-channel', channelId);
  }

  void leaveChannel(String channelId) {
    _socket?.emit('leave-channel', channelId);
  }

  void sendPttStart(String channelId) {
    _socket?.emit('ptt-start', channelId);
  }

  void sendPttEnd(String channelId) {
    _socket?.emit('ptt-end', channelId);
  }

  void sendOffer(String channelId, dynamic offer) {
    debugPrint('📤 Enviando offer al canal $channelId');
    _socket?.emit('webrtc-offer', {'channelId': channelId, 'offer': offer});
  }

  void sendAnswer(String channelId, dynamic answer) {
    debugPrint('📤 Enviando answer al canal $channelId');
    _socket?.emit('webrtc-answer', {'channelId': channelId, 'answer': answer});
  }

  void sendIceCandidate(String channelId, dynamic candidate) {
    _socket?.emit('webrtc-ice-candidate', {
      'channelId': channelId,
      'candidate': candidate,
    });
  }

  void sendAudio(String channelId, String audioData) {
    _socket?.emit('send-audio', {'channelId': channelId, 'audioData': audioData});
  }

  // LISTENERS - limpia antes de agregar para evitar duplicados
  void onReceiveOffer(Function(dynamic) callback) {
    _socket?.off('webrtc-offer');
    _socket?.on('webrtc-offer', callback);
  }

  void onReceiveAnswer(Function(dynamic) callback) {
    _socket?.off('webrtc-answer');
    _socket?.on('webrtc-answer', callback);
  }

  void onReceiveIceCandidate(Function(dynamic) callback) {
    _socket?.off('webrtc-ice-candidate');
    _socket?.on('webrtc-ice-candidate', callback);
  }

  void onReceiveAudio(Function(dynamic) callback) {
    _socket?.off('receive-audio');
    _socket?.on('receive-audio', callback);
  }

  void onPttStatus(Function(dynamic) callback) {
    _socket?.off('ptt-status');
    _socket?.on('ptt-status', callback);
  }

  void onChannelEvent(Function(dynamic) callback) {
    _socket?.off('channel-event');
    _socket?.on('channel-event', callback);
  }

  void removeChannelListeners() {
    _socket?.off('webrtc-offer');
    _socket?.off('webrtc-answer');
    _socket?.off('webrtc-ice-candidate');
    _socket?.off('ptt-status');
    _socket?.off('receive-audio');
    _socket?.off('channel-event');
  }

  // Solo desconectar al hacer logout, NO al salir de un canal
  void disconnect() {
    debugPrint('🔌 Desconectando socket permanentemente');
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
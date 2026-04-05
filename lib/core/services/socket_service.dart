import 'dart:async';

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
  final Set<String> _joinedChannels = {};

  bool get isConnected => _socket?.connected ?? false;
  IO.Socket? get socket => _socket;

  Future<void> connect() async {
  if (_socket != null && _socket!.connected) return;

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  if (token == null) return;

  if (_socket != null) {
    _socket!.dispose();
    _socket = null;
  }

  // Usamos un Completer para esperar la conexión real
  Completer<void> connectionCompleter = Completer();

  _socket = IO.io(baseUrl, IO.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({'token': token})
      .disableAutoConnect()
      .build());

  _socket!.connect();

  _socket!.onConnect((_) {
    debugPrint('✅ Socket conectado - ID: ${_socket!.id}');
    if (!connectionCompleter.isCompleted) connectionCompleter.complete();
    
    // Auto re-join tras una desconexión (por ej. background)
    for (final channelId in _joinedChannels) {
      _socket?.emit('join-channel', channelId);
    }
  });

  _socket!.onConnectError((data) {
    debugPrint('❌ Error conexión socket: $data');
    if (!connectionCompleter.isCompleted) connectionCompleter.completeError(data);
  });

  // Retornamos el futuro del completer con un timeout de seguridad para no bloquear pantallas de carga (login/splash)
  return connectionCompleter.future.timeout(
    const Duration(seconds: 4),
    onTimeout: () {
      debugPrint('⚠️ Socket connect timeout... continuando en segundo plano.');
      // Dejamos que siga intentando pero liberamos la espera para no atrapar la UI
    },
  );
}

  void joinChannel(String channelId) {
    debugPrint('📻 Uniéndose al canal: $channelId');
    _joinedChannels.add(channelId);
    _socket?.emit('join-channel', channelId);
  }

  void leaveChannel(String channelId) {
    _joinedChannels.remove(channelId);
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

  void checkOnlineStatus(String userId) {
    _socket?.emit('check-online-status', userId);
  }

  void checkUsersStatus(List<String> userIds) {
    _socket?.emit('check-users-status', userIds);
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

  void onOnlineStatus(Function(dynamic) callback) {
    _socket?.off('online-status');
    _socket?.on('online-status', callback);
  }

  void onUserStatusChanged(Function(dynamic) callback) {
    _socket?.off('user-status-changed');
    _socket?.on('user-status-changed', callback);
  }

  void onUsersStatus(Function(dynamic) callback) {
    _socket?.off('users-status');
    _socket?.on('users-status', callback);
  }

  void onTalkError(Function(dynamic) callback) {
    _socket?.off('talk-error');
    _socket?.on('talk-error', callback);
  }

  void cancelAlert(String alertId, String? channelId) {
    _socket?.emit('cancel-alert', {'alertId': alertId, 'channelId': channelId});
  }

  void removeChannelListeners() {
    _socket?.off('webrtc-offer');
    _socket?.off('webrtc-answer');
    _socket?.off('webrtc-ice-candidate');
    _socket?.off('ptt-status');
    _socket?.off('receive-audio');
    _socket?.off('channel-event');
    _socket?.off('online-status');
    _socket?.off('user-status-changed');
    _socket?.off('users-status');
    _socket?.off('talk-error');
  }

  // Solo desconectar al hacer logout, NO al salir de un canal
  void disconnect() {
    debugPrint('🔌 Desconectando socket permanentemente');
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _joinedChannels.clear();
  }
}
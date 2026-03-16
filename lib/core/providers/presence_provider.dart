import 'package:flutter/material.dart';
import '../services/socket_service.dart';

/// Fuente global de verdad para el estado en línea de los usuarios.
/// Escucha eventos de socket en tiempo real y responde a consultas masivas.
class PresenceProvider extends ChangeNotifier {
  final SocketService _socket = SocketService();
  bool _listening = false;

  // Mapa: userId → isOnline
  final Map<String, bool> _onlineUsers = {};

  bool isOnline(String userId) => _onlineUsers[userId] ?? false;

  /// Asegura que los listeners de socket estén registrados.
  /// Usa el socket raw para no sobreescribir otros listeners.
  void _ensureListening() {
    if (_listening) return;
    final rawSocket = _socket.socket;
    if (rawSocket == null) return;
    _listening = true;

    // Respuesta a consulta masiva (check-users-status → users-status)
    rawSocket.on('users-status', (data) {
      if (data is List) {
        for (final item in data) {
          final userId = item['userId']?.toString();
          final online = item['isOnline'] == true;
          if (userId != null) _onlineUsers[userId] = online;
        }
        notifyListeners();
      }
    });

    // Respuesta a consulta individual (check-online-status → online-status)
    rawSocket.on('online-status', (data) {
      final userId = data['userId']?.toString();
      final online = data['isOnline'] == true;
      if (userId != null) {
        _onlineUsers[userId] = online;
        notifyListeners();
      }
    });

    // Cambios en tiempo real (broadcast cuando alguien conecta/desconecta)
    rawSocket.on('user-status-changed', (data) {
      final userId = data['userId']?.toString();
      final online = data['isOnline'] == true;
      if (userId != null) {
        _onlineUsers[userId] = online;
        notifyListeners();
      }
    });
  }

  /// Consulta el estado de múltiples usuarios a la vez.
  void checkPresence(List<String> userIds) {
    if (userIds.isEmpty) return;
    _ensureListening();
    _socket.checkUsersStatus(userIds);
  }

  /// Consulta el estado de un único usuario.
  void checkSinglePresence(String userId) {
    _ensureListening();
    _socket.checkOnlineStatus(userId);
  }

  /// Llamar desde main.dart al iniciar para intentar registrar listeners.
  /// Si el socket aún no existe se registrarán de forma lazy en la primera consulta.
  void startListening() => _ensureListening();
}

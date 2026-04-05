import 'package:flutter/material.dart';
import '../models/channel_model.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class ChannelProvider extends ChangeNotifier {
  List<ChannelModel> _myChannels = [];
  List<ChannelModel> _publicChannels = [];
  bool _isLoading = false;
  String? _error;

  List<ChannelModel> get myChannels => _myChannels;
  List<ChannelModel> get publicChannels => _publicChannels;
  bool get isLoading => _isLoading;
  String? get error => _error;

  final ApiService _api = ApiService();

  Future<void> loadMyChannels() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await _api.getMyChannels();
      _myChannels = data.map((e) => ChannelModel.fromJson(e)).toList();
      for (final c in _myChannels) {
        SocketService().joinChannel(c.id);
      }
      _error = null;
    } catch (e) {
      _error = 'Error al cargar canales';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadPublicChannels() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await _api.getPublicChannels();
      _publicChannels = data.map((e) => ChannelModel.fromJson(e)).toList();
      _error = null;
    } catch (e) {
      _error = 'Error al cargar canales públicos';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createChannel(String name, String password, {String? description, int maxMessageDuration = 60}) async {
    try {
      final data = await _api.createChannel(name: name, password: password, description: description, maxMessageDuration: maxMessageDuration);
      _myChannels.insert(0, ChannelModel.fromJson(data));
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al crear grupo';
      notifyListeners();
      return false;
    }
  }

  Future<bool> joinChannel(String name, String password) async {
    try {
      await _api.joinChannelByName(name, password);
      await loadMyChannels();
      return true;
    } catch (e) {
      _error = 'Contraseña incorrecta o grupo no existe';
      notifyListeners();
      return false;
    }
  }

  /// NUEVO MËTODO: Intenta unirse, si no existe lo crea.
  Future<bool> joinOrCreateGroup(String name, String password, {String? description, int maxMessageDuration = 60}) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Intentamos unirnos
      await _api.joinChannelByName(name, password);
      await loadMyChannels();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // 2. Si falla, asumimos que no existe o la contra es mala.
      // Si la contra es mala del grupo existente, podría fallar si intentamos crearlo y el backend dice "ya existe".
      // Lo creamos.
      try {
        final data = await _api.createChannel(
          name: name,
          password: password,
          description: description,
          maxMessageDuration: maxMessageDuration,
        );
        _myChannels.insert(0, ChannelModel.fromJson(data));
        _isLoading = false;
        notifyListeners();
        return true;
      } catch (creationError) {
        // Falló al crearlo, probablemente ya existe pero la contraseña era incorrecta, o hubo otro error.
        _error = 'Contraseña incorrecta o nombre no disponible';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    }
  }

  // ADMINISTRACIÓN DE GRUPOS
  Future<List<dynamic>> getChannelMembers(String channelId) async {
    try {
      return await _api.getChannelMembers(channelId);
    } catch (e) {
      _error = 'Error al cargar miembros';
      return [];
    }
  }

  Future<bool> toggleMuteChannel(String channelId, bool isMuted) async {
    try {
      await _api.toggleMuteChannel(channelId, isMuted);
      return true;
    } catch (e) {
      _error = 'Error al cambiar estado del grupo';
      return false;
    }
  }

  Future<bool> penalizeMember(String channelId, String userId, int? minutes) async {
    try {
      await _api.penalizeMember(channelId, userId, minutes);
      return true;
    } catch (e) {
      _error = 'Error al penalizar usuario';
      return false;
    }
  }

  Future<bool> changeMemberRole(String channelId, String userId, String role) async {
    try {
      await _api.changeMemberRole(channelId, userId, role);
      return true;
    } catch (e) {
      _error = 'Error al cambiar rol del usuario';
      return false;
    }
  }

  Future<bool> deleteChannel(String channelId) async {
    try {
      await _api.deleteChannel(channelId);
      _myChannels.removeWhere((c) => c.id == channelId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al eliminar el grupo';
      return false;
    }
  }

  Future<bool> updateChannelSettings(String channelId, {String? password, int? maxMessageDuration}) async {
    try {
      await _api.updateChannelSettings(channelId, password: password, maxMessageDuration: maxMessageDuration);
      return true;
    } catch (e) {
      _error = 'Error al actualizar grupo';
      return false;
    }
  }
}
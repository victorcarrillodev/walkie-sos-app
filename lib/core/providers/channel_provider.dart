import 'package:flutter/material.dart';
import '../models/channel_model.dart';
import '../services/api_service.dart';

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

  Future<bool> createChannel(String name, {String? description}) async {
    try {
      final data = await _api.createChannel(name: name, description: description);
      _myChannels.insert(0, ChannelModel.fromJson(data));
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al crear canal';
      notifyListeners();
      return false;
    }
  }

  Future<bool> joinChannel(String name) async {
    try {
      await _api.joinChannelByName(name);
      await loadMyChannels();
      return true;
    } catch (e) {
      _error = 'No se pudo unir al canal';
      notifyListeners();
      return false;
    }
  }
}
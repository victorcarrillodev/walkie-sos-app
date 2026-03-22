import 'package:app_walkie/core/services/socket_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  bool _isLoading = false;
  String? _error;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;

  final ApiService _api = ApiService();

  Future<void> tryAutoLogin() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  final savedUserId = prefs.getString('userId');
  final savedEmail = prefs.getString('email');
  final savedAlias = prefs.getString('alias');
  final savedFirstName = prefs.getString('firstName');
  final savedLastName = prefs.getString('lastName');

  if (token != null && savedUserId != null) {
    _user = UserModel(
      id: savedUserId,
      email: savedEmail ?? '',
      alias: savedAlias ?? '',
      firstName: savedFirstName ?? '',
      lastName: savedLastName ?? '',
    );
    await SocketService().connect();
    notifyListeners();
  }
}

  // Dentro del método login(), después de _saveSession:
Future<bool> login(String email, String password) async {
  _isLoading = true;
  _error = null;
  notifyListeners();

  try {
    final result = await _api.login(email, password);
    _user = UserModel.fromJson(result['user']);
    await _saveSession(result['token'], _user!);

    // Conectar socket inmediatamente al hacer login
    await SocketService().connect();

    _isLoading = false;
    notifyListeners();
    return true;
  } catch (e) {
    _error = _parseError(e);
    _isLoading = false;
    notifyListeners();
    return false;
  }
}

  Future<bool> register({
    required String email,
    required String password,
    required String alias,
    required String firstName,
    required String lastName,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.register(
        email: email,
        password: password,
        alias: alias,
        firstName: firstName,
        lastName: lastName,
      );
      _user = UserModel.fromJson(result['user']);
      await _saveSession(result['token'], _user!);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _parseError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _api.changePassword(currentPassword, newPassword);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _parseError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
  SocketService().disconnect(); // ← desconectar aquí
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  _user = null;
  notifyListeners();
}

  Future<void> _saveSession(String token, UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('userId', user.id);
    await prefs.setString('email', user.email);
    await prefs.setString('alias', user.alias);
    await prefs.setString('firstName', user.firstName);
    await prefs.setString('lastName', user.lastName);
  }

  

  String _parseError(dynamic e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data != null && data['error'] != null) {
      return data['error'].toString();
    }
    if (e.response?.statusCode == 400) return 'Datos inválidos. Revisa los campos.';
    if (e.response?.statusCode == 401) return 'Email o contraseña incorrectos';
    if (e.response?.statusCode == 500) return 'Error del servidor. Intenta más tarde.';
  }
  final msg = e.toString();
  if (msg.contains('email')) return 'El email ya está registrado';
  if (msg.contains('alias')) return 'El alias ya está en uso';
  if (msg.contains('SocketException')) return 'Sin conexión a internet';
  return 'Ocurrió un error. Intenta de nuevo.';
}
}
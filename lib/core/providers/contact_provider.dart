import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/contact_model.dart';
import '../services/api_service.dart';

class ContactProvider extends ChangeNotifier {
  List<ContactModel> _contacts = [];
  bool _isLoading = false;
  String? _error;

  List<ContactModel> get contacts => _contacts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  final ApiService _api = ApiService();

  Future<void> loadContacts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.getContacts();
      _contacts = data.map((e) => ContactModel.fromJson(e)).toList();
    } catch (e) {
      _error = _parseError(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> addContact(String alias) async {
    _error = null;
    try {
      await _api.addContact(alias);
      await loadContacts();
      return true;
    } catch (e) {
      _error = _parseError(e);
      notifyListeners();
      return false;
    }
  }

  /// Extrae el mensaje de error real desde la respuesta del servidor (Dio)
  /// o del mensaje de la excepción directamente.
  String _parseError(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      // El servidor siempre responde con { "error": "mensaje" }
      if (data is Map && data['error'] != null) {
        return data['error'].toString();
      }
      switch (e.response?.statusCode) {
        case 400:
          return 'Datos inválidos.';
        case 401:
          return 'Sesión expirada, vuelve a iniciar sesión.';
        case 500:
          return 'Error interno del servidor.';
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Sin conexión con el servidor. Verifica tu internet.';
      }
      if (e.type == DioExceptionType.connectionError) {
        return 'No se pudo conectar con el servidor.';
      }
    }
    return e.toString();
  }
}
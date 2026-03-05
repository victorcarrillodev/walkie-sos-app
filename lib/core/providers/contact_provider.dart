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
      _error = 'Error al cargar contactos';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> addContact(String alias) async {
    try {
      await _api.addContact(alias);
      await loadContacts();
      return true;
    } catch (e) {
      _error = e.toString().contains('alias')
          ? 'No se encontró ese alias'
          : 'Error al agregar contacto';
      notifyListeners();
      return false;
    }
  }
}
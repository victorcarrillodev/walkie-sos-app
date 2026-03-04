import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class AuthService {
  // Función para iniciar sesión
  static Future<bool> login(String email, String password) async {
    try {
      final response = await ApiClient.post('/auth/login', {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        
        // Asumimos que tu backend devuelve un token así: { "token": "eyJh..." }
        // Si la propiedad se llama diferente (ej. accessToken), cámbialo aquí abajo.
        final token = data['token']; 
        
        if (token != null) {
          // Guardamos el token en el dispositivo para no tener que iniciar sesión siempre
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', token);
          return true;
        }
      }
      return false;
    } catch (e) {
      print("Error en login: $e");
      return false;
    }
  }

  // Función para registrar (usaremos username y fullName como pide tu DTO)
  static Future<bool> register(String email, String password, String username, String? fullName) async {
    try {
      final response = await ApiClient.post('/auth/register', {
        'email': email,
        'password': password,
        'username': username,
        if (fullName != null && fullName.isNotEmpty) 'fullName': fullName,
      });

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print("Error en registro: $e");
      return false;
    }
  }
}
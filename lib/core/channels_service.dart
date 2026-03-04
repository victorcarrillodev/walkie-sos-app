import 'dart:convert';
import 'api_client.dart';

class ChannelsService {
  // 1. Obtener mis canales (Llama a tu ruta /mine)
  static Future<List<dynamic>> getMyChannels() async {
    try {
      final response = await ApiClient.get('/channels/mine');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      print("Error al obtener mis canales: $e");
      return [];
    }
  }

  // 2. Unirse a un canal por nombre (Llama a tu ruta /join)
  static Future<Map<String, dynamic>> joinChannel(String name) async {
    try {
      final response = await ApiClient.post('/channels/join', {
        'name': name,
      });
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['error'] ?? 'Error desconocido'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión'};
    }
  }

  // 3. Crear un canal nuevo (Llama a tu ruta principal /)
  static Future<bool> createChannel(String name, String description) async {
    try {
      final response = await ApiClient.post('/channels', {
        'name': name,
        'description': description,
      });
      return response.statusCode == 201;
    } catch (e) {
      print("Error al crear canal: $e");
      return false;
    }
  }
}
import 'dart:convert';
import 'api_client.dart';

class ContactsService {
  // Obtener la lista de contactos del usuario
  static Future<List<dynamic>> getContacts() async {
    try {
      final response = await ApiClient.get('/contacts'); // Llama a tu router.get('/', getContacts)
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      print("Error al obtener contactos: $e");
      return [];
    }
  }

  // Agregar un nuevo contacto usando su ALIAS
  static Future<bool> addContact(String alias) async {
    try {
      final response = await ApiClient.post('/contacts/add', {
        'alias': alias, // Mandamos el alias como pide tu validador Zod
      });
      return response.statusCode == 201;
    } catch (e) {
      print("Error al agregar contacto: $e");
      return false;
    }
  }
}
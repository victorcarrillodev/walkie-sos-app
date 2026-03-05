import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://walkiesos.jegode.com/api';
  late Dio _dio;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) => handler.next(error),
    ));
  }

  // AUTH
  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _dio.post('/auth/login',
        data: {'email': email, 'password': password});
    return response.data;
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String alias,
    required String firstName,
    required String lastName,
  }) async {
    final response = await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      'alias': alias,
      'firstName': firstName,
      'lastName': lastName,
    });
    return response.data;
  }

  // CANALES
  Future<List<dynamic>> getMyChannels() async {
    final response = await _dio.get('/channels/mine');
    return response.data;
  }

  Future<List<dynamic>> getPublicChannels() async {
    final response = await _dio.get('/channels/public');
    return response.data;
  }

  Future<Map<String, dynamic>> createChannel({
    required String name,
    String? description,
    bool isPrivate = false,
  }) async {
    final response = await _dio.post('/channels', data: {
      'name': name,
      if (description != null) 'description': description,
      'isPrivate': isPrivate,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> joinChannelByName(String name) async {
    final response = await _dio.post('/channels/join', data: {'name': name});
    return response.data;
  }

  // Canal directo entre dos usuarios
  Future<Map<String, dynamic>> createDirectChannel(
    String myUserId, String targetUserId) async {
  final ids = [myUserId, targetUserId]..sort();
  final channelName = 'direct_${ids[0]}_${ids[1]}';

  try {
    // Primero intentar unirse por nombre (por si ya existe)
    final joinResponse = await _dio.post('/channels/join',
        data: {'name': channelName});
    // Si se unió exitosamente, buscar el canal en mis canales
    final myChannels = await _dio.get('/channels/mine');
    final List channels = myChannels.data;
    final existing = channels.firstWhere(
      (c) => c['name'] == channelName,
      orElse: () => null,
    );
    if (existing != null) return existing;
    return joinResponse.data;
  } on DioException catch (e) {
    // Si ya es miembro (400) o canal no existe, intentar crear
    if (e.response?.statusCode == 400) {
      final errorMsg = e.response?.data?['error'] ?? '';
      if (errorMsg.contains('miembro') || errorMsg.contains('member')) {
        // Ya es miembro, obtener el canal
        final myChannels = await _dio.get('/channels/mine');
        final List channels = myChannels.data;
        final existing = channels.firstWhere(
          (c) => c['name'] == channelName,
          orElse: () => null,
        );
        if (existing != null) return existing;
      }
    }
    // Canal no existe, crear uno nuevo
    final response = await _dio.post('/channels', data: {
      'name': channelName,
      'isPrivate': true,
    });
    return response.data;
  }
}

  // CONTACTOS
  Future<List<dynamic>> getContacts() async {
    final response = await _dio.get('/contacts');
    return response.data;
  }

  Future<Map<String, dynamic>> addContact(String alias) async {
    final response =
        await _dio.post('/contacts/add', data: {'alias': alias});
    return response.data;
  }
}
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
      'description': ?description,
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

    debugPrint('🔍 Buscando canal directo: $channelName');

    // Paso 1: ¿Ya soy miembro?
    try {
      final myChannels = await _dio.get('/channels/mine');
      final List channels = myChannels.data;
      final existing = channels.firstWhere(
        (c) => c['name'] == channelName,
        orElse: () => null,
      );
      if (existing != null) {
        debugPrint('✅ Ya soy miembro del canal: ${existing['id']}');
        return existing;
      }
    } catch (e) {
      debugPrint('⚠️ Error buscando mis canales: $e');
    }

    // Paso 2: Intentar unirse
    try {
      await _dio.post('/channels/join', data: {'name': channelName});
      debugPrint('✅ Me uní al canal existente');
      final myChannels = await _dio.get('/channels/mine');
      final List channels = myChannels.data;
      final joined = channels.firstWhere(
        (c) => c['name'] == channelName,
        orElse: () => null,
      );
      if (joined != null) return joined;
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['error'] ?? '';
      debugPrint('⚠️ Join resultado: $errorMsg');
      if (errorMsg.contains('miembro') || errorMsg.contains('member')) {
        final myChannels = await _dio.get('/channels/mine');
        final List channels = myChannels.data;
        final existing = channels.firstWhere(
          (c) => c['name'] == channelName,
          orElse: () => null,
        );
        if (existing != null) return existing;
      }
    }

    // Paso 3: Crear canal nuevo
    debugPrint('📡 Creando canal directo nuevo: $channelName');
    final response = await _dio.post('/channels', data: {
      'name': channelName,
      'isPrivate': false,
      'description': 'Canal directo',
    });
    return response.data;
  }

  // ADMINISTRACIÓN DE GRUPOS
  Future<List<dynamic>> getChannelMembers(String channelId) async {
    final response = await _dio.get('/channels/$channelId/members');
    return response.data;
  }

  Future<void> toggleMuteChannel(String channelId, bool isMuted) async {
    await _dio.patch('/channels/$channelId/mute', data: {'isMuted': isMuted});
  }

  Future<void> penalizeMember(String channelId, String userId, int? minutes) async {
    await _dio.patch('/channels/$channelId/members/$userId/penalize', data: {'minutes': minutes});
  }

  Future<void> deleteChannel(String channelId) async {
    await _dio.delete('/channels/$channelId');
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
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import '../services/socket_service.dart';
import '../services/webrtc_service.dart';
import '../services/database_service.dart';
import '../models/message_model.dart';
import 'dart:async';

class VoiceProvider extends ChangeNotifier {
  final SocketService _socketService = SocketService();
  final WebRTCService _webrtcService = WebRTCService();
  final DatabaseService _db = DatabaseService();

  final StreamController<MessageModel> _newMessageController = StreamController<MessageModel>.broadcast();
  Stream<MessageModel> get newMessageStream => _newMessageController.stream;

  String? _whoIsTalking;
  String? _activeChannelId;
  String? _myUserId;
  bool _isInitialized = false;

  String? get whoIsTalking => _whoIsTalking;
  String? get activeChannelId => _activeChannelId;

  Future<void> init(String myUserId) async {
    if (_isInitialized) return;
    _isInitialized = true;
    _myUserId = myUserId;
    
    await _setupBackground();
    _setupListeners();
    _webrtcService.initGlobal(myUserId: myUserId);
  }

  Future<void> _setupBackground() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      if (Platform.isAndroid) {
        final androidConfig = const FlutterBackgroundAndroidConfig(
          notificationTitle: "WalkieSOS",
          notificationText: "Escuchando múltiples canales",
          notificationImportance: AndroidNotificationImportance.normal,
          notificationIcon: AndroidResource(name: 'logo', defType: 'drawable'),
        );
        
        bool hasPermissions = await FlutterBackground.initialize(androidConfig: androidConfig);
        if (hasPermissions) {
          await FlutterBackground.enableBackgroundExecution();
          debugPrint('✅ Ejecución en segundo plano global activada');
        }
      }
    } catch (e) {
      debugPrint('❌ Error al configurar background global: $e');
    }
  }

  void _setupListeners() {
    _socketService.onPttStatus((data) {
      final map = data is List ? data[0] : data;
      if (map['isTalking'] == true) {
        _whoIsTalking = map['alias'];
        _activeChannelId = map['channelId'];
      } else {
        _whoIsTalking = null;
        _activeChannelId = null;
      }
      notifyListeners();
    });

    _socketService.onReceiveAudio((data) async {
       final map = data is List ? data[0] : data;
       final senderId = map['userId'] as String? ?? '';
       final channelId = map['channelId'] as String?;
       
       if (senderId == _myUserId || channelId == null) return;
       await _saveAudioHistory(map, channelId);
    });
  }

  Future<void> _saveAudioHistory(Map<String, dynamic> data, String channelId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/recv_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final bytes = base64Decode(data['audioData']);
      await File(path).writeAsBytes(bytes);
      
      final msg = MessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        channelId: channelId,
        userId: data['userId'] ?? '',
        alias: data['alias'] ?? 'Desconocido',
        audioPath: path,
        createdAt: DateTime.now(),
      );
      
      await _db.saveMessage(msg);
      _newMessageController.add(msg);
    } catch (e) {
      debugPrint('❌ Error guardando historial en background: $e');
    }
  }
}

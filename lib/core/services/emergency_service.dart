import 'package:flutter/material.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'socket_service.dart';
import 'dart:convert';

class EmergencyService extends ChangeNotifier {
  static final EmergencyService _instance = EmergencyService._internal();
  factory EmergencyService() => _instance;
  EmergencyService._internal();

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  SpeechService? _speechService;
  Model? _model;
  Recognizer? _recognizer;

  bool _isListening = false;
  bool _speechEnabled = false;
  
  String _keyPhrase = 'ayuda por favor'; // Frase por defecto
  List<String> _targetIds = []; 

  bool get isListening => _isListening;
  String get keyPhrase => _keyPhrase;
  List<String> get targetIds => _targetIds;

  Future<void> init() async {
    try {
      debugPrint('🎙️ Cargando modelo de rescate Vosk offline...');
      // Extrae y carga el modelo desde los assets
      final modelPath = await ModelLoader()
          .loadFromAssets('assets/models/vosk-model-small-es-0.42.zip');
      
      _model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );

      _speechService = await _vosk.initSpeechService(_recognizer!);
      
      _speechService!.onPartial().listen((e) {
        // e is usually a JSON string like {"partial": "ayuda"}
        try {
          final map = jsonDecode(e);
          final String partial = map['partial'] ?? '';
          _checkKeyword(partial);
        } catch (_) {}
      });

      _speechService!.onResult().listen((e) {
        try {
          final map = jsonDecode(e);
          final String text = map['text'] ?? '';
          _checkKeyword(text);
        } catch (_) {}
      });

      _speechEnabled = true;
      debugPrint('🎙️ Vosk model cargado con éxito. Sin ruido.');
    } catch (e) {
      debugPrint('❌ Error cargando Vosk: $e');
    }

    await loadSettings();
    if (_speechEnabled) {
      startListening();
    }
  }

  void _checkKeyword(String text) {
     if (text.isEmpty) return;
     if (text.toLowerCase().contains(_keyPhrase.trim().toLowerCase())) {
        debugPrint("🚨 Vosk Phrase detected! text: $text");
        triggerEmergency();
     }
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _keyPhrase = prefs.getString('emergency_key_phrase') ?? 'ayuda por favor';
    
    final list = prefs.getStringList('emergency_target_ids');
    if (list != null) {
      _targetIds = list;
    } else {
      final oldId = prefs.getString('emergency_target_id');
      final isGroup = prefs.getBool('emergency_is_group') ?? false;
      if (oldId != null) {
        _targetIds = [isGroup ? 'G_$oldId' : 'C_$oldId'];
        await prefs.setStringList('emergency_target_ids', _targetIds);
        await prefs.remove('emergency_target_id');
        await prefs.remove('emergency_is_group');
      } else {
        _targetIds = [];
      }
    }
    notifyListeners();
  }

  Future<void> saveSettings(String phrase, List<String> targetIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emergency_key_phrase', phrase);
    await prefs.setStringList('emergency_target_ids', targetIds);
    
    _keyPhrase = phrase;
    _targetIds = targetIds;
    notifyListeners();
  }

  Future<void> startListening() async {
    if (!_speechEnabled || _speechService == null) return;
    try {
      await _speechService!.start();
      _isListening = true;
      notifyListeners();
      debugPrint('✅ Vosk Listening Mode Started');
    } catch (e) {
      debugPrint('❌ Vosk Listening Start Error: $e');
    }
  }

  Future<void> stopListening() async {
    if (_speechService != null && _isListening) {
      await _speechService!.stop();
      _isListening = false;
      notifyListeners();
    }
  }

  Future<void> triggerEmergency() async {
    debugPrint("EMERGENCY TRIGGERED!");
    // Pausamos brevemente Vosk para evitar loops de ayuda
    await stopListening();
    
    Position? position;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
      } else {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        }
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
    }

    if (_targetIds.isNotEmpty && SocketService().isConnected) {
       for (final target in _targetIds) {
           final isGroup = target.startsWith('G_');
           final id = target.substring(2);
           final payload = {
             'channelId': id,
             'isGroup': isGroup,
             'lat': position?.latitude ?? 0.0,
             'lng': position?.longitude ?? 0.0,
             'type': 'PANIC',
           };
           SocketService().socket?.emit('send-alert', payload);
           debugPrint("EMERGENCY ALERT SENT: $payload");
       }
    } else {
       debugPrint("Could not send emergency alert. TargetIds: ${_targetIds.length}, Socket: ${SocketService().isConnected}");
    }

    // Reiniciamos reconocimiento
    Future.delayed(const Duration(seconds: 5), () {
       startListening();
    });
  }
}

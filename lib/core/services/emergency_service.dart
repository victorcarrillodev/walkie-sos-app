import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'socket_service.dart';

class EmergencyService extends ChangeNotifier {
  static final EmergencyService _instance = EmergencyService._internal();
  factory EmergencyService() => _instance;
  EmergencyService._internal();

  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;
  String _lastWords = '';

  String _keyPhrase = 'ayuda por favor'; // Frase por defecto
  String? _targetId; 
  bool _isGroupTarget = false;

  bool get isListening => _isListening;
  String get keyPhrase => _keyPhrase;
  String? get targetId => _targetId;
  bool get isGroupTarget => _isGroupTarget;

  Future<void> init() async {
    _speechEnabled = await _speechToText.initialize(
      onError: (val) => debugPrint('SpeechToText onError: $val'),
      onStatus: (val) {
        debugPrint('SpeechToText onStatus: $val');
        if ((val == 'done' || val == 'notListening') && _isListening) {
           // Reiniciar la escucha si se detiene (ya que la API a veces corta después de silencio)
           Future.delayed(const Duration(milliseconds: 500), () {
             if (_isListening && !_speechToText.isListening) {
               _startListeningInternal();
             }
           });
        }
      },
    );
    await loadSettings();
    if (_speechEnabled) {
      startListening();
    }
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _keyPhrase = prefs.getString('emergency_key_phrase') ?? 'ayuda por favor';
    _targetId = prefs.getString('emergency_target_id');
    _isGroupTarget = prefs.getBool('emergency_is_group') ?? false;
    notifyListeners();
  }

  Future<void> saveSettings(String phrase, String? targetId, bool isGroup) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emergency_key_phrase', phrase);
    if (targetId != null) {
      await prefs.setString('emergency_target_id', targetId);
    } else {
      await prefs.remove('emergency_target_id');
    }
    await prefs.setBool('emergency_is_group', isGroup);
    
    _keyPhrase = phrase;
    _targetId = targetId;
    _isGroupTarget = isGroup;
    notifyListeners();
  }

  void startListening() {
    if (!_speechEnabled) {
      debugPrint("Speech recognition not enabled");
      return;
    }
    _isListening = true;
    _startListeningInternal();
    notifyListeners();
  }
  
  void _startListeningInternal() async {
    await _speechToText.listen(
      onResult: (result) async {
        _lastWords = result.recognizedWords;
        debugPrint("Recognized words: $_lastWords");
        if (_lastWords.toLowerCase().contains(_keyPhrase.trim().toLowerCase())) {
          debugPrint("Key phrase detected!");
          await triggerEmergency();
        }
      },
      localeId: 'es_ES', // Forzar español para mayor precisión en la frase
      cancelOnError: false,
      partialResults: true,
      listenMode: ListenMode.dictation,
      listenFor: const Duration(hours: 24),
    );
  }

  void stopListening() {
    _isListening = false;
    _speechToText.stop();
    notifyListeners();
  }

  Future<void> triggerEmergency() async {
    debugPrint("EMERGENCY TRIGGERED!");
    // Detenemos la escucha brevemente para evitar múltiples envíos
    stopListening();
    
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

    if (_targetId != null && SocketService().isConnected) {
       final payload = {
         'channelId': _targetId,
         'isGroup': _isGroupTarget,
         'lat': position?.latitude ?? 0.0,
         'lng': position?.longitude ?? 0.0,
         'type': 'PANIC',
       };
       SocketService().socket?.emit('send-alert', payload);
       debugPrint("EMERGENCY ALERT SENT: $payload");
    } else {
       debugPrint("Could not send emergency alert. TargetId: $_targetId, Socket Connected: ${SocketService().isConnected}");
    }

    // Reiniciamos la escucha después de unos segundos
    Future.delayed(const Duration(seconds: 5), () {
       startListening();
    });
  }
}

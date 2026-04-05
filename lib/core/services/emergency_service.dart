import 'package:flutter/material.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'socket_service.dart';
import 'dart:async';
import 'dart:convert';

class EmergencyService extends ChangeNotifier {
  static final EmergencyService _instance = EmergencyService._internal();
  factory EmergencyService() => _instance;
  EmergencyService._internal();

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  SpeechService? _speechService;
  Model?         _model;
  Recognizer?    _recognizer;

  bool _isListening    = false;
  bool _speechEnabled  = false;
  bool _isCooldown     = false;   // evita disparar la alerta varias veces seguidas

  String       _keyPhrase = 'ayuda por favor';
  List<String> _targetIds = [];

  // Stream local → GlobalEmergencyOverlay escucha esto para mostrar la alerta propia
  final _localAlertController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get localAlertStream => _localAlertController.stream;

  bool         get isListening => _isListening;
  String       get keyPhrase   => _keyPhrase;
  List<String> get targetIds   => _targetIds;

  // ───────────────────────────────────────────────────────────────────────────
  Future<void> init() async {
    try {
      debugPrint('🎙️ [Vosk] Iniciando carga del modelo...');
      final modelPath = await ModelLoader()
          .loadFromAssets('assets/models/vosk-model-small-es-0.42.zip');
      debugPrint('🎙️ [Vosk] Modelo extraído en: $modelPath');

      _model      = await _vosk.createModel(modelPath);
      debugPrint('🎙️ [Vosk] Model creado OK');

      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );
      debugPrint('🎙️ [Vosk] Recognizer creado OK');

      _speechService = await _vosk.initSpeechService(_recognizer!);
      debugPrint('🎙️ [Vosk] SpeechService iniciado OK');

      _speechService!.onPartial().listen((e) {
        try {
          final map     = jsonDecode(e) as Map;
          final partial = (map['partial'] as String? ?? '').toLowerCase().trim();
          if (partial.isNotEmpty) {
            debugPrint('🎙️ [Vosk] partial: "$partial"');
            _checkKeyword(partial);
          }
        } catch (_) {}
      });

      _speechService!.onResult().listen((e) {
        try {
          final map  = jsonDecode(e) as Map;
          final text = (map['text'] as String? ?? '').toLowerCase().trim();
          if (text.isNotEmpty) {
            debugPrint('🎙️ [Vosk] result: "$text"');
            _checkKeyword(text);
          }
        } catch (_) {}
      });

      _speechEnabled = true;
      debugPrint('✅ [Vosk] Listo. Frase clave actual: "$_keyPhrase"');
    } catch (e, stack) {
      debugPrint('❌ [Vosk] Error cargando modelo: $e');
      debugPrint('$stack');
    }

    await loadSettings();
    debugPrint('🔑 [Vosk] Frase detectora: "$_keyPhrase" | Targets: $_targetIds');
    if (_speechEnabled) await startListening();
  }

  // ── Detección de la frase clave ─────────────────────────────────────────
  // Estrategia: se activa si el texto contiene al menos 2 de las palabras
  // significativas de la frase, O si contiene la frase exacta.
  void _checkKeyword(String text) {
    if (text.isEmpty || _isCooldown) return;

    final phrase = _keyPhrase.trim().toLowerCase();
    if (phrase.isEmpty) {
      debugPrint('⚠️ [Vosk] Frase clave vacía, no se puede detectar');
      return;
    }

    final words = phrase
        .split(' ')
        .where((w) => w.length > 3)
        .toList();

    final exactMatch = text.contains(phrase);
    int matches = 0;
    for (final w in words) {
      if (text.contains(w)) matches++;
    }
    final partialMatch = words.isNotEmpty && matches >= (words.length / 2).ceil();

    debugPrint('🔍 [Vosk] check: texto="$text" frase="$phrase" exact=$exactMatch matches=$matches/${words.length}');

    if (exactMatch || partialMatch) {
      debugPrint('🚨 [Vosk] ¡DETECTADO! Disparando emergencia...');
      triggerEmergency();
    }
  }

  // ── Configuración ─────────────────────────────────────────────────────────
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _keyPhrase = prefs.getString('emergency_key_phrase') ?? 'ayuda por favor';

    final list = prefs.getStringList('emergency_target_ids');
    if (list != null) {
      _targetIds = list;
    } else {
      final oldId   = prefs.getString('emergency_target_id');
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

  // ── Control del micrófono ─────────────────────────────────────────────────
  Future<void> startListening() async {
    if (!_speechEnabled || _speechService == null) {
      debugPrint('⚠️ [Vosk] startListening ignorado: speechEnabled=$_speechEnabled, service=${_speechService != null}');
      return;
    }
    if (_isListening) {
      debugPrint('⚠️ [Vosk] ya está escuchando, ignorando startListening');
      return;
    }
    try {
      await _speechService!.start();
      _isListening = true;
      notifyListeners();
      debugPrint('✅ [Vosk] Escuchando...');
    } catch (e) {
      debugPrint('❌ [Vosk] start error: $e');
      await _restartSpeechService();
    }
  }

  Future<void> stopListening() async {
    if (!_isListening || _speechService == null) {
      debugPrint('⚠️ [Vosk] stopListening ignorado: isListening=$_isListening');
      return;
    }
    try {
      await _speechService!.stop();
      debugPrint('⏸️ [Vosk] Pausado.');
    } catch (e) {
      debugPrint('⚠️ [Vosk] stop error (ignorado): $e');
    } finally {
      _isListening = false;
      notifyListeners();
    }
  }

  /// Destruye y recrea el SpeechService para resolver bloqueos de estado interno.
  Future<void> _restartSpeechService() async {
    debugPrint('🔄 Reiniciando SpeechService...');
    try {
      _speechService = null;
      _isListening   = false;
      if (_recognizer != null) {
        _speechService = await _vosk.initSpeechService(_recognizer!);

        _speechService!.onPartial().listen((e) {
          try {
            final map     = jsonDecode(e) as Map;
            final partial = (map['partial'] as String? ?? '').toLowerCase();
            if (partial.isNotEmpty) _checkKeyword(partial);
          } catch (_) {}
        });

        _speechService!.onResult().listen((e) {
          try {
            final map  = jsonDecode(e) as Map;
            final text = (map['text'] as String? ?? '').toLowerCase();
            if (text.isNotEmpty) {
              debugPrint('🎙️ Vosk result: "$text"');
              _checkKeyword(text);
            }
          } catch (_) {}
        });

        await _speechService!.start();
        _isListening = true;
        notifyListeners();
        debugPrint('✅ SpeechService reiniciado correctamente.');
      }
    } catch (e) {
      debugPrint('❌ Fallo reinicio SpeechService: $e');
    }
  }

  // ── Disparar emergencia ───────────────────────────────────────────────────
  Future<void> triggerEmergency() async {
    if (_isCooldown) return;
    _isCooldown = true;
    debugPrint('🚨 EMERGENCY TRIGGERED!');

    await stopListening();

    // Obtener ubicación
    Position? position;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error ubicación: $e');
    }

    // Enviar por socket
    if (_targetIds.isNotEmpty && SocketService().isConnected) {
      for (final target in _targetIds) {
        final isGroup = target.startsWith('G_');
        final id      = target.substring(2);
        SocketService().socket?.emit('send-alert', {
          'channelId': id,
          'isGroup':   isGroup,
          'lat':       position?.latitude  ?? 0.0,
          'lng':       position?.longitude ?? 0.0,
          'type':      'PANIC',
        });
        debugPrint('📡 Alert enviado a: $id');
      }
    } else {
      debugPrint('⚠️ No se pudo enviar: targets=${_targetIds.length}, socket=${SocketService().isConnected}');
    }

    // Cooldown de 10 s para evitar disparos repetidos
    Future.delayed(const Duration(seconds: 10), () {
      _isCooldown = false;
      startListening();
    });
  }
}

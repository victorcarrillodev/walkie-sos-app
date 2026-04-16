import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert_recording_model.dart';
import 'database_service.dart';
import 'socket_service.dart';

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
  bool _isCooldown     = false;
  bool _isInitializing = false;

  String       _keyPhrase = 'ayuda por favor';
  List<String> _targetIds = [];

  // ── Grabación post-alarma ─────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  final DatabaseService _db = DatabaseService();

  /// Emite el modelo de grabación cuando un clip de 10 s queda listo.
  final _recordingController = StreamController<AlertRecordingModel>.broadcast();
  Stream<AlertRecordingModel> get recordingStream => _recordingController.stream;

  // Stream local → GlobalEmergencyOverlay escucha esto para mostrar la alerta propia
  final _localAlertController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get localAlertStream => _localAlertController.stream;

  bool         get isListening    => _isListening;
  bool         get isSpeechEnabled => _speechEnabled;
  String       get keyPhrase      => _keyPhrase;
  List<String> get targetIds      => _targetIds;

  // ───────────────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      debugPrint('🎙️ [Vosk] Iniciando carga del modelo...');
      final modelPath = await ModelLoader()
          .loadFromAssets('assets/models/vosk-model-small-es-0.42.zip');
      debugPrint('🎙️ [Vosk] Modelo extraído en: $modelPath');

      _model      = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );
      _speechService = await _vosk.initSpeechService(_recognizer!);

      _attachListeners();

      _speechEnabled = true;
      debugPrint('✅ [Vosk] Listo.');
    } catch (e, stack) {
      debugPrint('❌ [Vosk] Error cargando modelo: $e\n$stack');
      _speechEnabled = false;
    } finally {
      _isInitializing = false;
    }

    await loadSettings();
    debugPrint('🔑 [Vosk] Frase: "$_keyPhrase" | Targets: $_targetIds');
    if (_speechEnabled) await startListening();
  }

  void _attachListeners() {
    // onPartial: sólo dispara si la frase completa ya aparece (detección rápida)
    _speechService!.onPartial().listen((e) {
      try {
        final map     = jsonDecode(e) as Map;
        final partial = _normalize(map['partial'] as String? ?? '');
        if (partial.isNotEmpty) _checkKeyword(partial, isPartial: true);
      } catch (_) {}
    });

    // onResult: texto final confirmado, usa la lógica de similitud completa
    _speechService!.onResult().listen((e) {
      try {
        final map  = jsonDecode(e) as Map;
        final text = _normalize(map['text'] as String? ?? '');
        if (text.isNotEmpty) {
          debugPrint('🎙️ [Vosk] result: "$text"');
          _checkKeyword(text, isPartial: false);
        }
      } catch (_) {}
    });
  }

  // ── Normalización: quita acentos, puntuación y espacios dobles ─────────────
  String _normalize(String text) {
    const accents = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u',
      'ä': 'a', 'ë': 'e', 'ï': 'i', 'ö': 'o', 'ü': 'u',
      'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u',
      'â': 'a', 'ê': 'e', 'î': 'i', 'ô': 'o', 'û': 'u',
      'ñ': 'n',
    };
    var s = text.toLowerCase().trim();
    accents.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^\w\s]'), ''); // quita puntuación
    s = s.replaceAll(RegExp(r'\s+'), ' ');     // normaliza espacios
    return s;
  }

  // ── Detección de la frase clave ─────────────────────────────────────────
  void _checkKeyword(String text, {required bool isPartial}) {
    if (text.isEmpty || _isCooldown) return;

    final phrase = _normalize(_keyPhrase);
    if (phrase.isEmpty) return;

    // 1. Coincidencia exacta — dispara inmediatamente aunque sea parcial
    if (text.contains(phrase)) {
      debugPrint('🚨 [Vosk] ¡EXACTO! "$phrase" en "$text"');
      triggerEmergency();
      return;
    }

    // 2. Solo en resultados finales: coincidencia por palabras clave (≥ 2 chars)
    // Esto captura frases cortas como "sos", "aux", "911", etc.
    if (!isPartial) {
      final words = phrase.split(' ').where((w) => w.length >= 2).toList();
      if (words.isEmpty) return;

      int matches = 0;
      for (final w in words) {
        if (text.contains(w)) matches++;
      }
      // Se requiere el 70% de las palabras − tolerante a muletillas y ruido
      final threshold = (words.length * 0.7).ceil();
      debugPrint('🔍 [Vosk] texto="$text" matches=$matches/${words.length} (need $threshold)');
      if (matches >= threshold) {
        debugPrint('🚨 [Vosk] ¡COINCIDENCIA PARCIAL! Disparando...');
        triggerEmergency();
      }
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
    // Guardar normalizado para que siempre coincida con lo transcripto por Vosk
    final normalizedPhrase = _normalize(phrase);
    await prefs.setString('emergency_key_phrase', normalizedPhrase);
    await prefs.setStringList('emergency_target_ids', targetIds);
    _keyPhrase = normalizedPhrase;
    _targetIds = targetIds;
    notifyListeners();
  }

  // ── Control del micrófono ─────────────────────────────────────────────────
  Future<void> startListening() async {
    if (!_speechEnabled || _speechService == null) return;
    if (_isListening) return;
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
    if (!_isListening || _speechService == null) return;
    try {
      await _speechService!.stop();
    } catch (e) {
      debugPrint('⚠️ [Vosk] stop error: $e');
    } finally {
      _isListening = false;
      notifyListeners();
    }
  }

  Future<void> _restartSpeechService() async {
    debugPrint('🔄 Reiniciando SpeechService...');
    try {
      _speechService = null;
      _isListening   = false;
      if (_recognizer != null) {
        _speechService = await _vosk.initSpeechService(_recognizer!);
        _attachListeners();
        _speechEnabled = true;
        await _speechService!.start();
        _isListening = true;
        notifyListeners();
        debugPrint('✅ SpeechService reiniciado.');
      }
    } catch (e) {
      debugPrint('❌ Fallo reinicio SpeechService: $e');
      _speechEnabled = false;
    }
  }

  // ── Disparar emergencia ───────────────────────────────────────────────────
  Future<void> triggerEmergency() async {
    if (_isCooldown) return;
    _isCooldown = true;
    debugPrint('🚨 EMERGENCY TRIGGERED!');

    await stopListening();

    // GPS con timeout agresivo de 4 s — no bloqueamos el envío de la alerta
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
            desiredAccuracy: LocationAccuracy.medium,
          ).timeout(
            const Duration(seconds: 4),
            onTimeout: () async {
              debugPrint('⚠️ [GPS] timeout — usando última posición conocida...');
              return await Geolocator.getLastKnownPosition() ??
                  (throw Exception('Sin posición disponible'));
            },
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error GPS: $e — la alerta se enviará sin coordenadas.');
    }

    // Enviar alerta por socket
    String? remoteAlertId;
    if (_targetIds.isNotEmpty && SocketService().isConnected) {
      for (final target in _targetIds) {
        final isGroup = target.startsWith('G_');
        final id      = target.substring(2);
        SocketService().socket?.emitWithAck('send-alert', {
          'channelId': id,
          'isGroup':   isGroup,
          'lat':       position?.latitude  ?? 0.0,
          'lng':       position?.longitude ?? 0.0,
          'type':      'PANIC',
        }, ack: (ackData) {
          if (ackData is Map && ackData['id'] != null) {
            remoteAlertId = ackData['id'].toString();
            debugPrint('📡 Alert remoteId: $remoteAlertId');
          }
        });
        debugPrint('📡 Alert → $id');
      }
    } else {
      debugPrint('⚠️ No se envió: targets=${_targetIds.length}, socket=${SocketService().isConnected}');
    }

    // ── Grabación de 10 segundos post-alarma ──────────────────────────────
    _startPostAlarmRecording(remoteAlertId);

    // Cooldown de 8 s para evitar disparos repetidos en la misma frase
    Future.delayed(const Duration(seconds: 8), () {
      _isCooldown = false;
      startListening();
    });
  }

  // ── Helpers de grabación ──────────────────────────────────────────────────

  Future<void> _startPostAlarmRecording(String? remoteAlertId) async {
    if (_isRecording) return;
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        debugPrint('⚠️ [Rec] Sin permiso de micrófono para grabación post-alarma.');
        return;
      }

      final dir  = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/emergency_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder:    AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate:    128000,
        ),
        path: path,
      );
      _isRecording = true;
      debugPrint('🎙️ [Rec] Grabando 10 s post-alarma → $path');

      // Detener automáticamente a los 10 segundos
      await Future.delayed(const Duration(seconds: 10));
      await _stopPostAlarmRecording(path, remoteAlertId);
    } catch (e) {
      _isRecording = false;
      debugPrint('❌ [Rec] Error iniciando grabación: $e');
    }
  }

  Future<void> _stopPostAlarmRecording(String path, String? remoteAlertId) async {
    try {
      await _recorder.stop();
      _isRecording = false;
      debugPrint('✅ [Rec] Grabación finalizada.');

      final fileExists = await File(path).exists();
      if (!fileExists) {
        debugPrint('⚠️ [Rec] El archivo de grabación no existe: $path');
        return;
      }

      final rec = AlertRecordingModel(
        id:        DateTime.now().millisecondsSinceEpoch.toString(),
        alertId:   remoteAlertId ?? '',
        audioPath: path,
        createdAt: DateTime.now(),
      );

      await _db.saveAlertRecording(rec);
      _recordingController.add(rec);
      debugPrint('💾 [Rec] Clip guardado en DB: ${rec.id}');
    } catch (e) {
      _isRecording = false;
      debugPrint('❌ [Rec] Error deteniendo grabación: $e');
    }
  }
}

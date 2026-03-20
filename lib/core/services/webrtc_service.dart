import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';

class WebRTCService {
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  final SocketService _socketService = SocketService();

  // Conexión de salida (cuando nosotros somos el hablante)
  RTCPeerConnection? _senderPc;
  // Conexiones de entrada (cuando recibimos de otros hablantes)
  final Map<String, RTCPeerConnection> _receiverPcs = {};
  // Tracks remotos activos para audio en background
  final Map<String, MediaStreamTrack> _remoteAudioTracks = {};

  MediaStream? _localStream;
  String? _currentChannelId;

  // ID del usuario local para ignorar señales WebRTC propias (evita auto-echo)
  String? _myUserId;

  // Forzamos los renderers de audio remotos a salida de altavoz
  // incluso en segundo plano gracias a la AudioSession configurada
  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    // Desactivar audio local en la PC receptora para evitar feedback
    'sdpSemantics': 'unified-plan',
  };

  // Constraints de medios: activan cancelación de eco a nivel de hardware
  static const Map<String, dynamic> _audioConstraints = {
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'sampleRate': 16000,
      'channelCount': 1,
    },
    'video': false,
  };

  void init(String channelId, {required String myUserId}) {
    _currentChannelId = channelId;
    _myUserId = myUserId;
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    _socketService.onReceiveOffer((data) async {
      final map = data is List ? data[0] : data;
      final senderId = map['userId'] as String?;
      // Ignorar nuestra propia oferta si el servidor hace broadcast total
      if (senderId == _myUserId) {
        debugPrint('🚫 Ignorando oferta WebRTC propia (self-echo)');
        return;
      }
      debugPrint('📥 Recibida oferta WebRTC de $senderId');
      await _handleIncomingOffer(senderId, map['offer']);
    });

    _socketService.onReceiveAnswer((data) async {
      final map = data is List ? data[0] : data;
      final senderId = map['userId'] as String?;
      if (senderId == _myUserId) return;
      debugPrint('📥 Recibida respuesta WebRTC de $senderId');
      await _handleIncomingAnswer(senderId, map['answer']);
    });

    _socketService.onReceiveIceCandidate((data) async {
      final map = data is List ? data[0] : data;
      final senderId = map['userId'] as String?;
      if (senderId == _myUserId) return;
      await _handleIncomingIceCandidate(senderId, map['candidate']);
    });
  }

  Future<void> startTalking() async {
    if (_currentChannelId == null) return;
    // Evitar arrancar si ya hay un stream activo
    if (_localStream != null) await stopTalking();

    // 1. Capturar micrófono con cancelación de eco forzada
    _localStream = await navigator.mediaDevices.getUserMedia(_audioConstraints);

    // 2. Crear la peer connection de salida
    _senderPc = await createPeerConnection(_configuration);
    _senderPc!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        _socketService.sendIceCandidate(_currentChannelId!, candidate.toMap());
      }
    };
    _senderPc!.onIceConnectionState = (state) {
      debugPrint('📡 ICE state (sender): $state');
    };

    // 3. Agregar tracks de audio al stream de salida
    for (final track in _localStream!.getAudioTracks()) {
      await _senderPc!.addTrack(track, _localStream!);
    }

    // 4. Crear oferta y enviarla
    try {
      final offer = await _senderPc!.createOffer({'offerToReceiveAudio': false});
      await _senderPc!.setLocalDescription(offer);
      _socketService.sendOffer(_currentChannelId!, offer.toMap());
      debugPrint('📤 Oferta WebRTC enviada');
    } catch (e) {
      debugPrint('❌ Error al crear oferta WebRTC: $e');
    }
  }

  Future<void> stopTalking() async {
    // Detener y limpiar stream local
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    // Cerrar peer connection de salida
    if (_senderPc != null) {
      await _senderPc!.close();
      _senderPc = null;
    }

    debugPrint('🔇 WebRTC stopTalking completado');
  }

  Future<void> _handleIncomingOffer(
    String? remoteUserId,
    Map<String, dynamic> offerMap,
  ) async {
    if (remoteUserId == null || _currentChannelId == null) return;

    // Cerrar conexión previa de este usuario si existe
    if (_receiverPcs.containsKey(remoteUserId)) {
      await _receiverPcs[remoteUserId]!.close();
      _receiverPcs.remove(remoteUserId);
    }

    final pc = await createPeerConnection(_configuration);
    _receiverPcs[remoteUserId] = pc;

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        _socketService.sendIceCandidate(_currentChannelId!, candidate.toMap());
      }
    };

    // onTrack: aquí llega el audio remoto. Flutter WebRTC lo reproduce
    // automáticamente en el altavoz del dispositivo, incluso en background,
    // siempre que AudioSession esté en voiceCommunication mode.
    pc.onTrack = (RTCTrackEvent event) {
      for (final stream in event.streams) {
        for (final track in stream.getAudioTracks()) {
          debugPrint('🔊 Audio en vivo recibido de $remoteUserId');
          _remoteAudioTracks[remoteUserId] = track;
        }
      }
    };

    pc.onIceConnectionState = (state) {
      debugPrint('📡 ICE state (receiver $remoteUserId): $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        debugPrint('⚠️ Conexión WebRTC perdida con $remoteUserId');
      }
    };

    try {
      final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
      await pc.setRemoteDescription(offer);

      // Crear respuesta: SOLO recibir audio (no enviamos nada desde el receptor)
      final answer = await pc.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await pc.setLocalDescription(answer);
      _socketService.sendAnswer(_currentChannelId!, answer.toMap());
      debugPrint('📥 Respuesta WebRTC enviada a $remoteUserId');
    } catch (e) {
      debugPrint('❌ Error procesando oferta de $remoteUserId: $e');
    }
  }

  Future<void> _handleIncomingAnswer(
    String? remoteUserId,
    Map<String, dynamic> answerMap,
  ) async {
    final pc = _senderPc;
    if (pc == null) {
      debugPrint('⚠️ No hay peer connection de salida para respuesta de $remoteUserId');
      return;
    }
    try {
      final answer = RTCSessionDescription(answerMap['sdp'], answerMap['type']);
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateClosed) {
        await pc.setRemoteDescription(answer);
        debugPrint('✅ Respuesta WebRTC aceptada de $remoteUserId');
      }
    } catch (e) {
      debugPrint('❌ Error procesando respuesta de $remoteUserId: $e');
    }
  }

  Future<void> _handleIncomingIceCandidate(
    String? remoteUserId,
    Map<String, dynamic> candidateMap,
  ) async {
    // Un ICE candidate puede ser para la conexión emisora o receptora
    final pc = _receiverPcs[remoteUserId] ?? _senderPc;
    if (pc == null) return;

    try {
      final candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateClosed) {
        await pc.addCandidate(candidate);
      }
    } catch (e) {
      debugPrint('❌ Error procesando ICE candidate de $remoteUserId: $e');
    }
  }

  /// Libera todos los recursos WebRTC (llamar al salir del canal)
  Future<void> dispose() async {
    await stopTalking();
    final pcs = _receiverPcs.values.toList();
    _receiverPcs.clear();
    _remoteAudioTracks.clear();
    for (final pc in pcs) {
      await pc.close();
    }
    debugPrint('🗑️ WebRTCService disposed');
  }
}
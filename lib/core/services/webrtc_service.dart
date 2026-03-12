import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';

class WebRTCService {
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  final SocketService _socketService = SocketService();
  
  // Soporte para múltiples conexiones si hay varios usuarios
  final Map<String, RTCPeerConnection> _peerConnections = {};
  MediaStream? _localStream;
  String? _currentChannelId;

  // Servidor STUN gratuito de Google para descubrir rutas de red
  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ]
  };

  void init(String channelId) {
    _currentChannelId = channelId;
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    _socketService.onReceiveOffer((data) async {
      final map = data is List ? data[0] : data;
      debugPrint('📥 Recibida oferta WebRTC de ${map['userId']}');
      await _handleIncomingOffer(map['userId'], map['offer']);
    });

    _socketService.onReceiveAnswer((data) async {
      final map = data is List ? data[0] : data;
      debugPrint('📥 Recibida respuesta WebRTC de ${map['userId']}');
      await _handleIncomingAnswer(map['userId'], map['answer']);
    });

    _socketService.onReceiveIceCandidate((data) async {
      final map = data is List ? data[0] : data;
      await _handleIncomingIceCandidate(map['userId'], map['candidate']);
    });
  }

  Future<void> startTalking() async {
    if (_currentChannelId == null) return;

    // 1. Capturar audio del micrófono con WebRTC
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    // 2. Crear conexión
    RTCPeerConnection pc = await createPeerConnection(_configuration);
    _peerConnections['broadcast'] = pc;

    // 3. Añadir pistas de audio a la conexión
    _localStream!.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    // 4. Escuchar candidatos ICE y enviarlos
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      _socketService.sendIceCandidate(_currentChannelId!, candidate.toMap());
    };

    // 5. Crear la Oferta y enviarla al servidor
    RTCSessionDescription offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    
    _socketService.sendOffer(_currentChannelId!, offer.toMap());
  }

  Future<void> stopTalking() async {
    if (_currentChannelId == null) return;
    
    // Cerrar streams y conexiones locales
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    // 1. Hacemos una copia estática de las conexiones actuales
    final connectionsToClose = _peerConnections.values.toList();
    
    // 2. Limpiamos el mapa original inmediatamente para que 
    // nuevos eventos no interfieran con este proceso
    _peerConnections.clear();

    // 3. Iteramos de forma 100% segura sobre la copia
    for (var pc in connectionsToClose) {
      await pc.close();
    }
  }

  Future<void> _handleIncomingOffer(String? remoteUserId, Map<String, dynamic> offerMap) async {
    if (remoteUserId == null) return;

    RTCPeerConnection pc = await createPeerConnection(_configuration);
    _peerConnections[remoteUserId] = pc;

    // El audio se reproduce automáticamente en WebRTC móvil al recibir el track
    pc.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'audio') {
        debugPrint('🔊 Audio en vivo (WebRTC) recibido de $remoteUserId');
      }
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      _socketService.sendIceCandidate(_currentChannelId!, candidate.toMap());
    };

    RTCSessionDescription offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
    await pc.setRemoteDescription(offer);

    RTCSessionDescription answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _socketService.sendAnswer(_currentChannelId!, answer.toMap());
  }

  Future<void> _handleIncomingAnswer(String? remoteUserId, Map<String, dynamic> answerMap) async {
    RTCPeerConnection? pc = _peerConnections['broadcast'];
    if (pc != null) {
      RTCSessionDescription answer = RTCSessionDescription(answerMap['sdp'], answerMap['type']);
      await pc.setRemoteDescription(answer);
    }
  }

  Future<void> _handleIncomingIceCandidate(String? remoteUserId, Map<String, dynamic> candidateMap) async {
    RTCPeerConnection? pc = remoteUserId != null ? _peerConnections[remoteUserId] : _peerConnections['broadcast'];
    
    if (pc != null) {
      RTCIceCandidate candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      await pc.addCandidate(candidate);
    }
  }
}
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../../../core/models/channel_model.dart';
import '../../../core/models/message_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/socket_service.dart';

class CallScreen extends StatefulWidget {
  final ChannelModel channel;
  const CallScreen({super.key, required this.channel});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final SocketService _socket = SocketService();
  final DatabaseService _db = DatabaseService();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  // WebRTC
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isNegotiating = false;

  // Estado UI
  bool _isTalking = false;
  bool _isConnected = false;
  bool _isInitializing = true;
  bool _webrtcConnected = false;
  String? _whoIsTalking;
  String? _initError;
  List<MessageModel> _messages = [];

  late String _myUserId;
  late String _myAlias;

  // ICE servers con tu TURN
  static const List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {
      'urls': 'turn:5.78.64.107:3478',
      'username': 'walkieuser',
      'credential': 'walkiepass123',
    },
    {
      'urls': 'turn:5.78.64.107:3478?transport=tcp',
      'username': 'walkieuser',
      'credential': 'walkiepass123',
    },
  ];

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user!;
    _myUserId = user.id;
    _myAlias = user.alias;
    _init();
  }

  Future<void> _init() async {
    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        setState(() {
          _initError = 'Se necesita permiso de micrófono.';
          _isInitializing = false;
        });
        return;
      }

      if (!_socket.isConnected) await _socket.connect();
      _socket.joinChannel(widget.channel.id);

      await _loadMessages();
      await _initWebRTC();
      _setupSocketListeners();

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = 'Error al conectar: $e';
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _loadMessages() async {
    final msgs = await _db.getMessagesByChannel(widget.channel.id);
    if (mounted) setState(() => _messages = msgs);
  }

  Future<void> _initWebRTC() async {
    final config = {
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'iceTransportPolicy': 'all',
    };

    _peerConnection = await createPeerConnection(config);

    // Obtener micrófono (silenciado hasta que se presione PTT)
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'sampleRate': 16000,
      },
      'video': false,
    });

    // Silenciar hasta PTT
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = false;
    }

    // Agregar tracks al peer connection
    for (final track in _localStream!.getAudioTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    // Audio remoto → reproducir automáticamente
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      debugPrint('🔊 Track remoto recibido: ${event.track.kind}');
      if (event.track.kind == 'audio') {
        event.track.enabled = true;
      }
    };

    // Candidatos ICE → enviar al otro
    _peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate != null && candidate.candidate != null) {
        _socket.sendIceCandidate(widget.channel.id, candidate.toMap());
      }
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('🧊 ICE: $state');
      if (mounted) {
        setState(() {
          _webrtcConnected =
              state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
              state == RTCIceConnectionState.RTCIceConnectionStateCompleted;
        });
      }
    };

    _peerConnection!.onSignalingState = (RTCSignalingState state) {
      debugPrint('📡 Signaling: $state');
      if (state == RTCSignalingState.RTCSignalingStateStable) {
        _isNegotiating = false;
      }
    };
  }

  void _setupSocketListeners() {
    // Recibir offer → responder con answer
    _socket.onReceiveOffer((data) async {
      if (data['userId'] == _myUserId) return;
      debugPrint('📥 Offer de: ${data['alias']}');

      if (_isNegotiating) {
        debugPrint('⚠️ Ya negociando, ignorando offer');
        return;
      }
      _isNegotiating = true;

      try {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['offer']['sdp'], data['offer']['type']),
        );
        final answer = await _peerConnection!.createAnswer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': false,
        });
        await _peerConnection!.setLocalDescription(answer);
        _socket.sendAnswer(widget.channel.id, answer.toMap());
        debugPrint('📤 Answer enviado');
      } catch (e) {
        debugPrint('Error procesando offer: $e');
        _isNegotiating = false;
      }
    });

    // Recibir answer
    _socket.onReceiveAnswer((data) async {
      if (data['userId'] == _myUserId) return;
      debugPrint('📥 Answer recibido');
      try {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['answer']['sdp'], data['answer']['type']),
        );
        _isNegotiating = false;
      } catch (e) {
        debugPrint('Error procesando answer: $e');
      }
    });

    // Recibir ICE candidates
    _socket.onReceiveIceCandidate((data) async {
      if (data['userId'] == _myUserId) return;
      try {
        if (data['candidate'] != null) {
          await _peerConnection!.addCandidate(RTCIceCandidate(
            data['candidate']['candidate'],
            data['candidate']['sdpMid'],
            data['candidate']['sdpMLineIndex'],
          ));
        }
      } catch (e) {
        debugPrint('Error ICE candidate: $e');
      }
    });

    // PTT status del otro usuario
    _socket.onPttStatus((data) {
      if (mounted) {
        setState(() {
          _whoIsTalking = (data['isTalking'] == true) ? data['alias'] : null;
        });
      }
    });

    // Audio recibido por socket (fallback + historial)
    _socket.onReceiveAudio((data) async {
      await _saveAndPlayReceivedAudio(data);
    });

    _socket.onChannelEvent((data) {
      if (mounted && data['type'] == 'JOINED') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${data['message']}'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1A1A1A),
        ));
        // Nuevo usuario entró → renegociar WebRTC
        if (!_isNegotiating) _sendOffer();
      }
    });
  }

  Future<void> _sendOffer() async {
    if (_isNegotiating || _peerConnection == null) return;
    _isNegotiating = true;
    try {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _peerConnection!.setLocalDescription(offer);
      _socket.sendOffer(widget.channel.id, offer.toMap());
      debugPrint('📤 Offer enviado');
    } catch (e) {
      debugPrint('Error enviando offer: $e');
      _isNegotiating = false;
    }
  }

  Future<void> _startTalking() async {
    if (_isTalking || _peerConnection == null) return;
    setState(() => _isTalking = true);

    // Activar micrófono
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = true;
    }

    _socket.sendPttStart(widget.channel.id);

    // Iniciar negociación WebRTC si no hay conexión
    if (!_webrtcConnected && !_isNegotiating) {
      await _sendOffer();
    }

    // Grabar para historial y fallback por socket
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/ptt_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (e) {
      debugPrint('Error iniciando grabación: $e');
    }
  }

  Future<void> _stopTalking() async {
    if (!_isTalking) return;
    setState(() => _isTalking = false);

    // Silenciar micrófono
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = false;
    }

    _socket.sendPttEnd(widget.channel.id);

    // Detener grabación y enviar por socket como backup
    try {
      final path = await _recorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final base64Audio = base64Encode(bytes);
          _socket.sendAudio(widget.channel.id, base64Audio);

          // Guardar en historial
          final message = MessageModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            channelId: widget.channel.id,
            userId: _myUserId,
            alias: _myAlias,
            audioPath: path,
            createdAt: DateTime.now(),
          );
          await _db.saveMessage(message);
          if (mounted) setState(() => _messages.add(message));
        }
      }
    } catch (e) {
      debugPrint('Error deteniendo grabación: $e');
    }
  }

  Future<void> _saveAndPlayReceivedAudio(Map<String, dynamic> data) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'recv_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final filePath = '${dir.path}/$fileName';

      if (data['audioData'] != null) {
        final audioBytes = base64Decode(data['audioData']);
        await File(filePath).writeAsBytes(audioBytes);
        // Solo reproducir por socket si WebRTC no está conectado
        if (!_webrtcConnected) {
          await _player.play(DeviceFileSource(filePath));
        }
      }

      final message = MessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        channelId: widget.channel.id,
        userId: data['userId'] ?? '',
        alias: data['alias'] ?? 'Desconocido',
        audioPath: filePath,
        createdAt: DateTime.now(),
      );
      await _db.saveMessage(message);
      if (mounted) setState(() => _messages.add(message));
    } catch (e) {
      debugPrint('Error guardando audio: $e');
    }
  }

  @override
  void dispose() {
    _socket.leaveChannel(widget.channel.id);
    _socket.removeChannelListeners();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _peerConnection?.close();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.channel.name,
                style: const TextStyle(color: Colors.white, fontSize: 18)),
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _webrtcConnected
                        ? const Color(0xFF00E676)
                        : _isConnected
                            ? Colors.orange
                            : Colors.red,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _isInitializing
                      ? 'Conectando...'
                      : _webrtcConnected
                          ? 'WebRTC activo'
                          : _isConnected
                              ? 'Socket conectado'
                              : 'Sin conexión',
                  style: TextStyle(
                    color: _webrtcConnected
                        ? const Color(0xFF00E676)
                        : _isConnected ? Colors.orange : Colors.red,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF00E676)),
            SizedBox(height: 16),
            Text('Inicializando canal...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Text(_initError!,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() { _initError = null; _isInitializing = true; });
                  _init();
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
                child: const Text('Reintentar', style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Banner quién habla
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _whoIsTalking != null ? 44 : 0,
          color: const Color(0xFF00E676).withOpacity(0.12),
          child: _whoIsTalking != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.graphic_eq, color: Color(0xFF00E676), size: 18),
                    const SizedBox(width: 8),
                    Text('$_whoIsTalking está hablando...',
                        style: const TextStyle(color: Color(0xFF00E676), fontSize: 14)),
                  ],
                )
              : null,
        ),

        // Historial
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic_none, size: 72, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Mantén el botón para hablar',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                      SizedBox(height: 4),
                      Text('El historial aparecerá aquí',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _messageTile(_messages[i]),
                ),
        ),

        // Botón PTT
        Container(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 44),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, -2))],
          ),
          child: Column(
            children: [
              GestureDetector(
                onTapDown: (_) => _startTalking(),
                onTapUp: (_) => _stopTalking(),
                onTapCancel: () => _stopTalking(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _isTalking ? 130 : 110,
                  height: _isTalking ? 130 : 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isTalking ? const Color(0xFF00E676) : const Color(0xFF1C1C1C),
                    border: Border.all(
                      color: _isTalking ? const Color(0xFF00E676) : const Color(0xFF333333),
                      width: 2,
                    ),
                    boxShadow: _isTalking ? [BoxShadow(
                      color: const Color(0xFF00E676).withOpacity(0.45),
                      blurRadius: 35, spreadRadius: 10,
                    )] : [],
                  ),
                  child: Icon(
                    _isTalking ? Icons.mic : Icons.mic_none,
                    size: 52,
                    color: _isTalking ? Colors.black : Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _isTalking ? '🔴 Transmitiendo...' : 'Mantén para hablar',
                  key: ValueKey(_isTalking),
                  style: TextStyle(
                    color: _isTalking ? const Color(0xFF00E676) : Colors.grey,
                    fontSize: 14,
                    fontWeight: _isTalking ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _messageTile(MessageModel msg) {
    final isMe = msg.userId == _myUserId;
    final time = '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF00E676).withOpacity(0.12) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe ? const Color(0xFF00E676).withOpacity(0.25) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq, size: 20,
                color: isMe ? const Color(0xFF00E676) : Colors.grey),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isMe ? 'Tú' : msg.alias,
                      style: TextStyle(
                        color: isMe ? const Color(0xFF00E676) : Colors.grey,
                        fontSize: 11, fontWeight: FontWeight.bold,
                      )),
                  const Text('Mensaje de voz',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(time, style: const TextStyle(color: Colors.grey, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
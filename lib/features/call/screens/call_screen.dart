import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../core/models/channel_model.dart';
import '../../../core/models/message_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/webrtc_service.dart';

class CallScreen extends StatefulWidget {
  final ChannelModel channel;
  const CallScreen({super.key, required this.channel});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final SocketService _socket = SocketService();
  final DatabaseService _db = DatabaseService();
  final WebRTCService _webRTCService = WebRTCService();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _beepPlayer = AudioPlayer();

  bool _isTalking = false;
  bool _isConnected = false;
  bool _isInitializing = true;
  String? _whoIsTalking;
  String? _initError;
  List<MessageModel> _messages = [];
  String? _beepPath;
  final Map<String, bool> _playingMessages = {};

  late String _myUserId;
  late String _myAlias;

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
      // Pedimos múltiples permisos al mismo tiempo: Micrófono y Notificaciones
      Map<Permission, PermissionStatus> statuses = await [
        Permission.microphone,
        Permission.notification,
      ].request();

      // Verificamos si nos dio el permiso del micrófono (es el único estrictamente necesario para hablar)
      if (statuses[Permission.microphone] != PermissionStatus.granted) {
        setState(() {
          _initError = 'Se necesita permiso de micrófono.';
          _isInitializing = false;
        });
        return;
      }

      // Configurar audio y ejecución en segundo plano
      await _setupBackgroundExecution();

      if (!_socket.isConnected) await _socket.connect();
      _socket.joinChannel(widget.channel.id);
      _webRTCService.init(widget.channel.id); 
      
      await _loadMessages();
      await _generateBeep();
      _setupListeners();

      if (mounted) setState(() { _isConnected = true; _isInitializing = false; });
    } catch (e) {
      if (mounted) setState(() { _initError = '$e'; _isInitializing = false; });
    }
  }

  Future<void> _setupBackgroundExecution() async {
    try {
      // 1. Configurar la sesión de audio para que no se interrumpa
      final session = await AudioSession.instance;
      // USAR speech() SIN const
      await session.configure(AudioSessionConfiguration.speech());

      // 2. Configurar el servicio en segundo plano (Solo Android)
      if (Platform.isAndroid) {
        final androidConfig = FlutterBackgroundAndroidConfig(
          notificationTitle: "Walkie SOS Activo",
          notificationText: "Escuchando el canal de emergencia...",
          notificationImportance: AndroidNotificationImportance.normal, // Cambiado a normal
          notificationIcon: const AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        );
        
        bool hasPermissions = await FlutterBackground.initialize(androidConfig: androidConfig);
        if (hasPermissions) {
          await FlutterBackground.enableBackgroundExecution();
          debugPrint('✅ Ejecución en segundo plano activada');
        }
      }
    } catch (e) {
      debugPrint('❌ Error al configurar segundo plano: $e');
    }
  }

  Future<void> _generateBeep() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _beepPath = '${dir.path}/beep.wav';
      if (await File(_beepPath!).exists()) return;

      const sampleRate = 44100;
      const frequency = 880.0;
      const durationMs = 150;
      final numSamples = (sampleRate * durationMs / 1000).round();

      final samples = Int16List(numSamples);
      for (int i = 0; i < numSamples; i++) {
        final t = i / sampleRate;
        double envelope = 1.0;
        if (i < 100) envelope = i / 100.0;
        if (i > numSamples - 100) envelope = (numSamples - i) / 100.0;
        samples[i] = (sin(2 * pi * frequency * t) * 32767 * envelope)
            .round()
            .clamp(-32768, 32767);
      }

      final byteData = ByteData(44 + numSamples * 2);
      byteData.setUint8(0, 0x52); byteData.setUint8(1, 0x49);
      byteData.setUint8(2, 0x46); byteData.setUint8(3, 0x46);
      byteData.setUint32(4, 36 + numSamples * 2, Endian.little);
      byteData.setUint8(8, 0x57); byteData.setUint8(9, 0x41);
      byteData.setUint8(10, 0x56); byteData.setUint8(11, 0x45);
      byteData.setUint8(12, 0x66); byteData.setUint8(13, 0x6D);
      byteData.setUint8(14, 0x74); byteData.setUint8(15, 0x20);
      byteData.setUint32(16, 16, Endian.little);
      byteData.setUint16(20, 1, Endian.little);
      byteData.setUint16(22, 1, Endian.little);
      byteData.setUint32(24, sampleRate, Endian.little);
      byteData.setUint32(28, sampleRate * 2, Endian.little);
      byteData.setUint16(32, 2, Endian.little);
      byteData.setUint16(34, 16, Endian.little);
      byteData.setUint8(36, 0x64); byteData.setUint8(37, 0x61);
      byteData.setUint8(38, 0x74); byteData.setUint8(39, 0x61);
      byteData.setUint32(40, numSamples * 2, Endian.little);
      for (int i = 0; i < numSamples; i++) {
        byteData.setInt16(44 + i * 2, samples[i], Endian.little);
      }

      await File(_beepPath!).writeAsBytes(byteData.buffer.asUint8List());
      debugPrint('✅ Beep generado');
    } catch (e) {
      debugPrint('Error generando beep: $e');
    }
  }

  Future<void> _playBeep() async {
    try {
      if (_beepPath == null) return;
      await _beepPlayer.play(DeviceFileSource(_beepPath!));
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      debugPrint('Error beep: $e');
    }
  }

  Future<void> _loadMessages() async {
    final msgs = await _db.getMessagesByChannel(widget.channel.id);
    if (mounted) setState(() => _messages = msgs);
  }

  void _setupListeners() {
    _socket.onPttStatus((data) {
      if (mounted) setState(() {
        _whoIsTalking = (data['isTalking'] == true) ? data['alias'] : null;
      });
    });

    _socket.onReceiveAudio((data) async {
      debugPrint('📥 Archivo de historial recibido por socket');
      final map = data is List ? data[0] : data;
      await _saveAudioHistory(map); 
    });
  }

  Future<void> _startTalking() async {
    // Evita grabar si ya está hablando alguien más (Half-Duplex)
    if (_isTalking || _whoIsTalking != null) return; 

    setState(() => _isTalking = true);
    
    // 1. Iniciar transmisión en TIEMPO REAL
    await _webRTCService.startTalking();
    
    // 2. Avisar por socket y hacer beep
    _socket.sendPttStart(widget.channel.id);
    await _playBeep();

    // 3. Iniciar grabación local para el historial (.m4a)
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/ptt_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      debugPrint('🎙️ Grabando respaldo...');
    } catch (e) {
      debugPrint('Error grabando: $e');
      setState(() => _isTalking = false);
    }
  }

  Future<void> _stopTalking() async {
    if (!_isTalking) return;
    setState(() => _isTalking = false);
    
    // 1. Detener TIEMPO REAL
    await _webRTCService.stopTalking();
    
    // 2. Avisar por socket
    _socket.sendPttEnd(widget.channel.id);

    // 3. Detener grabación y enviarla para el historial
    try {
      final path = await _recorder.stop();
      if (path == null) return;

      final file = File(path);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      final base64Audio = base64Encode(bytes);
      debugPrint('📤 Enviando archivo de historial: ${bytes.length} bytes');
      _socket.sendAudio(widget.channel.id, base64Audio);

      final msg = MessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        channelId: widget.channel.id,
        userId: _myUserId,
        alias: _myAlias,
        audioPath: path,
        createdAt: DateTime.now(),
      );
      await _db.saveMessage(msg);
      if (mounted) setState(() => _messages.add(msg));
    } catch (e) {
      debugPrint('Error enviando respaldo: $e');
    }
  }

  Future<void> _saveAudioHistory(dynamic data) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/recv_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final bytes = base64Decode(data['audioData']);
      await File(path).writeAsBytes(bytes);
      
      debugPrint('💾 Historial guardado de ${data['alias']}');

      final msg = MessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        channelId: widget.channel.id,
        userId: data['userId'] ?? '',
        alias: data['alias'] ?? 'Desconocido',
        audioPath: path,
        createdAt: DateTime.now(),
      );
      await _db.saveMessage(msg);
      if (mounted) setState(() => _messages.add(msg));
    } catch (e) {
      debugPrint('Error guardando historial: $e');
    }
  }

  Future<void> _togglePlayMessage(MessageModel msg) async {
    final isPlaying = _playingMessages[msg.id] == true;

    if (isPlaying) {
      await _player.stop();
      if (mounted) setState(() => _playingMessages[msg.id] = false);
      return;
    }

    await _player.stop();
    if (mounted) setState(() {
      for (final key in _playingMessages.keys) {
        _playingMessages[key] = false;
      }
      _playingMessages[msg.id] = true;
    });

    try {
      final file = File(msg.audioPath);
      if (!await file.exists()) {
        debugPrint('❌ Archivo no existe: ${msg.audioPath}');
        if (mounted) setState(() => _playingMessages[msg.id] = false);
        return;
      }

      await _player.play(DeviceFileSource(msg.audioPath));
      debugPrint('▶️ Reproduciendo historial: ${msg.audioPath}');

      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playingMessages[msg.id] = false);
      });
    } catch (e) {
      debugPrint('Error reproduciendo mensaje: $e');
      if (mounted) setState(() => _playingMessages[msg.id] = false);
    }
  }

  @override
  void dispose() {
    _webRTCService.stopTalking(); 
    _socket.leaveChannel(widget.channel.id);
    _socket.removeChannelListeners();
    _recorder.dispose();
    _player.dispose();
    _beepPlayer.dispose();
    
    // Detener el servicio en segundo plano al salir de la pantalla
    if (Platform.isAndroid) {
      FlutterBackground.disableBackgroundExecution();
    }
    
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
            Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isConnected ? const Color(0xFF00E676) : Colors.red,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _isInitializing
                    ? 'Conectando...'
                    : _isConnected ? 'En línea' : 'Sin conexión',
                style: TextStyle(
                  color: _isConnected ? const Color(0xFF00E676) : Colors.red,
                  fontSize: 11,
                ),
              ),
            ]),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF00E676)),
          SizedBox(height: 16),
          Text('Conectando...', style: TextStyle(color: Colors.grey)),
        ],
      ));
    }

    if (_initError != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 64),
          const SizedBox(height: 16),
          Text(_initError!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() { _initError = null; _isInitializing = true; });
              _init();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676)),
            child: const Text('Reintentar',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ));
    }

    return Column(children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: _whoIsTalking != null ? 44 : 0,
        color: const Color(0xFF00E676).withOpacity(0.12),
        child: _whoIsTalking != null
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.graphic_eq,
                    color: Color(0xFF00E676), size: 18),
                const SizedBox(width: 8),
                Text('$_whoIsTalking está hablando...',
                    style: const TextStyle(
                        color: Color(0xFF00E676), fontSize: 14)),
              ])
            : null,
      ),
      Expanded(
        child: _messages.isEmpty
            ? const Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mic_none, size: 72, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Mantén el botón para hablar',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (_, i) => _messageTile(_messages[i]),
              ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 44),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, -2),
          )],
        ),
        child: Column(children: [
          GestureDetector(
            onTapDown: _whoIsTalking != null ? null : (_) => _startTalking(),
            onTapUp: (_) => _stopTalking(),
            onTapCancel: () => _stopTalking(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _isTalking ? 130 : 110,
              height: _isTalking ? 130 : 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isTalking
                    ? const Color(0xFF00E676)
                    : (_whoIsTalking != null) 
                        ? const Color(0xFF111111)
                        : const Color(0xFF1C1C1C),
                border: Border.all(
                  color: _isTalking
                      ? const Color(0xFF00E676)
                      : (_whoIsTalking != null)
                          ? Colors.red.withOpacity(0.3)
                          : const Color(0xFF333333),
                  width: 2,
                ),
                boxShadow: _isTalking ? [BoxShadow(
                  color: const Color(0xFF00E676).withOpacity(0.45),
                  blurRadius: 35,
                  spreadRadius: 10,
                )] : [],
              ),
              child: Icon(
                _whoIsTalking != null 
                    ? Icons.lock 
                    : (_isTalking ? Icons.mic : Icons.mic_none),
                size: 52,
                color: _isTalking 
                    ? Colors.black 
                    : (_whoIsTalking != null ? Colors.red.withOpacity(0.5) : Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _isTalking 
                ? '🔴 Transmitiendo...' 
                : (_whoIsTalking != null)
                    ? 'Canal ocupado'
                    : 'Mantén para hablar',
            style: TextStyle(
              color: _isTalking 
                  ? const Color(0xFF00E676) 
                  : (_whoIsTalking != null ? Colors.red.withOpacity(0.8) : Colors.grey),
              fontSize: 14,
              fontWeight: _isTalking ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _messageTile(MessageModel msg) {
    final isMe = msg.userId == _myUserId;
    final time =
        '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}';
    final isPlaying = _playingMessages[msg.id] == true;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMe
              ? const Color(0xFF00E676).withOpacity(0.12)
              : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe
                ? const Color(0xFF00E676).withOpacity(0.25)
                : Colors.transparent,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () => _togglePlayMessage(msg),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isMe
                    ? const Color(0xFF00E676).withOpacity(0.2)
                    : const Color(0xFF333333),
              ),
              child: Icon(
                isPlaying ? Icons.stop : Icons.play_arrow,
                size: 20,
                color: isMe ? const Color(0xFF00E676) : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMe ? 'Tú' : msg.alias,
                style: TextStyle(
                  color: isMe ? const Color(0xFF00E676) : Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(children: [
                ...List.generate(12, (i) => AnimatedContainer(
                  duration: Duration(milliseconds: 200 + i * 30),
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  width: 2,
                  height: isPlaying ? (4.0 + (i % 4) * 5) : 4,
                  decoration: BoxDecoration(
                    color: isMe
                        ? const Color(0xFF00E676)
                            .withOpacity(isPlaying ? 1 : 0.5)
                        : Colors.grey.withOpacity(isPlaying ? 1 : 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
                const SizedBox(width: 6),
                Text(
                  'Mensaje de voz',
                  style: TextStyle(
                    color: isPlaying
                        ? (isMe ? const Color(0xFF00E676) : Colors.white)
                        : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ]),
            ],
          )),
          const SizedBox(width: 8),
          Text(time,
              style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ]),
      ),
    );
  }
}
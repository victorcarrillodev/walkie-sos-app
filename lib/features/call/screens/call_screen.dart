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
  
  final ScrollController _scrollController = ScrollController();

  bool _isTalking = false;
  bool _isConnected = false;
  bool _isInitializing = true;
  String? _whoIsTalking;
  String? _initError;
  List<MessageModel> _messages = [];
  String? _beepPath;
  
  final Map<String, bool> _playingMessages = {};
  
  final ValueNotifier<Duration> _currentPosition = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _totalDuration = ValueNotifier(Duration.zero);

  late String _myUserId;
  late String _myAlias;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user!;
    _myUserId = user.id;
    _myAlias = user.alias;
    
    _player.onPositionChanged.listen((pos) {
      if (mounted) _currentPosition.value = pos;
    });
    _player.onDurationChanged.listen((dur) {
      if (mounted) _totalDuration.value = dur;
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _playingMessages.clear());
        _currentPosition.value = Duration.zero;
      }
    });

    _init();
  }

  Future<void> _init() async {
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.microphone,
        Permission.notification,
      ].request();

      if (statuses[Permission.microphone] != PermissionStatus.granted) {
        setState(() {
          _initError = 'Se necesita permiso de micrófono.';
          _isInitializing = false;
        });
        return;
      }

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
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.speech());

      if (Platform.isAndroid) {
        final androidConfig = FlutterBackgroundAndroidConfig(
          notificationTitle: "Walkie SOS Activo",
          notificationText: "Escuchando el canal de emergencia...",
          notificationImportance: AndroidNotificationImportance.normal,
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

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadMessages() async {
    final msgs = await _db.getMessagesByChannel(widget.channel.id);
    if (mounted) {
      setState(() => _messages = msgs);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _setupListeners() {
    _socket.onPttStatus((data) {
      if (mounted) setState(() {
        _whoIsTalking = (data['isTalking'] == true) ? data['alias'] : null;
      });
    });

    _socket.onReceiveAudio((data) async {
      final map = data is List ? data[0] : data;
      await _saveAudioHistory(map); 
    });
  }

  Future<void> _startTalking() async {
    if (_isTalking || _whoIsTalking != null) return; 

    setState(() => _isTalking = true);
    
    await _webRTCService.startTalking();
    _socket.sendPttStart(widget.channel.id);
    await _playBeep();

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
    } catch (e) {
      setState(() => _isTalking = false);
    }
  }

  Future<void> _stopTalking() async {
    if (!_isTalking) return;
    setState(() => _isTalking = false);
    
    await _webRTCService.stopTalking();
    _socket.sendPttEnd(widget.channel.id);

    try {
      final path = await _recorder.stop();
      if (path == null) return;

      final file = File(path);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      final base64Audio = base64Encode(bytes);
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
      if (mounted) {
        setState(() => _messages.add(msg));
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
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
      
      final msg = MessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        channelId: widget.channel.id,
        userId: data['userId'] ?? '',
        alias: data['alias'] ?? 'Desconocido',
        audioPath: path,
        createdAt: DateTime.now(),
      );
      await _db.saveMessage(msg);
      if (mounted) {
        setState(() => _messages.add(msg));
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      debugPrint('Error guardando historial: $e');
    }
  }

  Future<void> _togglePlayMessage(MessageModel msg) async {
    final isPlaying = _playingMessages[msg.id] == true;

    if (isPlaying) {
      await _player.stop();
      if (mounted) {
        setState(() => _playingMessages[msg.id] = false);
        _currentPosition.value = Duration.zero;
      }
      return;
    }

    await _player.stop();
    if (mounted) {
      setState(() {
        _playingMessages.clear();
        _playingMessages[msg.id] = true;
      });
      _currentPosition.value = Duration.zero;
      _totalDuration.value = Duration.zero;
    }

    try {
      final file = File(msg.audioPath);
      if (!await file.exists()) {
        if (mounted) setState(() => _playingMessages[msg.id] = false);
        return;
      }

      await _player.play(DeviceFileSource(msg.audioPath));
    } catch (e) {
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
    _scrollController.dispose();
    _currentPosition.dispose();
    _totalDuration.dispose();
    
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
            Text(widget.channel.name, style: const TextStyle(color: Colors.white, fontSize: 18)),
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
                _isInitializing ? 'Conectando...' : _isConnected ? 'En línea' : 'Sin conexión',
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
          Text(_initError!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
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
      ));
    }

    return Column(children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: _whoIsTalking != null ? 44 : 0,
        color: const Color(0xFF00E676).withOpacity(0.12),
        child: _whoIsTalking != null
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.graphic_eq, color: Color(0xFF00E676), size: 18),
                const SizedBox(width: 8),
                Text('$_whoIsTalking está hablando...', style: const TextStyle(color: Color(0xFF00E676), fontSize: 14)),
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
                  Text('Mantén el botón para hablar', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ))
            : ListView.builder(
                controller: _scrollController, 
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (_, i) {
                  final msg = _messages[i];
                  return MessageBubble(
                    msg: msg,
                    isMe: msg.userId == _myUserId,
                    isPlaying: _playingMessages[msg.id] == true,
                    onPlayToggle: () => _togglePlayMessage(msg),
                    currentPositionNotifier: _currentPosition,
                    totalDurationNotifier: _totalDuration,
                  );
                },
              ),
      ),
      
      // BOTÓN PTT
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, -2))],
        ),
        child: GestureDetector(
          onTapDown: _whoIsTalking != null ? null : (_) => _startTalking(),
          onTapUp: (_) => _stopTalking(),
          onTapCancel: () => _stopTalking(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity, 
            height: 72, 
            decoration: BoxDecoration(
              color: _isTalking
                  ? const Color(0xFF00E676)
                  : (_whoIsTalking != null) 
                      ? const Color(0xFF111111)
                      : const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(20),
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
                blurRadius: 20,
                spreadRadius: 2,
              )] : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _whoIsTalking != null 
                      ? Icons.lock 
                      : (_isTalking ? Icons.mic : Icons.mic_none),
                  size: 32,
                  color: _isTalking 
                      ? Colors.black 
                      : (_whoIsTalking != null ? Colors.red.withOpacity(0.5) : Colors.white),
                ),
                const SizedBox(width: 12),
                Text(
                  _isTalking 
                      ? '🔴 Transmitiendo...' 
                      : (_whoIsTalking != null)
                          ? 'Canal ocupado'
                          : 'Mantén para hablar',
                  style: TextStyle(
                    color: _isTalking 
                        ? Colors.black 
                        : (_whoIsTalking != null ? Colors.red.withOpacity(0.8) : Colors.white),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

// =========================================================================
// NUEVO WIDGET INDEPENDIENTE: Burbuja de Mensaje (Evita crasheos y lagueos)
// =========================================================================
class MessageBubble extends StatefulWidget {
  final MessageModel msg;
  final bool isMe;
  final bool isPlaying;
  final VoidCallback onPlayToggle;
  final ValueNotifier<Duration> currentPositionNotifier;
  final ValueNotifier<Duration> totalDurationNotifier;

  const MessageBubble({
    super.key,
    required this.msg,
    required this.isMe,
    required this.isPlaying,
    required this.onPlayToggle,
    required this.currentPositionNotifier,
    required this.totalDurationNotifier,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _fetchDuration();
  }

  // Analiza la duración del archivo en segundo plano sin saturar la UI
  Future<void> _fetchDuration() async {
    try {
      final file = File(widget.msg.audioPath);
      if (await file.exists()) {
        final tempPlayer = AudioPlayer();
        await tempPlayer.setSourceDeviceFile(widget.msg.audioPath);
        final dur = await tempPlayer.getDuration();
        if (mounted && dur != null) {
          setState(() => _duration = dur);
        }
        await tempPlayer.dispose();
      }
    } catch (e) {
      debugPrint('Error leyendo duracion: $e');
    }
  }

  // Convierte los milisegundos en formato 0:00
  String _formatDuration(Duration? d) {
    if (d == null) return '--:--';
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final time = '${widget.msg.createdAt.hour.toString().padLeft(2, '0')}:${widget.msg.createdAt.minute.toString().padLeft(2, '0')}';
    final screenWidth = MediaQuery.of(context).size.width;

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        width: screenWidth * 0.75, // Ocupa el 75% de la pantalla
        decoration: BoxDecoration(
          color: widget.isMe ? const Color(0xFF00E676).withOpacity(0.12) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
            bottomRight: Radius.circular(widget.isMe ? 4 : 16),
          ),
          border: Border.all(
            color: widget.isMe ? const Color(0xFF00E676).withOpacity(0.25) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: widget.onPlayToggle,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isMe ? const Color(0xFF00E676).withOpacity(0.2) : const Color(0xFF333333),
                ),
                child: Icon(
                  widget.isPlaying ? Icons.stop : Icons.play_arrow,
                  size: 20,
                  color: widget.isMe ? const Color(0xFF00E676) : Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.isMe ? 'Tú' : widget.msg.alias,
                    style: TextStyle(
                      color: widget.isMe ? const Color(0xFF00E676) : Colors.grey,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  
                  // CONTENEDOR DE LA ONDA AUTO-AJUSTABLE
                  SizedBox(
                    height: 28,
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final int numBars = (constraints.maxWidth / 5).floor() - 1;
                        if (numBars <= 0) return const SizedBox();

                        return ValueListenableBuilder<Duration>(
                          valueListenable: widget.currentPositionNotifier,
                          builder: (context, currentPos, _) {
                            final Random random = Random(widget.msg.id.hashCode);
                            final totalDur = widget.totalDurationNotifier.value;
                            
                            double percent = (widget.isPlaying && totalDur.inMilliseconds > 0)
                                ? currentPos.inMilliseconds / totalDur.inMilliseconds 
                                : 0.0;

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: List.generate(numBars, (i) {
                                double t = numBars > 1 ? i / (numBars - 1) : 0.5;
                                double envelope = sin(t * pi); 
                                double randVal = 0.3 + random.nextDouble() * 0.7;
                                double height = 4.0 + (24.0 * randVal * envelope);
                                
                                bool isPlayed = widget.isPlaying && ((i / numBars) <= percent);
                                
                                Color baseColor = widget.isMe ? const Color(0xFF00E676) : Colors.white;
                                Color unplayedColor = widget.isMe ? const Color(0xFF00E676).withOpacity(0.4) : Colors.grey.withOpacity(0.4);

                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                  width: 2,
                                  height: widget.isPlaying && isPlayed ? height : height * 0.85,
                                  decoration: BoxDecoration(
                                    color: isPlayed ? baseColor : unplayedColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                );
                              }),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),

                  // CONTADOR DE TIEMPO Y DURACIÓN TOTAL
                  ValueListenableBuilder<Duration>(
                    valueListenable: widget.currentPositionNotifier,
                    builder: (context, currentPos, _) {
                      final totalDur = widget.totalDurationNotifier.value;
                      return Text(
                        widget.isPlaying
                            ? '${_formatDuration(currentPos)} / ${_formatDuration(totalDur.inMilliseconds > 0 ? totalDur : _duration)}'
                            : _formatDuration(_duration),
                        style: TextStyle(
                          color: widget.isMe ? const Color(0xFF00E676).withOpacity(0.8) : Colors.grey, 
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
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
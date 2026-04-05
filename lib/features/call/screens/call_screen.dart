import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart' hide AVAudioSessionCategory;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../core/models/channel_model.dart';
import '../../../core/models/message_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/presence_provider.dart';
import '../../../core/providers/channel_provider.dart';
import '../../../core/providers/voice_provider.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/bubble_service.dart';
import '../../../core/services/webrtc_service.dart';
import '../../../core/services/emergency_service.dart';
import '../../groups/screens/group_settings_screen.dart';

class CallScreen extends StatefulWidget {
  final ChannelModel channel;
  /// El userId del otro usuario en un chat directo (1-a-1).
  /// Si se provee, habilita el indicador de presencia sin parsear el nombre del canal.
  final String? targetUserId;
  final String? displayTitle;
  
  const CallScreen({
    super.key, 
    required this.channel, 
    this.targetUserId,
    this.displayTitle,
  });

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
  Timer? _maxDurationTimer;
  String? _whoIsTalking;
  String? _initError;
  List<MessageModel> _messages = [];
  String? _beepPath;
  StreamSubscription? _newMessageSub;
  
  final Map<String, bool> _playingMessages = {};

  final ReceivePort _bubbleReceivePort = ReceivePort();
  
  final ValueNotifier<Duration> _currentPosition = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _totalDuration = ValueNotifier(Duration.zero);

  late String _myUserId;
  late String _myAlias;

  // Variables para canal directo (sin estado de online — lo lee PresenceProvider)
  bool _isDirectChannel = false;
  String? _targetUserId;
  bool _isAdmin = false;
  
  bool _isChatView = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user!;
    _myUserId = user.id;
    _myAlias = user.alias;
    
    IsolateNameServer.removePortNameMapping(bubblePortName);
    IsolateNameServer.registerPortWithName(_bubbleReceivePort.sendPort, bubblePortName);
    _bubbleReceivePort.listen((message) {
      if (message == 'start') {
        _startTalking();
      } else if (message == 'stop') {
        _stopTalking();
      } else if (message == 'stop_cancel') {
        _stopTalking(cancel: true);
      }
    });
    
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

    // Detectar canal directo:
    // 1. Si se pasa targetUserId directamente (desde ContactsScreen), usarlo.
    // 2. Si no, intentar parsear el nombre del canal como fallback.
    if (widget.targetUserId != null) {
      _isDirectChannel = true;
      _targetUserId = widget.targetUserId;
    } else if (widget.channel.name.startsWith('direct_')) {
      _isDirectChannel = true;
      final parts = widget.channel.name.split('_');
      if (parts.length >= 3) {
        _targetUserId = (parts[1] == _myUserId) ? parts[2] : parts[1];
      }
    }

    _newMessageSub = context.read<VoiceProvider>().newMessageStream.listen((msg) {
      if (msg.channelId == widget.channel.id && mounted) {
        setState(() => _messages.insert(0, msg));
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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

      if (!_socket.isConnected) await _socket.connect();
      _socket.joinChannel(widget.channel.id);
      // Ya no llamamos _webRTCService.init ni FlutterBackground aquí.
      
      await _loadMessages();
      await _generateBeep();
      _setupListeners();
      
      // Obtener rol si es un grupo
      if (widget.channel.isGroup) {
        final members = await context.read<ChannelProvider>().getChannelMembers(widget.channel.id);
        final me = members.firstWhere((m) => m['userId'] == _myUserId, orElse: () => null);
        if (me != null && (me['role'] == 'ADMIN' || me['role'] == 'MODERATOR')) {
          if (mounted) {
            setState(() {
              _isAdmin = true; // Permite abrir GroupSettingsScreen a ambos
            });
          }
        }
      }
      
      if (_isDirectChannel && _targetUserId != null) {
        context.read<PresenceProvider>().checkSinglePresence(_targetUserId!);
      }

      if (mounted) setState(() { _isConnected = true; _isInitializing = false; });
    } catch (e) {
      if (mounted) setState(() { _initError = '$e'; _isInitializing = false; });
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
    // Al usar reverse: true, el fondo de la pantalla corresponde a la posición 0.0
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadMessages() async {
    final msgs = await _db.getMessagesByChannel(widget.channel.id);
    if (mounted) {
      // Guardamos la lista en orden inverso (el más nuevo en index 0)
      setState(() => _messages = msgs.reversed.toList());
    }
  }

  void _setupListeners() {
    // onPttStatus y onReceiveAudio ahora los maneja VoiceProvider globalmente.
    // Solo manejaremos errores locales.

    _socket.onTalkError((data) async {
      if (!mounted) return;
      // Detenemos activamente WebRTC y la grabación pendiente (así se libera el loop y _isTalking pasa a false)
      await _stopTalking(cancel: true);
      
      final msg = data is Map ? data['message'] : data[0]['message'];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg ?? 'No puedes hablar en este momento.'),
        backgroundColor: Colors.red,
      ));
    });
  }

  Future<void> _startTalking() async {
    final vp = context.read<VoiceProvider>();
    if (_isTalking || vp.whoIsTalking != null) return; 

    setState(() => _isTalking = true);

    // Pausar escucha de emergencia temporalmente para liberar el micrófono
    await EmergencyService().stopListening();

    // Iniciar timer para cortar cuando se exceda el tiempo
    final maxSecs = widget.channel.maxMessageDuration;
    _maxDurationTimer = Timer(Duration(seconds: maxSecs), () {
      if (_isTalking && mounted) {
        _stopTalking(); 
      }
    });
    
    // Pausar reproducción para que el micrófono no capture el altavoz
    await _player.pause();
    
    // Notificamos a los demás inmediatamente
    _socket.sendPttStart(widget.channel.id);
    
    // Reproducimos el beep sin hacer await para ganar 200ms de velocidad
    _playBeep();
    
    // Iniciamos WebRTC para streaming en tiempo real
    await _webRTCService.startTalking(widget.channel.id);

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

  Future<void> _stopTalking({bool cancel = false}) async {
    if (!_isTalking) return;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    setState(() => _isTalking = false);
    
    await _webRTCService.stopTalking();
    _socket.sendPttEnd(widget.channel.id);

    try {
      final path = await _recorder.stop();
      if (path == null) return;

      final file = File(path);
      if (!await file.exists()) return;

      if (cancel) {
        await file.delete();
        return;
      }

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
        setState(() => _messages.insert(0, msg));
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      debugPrint('Error enviando respaldo: $e');
    } finally {
      // Reanudar escucha de emergencia
      await EmergencyService().startListening();
    }
  }

  // Historial lo guarda VoiceProvider en global. Nos podemos ahorrar este bloque,
  // pero ya fue eliminado con el refactor de onReceiveAudio.

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
    _newMessageSub?.cancel();
    BubbleService().hideBubble();
    IsolateNameServer.removePortNameMapping(bubblePortName);
    _bubbleReceivePort.close();
    _recorder.dispose();
    _player.dispose();
    _beepPlayer.dispose();
    _scrollController.dispose();
    _currentPosition.dispose();
    _totalDuration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isAdmin)
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => GroupSettingsScreen(channel: widget.channel)),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.settings, color: Theme.of(context).scaffoldBackgroundColor, size: 16),
                    ),
                    const SizedBox(height: 2),
                    Text('Ajustes', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          InkWell(
            onTap: () {
              setState(() => _isChatView = !_isChatView);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_isChatView ? Icons.mic : Icons.chat, color: Theme.of(context).scaffoldBackgroundColor, size: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(_isChatView ? 'Audio' : 'Chat', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () async {
              await BubbleService().init();
              await BubbleService().showBubble(chatName: widget.displayTitle ?? widget.channel.name);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.picture_in_picture_alt, color: Theme.of(context).scaffoldBackgroundColor, size: 16),
                  ),
                  const SizedBox(height: 2),
                  Text('Flotante', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.displayTitle ?? widget.channel.name,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // Para canales directos: muestra si EL OTRO usuario está conectado.
            // Para canales grupales: muestra el estado de nuestra propia conexión.
            if (_isDirectChannel && _targetUserId != null)
              Builder(builder: (ctx) {
                final targetOnline = ctx.watch<PresenceProvider>().isOnline(_targetUserId!);
                return Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: targetOnline ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isInitializing ? 'Verificando...' : (targetOnline ? 'En línea' : 'Desconectado'),
                    style: TextStyle(
                      color: targetOnline ? Colors.green : Colors.grey,
                      fontSize: 11,
                    ),
                  ),
                ]);
              })
            else
              Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? Theme.of(context).colorScheme.primary : Colors.red,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _isInitializing ? 'Conectando...' : (_isConnected ? 'Canal activo' : 'Sin conexión'),
                  style: TextStyle(
                    color: _isConnected ? Theme.of(context).colorScheme.primary : Colors.red,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isInitializing) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('Conectando...', style: TextStyle(color: Colors.grey)),
        ],
      ));
    }

    if (_initError != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 64),
          const SizedBox(height: 16),
          Text(_initError!, style: TextStyle(color: isDark ? Colors.white : Colors.black87), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() { _initError = null; _isInitializing = true; });
              _init();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
            child: const Text('Reintentar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ));
    }

    if (!_isChatView) {
      return _buildBigButtonView(isDark);
    }

    return Column(children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: (context.watch<VoiceProvider>().whoIsTalking != null && context.watch<VoiceProvider>().activeChannelId == widget.channel.id) ? 44 : 0,
        color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
        child: (context.watch<VoiceProvider>().whoIsTalking != null && context.watch<VoiceProvider>().activeChannelId == widget.channel.id)
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.graphic_eq, color: Theme.of(context).colorScheme.primary, size: 18),
                const SizedBox(width: 8),
                Text('${context.watch<VoiceProvider>().whoIsTalking} está hablando...', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 14)),
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
                reverse: true, // Invierte la lista para empezar desde el fondo nativamente
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
                    onOptionsTap: _isAdmin && msg.userId != _myUserId 
                        ? () => _showMessageOptions(msg) 
                        : null,
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
          color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, -2))],
        ),
        child: Consumer<VoiceProvider>(
          builder: (context, voiceProvider, _) {
            final isOccupied = voiceProvider.whoIsTalking != null;
            return GestureDetector(
              onTapDown: isOccupied ? null : (_) => _startTalking(),
              onTapUp: (_) => _stopTalking(),
              onTapCancel: () => _stopTalking(cancel: true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity, 
                height: 72, 
                decoration: BoxDecoration(
                  color: _isTalking
                      ? Theme.of(context).colorScheme.primary
                      : isOccupied
                          ? (isDark ? const Color(0xFF111111) : Colors.grey.shade300)
                          : (isDark ? const Color(0xFF1C1C1C) : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isTalking
                        ? Theme.of(context).colorScheme.primary
                        : isOccupied
                            ? Colors.red.withOpacity(0.3)
                            : (isDark ? const Color(0xFF333333) : Colors.grey.shade400),
                    width: 2,
                  ),
                  boxShadow: _isTalking ? [BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.45),
                    blurRadius: 20,
                    spreadRadius: 2,
                  )] : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isOccupied 
                          ? Icons.lock 
                          : (_isTalking ? Icons.mic : Icons.mic_none),
                      size: 32,
                      color: _isTalking 
                          ? Colors.black 
                          : (isOccupied ? Colors.red.withOpacity(0.5) : (isDark ? Colors.white : Colors.black87)),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isTalking 
                          ? '🔴 Transmitiendo...' 
                          : isOccupied
                              ? 'Canal ocupado'
                              : 'Mantén para hablar',
                      style: TextStyle(
                        color: _isTalking 
                            ? Colors.black 
                            : (isOccupied ? Colors.red.withOpacity(0.8) : (isDark ? Colors.white : Colors.black87)),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        ),
      ),
    ]);
  }

  void _showMessageOptions(MessageModel msg) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Administrar a @${msg.alias}', 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('Silenciar por 5 minutos'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, msg.userId, 5);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('Silenciar por 15 minutos'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, msg.userId, 15);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('Silenciar por 30 minutos'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, msg.userId, 30);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.volume_up, color: Colors.green),
              title: const Text('Quitar penalización'),
              onTap: () async {
                Navigator.pop(context);
                await context.read<ChannelProvider>().penalizeMember(widget.channel.id, msg.userId, null);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBigButtonView(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTapDown: _whoIsTalking != null ? null : (_) => _startTalking(),
            onTapUp: (_) => _stopTalking(),
            onTapCancel: () => _stopTalking(cancel: true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isTalking
                    ? Colors.greenAccent.withOpacity(0.2)
                    : (_whoIsTalking != null)
                        ? Colors.redAccent.withOpacity(0.2)
                        : Colors.blueAccent.withOpacity(0.2),
                boxShadow: [
                  BoxShadow(
                    color: _isTalking
                        ? Colors.greenAccent.withOpacity(0.6)
                        : (_whoIsTalking != null)
                            ? Colors.redAccent.withOpacity(0.6)
                            : Colors.blueAccent.withOpacity(0.6),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Image.asset(
                'assets/btn_walkie_mic.png',
                fit: BoxFit.contain,
                color: _whoIsTalking != null 
                    ? Colors.grey.withOpacity(0.5) 
                    : null,
                colorBlendMode: _whoIsTalking != null ? BlendMode.modulate : null,
              ),
            ),
          ),
          const SizedBox(height: 50),
          Text(
            _isTalking 
                ? '🔴 Transmitiendo...' 
                : (_whoIsTalking != null)
                    ? '$_whoIsTalking está hablando...'
                    : 'Mantén para hablar',
            style: TextStyle(
              color: _isTalking 
                  ? Theme.of(context).colorScheme.primary
                  : (_whoIsTalking != null ? Colors.red.withOpacity(0.8) : (isDark ? Colors.white70 : Colors.black54)),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
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
  final VoidCallback? onOptionsTap;
  final ValueNotifier<Duration> currentPositionNotifier;
  final ValueNotifier<Duration> totalDurationNotifier;

  const MessageBubble({
    super.key,
    required this.msg,
    required this.isMe,
    required this.isPlaying,
    required this.onPlayToggle,
    this.onOptionsTap,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        width: screenWidth * 0.75, // Ocupa el 75% de la pantalla
        decoration: BoxDecoration(
          color: widget.isMe ? Theme.of(context).colorScheme.primary.withOpacity(0.12) : (isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade200),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
            bottomRight: Radius.circular(widget.isMe ? 4 : 16),
          ),
          border: Border.all(
            color: widget.isMe ? Theme.of(context).colorScheme.primary.withOpacity(0.25) : Colors.transparent,
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
                  color: widget.isMe ? Theme.of(context).colorScheme.primary.withOpacity(0.2) : (isDark ? const Color(0xFF333333) : Colors.grey.shade300),
                ),
                child: Icon(
                  widget.isPlaying ? Icons.stop : Icons.play_arrow,
                  size: 20,
                  color: widget.isMe ? Theme.of(context).colorScheme.primary : (isDark ? Colors.white : Colors.black87),
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
                      color: widget.isMe ? Theme.of(context).colorScheme.primary : Colors.grey,
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
                                
                                Color baseColor = widget.isMe ? Theme.of(context).colorScheme.primary : (isDark ? Colors.white : Colors.black87);
                                Color unplayedColor = widget.isMe ? Theme.of(context).colorScheme.primary.withOpacity(0.4) : Colors.grey.withOpacity(0.4);

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
                          color: widget.isMe ? Theme.of(context).colorScheme.primary.withOpacity(0.8) : Colors.grey, 
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
            if (widget.onOptionsTap != null && !widget.isMe)
              GestureDetector(
                onTap: widget.onOptionsTap,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.more_vert, size: 16, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

const String bubblePortName = 'bubble_ptt_port';

class BubbleService {
  static final BubbleService _instance = BubbleService._internal();
  factory BubbleService() => _instance;
  BubbleService._internal();

  Future<void> init() async {
    final status = await FlutterOverlayWindow.isPermissionGranted();
    if (!status) {
      await FlutterOverlayWindow.requestPermission();
    }
  }

  Future<void> showBubble({String? chatName}) async {
    final status = await FlutterOverlayWindow.isPermissionGranted();
    if (!status) {
      await FlutterOverlayWindow.requestPermission();
      return; 
    }
    
    final isActive = await FlutterOverlayWindow.isActive();
    if (isActive) return;

    await FlutterOverlayWindow.showOverlay(
      overlayTitle: "WalkieSOS",
      overlayContent: "Botón activo",
      flag: OverlayFlag.focusPointer,
      visibility: NotificationVisibility.visibilityPublic,
      positionGravity: PositionGravity.auto,
      height: 400,
      width: 200,
      enableDrag: true,
    );
    
    // Compartimos el nombre del chat con el overlay
    await FlutterOverlayWindow.shareData(chatName ?? '');
  }

  Future<void> hideBubble() async {
    final isActive = await FlutterOverlayWindow.isActive();
    if (isActive) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }
}

// ---------------------------------------------------------
// Callbacks para el Overlay (deben ser top-level)
// ---------------------------------------------------------

class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  String _chatName = "";
  bool _isPermanentRecording = false;
  bool _isPressed = false;
  Timer? _bubblePressTimer;
  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is String) {
        setState(() {
          _chatName = event;
        });
      }
    });

    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
       try {
         final position = await FlutterOverlayWindow.getOverlayPosition();
         
         // Fetch real device height bounds
         final view = PlatformDispatcher.instance.views.first;
         final screenHeight = view.physicalSize.height / view.devicePixelRatio;

         debugPrint("Overlay Y position: ${position.y} | Screen height: $screenHeight");

         // If dragged down past the 85% mark of the screen length
         if (position.y > (screenHeight * 0.85)) { 
           FlutterOverlayWindow.closeOverlay();
         }
       } catch (e) {
         debugPrint("Error al obtener posición: $e");
       }
    });
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _bubblePressTimer?.cancel();
    _bubblePressTimer = Timer(const Duration(milliseconds: 200), () {
      if (!_isPermanentRecording) {
        final sendPort = IsolateNameServer.lookupPortByName(bubblePortName);
        sendPort?.send('start');
      }
    });
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    bool isShortTap = false;
    if (_bubblePressTimer != null && _bubblePressTimer!.isActive) {
      isShortTap = true;
    }
    _bubblePressTimer?.cancel();
    
    if (isShortTap) {
      final sendPort = IsolateNameServer.lookupPortByName(bubblePortName);
      if (_isPermanentRecording) {
        _isPermanentRecording = false;
        sendPort?.send('stop'); 
      } else {
        _isPermanentRecording = true;
        sendPort?.send('start');
      }
    } else {
      if (!_isPermanentRecording) {
        final sendPort = IsolateNameServer.lookupPortByName(bubblePortName);
        sendPort?.send('stop');
      }
    }
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _bubblePressTimer?.cancel();
    if (!_isPermanentRecording) {
      final sendPort = IsolateNameServer.lookupPortByName(bubblePortName);
      sendPort?.send('stop_cancel');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTapDown: _onTapDown,
              onTapUp: _onTapUp,
              onTapCancel: _onTapCancel,
              child: Container(
                 width: 72,
                 height: 72,
                 decoration: BoxDecoration(
                   color: _isPermanentRecording ? Colors.red : (_isPressed ? Colors.green.shade700 : Colors.green),
                   shape: BoxShape.circle,
                   boxShadow: [
                     BoxShadow(
                       color: Colors.black.withOpacity(0.3),
                       blurRadius: 8,
                       offset: const Offset(0, 4),
                     )
                   ],
                 ),
                 child: const Icon(Icons.mic, size: 40, color: Colors.white),
              ),
            ),
            if (_chatName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _chatName,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

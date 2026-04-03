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
      positionGravity: PositionGravity.none,
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

    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
       try {
         final position = await FlutterOverlayWindow.getOverlayPosition();
         
         // Fetch real device height bounds
         final view = PlatformDispatcher.instance.views.first;
         final screenHeight = view.physicalSize.height / view.devicePixelRatio;

         debugPrint("Overlay Y position: ${position.y} | Screen height: $screenHeight");

         // En Android, dependiente de la configuración, position.y puede representar una coordenada absoluta.
         // Para cerrarlo solo en la parte inferior, verificamos que rebase el 90% (o más abajo) de la pantalla.
         if (position.y > (screenHeight * 0.90)) { 
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
    _bubblePressTimer = Timer(const Duration(milliseconds: 200), () {});
    
    if (!_isPermanentRecording) {
      final sendPort = IsolateNameServer.lookupPortByName(bubblePortName);
      sendPort?.send('start');
    }
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
              child: AnimatedContainer(
                 duration: const Duration(milliseconds: 150),
                 width: 80,
                 height: 80,
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(
                   color: (_isPermanentRecording || _isPressed)
                       ? Colors.greenAccent.withOpacity(0.2)
                       : Colors.blueAccent.withOpacity(0.2),
                   shape: BoxShape.circle,
                   boxShadow: [
                     BoxShadow(
                       color: (_isPermanentRecording || _isPressed)
                           ? Colors.greenAccent.withOpacity(0.6)
                           : Colors.blueAccent.withOpacity(0.6),
                       blurRadius: 20,
                       spreadRadius: 5,
                     )
                   ],
                 ),
                 child: Image.asset(
                   'assets/btn_walkie_mic.png',
                   fit: BoxFit.contain,
                 ),
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

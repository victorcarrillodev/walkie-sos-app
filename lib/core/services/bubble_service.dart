import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String bubblePortName = 'bubble_ptt_port';

// ─── Tamaños en dp ───
const int _kSmallDp  = 55;
const int _kMediumDp = 72;
const int _kLargeDp  = 95;

// Margen extra alrededor del botón para que el glow no se recorte
const int _kGlowPadding = 20; // dp a cada lado
// Altura reservada para el texto del canal
const int _kLabelDp     = 28; // dp

int _dpFromKey(String key) {
  if (key == 'small')  return _kSmallDp;
  if (key == 'large')  return _kLargeDp;
  return _kMediumDp;
}

// Ventana nativa = buttonDp + padding doble (izq+der / arriba+abajo)
int _windowW(int dp) => dp + _kGlowPadding * 2;
int _windowH(int dp) => dp + _kGlowPadding * 2 + _kLabelDp;

// ─────────────────────────────────────────────────────────
// Servicio principal (hilo de la app)
// ─────────────────────────────────────────────────────────
class BubbleService {
  static final BubbleService _instance = BubbleService._internal();
  factory BubbleService() => _instance;
  BubbleService._internal();

  Future<void> init() async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await FlutterOverlayWindow.requestPermission();
    }
  }

  Future<void> showBubble({String? chatName}) async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await FlutterOverlayWindow.requestPermission();
      return;
    }
    if (await FlutterOverlayWindow.isActive()) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final sizeKey = prefs.getString('bubble_size') ?? 'medium';
    final sizeDp  = _dpFromKey(sizeKey);

    // Ventana nativa = ancho del botón, alto = botón + label
    // enableDrag: true → el arrastre lo gestiona Android nativamente sin bloquear la app
    await FlutterOverlayWindow.showOverlay(
      overlayTitle:    'WalkieSOS',
      overlayContent:  'Botón activo',
      flag:            OverlayFlag.focusPointer,
      visibility:      NotificationVisibility.visibilityPublic,
      positionGravity: PositionGravity.none,
      width:           _windowW(sizeDp),
      height:          _windowH(sizeDp),
      enableDrag:      true,
    );

    // Enviar nombre y tamaño al isolate después de que arranque
    await Future.delayed(const Duration(milliseconds: 500));
    await FlutterOverlayWindow.shareData(chatName ?? '');
    await Future.delayed(const Duration(milliseconds: 150));
    await FlutterOverlayWindow.shareData('SIZE:$sizeKey');
  }

  Future<void> hideBubble() async {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }
}

// ─────────────────────────────────────────────────────────
// Widget del Overlay (corre en Isolate aparte)
// ─────────────────────────────────────────────────────────
class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  String _chatName  = '';
  bool   _isPermanentRecording = false;
  bool   _isPressed = false;
  Timer? _bubblePressTimer;
  Timer? _positionTimer;

  // Tamaño en píxeles lógicos (coincide con dp en este plugin)
  double _bubbleSize = _kMediumDp.toDouble();

  @override
  void initState() {
    super.initState();
    _loadInitialSize();

    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is! String) return;
      if (event.startsWith('SIZE:')) {
        _applySize(event.substring(5).trim());
      } else if (event.isNotEmpty) {
        if (mounted) setState(() => _chatName = event);
      }
    });

    // Cerrar al arrastrar al borde inferior
    _positionTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      try {
        final pos = await FlutterOverlayWindow.getOverlayPosition();
        final view = PlatformDispatcher.instance.views.first;
        final screenH = view.physicalSize.height / view.devicePixelRatio;
        if (pos.y > screenH * 0.90) FlutterOverlayWindow.closeOverlay();
      } catch (_) {}
    });
  }

  Future<void> _loadInitialSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final key = prefs.getString('bubble_size') ?? 'medium';
      if (mounted) setState(() => _bubbleSize = _dpFromKey(key).toDouble());
    } catch (_) {}
  }

  void _applySize(String key) {
    if (!mounted) return;
    final dp = _dpFromKey(key);
    setState(() => _bubbleSize = dp.toDouble());
    FlutterOverlayWindow.resizeOverlay(_windowW(dp), _windowH(dp), true);
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    setState(() => _isPressed = true);
    _bubblePressTimer?.cancel();
    _bubblePressTimer = Timer(const Duration(milliseconds: 200), () {});
    if (!_isPermanentRecording) {
      IsolateNameServer.lookupPortByName(bubblePortName)?.send('start');
    }
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _isPressed = false);
    final isShortTap = _bubblePressTimer?.isActive ?? false;
    _bubblePressTimer?.cancel();

    if (isShortTap) {
      final port = IsolateNameServer.lookupPortByName(bubblePortName);
      if (_isPermanentRecording) {
        setState(() => _isPermanentRecording = false);
        port?.send('stop');
      } else {
        setState(() => _isPermanentRecording = true);
      }
    } else {
      if (!_isPermanentRecording) {
        IsolateNameServer.lookupPortByName(bubblePortName)?.send('stop');
      }
    }
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _bubblePressTimer?.cancel();
    if (!_isPermanentRecording) {
      IsolateNameServer.lookupPortByName(bubblePortName)?.send('stop_cancel');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool active = _isPermanentRecording || _isPressed;
    final Color glowColor = active ? Colors.greenAccent : Colors.blueAccent;

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width:  _bubbleSize + _kGlowPadding * 2,
        height: _bubbleSize + _kGlowPadding * 2 + _kLabelDp,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Margen superior para que el glow no se recorte arriba
            SizedBox(height: _kGlowPadding.toDouble()),
            // ── Botón circular ──
            GestureDetector(
              onTapDown:   _onTapDown,
              onTapUp:     _onTapUp,
              onTapCancel: _onTapCancel,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width:   _bubbleSize,
                height:  _bubbleSize,
                padding: EdgeInsets.all(_bubbleSize * 0.1),
                decoration: BoxDecoration(
                  shape:    BoxShape.circle,
                  color:    glowColor.withValues(alpha: 0.2),
                  boxShadow: [
                    BoxShadow(
                      color:        glowColor.withValues(alpha: 0.65),
                      blurRadius:   _bubbleSize * 0.20,
                      spreadRadius: _bubbleSize * 0.05,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/btn_walkie_mic.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),

            // ── Nombre del canal ──
            if (_chatName.isNotEmpty) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: _bubbleSize,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _chatName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color:      Colors.white,
                      fontSize:   10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            // Margen inferior para que el glow no se recorte abajo
            SizedBox(height: _chatName.isEmpty ? _kGlowPadding.toDouble() : 0),
          ],
        ),
      ),
    );
  }
}

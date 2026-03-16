import 'dart:ui';
import 'dart:async';
import 'package:dash_bubble/dash_bubble.dart';

const String bubblePortName = 'bubble_ptt_port';

class BubbleService {
  static final BubbleService _instance = BubbleService._internal();
  factory BubbleService() => _instance;
  BubbleService._internal();

  Future<void> init() async {
    await DashBubble.instance.requestOverlayPermission();
    await DashBubble.instance.requestPostNotificationsPermission();
  }

  Future<void> showBubble({String? chatName}) async {
    final hasOverlay = await DashBubble.instance.hasOverlayPermission();
    if (!hasOverlay) {
      await DashBubble.instance.requestOverlayPermission();
      return; // Do not proceed if permission wasn't there initially, user must grant it.
    }
    
    // Si ya está corriendo, no hacemos nada
    if (await DashBubble.instance.isRunning()) return;

    await DashBubble.instance.startBubble(
      bubbleOptions: BubbleOptions(
        bubbleIcon: 'ic_mic',
        closeIcon: 'ic_close',
        bubbleSize: 72,
        opacity: 1,
        enableClose: true,
        closeBehavior: CloseBehavior.fixed, // Evita que se mueva feo la "X" al arrastrar
        distanceToClose: 80,
        enableAnimateToEdge: true,
        enableBottomShadow: false, // Desactiva la sombra rara que se movía
        keepAliveWhenAppExit: false, 
      ),
      notificationOptions: NotificationOptions(
        id: 99,
        title: chatName != null ? 'WalkieSOS - $chatName' : 'WalkieSOS',
        body: 'Botón de emergencias (PTT) activo',
        channelId: 'walkiesos_bubble',
        channelName: 'WalkieSOS Bubble',
      ),
      onTapDown: _onBubbleTapDown,
      onMove: _onBubbleMove,
      onTapUp: _onBubbleTapUp,
    );
  }

  Future<void> hideBubble() async {
    if (await DashBubble.instance.isRunning()) {
      await DashBubble.instance.stopBubble();
    }
  }
}

// ---------------------------------------------------------
// Callbacks para DashBubble (deben ser top-level)
// ---------------------------------------------------------

// Guardamos variables globales en el Isolate
bool _isBubbleDragging = false;
Timer? _bubblePressTimer;
double _startX = 0;
double _startY = 0;

// Variables para la mantención del estado
bool _isPermanentRecording = false;

@pragma('vm:entry-point')
void _onBubbleTapDown(double x, double y) {
  _isBubbleDragging = false;
  _startX = x;
  _startY = y;
  
  _bubblePressTimer?.cancel();
  _bubblePressTimer = Timer(const Duration(milliseconds: 200), () {
    // Si no se está arrastrando y no está en modo permanente, se inicia PTT por hold
    if (!_isBubbleDragging && !_isPermanentRecording) {
      final sendPort = IsolateNameServer.lookupPortByName(bubblePortName);
      sendPort?.send('start');
    }
  });
}

@pragma('vm:entry-point')
void _onBubbleMove(double x, double y) {
  // Calcular distancia desde el punto inicial
  final distance = (x - _startX).abs() + (y - _startY).abs();
  
  // Solo se considera arrastre si se movió más de 10 unidades
  if (!_isBubbleDragging && distance > 10) {
    _isBubbleDragging = true;
    _bubblePressTimer?.cancel();
    final sendPort = IsolateNameServer.lookupPortByName(bubblePortName);
    sendPort?.send('stop_cancel'); 
  }
}

@pragma('vm:entry-point')
void _onBubbleTapUp(double x, double y) {
  bool isShortTap = false;
  
  // Si el timer sigue activo, significa que soltó antes de 200ms (un toque rápido)
  if (_bubblePressTimer != null && _bubblePressTimer!.isActive) {
    isShortTap = true;
  }
  _bubblePressTimer?.cancel();
  
  if (!_isBubbleDragging) {
    if (isShortTap) {
      // Toque corto: alternar modo grabación permanente
      final sendPort = IsolateNameServer.lookupPortByName(bubblePortName);
      if (_isPermanentRecording) {
        _isPermanentRecording = false;
        sendPort?.send('stop'); 
      } else {
        _isPermanentRecording = true;
        sendPort?.send('start');
      }
    } else {
      // Toque largo: detener solo si no estaba en modo permanente
      if (!_isPermanentRecording) {
        final sendPort = IsolateNameServer.lookupPortByName(bubblePortName);
        sendPort?.send('stop');
      }
    }
  }

  _isBubbleDragging = false;
}

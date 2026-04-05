import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../../core/providers/auth_provider.dart';

class GlobalEmergencyOverlay extends StatefulWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final Widget child;
  const GlobalEmergencyOverlay({super.key, required this.child});

  @override
  State<GlobalEmergencyOverlay> createState() => _GlobalEmergencyOverlayState();
}

class _GlobalEmergencyOverlayState extends State<GlobalEmergencyOverlay> {
  bool _isAlertActive   = false;
  bool _isAlertExpanded = false;
  bool _showConfirmTerminate = false;
  Map<String, dynamic>? _activeAlertData;

  final AudioPlayer _sirenPlayer = AudioPlayer();
  Timer?            _sirenTimer;

  @override
  void initState() {
    super.initState();
    _registerListeners();
  }

  void _registerListeners() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Solo alertas recibidas por socket — el emisor usa socket.to() y no recibe el suyo
      SocketService().socket?.on('emergency-alert', _onEmergencyAlert);
      SocketService().socket?.on('alert-resolved',  _onAlertResolved);

      SocketService().onOnlineStatus((_) {
        SocketService().socket?.off('emergency-alert', _onEmergencyAlert);
        SocketService().socket?.on('emergency-alert',  _onEmergencyAlert);
        SocketService().socket?.off('alert-resolved',  _onAlertResolved);
        SocketService().socket?.on('alert-resolved',   _onAlertResolved);
      });
    });
  }

  @override
  void dispose() {
    _sirenTimer?.cancel();
    _sirenPlayer.dispose();
    SocketService().socket?.off('emergency-alert', _onEmergencyAlert);
    SocketService().socket?.off('alert-resolved',  _onAlertResolved);
    super.dispose();
  }

  // ── Handlers ─────────────────────────────────────────────────────────────

  void _onEmergencyAlert(dynamic data) {
    if (!mounted) return;

    // Si el emisor SOY YO, no mostrar la alerta (ni en grupos ni en directos)
    final myUserId = context.read<AuthProvider>().user?.id;
    String? senderId;
    if (data is Map) {
      final userMap = data['user'];
      if (userMap is Map) senderId = userMap['id'] as String?;
    }
    if (myUserId != null && senderId != null && myUserId == senderId) {
      debugPrint('🔕 Alerta propia ignorada (soy el emisor)');
      return;
    }

    debugPrint('¡ALERTA RECIBIDA!: $data');
    setState(() {
      _isAlertActive   = true;
      _isAlertExpanded = true;
      _activeAlertData = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);
    });
    _playSiren();
  }

  void _onAlertResolved(dynamic data) {
    if (!mounted) return;
    final alertId = data['alertId'];
    if (_activeAlertData != null && _activeAlertData!['id'] == alertId) {
      _dismissAlert();
    }
  }

  void _dismissAlert() {
    _sirenTimer?.cancel();
    _sirenPlayer.stop();
    if (mounted) {
      setState(() {
        _isAlertActive        = false;
        _isAlertExpanded      = false;
        _activeAlertData      = null;
        _showConfirmTerminate = false;
      });
    }
  }

  // ── Audio ─────────────────────────────────────────────────────────────────

  Future<void> _playSiren() async {
    try {
      await _sirenPlayer.stop();
      await _sirenPlayer.play(AssetSource('sounds/alerta.mp3'));
      _sirenTimer?.cancel();
      _sirenTimer = Timer(const Duration(seconds: 3), () => _sirenPlayer.stop());
    } catch (e) {
      debugPrint('Siren error: $e');
    }
  }

  // ── Google Maps ───────────────────────────────────────────────────────────

  Future<void> _openGoogleMaps() async {
    if (_activeAlertData == null) return;
    final lat = (_activeAlertData!['location']?['lat'] ?? 0.0).toDouble();
    final lng = (_activeAlertData!['location']?['lng'] ?? 0.0).toDouble();
    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (!await launchUrl(geo, mode: LaunchMode.externalApplication)) {
        await launchUrl(web, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try { await launchUrl(web, mode: LaunchMode.externalApplication); } catch (_) {}
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,

        // ── Alerta expandida (pantalla completa, estática) ──
        if (_isAlertActive && _isAlertExpanded && _activeAlertData != null)
          _buildFullscreenAlert(context),

        // ── Alerta minimizada (chip fijo, sin arrastrar) ──
        if (_isAlertActive && !_isAlertExpanded && _activeAlertData != null)
          _buildMinimizedChip(context),

        // ── Diálogo de confirmación ──
        if (_showConfirmTerminate)
          _buildConfirmDialog(context),
      ],
    );
  }

  Widget _buildFullscreenAlert(BuildContext context) {
    final alias = _activeAlertData!['user']?['alias'] ?? 'Desconocido';
    final lat   = (_activeAlertData!['location']?['lat'] ?? 0.0).toDouble();
    final lng   = (_activeAlertData!['location']?['lng'] ?? 0.0).toDouble();

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end:   Alignment.bottomCenter,
              colors: [Color(0xFFB71C1C), Color(0xFF880000)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────────
                const SizedBox(height: 24),
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 80),
                const SizedBox(height: 12),
                const Text(
                  '¡ALERTA DE EMERGENCIA!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '@$alias activó un código de pánico',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // ── Mapa ────────────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(lat, lng),
                          initialZoom: 16.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.walkiesos.app',
                          ),
                          MarkerLayer(markers: [
                            Marker(
                              point: LatLng(lat, lng),
                              width: 48, height: 48,
                              child: const Icon(Icons.location_on, color: Colors.red, size: 48),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Botones ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.map),
                              label: const Text('Abrir Maps'),
                              onPressed: _openGoogleMaps,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.minimize),
                              label: const Text('Minimizar'),
                              onPressed: () => setState(() => _isAlertExpanded = false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFFB71C1C),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Terminar Alerta'),
                          onPressed: () {
                            if (_activeAlertData != null) {
                              setState(() => _showConfirmTerminate = true);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Chip minimizado — fijo en esquina inferior derecha, sin arrastre
  Widget _buildMinimizedChip(BuildContext context) {
    final alias = _activeAlertData!['user']?['alias'] ?? 'Desc';
    return Positioned(
      right:  16,
      bottom: 100,
      child: SafeArea(
        child: GestureDetector(
          onTap: () => setState(() => _isAlertExpanded = true),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(30),
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade700.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4))
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    '🚨 @$alias',
                    style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmDialog(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('¿Terminar Alerta?',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 12),
                const Text(
                  'Esto cancelará la alerta para todos los participantes.',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _showConfirmTerminate = false),
                      child: const Text('Cancelar',
                          style: TextStyle(color: Colors.white70)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () {
                        if (_activeAlertData != null) {
                          SocketService().socket?.emit('resolve-alert', {
                            'alertId':   _activeAlertData!['id'],
                            'channelId': _activeAlertData!['channelId'] ?? '',
                          });
                        }
                        _dismissAlert();
                      },
                      child: const Text('Terminar',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

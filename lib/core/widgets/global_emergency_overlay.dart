import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/socket_service.dart';

class GlobalEmergencyOverlay extends StatefulWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  final Widget child;

  const GlobalEmergencyOverlay({super.key, required this.child});

  @override
  State<GlobalEmergencyOverlay> createState() => _GlobalEmergencyOverlayState();
}

class _GlobalEmergencyOverlayState extends State<GlobalEmergencyOverlay> {
  bool _isAlertActive = false;
  bool _isAlertExpanded = false;
  Map<String, dynamic>? _activeAlertData;
  Offset? _minimizedOffset;

  @override
  void initState() {
    super.initState();
    _registerEmergencyListener();
  }

  void _registerEmergencyListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SocketService().socket?.on('emergency-alert', _onEmergencyAlert);
      SocketService().socket?.on('alert-resolved', _onAlertResolved);
      SocketService().onOnlineStatus((_) {
        // Re-listen when reconnected
        SocketService().socket?.off('emergency-alert', _onEmergencyAlert);
        SocketService().socket?.on('emergency-alert', _onEmergencyAlert);
        SocketService().socket?.off('alert-resolved', _onAlertResolved);
        SocketService().socket?.on('alert-resolved', _onAlertResolved);
      });
    });
  }

  @override
  void dispose() {
    SocketService().socket?.off('emergency-alert', _onEmergencyAlert);
    SocketService().socket?.off('alert-resolved', _onAlertResolved);
    super.dispose();
  }

  void _onEmergencyAlert(dynamic data) {
    if (!mounted) return;
    debugPrint('¡ALERTA RECIBIDA!: $data');
    
    setState(() {
      _isAlertActive = true;
      _isAlertExpanded = true;
      _activeAlertData = data;
    });
  }

  void _onAlertResolved(dynamic data) {
    if (!mounted) return;
    final alertId = data['alertId'];
    if (_activeAlertData != null && _activeAlertData!['id'] == alertId) {
      setState(() {
        _isAlertActive = false;
        _isAlertExpanded = false;
        _activeAlertData = null;
        _minimizedOffset = null;
      });
    }
  }

  void _confirmTerminateAlert(String alertId) {
    final navContext = GlobalEmergencyOverlay.navigatorKey.currentContext ?? context;
    showDialog(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Terminar Alerta?'),
        content: const Text('Esto cancelará la alerta para todos los participantes. ¿Deseas continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              final channelId = _activeAlertData?['channelId'] ?? '';
              SocketService().socket?.emit('resolve-alert', { 'alertId': alertId, 'channelId': channelId });
              setState(() {
                _isAlertActive = false;
                _isAlertExpanded = false;
                _activeAlertData = null;
                _minimizedOffset = null;
              });
            },
            child: const Text('Terminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _openGoogleMaps() async {
    if (_activeAlertData == null) return;
    final lat = (_activeAlertData!['location']?['lat'] ?? 0.0).toDouble();
    final lng = (_activeAlertData!['location']?['lng'] ?? 0.0).toDouble();
    
    final geoUrl = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final webUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    
    try {
      bool launched = await launchUrl(geoUrl, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching maps: $e');
      try {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      } catch (e2) {
        debugPrint('Error launching maps fallback: $e2');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        widget.child,

        // --- BANNER DE ALERTA MINIMIZADA ---
        if (_isAlertActive && !_isAlertExpanded && _activeAlertData != null)
          Positioned(
            left: _minimizedOffset?.dx,
            top: _minimizedOffset?.dy,
            right: _minimizedOffset == null ? 16 : null,
            bottom: _minimizedOffset == null ? 100 : null,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => setState(() => _isAlertExpanded = true),
                onPanUpdate: (details) {
                  setState(() {
                    if (_minimizedOffset == null) {
                      final size = MediaQuery.of(context).size;
                      // Estimación de posición inicial basada en bottom:100 y right:16
                      _minimizedOffset = Offset(size.width - 200, size.height - 150);
                    }
                    _minimizedOffset = _minimizedOffset! + details.delta;
                  });
                },
                child: Material(
                  elevation: 10,
                  borderRadius: BorderRadius.circular(30),
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4))],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'Alerta: @${_activeAlertData!['user']?['alias'] ?? 'Desc'}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    )
                  ),
                ),
              ),
            ),
          ),

        // --- OVERLAY DE ALERTA EXPANDIDA (PANTALLA COMPLETA) ---
        if (_isAlertActive && _isAlertExpanded && _activeAlertData != null)
          Positioned.fill(
             child: Material(
               color: Colors.black.withOpacity(0.85),
               child: Align(
                 alignment: Alignment.bottomCenter,
                 child: Container(
                   decoration: BoxDecoration(
                     color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                     borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                     boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, -5))],
                   ),
                   child: SafeArea(
                     top: false,
                     child: Padding(
                       padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                       child: Column(
                       mainAxisSize: MainAxisSize.min,
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Row(
                           children: [
                             const Icon(Icons.warning, color: Colors.red, size: 32),
                             const SizedBox(width: 12),
                             const Expanded(child: Text('¡ALERTA DE EMERGENCIA!', style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold))),
                           ],
                         ),
                         const SizedBox(height: 12),
                         Text('El usuario @${_activeAlertData!['user']?['alias'] ?? 'Desconocido'} activó un código de pánico. Ubicación en tiempo real:', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                         const SizedBox(height: 16),
                         SizedBox(
                           height: 280,
                           width: double.maxFinite,
                           child: ClipRRect(
                             borderRadius: BorderRadius.circular(12),
                             child: FlutterMap(
                               options: MapOptions(
                                 initialCenter: LatLng(
                                   (_activeAlertData!['location']?['lat'] ?? 0.0).toDouble(),
                                   (_activeAlertData!['location']?['lng'] ?? 0.0).toDouble()
                                 ),
                                 initialZoom: 16.0,
                               ),
                               children: [
                                 TileLayer(
                                   urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                   userAgentPackageName: 'com.walkiesos.app',
                                 ),
                                 MarkerLayer(
                                   markers: [
                                     Marker(
                                       point: LatLng(
                                         (_activeAlertData!['location']?['lat'] ?? 0.0).toDouble(),
                                         (_activeAlertData!['location']?['lng'] ?? 0.0).toDouble()
                                       ),
                                       width: 40,
                                       height: 40,
                                       child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                                     ),
                                   ],
                                 ),
                               ],
                             ),
                           ),
                         ),
                         const SizedBox(height: 20),
                         Row(
                           children: [
                             Expanded(
                               child: OutlinedButton.icon(
                                 icon: const Icon(Icons.map),
                                 label: const Text('Maps'),
                                 onPressed: _openGoogleMaps,
                               ),
                             ),
                             const SizedBox(width: 8),
                             Expanded(
                               child: OutlinedButton.icon(
                                 icon: const Icon(Icons.close_fullscreen),
                                 label: const Text('Minimizar'),
                                 onPressed: () => setState(() => _isAlertExpanded = false),
                               ),
                             ),
                           ],
                         ),
                         const SizedBox(height: 12),
                         SizedBox(
                           width: double.maxFinite,
                           child: ElevatedButton.icon(
                             style: ElevatedButton.styleFrom(
                               backgroundColor: Colors.red,
                               foregroundColor: Colors.white,
                               padding: const EdgeInsets.symmetric(vertical: 12),
                             ),
                             icon: const Icon(Icons.stop_circle),
                             label: const Text('Terminar Alerta', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                             onPressed: () {
                                if (_activeAlertData != null) {
                                   _confirmTerminateAlert(_activeAlertData!['id']);
                                }
                             },
                           ),
                         )
                       ],
                     ),
                   ),
                 ),
                 ),
               )
             )
          ),
      ],
    );
  }
}

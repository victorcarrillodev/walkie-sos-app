import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/alert_recording_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/emergency_service.dart';
import '../../../core/services/socket_service.dart';

class AlertsHistoryScreen extends StatefulWidget {
  const AlertsHistoryScreen({super.key});

  @override
  State<AlertsHistoryScreen> createState() => _AlertsHistoryScreenState();
}

class _AlertsHistoryScreenState extends State<AlertsHistoryScreen> {
  bool _isLoading = true;
  List<dynamic> _alerts = [];
  String? _error;

  // Grabaciones locales indexadas por alertId
  final Map<String, AlertRecordingModel> _recordings = {};

  // Reproductor de audio inline
  final AudioPlayer _player = AudioPlayer();
  String? _playingPath;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadLocalRecordings();

    // Suscribirse a nuevas grabaciones que lleguen en tiempo real
    _subscribeToNewRecordings();

    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state == PlayerState.playing;
        if (state == PlayerState.completed || state == PlayerState.stopped) {
          _playingPath = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // ── Data loaders ───────────────────────────────────────────────────────────

  Future<void> _loadLocalRecordings() async {
    final recs = await DatabaseService().getAllRecordings();
    if (!mounted) return;
    setState(() {
      for (final r in recs) {
        _recordings[r.alertId] = r;
      }
    });
  }

  void _subscribeToNewRecordings() {
    EmergencyService().recordingStream.listen((rec) {
      if (!mounted) return;
      setState(() => _recordings[rec.alertId] = rec);
    });
  }

  void _loadHistory() {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    bool hasResponded = false;

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !hasResponded) {
        setState(() {
          _error = 'Tiempo de espera agotado o el servidor no respondió.';
          _isLoading = false;
        });
      }
    });

    SocketService().socket?.emitWithAck('get-alerts-history', {}, ack: (data) {
      hasResponded = true;
      if (!mounted) return;

      try {
        if (data is List) {
          setState(() {
            _alerts = data;
            _isLoading = false;
          });
        } else if (data is Map) {
          if (data['success'] == true || data.containsKey('alerts')) {
            setState(() {
              _alerts = data['alerts'] ?? [];
              _isLoading = false;
            });
          } else {
            setState(() {
              _error = data['error'] ?? 'Error desconocido';
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _error = 'Formato de respuesta desconocido.';
            _isLoading = false;
          });
        }
      } catch (e) {
        setState(() {
          _error = 'Error procesando los datos: $e';
          _isLoading = false;
        });
      }
    });
  }

  // ── Audio playback ─────────────────────────────────────────────────────────

  Future<void> _togglePlayback(String audioPath) async {
    if (_playingPath == audioPath && _isPlaying) {
      await _player.pause();
    } else {
      _playingPath = audioPath;
      await _player.stop();
      await _player.play(DeviceFileSource(audioPath));
    }
  }

  // ── Cancel alert ───────────────────────────────────────────────────────────

  void _confirmCancelAlert(String alertId, String? channelId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Alerta'),
        content: const Text(
            '¿Estás seguro de que deseas cancelar esta alerta? '
            'Esto detendrá la notificación a los demás usuarios si es que aún está activa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No, mantenerla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              SocketService().cancelAlert(alertId, channelId);
              setState(() {
                final idx = _alerts.indexWhere((a) => a['id'] == alertId);
                if (idx != -1) {
                  _alerts[idx]['status'] = 'DISMISSED';
                  _alerts[idx]['resolvedAt'] = DateTime.now().toIso8601String();
                }
              });
            },
            child: const Text('Sí, Cancelar',
                style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatDuration(String? start, String? end) {
    if (start == null) return 'Desconocida';
    final s = DateTime.tryParse(start);
    if (s == null) return 'Desconocida';
    if (end == null) return 'Activa actualmente';
    final e = DateTime.tryParse(end);
    if (e == null) return 'Desconocida';
    final diff = e.difference(s);
    return '${diff.inMinutes}m ${diff.inSeconds % 60}s';
  }

  Widget _buildRecordingPlayer(AlertRecordingModel rec) {
    final isThisPlaying = _playingPath == rec.audioPath && _isPlaying;
    final fileOk = File(rec.audioPath).existsSync();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.graphic_eq,
              color: isThisPlaying ? Colors.red : Colors.red.withValues(alpha: 0.6),
              size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '🎙️ Grabación post-alarma (10 s)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (fileOk)
            IconButton(
              icon: Icon(
                isThisPlaying ? Icons.pause_circle : Icons.play_circle,
                color: Colors.red,
                size: 30,
              ),
              tooltip: isThisPlaying ? 'Pausar' : 'Reproducir',
              onPressed: () => _togglePlayback(rec.audioPath),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text('Archivo no encontrado',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final myId = auth.user?.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Alertas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadHistory();
              _loadLocalRecordings();
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red)))
              : _alerts.isEmpty
                  ? const Center(child: Text('No hay registros de alertas'))
                  : ListView.builder(
                      itemCount: _alerts.length,
                      itemBuilder: (context, index) {
                        final alert = _alerts[index];
                        final isMine = alert['userId'] == myId;

                        String counterpart = 'Desconocido';
                        if (isMine) {
                          if (alert['channel'] != null) {
                            counterpart = 'Grupo: ${alert['channel']['name']}';
                          } else if (alert['targetUser'] != null) {
                            counterpart =
                                'Para: @${alert['targetUser']['alias']}';
                          }
                        } else {
                          counterpart = 'De: @${alert['user']['alias']}';
                        }

                        final createdAt = alert['createdAt'] != null
                            ? DateFormat('dd/MM/yyyy HH:mm:ss').format(
                                DateTime.parse(alert['createdAt']).toLocal())
                            : 'Fecha desconocida';

                        final isActive = alert['status'] == 'ACTIVE';
                        final isDismissed = alert['status'] == 'DISMISSED';

                        // Buscar grabación local asociada (por alertId remoto)
                        final alertId = alert['id']?.toString() ?? '';
                        final recording = _recordings[alertId];

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          color: isDark
                              ? const Color(0xFF1E1E1E)
                              : Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isDismissed
                                          ? Icons.cancel_outlined
                                          : Icons.warning_amber_rounded,
                                      color: isActive
                                          ? Colors.red
                                          : (isDismissed
                                              ? Colors.orange
                                              : Colors.grey),
                                      size: 32,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isDismissed
                                                ? 'Alerta Cancelada'
                                                : (isMine
                                                    ? 'Alerta Emitida'
                                                    : 'Alerta Recibida'),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isDismissed
                                                  ? Colors.orange
                                                  : (isMine
                                                      ? Colors.red
                                                      : Colors.blue),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(counterpart,
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                          Text('Fecha: $createdAt',
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                          Text(
                                            'Duración: ${_formatDuration(alert['createdAt'], alert['resolvedAt'])}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isActive
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: isActive
                                                  ? Colors.red
                                                  : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isMine && isActive)
                                      IconButton(
                                        icon: const Icon(Icons.cancel,
                                            color: Colors.red),
                                        onPressed: () {
                                          final String? cId =
                                              alert['channel']?['id'] ??
                                                  alert['channelId'];
                                          _confirmCancelAlert(alertId, cId);
                                        },
                                      ),
                                  ],
                                ),

                                // Reproductor de grabación (solo alertas propias con clip)
                                if (isMine && recording != null)
                                  _buildRecordingPlayer(recording),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

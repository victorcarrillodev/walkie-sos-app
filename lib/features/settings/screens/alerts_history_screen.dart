import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/auth_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    // Usamos Socket.io con ack callback para pedir el historial
    SocketService().socket?.emitWithAck('get-alerts-history', {}, ack: (data) {
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        setState(() {
          _alerts = data['alerts'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = data?['error'] ?? 'Error desconocido';
          _isLoading = false;
        });
      }
    });
  }

  String _formatDuration(String? start, String? end) {
    if (start == null) return 'Desconocida';
    final s = DateTime.tryParse(start);
    if (s == null) return 'Desconocida';
    
    if (end == null) return 'Activa actualmente';
    final e = DateTime.tryParse(end);
    if (e == null) return 'Desconocida';
    
    final diff = e.difference(s);
    final minutes = diff.inMinutes;
    final seconds = diff.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

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
            onPressed: _loadHistory,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _alerts.isEmpty
                  ? const Center(child: Text('No hay registros de alertas'))
                  : ListView.builder(
                      itemCount: _alerts.length,
                      itemBuilder: (context, index) {
                        final alert = _alerts[index];
                        final isMine = alert['userId'] == myId;
                        
                        // Determinar a quién fue enviada o de quién vino
                        String counterpart = 'Desconocido';
                        if (isMine) {
                          if (alert['channel'] != null) {
                            counterpart = 'Grupo: ${alert['channel']['name']}';
                          } else if (alert['targetUser'] != null) {
                            counterpart = 'Para: @${alert['targetUser']['alias']}';
                          }
                        } else {
                          counterpart = 'De: @${alert['user']['alias']}';
                        }

                        final createdAt = alert['createdAt'] != null 
                            ? DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.parse(alert['createdAt']).toLocal()) 
                            : 'Fecha desconocida';
                            
                        final isActive = alert['status'] == 'ACTIVE';

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          child: ListTile(
                            leading: Icon(
                              Icons.warning_amber_rounded,
                              color: isActive ? Colors.red : Colors.grey,
                              size: 32,
                            ),
                            title: Text(
                              isMine ? 'Alerta Emitida' : 'Alerta Recibida',
                              style: TextStyle(fontWeight: FontWeight.bold, color: isMine ? Colors.orange : Colors.blue),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(counterpart),
                                Text('Fecha: $createdAt'),
                                Text('Duración: ${_formatDuration(alert['createdAt'], alert['resolvedAt'])}', 
                                  style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.red : null)),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
    );
  }
}

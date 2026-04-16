/// Modelo local que asocia un clip de audio grabado automáticamente
/// tras disparar la alarma de emergencia con el ID de alerta del backend.
class AlertRecordingModel {
  final String id;        // LOCAL id (timestamp)
  final String alertId;   // ID del alert enviado al servidor (puede ser vacío si no se recibió)
  final String audioPath; // ruta absoluta del archivo .m4a
  final DateTime createdAt;

  AlertRecordingModel({
    required this.id,
    required this.alertId,
    required this.audioPath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'alertId': alertId,
        'audioPath': audioPath,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AlertRecordingModel.fromMap(Map<String, dynamic> map) {
    return AlertRecordingModel(
      id: map['id'],
      alertId: map['alertId'],
      audioPath: map['audioPath'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}

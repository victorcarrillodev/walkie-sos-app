class MessageModel {
  final String id;
  final String channelId;
  final String userId;
  final String alias;
  final String audioPath;
  final DateTime createdAt;

  MessageModel({
    required this.id,
    required this.channelId,
    required this.userId,
    required this.alias,
    required this.audioPath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'channelId': channelId,
        'userId': userId,
        'alias': alias,
        'audioPath': audioPath,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'],
      channelId: map['channelId'],
      userId: map['userId'],
      alias: map['alias'],
      audioPath: map['audioPath'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}
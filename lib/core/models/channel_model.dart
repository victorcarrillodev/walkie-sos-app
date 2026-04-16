class ChannelModel {
  final String id;
  final String name;
  final String? description;
  final int maxMessageDuration;
  final bool isGroup;
  final int? memberCount;

  ChannelModel({
    required this.id,
    required this.name,
    this.description,
    required this.maxMessageDuration,
    required this.isGroup,
    this.memberCount,
  });

  factory ChannelModel.fromJson(Map<String, dynamic> json) {
    return ChannelModel(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      maxMessageDuration: json['maxMessageDuration'] ?? 60,
      isGroup: json['isGroup'] ?? !json['name'].toString().startsWith('direct_'),
      memberCount: json['_count']?['members'],
    );
  }
}
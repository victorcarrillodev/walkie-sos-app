class ChannelModel {
  final String id;
  final String name;
  final String? description;
  final bool isPrivate;
  final bool isGroup;
  final int? memberCount;

  ChannelModel({
    required this.id,
    required this.name,
    this.description,
    required this.isPrivate,
    required this.isGroup,
    this.memberCount,
  });

  factory ChannelModel.fromJson(Map<String, dynamic> json) {
    return ChannelModel(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      isPrivate: json['isPrivate'] ?? false,
      isGroup: json['isGroup'] ?? true,
      memberCount: json['_count']?['members'],
    );
  }
}
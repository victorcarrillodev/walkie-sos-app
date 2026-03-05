class ContactModel {
  final String contactId;
  final String alias;
  final String name;
  final String? avatarUrl;
  final DateTime? lastContactedAt;

  ContactModel({
    required this.contactId,
    required this.alias,
    required this.name,
    this.avatarUrl,
    this.lastContactedAt,
  });

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    return ContactModel(
      contactId: json['contactId'],
      alias: json['alias'],
      name: json['name'],
      avatarUrl: json['avatarUrl'],
      lastContactedAt: json['lastContactedAt'] != null
          ? DateTime.parse(json['lastContactedAt'])
          : null,
    );
  }
}
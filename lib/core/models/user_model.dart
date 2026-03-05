class UserModel {
  final String id;
  final String email;
  final String alias;
  final String firstName;
  final String lastName;
  final String? avatarUrl;

  UserModel({
    required this.id,
    required this.email,
    required this.alias,
    required this.firstName,
    required this.lastName,
    this.avatarUrl,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      email: json['email'],
      alias: json['alias'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      avatarUrl: json['avatarUrl'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'alias': alias,
        'firstName': firstName,
        'lastName': lastName,
        'avatarUrl': avatarUrl,
      };
}
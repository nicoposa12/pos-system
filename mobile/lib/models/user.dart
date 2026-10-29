class User {
  final int? id;
  final String username;
  final String password;
  final String? pin;
  final String fullName;
  final DateTime createdAt;

  User({
    this.id,
    required this.username,
    required this.password,
    this.pin,
    required this.fullName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'pin': pin,
      'full_name': fullName,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      username: map['username'],
      password: map['password'],
      pin: map['pin'],
      fullName: map['full_name'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  User copyWith({
    int? id,
    String? username,
    String? password,
    String? pin,
    String? fullName,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      pin: pin ?? this.pin,
      fullName: fullName ?? this.fullName,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

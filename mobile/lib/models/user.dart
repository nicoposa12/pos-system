class User {
  final int? id;
  final String username;
  final String password;
  final String? pin;
  final String fullName;
  final String? email;
  final String? imagePath;
  final String role;
  final bool isActive;
  final DateTime createdAt;

  User({
    this.id,
    required this.username,
    required this.password,
    this.pin,
    required this.fullName,
    this.email,
    this.imagePath,
    this.role = 'client',
    this.isActive = true,
    required this.createdAt,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get hasPin => pin != null && pin!.isNotEmpty;
  bool get hasValidImage => imagePath != null && imagePath!.trim().isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'pin': pin,
      'full_name': fullName,
      'email': email,
      'image_path': imagePath,
      'role': role,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      pin: map['pin'],
      fullName: map['full_name'] ?? '',
      email: map['email'],
      imagePath: map['image_path']?.toString(),
      role: map['role'] ?? 'client',
      isActive: (map['is_active'] == null || map['is_active'] == 1 || map['is_active'] == true),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  User copyWith({
    int? id,
    String? username,
    String? password,
    String? pin,
    String? fullName,
    String? email,
    String? imagePath,
    String? role,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      pin: pin ?? this.pin,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      imagePath: imagePath ?? this.imagePath,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

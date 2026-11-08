class User {
  final int? id;
  final String username;
  final String fullName;
  final String? email;
  final String? imagePath;
  final String role;
  final bool isActive;

  /// Whether a quick PIN is configured on the server. The PIN itself is never
  /// stored on the device; it is always verified by the API.
  final bool hasPin;
  final DateTime createdAt;

  User({
    this.id,
    required this.username,
    required this.fullName,
    this.email,
    this.imagePath,
    this.role = 'client',
    this.isActive = true,
    this.hasPin = false,
    required this.createdAt,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get hasValidImage => imagePath != null && imagePath!.trim().isNotEmpty;

  /// Builds a user from the API payload (`/auth/login`, `/auth/me`, `/admin/clients`).
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as num?)?.toInt(),
      username: json['username']?.toString() ?? '',
      fullName: (json['full_name'] ?? json['username'] ?? '').toString(),
      email: json['email']?.toString(),
      imagePath: json['image_path']?.toString(),
      role: json['role']?.toString() ?? 'client',
      isActive: json['is_active'] != false && json['is_active'] != 0,
      hasPin: json['has_pin'] == true || json['has_pin'] == 1,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Minimal session snapshot persisted on the device (no credentials).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'email': email,
      'image_path': imagePath,
      'role': role,
      'is_active': isActive,
      'has_pin': hasPin,
      'created_at': createdAt.toIso8601String(),
    };
  }

  User copyWith({
    int? id,
    String? username,
    String? fullName,
    String? email,
    String? imagePath,
    String? role,
    bool? isActive,
    bool? hasPin,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      imagePath: imagePath ?? this.imagePath,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      hasPin: hasPin ?? this.hasPin,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

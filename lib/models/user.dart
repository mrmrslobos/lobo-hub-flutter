// lib/models/user.dart
// ignore_for_file: constant_identifier_names
class User {
  final String id;
  final String name;
  final String email;
  final String? avatar;
  /// Per-device prefs (e.g. Health sync). Not all backends persist every key.
  final Map<String, dynamic> settings;

  const User({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
    this.settings = const {},
    DateTime? createdAt,
  });

  String get initials {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  String? get avatarUrl => avatar;

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    email: j['email'] as String? ?? '',
    avatar: j['avatar'] as String?,
    settings: j['settings'] is Map
        ? Map<String, dynamic>.from(j['settings'] as Map)
        : const {},
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'avatar': avatar,
    'settings': settings,
  };

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? avatar,
    Map<String, dynamic>? settings,
  }) =>
    User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      settings: settings ?? this.settings,
    );
}

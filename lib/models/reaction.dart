// lib/models/reaction.dart
// ignore_for_file: constant_identifier_names
class Reaction {
  final String userId;
  final String emoji;

  const Reaction({required this.userId, required this.emoji});

  factory Reaction.fromJson(Map<String, dynamic> j) => Reaction(
    userId: j['user_id'] as String? ?? '',
    emoji: j['emoji'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'user_id': userId, 'emoji': emoji};
}

// lib/models/chat_message.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import '_enums.dart';
import 'model_json_helpers.dart';

class ChatMessage {
  final String id;
  final String familyId;
  final String userId;
  final String text;
  final String? replyToId;
  final Map<String, List<String>> reactions;
  final DateTime? editedAt;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.text,
    this.replyToId,
    this.reactions = const {},
    this.editedAt,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    // Reactions may be encrypted as a JSON string or legacy plain map
    final rawReactions = FieldEncryption.decryptJson(j['reactions'], fid);
    Map<String, List<String>> parsedReactions = {};
    if (rawReactions is Map) {
      rawReactions.forEach((k, v) {
        parsedReactions[k.toString()] = (v is List) ? v.map((e) => e.toString()).toList() : <String>[];
      });
    }
    return ChatMessage(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      text: FieldEncryption.decryptField(j['text'] as String?, fid) ?? '',
      replyToId: j['reply_to_id'] as String?,
      reactions: parsedReactions,
      editedAt: parseDateOpt(j['edited_at']),
      createdAt: parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'text': FieldEncryption.encryptField(text, familyId),
    'reply_to_id': replyToId,
    'reactions': FieldEncryption.encryptJson(reactions, familyId),
    'edited_at': editedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  // Convenience getters
  String get senderId => userId;
  String get content => text;
  MessageType get type => MessageType.text;

  ChatMessage copyWith({
    String? id, String? familyId, String? userId, String? text,
    String? replyToId, Map<String, List<String>>? reactions,
    DateTime? editedAt, DateTime? createdAt,
  }) => ChatMessage(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    userId: userId ?? this.userId, text: text ?? this.text,
    replyToId: replyToId ?? this.replyToId,
    reactions: reactions ?? this.reactions,
    editedAt: editedAt ?? this.editedAt,
    createdAt: createdAt ?? this.createdAt,
  );
}

// lib/models/devotional_thought.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';

class DevotionalThought {
  final String id;
  final String devotionalId;
  final String familyId;
  final String userId;
  final DevotionalNoteKind kind;
  final String body;
  final DateTime updatedAt;

  DevotionalThought({
    required this.id,
    required this.devotionalId,
    required this.familyId,
    required this.userId,
    this.kind = DevotionalNoteKind.thought,
    this.body = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Canonical id so all devices agree (matches DB upsert conflict key).
  static String stableId(String devotionalId, String userId, DevotionalNoteKind kind) {
    switch (kind) {
      case DevotionalNoteKind.thought:
        return 'dt_${devotionalId}_$userId';
      case DevotionalNoteKind.prayer:
        return 'dp_${devotionalId}_$userId';
    }
  }

  String get mergeKey => '$devotionalId|$userId|${kind.wireValue}';

  factory DevotionalThought.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    final did = j['devotional_id'] as String? ?? '';
    final uid = j['user_id'] as String? ?? '';
    var kind = DevotionalNoteKind.fromWire(j['note_kind'] as String?);
    if (kind == DevotionalNoteKind.thought &&
        id.startsWith('dp_') &&
        did.isNotEmpty &&
        uid.isNotEmpty) {
      kind = DevotionalNoteKind.prayer;
    }
    return DevotionalThought(
      id: id,
      devotionalId: did,
      familyId: j['family_id'] as String? ?? '',
      userId: uid,
      kind: kind,
      body: j['body'] as String? ?? '',
      updatedAt: parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'devotional_id': devotionalId,
    'family_id': familyId,
    'user_id': userId,
    'note_kind': kind.wireValue,
    'body': body,
    'updated_at': updatedAt.toIso8601String(),
  };

  DevotionalThought copyWith({
    String? id,
    String? devotionalId,
    String? familyId,
    String? userId,
    DevotionalNoteKind? kind,
    String? body,
    DateTime? updatedAt,
  }) {
    final any = id != null ||
        devotionalId != null ||
        familyId != null ||
        userId != null ||
        kind != null ||
        body != null;
    return DevotionalThought(
      id: id ?? this.id,
      devotionalId: devotionalId ?? this.devotionalId,
      familyId: familyId ?? this.familyId,
      userId: userId ?? this.userId,
      kind: kind ?? this.kind,
      body: body ?? this.body,
      updatedAt: updatedAt ?? (any ? DateTime.now() : this.updatedAt),
    );
  }
}

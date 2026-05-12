// lib/models/poll.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';
import 'poll_option.dart';

class Poll {
  final String id;
  final String familyId;
  final String creatorId;
  final String question;
  final List<PollOption> options;
  final bool allowMultiple;
  final bool anonymous;
  final PollStatus status;
  final DateTime? deadline;
  final Visibility visibility;
  final DateTime createdAt;
  final DateTime updatedAt;

  Poll({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    required this.question,
    this.options = const [],
    this.allowMultiple = false,
    this.anonymous = false,
    this.status = PollStatus.open,
    DateTime? deadline,
    DateTime? expiresAt,
    this.visibility = Visibility.FAMILY,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? createdBy ?? '',
       deadline = deadline ?? expiresAt,
       createdAt = createdAt ?? DateTime.now();

  factory Poll.fromJson(Map<String, dynamic> j) => Poll(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    question: j['question'] as String? ?? '',
    options: parseList(j['options'], PollOption.fromJson),
    allowMultiple: (j['allow_multiple'] ?? false) as bool,
    anonymous: (j['anonymous'] ?? false) as bool,
    status: pollStatusFromString(j['status'] as String?),
    deadline: parseDateOpt(j['deadline']),
    visibility: visibilityFromString(j['visibility'] as String?),
    createdAt: parseDate(j['created_at']),
    updatedAt: parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'question': question,
    'options': options.map((o) => o.toJson()).toList(),
    'allow_multiple': allowMultiple,
    'anonymous': anonymous,
    'status': status.name,
    'deadline': deadline?.toIso8601String(),
    'visibility': visibility.name,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience aliases
  String get createdBy => creatorId;
  DateTime? get expiresAt => deadline;
  int get totalVotes => options.fold(0, (sum, o) => sum + o.voterIds.length);

  Poll copyWith({
    String? id, String? familyId, String? creatorId, String? question,
    List<PollOption>? options, bool? allowMultiple, bool? anonymous,
    PollStatus? status, DateTime? deadline, Visibility? visibility, DateTime? createdAt,
    DateTime? updatedAt,
  }) => Poll(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, question: question ?? this.question,
    options: options ?? this.options, allowMultiple: allowMultiple ?? this.allowMultiple,
    anonymous: anonymous ?? this.anonymous, status: status ?? this.status,
    deadline: deadline ?? this.deadline, visibility: visibility ?? this.visibility,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ??
        ((question != null || options != null || status != null || deadline != null)
            ? DateTime.now()
            : this.updatedAt),
  );
}

// lib/models/chore.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';

class Chore {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String? description;
  final String? icon;
  final int points;
  final double? reward;
  final ChoreFrequency frequency;
  final List<int> daysOfWeek;
  final List<String> assignees;
  final String? color;
  final Visibility visibility;
  final DateTime createdAt;
  final bool requiresApproval;
  /// When true and multiple assignees exist, the next completion advances who is "up next".
  final bool rotationEnabled;
  /// Index into [assignees] for round-robin (persisted per chore).
  final int rotationCursor;
  final DateTime updatedAt;

  Chore({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    required this.title,
    this.description,
    this.icon,
    this.points = 0,
    this.reward,
    this.frequency = ChoreFrequency.DAILY,
    this.daysOfWeek = const [],
    List<String>? assignees,
    List<String>? assigneeIds,
    this.color,
    this.visibility = Visibility.FAMILY,
    DateTime? createdAt,
    this.requiresApproval = false,
    this.rotationEnabled = false,
    this.rotationCursor = 0,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? createdBy ?? '',
       assignees = assignees ?? assigneeIds ?? const [],
       createdAt = createdAt ?? DateTime.now();

  factory Chore.fromJson(Map<String, dynamic> j) => Chore(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    icon: j['icon'] as String?,
    points: (j['points'] as num?)?.toInt() ?? 0,
    reward: (j['reward'] as num?)?.toDouble(),
    frequency: choreFrequencyFromString(j['frequency'] as String?),
    daysOfWeek: intList(j['days_of_week']),
    assignees: strList(j['assignees']),
    color: j['color'] as String?,
    visibility: visibilityFromString(j['visibility'] as String?),
    createdAt: parseDate(j['created_at']),
    requiresApproval: (j['requires_approval'] ?? false) as bool,
    rotationEnabled: (j['rotation_enabled'] ?? false) as bool,
    rotationCursor: (j['rotation_cursor'] as num?)?.toInt() ?? 0,
    updatedAt: parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'description': description,
    'icon': icon,
    'points': points,
    'reward': reward,
    'frequency': frequency.name,
    'days_of_week': daysOfWeek,
    'assignees': assignees,
    'color': color,
    'visibility': visibility.name,
    'created_at': createdAt.toIso8601String(),
    'requires_approval': requiresApproval,
    'rotation_enabled': rotationEnabled,
    'rotation_cursor': rotationCursor,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getters
  List<String> get assigneeIds => assignees;
  DateTime? get lastCompletedAt => null; // populated from ChoreCompletion records

  Chore copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    String? description, String? icon, int? points, double? reward,
    ChoreFrequency? frequency, List<int>? daysOfWeek, List<String>? assignees,
    String? color, Visibility? visibility, DateTime? createdAt, bool? requiresApproval,
    bool? rotationEnabled, int? rotationCursor,
    DateTime? updatedAt,
  }) => Chore(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, title: title ?? this.title,
    description: description ?? this.description, icon: icon ?? this.icon,
    points: points ?? this.points, reward: reward ?? this.reward,
    frequency: frequency ?? this.frequency, daysOfWeek: daysOfWeek ?? this.daysOfWeek,
    assignees: assignees ?? this.assignees, color: color ?? this.color,
    visibility: visibility ?? this.visibility, createdAt: createdAt ?? this.createdAt,
    requiresApproval: requiresApproval ?? this.requiresApproval,
    rotationEnabled: rotationEnabled ?? this.rotationEnabled,
    rotationCursor: rotationCursor ?? this.rotationCursor,
    updatedAt: updatedAt ??
        ((title != null || description != null || points != null || frequency != null ||
                daysOfWeek != null || assignees != null || requiresApproval != null ||
                rotationEnabled != null || rotationCursor != null)
            ? DateTime.now()
            : this.updatedAt),
  );
}

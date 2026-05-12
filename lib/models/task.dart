// lib/models/task.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';

Priority? _taskPriorityToPriority(TaskPriority? tp) {
  if (tp == null) return null;
  switch (tp) {
    case TaskPriority.high: return Priority.HIGH;
    case TaskPriority.medium: return Priority.MEDIUM;
    case TaskPriority.low: return Priority.LOW;
  }
}

Recurrence? _taskRecurrenceToRecurrence(TaskRecurrence? tr) {
  if (tr == null) return null;
  switch (tr) {
    case TaskRecurrence.daily: return Recurrence.DAILY;
    case TaskRecurrence.weekly: return Recurrence.WEEKLY;
    case TaskRecurrence.monthly: return Recurrence.MONTHLY;
    case TaskRecurrence.none: return Recurrence.NONE;
  }
}

class Task {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String? notes;
  final DateTime? dueDate;
  final String? dueTime;
  final int? reminderMinutes;
  /// `push` (default), `email`, `sms`, or `voice` — used with server [reminder_jobs].
  final String? reminderChannel;
  final Priority priority;
  final bool completed;
  final String? completedBy;
  final String? updatedBy;
  final Visibility visibility;
  final List<String> assignees;
  final List<String> tags;
  final Recurrence recurrence;
  /// Monotonic sync version — bump on every user edit so other devices pull the latest.
  final DateTime updatedAt;

  Task({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    required this.title,
    this.notes,
    this.dueDate,
    this.dueTime,
    this.reminderMinutes,
    this.reminderChannel,
    Priority? priority,
    TaskPriority? taskPriority,
    this.completed = false,
    this.completedBy,
    this.updatedBy,
    this.visibility = Visibility.FAMILY,
    List<String>? assignees,
    List<String>? assigneeIds,
    this.tags = const [],
    Recurrence? recurrence,
    TaskRecurrence? taskRecurrence,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? createdBy ?? '',
       assignees = assignees ?? assigneeIds ?? const [],
       priority = priority ?? _taskPriorityToPriority(taskPriority) ?? Priority.MEDIUM,
       recurrence = recurrence ?? _taskRecurrenceToRecurrence(taskRecurrence) ?? Recurrence.NONE;

  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    notes: j['notes'] as String?,
    dueDate: parseDateOpt(j['due_date']),
    dueTime: j['due_time'] as String?,
    reminderMinutes: (j['reminder_minutes'] as num?)?.toInt() ?? (j['reminderMinutes'] as num?)?.toInt(),
    reminderChannel: j['reminder_channel'] as String? ?? j['reminderChannel'] as String?,
    priority: priorityFromString(j['priority'] as String?),
    completed: coerceBool(j['completed']),
    completedBy: j['completed_by'] as String?,
    updatedBy: j['updated_by'] as String?,
    visibility: visibilityFromString(j['visibility'] as String?),
    assignees: strList(j['assignees']),
    tags: strList(j['tags']),
    recurrence: recurrenceFromString(j['recurrence'] as String?),
    updatedAt: parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'notes': notes,
    'due_date': (dueDate ?? DateTime.now()).toIso8601String(),
    'due_time': dueTime,
    'reminder_minutes': reminderMinutes,
    if (reminderChannel != null) 'reminder_channel': reminderChannel,
    'priority': priority.name,
    'completed': completed,
    'completed_by': completedBy,
    'updated_by': updatedBy,
    'visibility': visibility.name,
    'assignees': assignees,
    'tags': tags,
    'recurrence': recurrence.name,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getters for screen compatibility
  List<String> get assigneeIds => assignees;
  String get createdBy => creatorId;
  bool get isOverdue => !completed && dueDate != null && dueDate!.isBefore(DateTime.now());

  Task copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    String? notes, DateTime? dueDate, String? dueTime, int? reminderMinutes,
    String? reminderChannel,
    Priority? priority, bool? completed, String? completedBy, String? updatedBy,
    Visibility? visibility, List<String>? assignees, List<String>? tags,
    Recurrence? recurrence, DateTime? updatedAt,
  }) => Task(
    id: id ?? this.id,
    familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    dueDate: dueDate ?? this.dueDate,
    dueTime: dueTime ?? this.dueTime,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    reminderChannel: reminderChannel ?? this.reminderChannel,
    priority: priority ?? this.priority,
    completed: completed ?? this.completed,
    completedBy: completedBy ?? this.completedBy,
    updatedBy: updatedBy ?? this.updatedBy,
    visibility: visibility ?? this.visibility,
    assignees: assignees ?? this.assignees,
    tags: tags ?? this.tags,
    recurrence: recurrence ?? this.recurrence,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

// lib/models/reading_plan_entry.dart
// ignore_for_file: constant_identifier_names
class ReadingPlanEntry {
  final String id;
  final String planId;
  final String devotionalId;
  final int dayNumber;
  final bool completed;

  ReadingPlanEntry({
    String? id,
    String? planId,
    String? devotionalId,
    int? dayNumber,
    int? day,
    String? title,
    String? scripture,
    String? content,
    this.completed = false,
  }) : id = id ?? '',
       planId = planId ?? '',
       devotionalId = devotionalId ?? title ?? '',
       dayNumber = day ?? dayNumber ?? 0;

  factory ReadingPlanEntry.fromJson(Map<String, dynamic> j) => ReadingPlanEntry(
    id: j['id'] as String? ?? '',
    planId: j['plan_id'] as String? ?? '',
    devotionalId: j['devotional_id'] as String? ?? '',
    dayNumber: (j['day_number'] as int?) ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'plan_id': planId, 'devotional_id': devotionalId, 'day_number': dayNumber,
  };

  // Convenience getters
  int get day => dayNumber;
  String get title => devotionalId;
  String? get scripture => null;

  ReadingPlanEntry copyWith({
    String? id, String? planId, String? devotionalId, int? dayNumber,
    bool? completed, int? day, String? title, String? scripture,
  }) => ReadingPlanEntry(
    id: id ?? this.id, planId: planId ?? this.planId,
    devotionalId: title ?? devotionalId ?? this.devotionalId,
    dayNumber: day ?? dayNumber ?? this.dayNumber,
    completed: completed ?? this.completed,
  );
}

// lib/models/reading_plan.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';
import 'reading_plan_entry.dart';

class ReadingPlan {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String description;
  final int totalDays;
  final List<dynamic> days;
  final List<String> entryIds;
  final DateTime createdAt;

  const ReadingPlan({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.title,
    this.description = '',
    this.totalDays = 0,
    this.days = const [],
    this.entryIds = const [],
    required this.createdAt,
  });

  factory ReadingPlan.fromJson(Map<String, dynamic> j) {
    final daysList = (j['days'] is List) ? (j['days'] as List) : <dynamic>[];
    final fromExplicit = strList(j['entry_ids']);
    final fromDays = <String>[];
    for (final x in daysList) {
      if (x is Map) {
        final id = x['devotional_id']?.toString();
        if (id != null && id.isNotEmpty) fromDays.add(id);
      }
    }
    final ids = fromExplicit.isNotEmpty ? fromExplicit : fromDays;
    final td = (j['total_days'] as num?)?.toInt() ?? 0;
    final total = td > 0 ? td : (ids.isNotEmpty ? ids.length : daysList.length);
    return ReadingPlan(
      id: j['id'] as String? ?? '',
      familyId: j['family_id'] as String? ?? '',
      creatorId: j['creator_id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      description: j['description'] as String? ?? '',
      totalDays: total,
      days: daysList,
      entryIds: ids,
      createdAt: parseDate(j['created_at']),
    );
  }

  /// Persist day→devotional links for local disk + Supabase (jsonb `days`).
  List<dynamic> _daysPayload() {
    if (days.isNotEmpty) return List<dynamic>.from(days);
    return [
      for (var i = 0; i < entryIds.length; i++)
        <String, dynamic>{'devotional_id': entryIds[i], 'day': i + 1},
    ];
  }

  int _totalDaysPayload() {
    if (totalDays > 0) return totalDays;
    if (entryIds.isNotEmpty) return entryIds.length;
    if (days.isNotEmpty) return days.length;
    return 0;
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'family_id': familyId, 'creator_id': creatorId,
    'title': title, 'description': description,
    'total_days': _totalDaysPayload(),
    'days': _daysPayload(),
    // entryIds are encoded inside [days][].devotional_id (no entry_ids DB column)
    'created_at': createdAt.toIso8601String(),
  };

  // Convenience getter - entries are stored in entryIds; screens may hold them in-memory
  List<ReadingPlanEntry> get entries => const [];
  int get completedCount => 0;
  double get progress => 0.0;

  ReadingPlan copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    String? description, int? totalDays, List<dynamic>? days,
    List<String>? entryIds, DateTime? createdAt,
    List<ReadingPlanEntry>? entries,
  }) => ReadingPlan(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, title: title ?? this.title,
    description: description ?? this.description,
    totalDays: totalDays ?? this.totalDays,
    days: days ?? this.days,
    entryIds: entries?.map((e) => e.id).toList() ?? entryIds ?? this.entryIds,
    createdAt: createdAt ?? this.createdAt,
  );
}

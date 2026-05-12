// lib/models/milestone.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class Milestone {
  final String id;
  final String familyId;
  final String childId;
  final String title;
  final String? emoji;
  final String? category;
  final DateTime date;
  final String? notes;
  final List<String> photoIds;
  final String? ageLabel;
  final DateTime createdAt;

  const Milestone({
    required this.id,
    required this.familyId,
    this.childId = '',
    required this.title,
    this.emoji,
    this.category,
    required this.date,
    this.notes,
    this.photoIds = const [],
    this.ageLabel,
    required this.createdAt,
  });

  factory Milestone.fromJson(Map<String, dynamic> j) => Milestone(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    childId: j['child_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    emoji: j['emoji'] as String?,
    category: j['category'] as String?,
    date: parseDate(j['date']),
    notes: j['notes'] as String?,
    photoIds: strList(j['photo_ids']),
    ageLabel: j['age_label'] as String?,
    createdAt: parseDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'child_id': childId,
    'title': title,
    'emoji': emoji,
    'category': category,
    'date': date.toIso8601String(),
    'notes': notes,
    'photo_ids': photoIds,
    'age_label': ageLabel,
    'created_at': createdAt.toIso8601String(),
  };
}

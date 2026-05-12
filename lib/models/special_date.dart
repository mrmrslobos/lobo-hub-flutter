// lib/models/special_date.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';

class SpecialDate {
  final String id;
  final String familyId;
  final String creatorId;
  final String name;
  final SpecialDateType type;
  final int month;
  final int day;
  final int? year;
  final String? emoji;
  final String? notes;
  final List<int> reminderDays;
  final Visibility visibility;
  final DateTime createdAt;

  SpecialDate({
    required this.id,
    required this.familyId,
    required this.creatorId,
    String? name,
    String? title,
    SpecialDateType? type,
    String? typeStr,
    int? month,
    int? day,
    int? year,
    DateTime? date,
    bool? recurring,
    this.emoji,
    this.notes,
    this.reminderDays = const [7],
    this.visibility = Visibility.FAMILY,
    DateTime? createdAt,
  }) : name = name ?? title ?? '',
       type = type ?? (typeStr != null ? specialDateTypeFromString(typeStr) : SpecialDateType.BIRTHDAY),
       month = month ?? date?.month ?? 1,
       day = day ?? date?.day ?? 1,
       year = (recurring == true) ? null : (year ?? date?.year),
       createdAt = createdAt ?? DateTime.now();

  factory SpecialDate.fromJson(Map<String, dynamic> j) => SpecialDate(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    type: specialDateTypeFromString(j['type'] as String?),
    month: (j['month'] as num?)?.toInt() ?? 1,
    day: (j['day'] as num?)?.toInt() ?? 1,
    year: (j['year'] as num?)?.toInt(),
    emoji: j['emoji'] as String?,
    notes: j['notes'] as String?,
    reminderDays: intList(j['reminder_days']),
    visibility: visibilityFromString(j['visibility'] as String?),
    createdAt: parseDate(j['created_at']),
  );

  /// DB column `emoji` is NOT NULL — use when local/cloud row has no emoji.
  static String defaultEmojiForType(SpecialDateType t) {
    switch (t) {
      case SpecialDateType.BIRTHDAY:
        return '🎂';
      case SpecialDateType.ANNIVERSARY:
        return '💝';
      case SpecialDateType.MEMORIAL:
        return '🕯️';
      case SpecialDateType.OTHER:
        return '📅';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'name': name,
    'type': type.name,
    'month': month,
    'day': day,
    'year': year,
    'emoji': emoji ?? defaultEmojiForType(type),
    'notes': notes,
    'reminder_days': reminderDays,
    'visibility': visibility.name,
    'created_at': createdAt.toIso8601String(),
  };

  // Convenience getters
  DateTime get date => DateTime(year ?? DateTime.now().year, month, day);
  bool get recurring => year == null;
  String get title => name;

  SpecialDate copyWith({
    String? id, String? familyId, String? creatorId, String? name,
    SpecialDateType? type, int? month, int? day, int? year,
    String? emoji, String? notes, List<int>? reminderDays,
    Visibility? visibility, DateTime? createdAt,
  }) => SpecialDate(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, name: name ?? this.name,
    type: type ?? this.type, month: month ?? this.month, day: day ?? this.day,
    year: year ?? this.year, emoji: emoji ?? this.emoji, notes: notes ?? this.notes,
    reminderDays: reminderDays ?? this.reminderDays, visibility: visibility ?? this.visibility,
    createdAt: createdAt ?? this.createdAt,
  );
}

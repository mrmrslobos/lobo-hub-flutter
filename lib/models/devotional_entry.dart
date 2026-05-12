// lib/models/devotional_entry.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';

class DevotionalEntry {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String? scripture;
  final String? content;
  final List<String> reflectionPrompts;
  final String? prayer;
  final String? userPrayer;
  final List<String> tags;
  final DateTime date;
  final Visibility visibility;
  final bool isFavorited;
  final DateTime updatedAt;

  DevotionalEntry({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? userId,
    required this.title,
    this.scripture,
    this.content,
    this.reflectionPrompts = const [],
    this.prayer,
    this.userPrayer,
    this.tags = const [],
    DateTime? date,
    this.visibility = Visibility.FAMILY,
    this.isFavorited = false,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? userId ?? '',
       date = date ?? DateTime.now();

  factory DevotionalEntry.fromJson(Map<String, dynamic> j) => DevotionalEntry(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    scripture: j['scripture'] as String?,
    content: j['content'] as String?,
    reflectionPrompts: strList(j['reflection_prompts']),
    prayer: j['prayer'] as String?,
    userPrayer: j['user_prayer'] as String?,
    tags: strList(j['tags']),
    date: parseDate(j['date']),
    visibility: visibilityFromString(j['visibility'] as String?),
    isFavorited: (j['is_favorited'] ?? false) as bool,
    updatedAt: parseDateOpt(j['updated_at']) ?? parseDate(j['date']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'scripture': scripture,
    'content': content,
    'reflection_prompts': reflectionPrompts,
    'prayer': prayer,
    'user_prayer': userPrayer,
    'tags': tags,
    'date': date.toIso8601String(),
    'visibility': visibility.name,
    'is_favorited': isFavorited,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getter
  String get userId => creatorId;

  DevotionalEntry copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    String? scripture, String? content, List<String>? reflectionPrompts,
    String? prayer, String? userPrayer, List<String>? tags,
    DateTime? date, Visibility? visibility, bool? isFavorited, DateTime? updatedAt,
  }) => DevotionalEntry(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, title: title ?? this.title,
    scripture: scripture ?? this.scripture, content: content ?? this.content,
    reflectionPrompts: reflectionPrompts ?? this.reflectionPrompts,
    prayer: prayer ?? this.prayer, userPrayer: userPrayer ?? this.userPrayer,
    tags: tags ?? this.tags, date: date ?? this.date,
    visibility: visibility ?? this.visibility,
    isFavorited: isFavorited ?? this.isFavorited,
    updatedAt: updatedAt ??
        ((title != null ||
                content != null ||
                isFavorited != null ||
                visibility != null)
            ? DateTime.now()
            : this.updatedAt),
  );
}

// lib/models/prayer_wall_entry.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';
import 'reaction.dart';

class PrayerWallEntry {
  final String id;
  final String familyId;
  final String creatorId;
  final PrayerWallType type;
  final String text;
  final String? originalRequestId;
  final List<Reaction> reactions;
  final List<String> prayedByIds;
  final DateTime date;
  final DateTime? answeredAt;
  final Visibility visibility;

  PrayerWallEntry({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? userId,
    this.type = PrayerWallType.REQUEST,
    String? text,
    String? title,
    String? body,
    this.originalRequestId,
    this.reactions = const [],
    this.prayedByIds = const [],
    DateTime? date,
    DateTime? createdAt,
    this.answeredAt,
    bool? answered,
    this.visibility = Visibility.FAMILY,
  }) : creatorId = creatorId ?? userId ?? '',
       text = text ?? (title != null ? (body != null ? '$title\n$body' : title) : body ?? ''),
       date = date ?? createdAt ?? DateTime.now();

  PrayerWallEntry copyWith({
    String? id, String? familyId, String? creatorId, PrayerWallType? type,
    String? text, String? originalRequestId, List<Reaction>? reactions,
    List<String>? prayedByIds, DateTime? date, DateTime? answeredAt, Visibility? visibility,
  }) => PrayerWallEntry(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, type: type ?? this.type,
    text: text ?? this.text, originalRequestId: originalRequestId ?? this.originalRequestId,
    reactions: reactions ?? this.reactions, prayedByIds: prayedByIds ?? this.prayedByIds,
    date: date ?? this.date, answeredAt: answeredAt ?? this.answeredAt,
    visibility: visibility ?? this.visibility,
  );

  factory PrayerWallEntry.fromJson(Map<String, dynamic> j) => PrayerWallEntry(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    type: prayerWallTypeFromString(j['type'] as String?),
    text: j['text'] as String? ?? '',
    originalRequestId: j['original_request_id'] as String?,
    reactions: parseList(j['reactions'], Reaction.fromJson),
    prayedByIds: strList(j['prayed_by_ids']),
    date: parseDate(j['date']),
    answeredAt: parseDateOpt(j['answered_at']),
    visibility: visibilityFromString(j['visibility'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'family_id': familyId, 'creator_id': creatorId,
    'type': type.name, 'text': text,
    'original_request_id': originalRequestId,
    'reactions': reactions.map((r) => r.toJson()).toList(),
    'prayed_by_ids': prayedByIds,
    'date': date.toIso8601String(),
    'answered_at': answeredAt?.toIso8601String(),
    'visibility': visibility.name,
  };

  // Convenience getters
  bool get answered => answeredAt != null || type == PrayerWallType.ANSWERED;
  DateTime get createdAt => date;
  String get userId => creatorId;
  String get title => text.contains('\n') ? text.split('\n').first : text;
  String? get body => text.contains('\n') ? text.substring(text.indexOf('\n') + 1) : null;
}

// lib/models/calendar_event.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';

class CalendarEvent {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String? description;
  final String? location;
  final DateTime start;
  final DateTime end;
  final Visibility visibility;
  final List<String> sharedWith;
  final List<String> checklist;
  /// User IDs who RSVP'd yes / no / maybe (family calendar only; stored as JSON arrays in Supabase).
  final List<String> rsvpYesIds;
  final List<String> rsvpNoIds;
  final List<String> rsvpMaybeIds;
  final double? budgetEstimate;
  final String? externalCalendarId;
  /// Provider-native event id (e.g. Google Graph / Outlook) when syncing or pushing.
  final String? externalUid;
  final Recurrence recurrence;
  final DateTime updatedAt;

  CalendarEvent({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    required this.title,
    this.description,
    this.location,
    DateTime? start,
    DateTime? startDate,
    DateTime? end,
    DateTime? endDate,
    bool? allDay,
    DateTime? createdAt,
    this.visibility = Visibility.FAMILY,
    this.sharedWith = const [],
    this.checklist = const [],
    this.rsvpYesIds = const [],
    this.rsvpNoIds = const [],
    this.rsvpMaybeIds = const [],
    this.budgetEstimate,
    this.externalCalendarId,
    this.externalUid,
    this.recurrence = Recurrence.NONE,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? createdBy ?? '',
       start = start ?? startDate ?? DateTime.now(),
       end = end ?? endDate ?? (startDate ?? DateTime.now()).add(const Duration(hours: 1));

  factory CalendarEvent.fromJson(Map<String, dynamic> j) => CalendarEvent(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    location: j['location'] as String?,
    start: parseDate(j['start']),
    end: parseDate(j['end']),
    visibility: visibilityFromString(j['visibility'] as String?),
    sharedWith: strList(j['shared_with']),
    checklist: strList(j['checklist']),
    rsvpYesIds: strList(j['rsvp_yes_ids']),
    rsvpNoIds: strList(j['rsvp_no_ids']),
    rsvpMaybeIds: strList(j['rsvp_maybe_ids']),
    budgetEstimate: j['budget_estimate'] != null
        ? (j['budget_estimate'] as num).toDouble()
        : null,
    externalCalendarId: j['external_calendar_id'] as String?,
    externalUid: j['external_uid'] as String?,
    recurrence: recurrenceFromString(j['recurrence'] as String?),
    updatedAt: parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'description': description,
    'location': location,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'visibility': visibility.name,
    'shared_with': sharedWith,
    'checklist': checklist,
    'rsvp_yes_ids': rsvpYesIds,
    'rsvp_no_ids': rsvpNoIds,
    'rsvp_maybe_ids': rsvpMaybeIds,
    'budget_estimate': budgetEstimate,
    'external_calendar_id': externalCalendarId,
    if (externalUid != null) 'external_uid': externalUid,
    'recurrence': recurrence.name,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getters
  DateTime get startDate => start;
  DateTime get endDate => end;
  bool get allDay => start.hour == 0 && start.minute == 0 && end.hour == 0 && end.minute == 0;
  String get createdBy => creatorId;
  DateTime get createdAt => start; // fallback - use start as proxy

  CalendarEvent copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    String? description, String? location, DateTime? start, DateTime? end,
    Visibility? visibility, List<String>? sharedWith, List<String>? checklist,
    List<String>? rsvpYesIds, List<String>? rsvpNoIds, List<String>? rsvpMaybeIds,
    double? budgetEstimate, String? externalCalendarId, String? externalUid,
    Recurrence? recurrence,
    DateTime? updatedAt,
  }) => CalendarEvent(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, title: title ?? this.title,
    description: description ?? this.description, location: location ?? this.location,
    start: start ?? this.start, end: end ?? this.end,
    visibility: visibility ?? this.visibility, sharedWith: sharedWith ?? this.sharedWith,
    checklist: checklist ?? this.checklist,
    rsvpYesIds: rsvpYesIds ?? this.rsvpYesIds,
    rsvpNoIds: rsvpNoIds ?? this.rsvpNoIds,
    rsvpMaybeIds: rsvpMaybeIds ?? this.rsvpMaybeIds,
    budgetEstimate: budgetEstimate ?? this.budgetEstimate,
    externalCalendarId: externalCalendarId ?? this.externalCalendarId,
    externalUid: externalUid ?? this.externalUid,
    recurrence: recurrence ?? this.recurrence,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

// lib/models/external_calendar.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';

class ExternalCalendar {
  final String id;
  final String familyId;
  final String creatorId;
  final ExternalCalendarType type;
  final String name;
  final String? googleCalendarId;
  final String? icsUrl;
  final String? color;
  final bool enabled;
  final DateTime lastSyncedAt;
  final DateTime createdAt;

  ExternalCalendar({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? userId,
    required this.type,
    required this.name,
    this.googleCalendarId,
    this.icsUrl,
    this.color,
    this.enabled = true,
    DateTime? lastSyncedAt,
    DateTime? createdAt,
  }) : creatorId = creatorId ?? userId ?? '',
       lastSyncedAt = lastSyncedAt ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now();

  // Convenience alias for screens that reference userId
  String get userId => creatorId;

  factory ExternalCalendar.fromJson(Map<String, dynamic> j) => ExternalCalendar(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: (j['creator_id'] ?? j['user_id']) as String? ?? '',
    type: externalCalendarTypeFromString(j['type'] as String?),
    name: j['name'] as String? ?? '',
    googleCalendarId: (j['google_calendar_id'] ?? (j['type'] == 'GOOGLE' ? j['url'] : null)) as String?,
    icsUrl: (j['ics_url'] ?? (j['type'] != 'GOOGLE' ? j['url'] : null)) as String?,
    color: j['color'] as String?,
    enabled: j['enabled'] as bool? ?? true,
    lastSyncedAt: parseDate(j['last_synced'] ?? j['last_synced_at']),
    createdAt: parseDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'type': type.name,
    'name': name,
    'url': googleCalendarId ?? icsUrl,
    'color': color,
    'enabled': enabled,
    'last_synced': lastSyncedAt.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  ExternalCalendar copyWith({
    String? id, String? familyId, String? creatorId, ExternalCalendarType? type,
    String? name, String? googleCalendarId, String? icsUrl, String? color,
    bool? enabled, DateTime? lastSyncedAt, DateTime? createdAt,
  }) => ExternalCalendar(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, type: type ?? this.type,
    name: name ?? this.name, googleCalendarId: googleCalendarId ?? this.googleCalendarId,
    icsUrl: icsUrl ?? this.icsUrl, color: color ?? this.color,
    enabled: enabled ?? this.enabled, lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    createdAt: createdAt ?? this.createdAt,
  );
}

// lib/services/outlook_calendar_edge_service.dart
// Fetches Outlook events via Supabase [calendar-sync] edge function (Microsoft Graph).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

const _uuid = Uuid();

class OutlookCalendarEdgeService {
  OutlookCalendarEdgeService._();

  /// Converts edge [NormalizedEvent] JSON to [CalendarEvent] rows for merge.
  static List<CalendarEvent> normalizedToEvents({
    required List<dynamic> rawEvents,
    required String familyId,
    required String userId,
    required String externalCalendarId,
  }) {
    final out = <CalendarEvent>[];
    for (final raw in rawEvents) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final extUid = m['externalUid']?.toString() ?? m['external_uid']?.toString() ?? '';
      final title = m['title']?.toString() ?? 'Event';
      final start = DateTime.tryParse(m['start']?.toString() ?? '') ?? DateTime.now();
      var end = DateTime.tryParse(m['end']?.toString() ?? '') ?? start.add(const Duration(hours: 1));
      if (!end.isAfter(start)) end = start.add(const Duration(hours: 1));
      out.add(CalendarEvent(
        id: extUid.isNotEmpty ? '${externalCalendarId}_$extUid' : '${externalCalendarId}_${_uuid.v4()}',
        familyId: familyId,
        creatorId: userId,
        title: title,
        description: m['description']?.toString(),
        location: m['location']?.toString(),
        start: start,
        end: end,
        visibility: Visibility.PRIVATE,
        externalCalendarId: externalCalendarId,
        externalUid: extUid.isNotEmpty ? extUid : null,
      ));
    }
    return out;
  }

  /// Calls `calendar-sync` with Microsoft Graph. Returns raw `events` list or null.
  static Future<List<dynamic>?> fetchOutlookEvents({
    required String accessToken,
    required String familyId,
  }) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'calendar-sync',
        body: {
          'provider': 'microsoft',
          'accessToken': accessToken,
          'calendarId': 'me',
          'familyId': familyId,
        },
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        if (data['error'] != null) {
          debugPrint('[OutlookCalendarEdge] ${data['error']}');
          return null;
        }
        final ev = data['events'];
        if (ev is List) return ev;
      }
      return null;
    } catch (e, st) {
      debugPrint('[OutlookCalendarEdge] invoke error: $e\n$st');
      return null;
    }
  }
}

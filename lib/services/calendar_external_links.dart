// lib/services/calendar_external_links.dart
// Deep links to add [CalendarEvent] to Google Calendar / Outlook (no API write scope).

import 'package:intl/intl.dart';

import '../models/models.dart';

class CalendarExternalLinks {
  CalendarExternalLinks._();

  static String _formatGcalUtc(DateTime dt) =>
      DateFormat("yyyyMMdd'T'HHmmss'Z'").format(dt.toUtc());

  /// Google Calendar “create event” URL (template).
  static String googleCalendarComposeUrl(CalendarEvent e) {
    final dates =
        '${_formatGcalUtc(e.start)}/${_formatGcalUtc(e.end)}';
    final qp = <String, String>{
      'action': 'TEMPLATE',
      'text': e.title,
      'dates': dates,
      if (e.description != null && e.description!.trim().isNotEmpty)
        'details': e.description!,
      if (e.location != null && e.location!.trim().isNotEmpty)
        'location': e.location!,
    };
    final q = qp.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'https://calendar.google.com/calendar/render?$q';
  }

  /// Outlook on the web compose deeplink (best-effort).
  static String outlookComposeUrl(CalendarEvent e) {
    final start = e.start.toUtc().toIso8601String();
    final end = e.end.toUtc().toIso8601String();
    final qp = <String, String>{
      'path': '/calendar/action/compose',
      'rru': 'addevent',
      'startdt': start,
      'enddt': end,
      'subject': e.title,
      if (e.location != null && e.location!.trim().isNotEmpty) 'location': e.location!,
      if (e.description != null && e.description!.trim().isNotEmpty) 'body': e.description!,
    };
    final uri = Uri.https('outlook.live.com', '/calendar/0/deeplink/compose', qp);
    return uri.toString();
  }

  static String openTableSearchUrl(String query) {
    final q = query.trim().isEmpty ? 'restaurants' : query;
    return 'https://www.opentable.com/s?covers=2&dateTime=${Uri.encodeComponent(DateTime.now().toIso8601String())}&term=${Uri.encodeComponent(q)}';
  }
}

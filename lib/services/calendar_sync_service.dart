// lib/services/calendar_sync_service.dart
// FamilyHub - Google Calendar & ICS URL sync service

// ignore_for_file: avoid_catches_without_on_clauses

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/models.dart';

class CalendarSyncService {
  static const _uuid = Uuid();

  // ── Google Calendar ────────────────────────────────────────────────────────

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [gcal.CalendarApi.calendarReadonlyScope],
  );

  static GoogleSignInAccount? get currentGoogleUser => _googleSignIn.currentUser;

  /// Sign in to Google and return the account. Returns null on failure/cancel.
  static Future<GoogleSignInAccount?> signInGoogle() async {
    try {
      return await _googleSignIn.signIn();
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      return null;
    }
  }

  /// Sign out of Google.
  static Future<void> signOutGoogle() async {
    await _googleSignIn.signOut();
  }

  /// Check if user is already signed in to Google.
  static Future<GoogleSignInAccount?> silentSignIn() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (_) {
      return null;
    }
  }

  /// Fetch the list of Google Calendars for the signed-in user.
  static Future<List<gcal.CalendarListEntry>> fetchGoogleCalendarList() async {
    var httpClient = await _googleSignIn.authenticatedClient();
    if (httpClient == null) {
      await _googleSignIn.signInSilently();
      httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient == null) return [];
    }
    try {
      final calendarApi = gcal.CalendarApi(httpClient);
      final calendarList = await calendarApi.calendarList.list();
      return calendarList.items ?? [];
    } catch (e) {
      debugPrint('Error fetching Google calendars: $e');
      return [];
    }
  }

  /// Fetch events from a specific Google Calendar.
  /// Returns CalendarEvent objects ready to be merged into AppDB.
  static Future<List<CalendarEvent>> fetchGoogleCalendarEvents({
    required String googleCalendarId,
    required String familyId,
    required String userId,
    required String externalCalendarId,
    DateTime? timeMin,
    DateTime? timeMax,
  }) async {
    var httpClient = await _googleSignIn.authenticatedClient();
    if (httpClient == null) {
      await _googleSignIn.signInSilently();
      httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient == null) return [];
    }

    try {
      final calendarApi = gcal.CalendarApi(httpClient);
      final now = DateTime.now();
      final events = await calendarApi.events.list(
        googleCalendarId,
        timeMin: timeMin ?? now.subtract(const Duration(days: 30)),
        timeMax: timeMax ?? now.add(const Duration(days: 90)),
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 250,
      );

      return (events.items ?? []).map((ge) {
        final start = ge.start?.dateTime ?? ge.start?.date ?? now;
        final end = ge.end?.dateTime ?? ge.end?.date ?? start.add(const Duration(hours: 1));

        return CalendarEvent(
          id: '${externalCalendarId}_${ge.id ?? _uuid.v4()}',
          familyId: familyId,
          creatorId: userId,
          title: ge.summary ?? 'Untitled',
          description: ge.description,
          location: ge.location,
          start: start,
          end: end,
          visibility: Visibility.PRIVATE,
          externalCalendarId: externalCalendarId,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error fetching Google events: $e');
      return [];
    }
  }

  // ── ICS URL Import ─────────────────────────────────────────────────────────

  /// Fetch and parse events from an ICS/iCal URL.
  static Future<List<CalendarEvent>> fetchIcsEvents({
    required String url,
    required String familyId,
    required String userId,
    required String externalCalendarId,
  }) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        debugPrint('ICS fetch failed: ${response.statusCode}');
        return [];
      }
      return _parseIcs(
        response.body,
        familyId: familyId,
        userId: userId,
        externalCalendarId: externalCalendarId,
      );
    } catch (e) {
      debugPrint('Error fetching ICS: $e');
      return [];
    }
  }

  /// Extract the calendar name from ICS content, if available.
  static String? extractIcsCalendarName(String icsContent) {
    final lines = icsContent.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('X-WR-CALNAME:')) {
        return trimmed.substring('X-WR-CALNAME:'.length).trim();
      }
    }
    return null;
  }

  /// Parse ICS content into CalendarEvent objects.
  static List<CalendarEvent> _parseIcs(
    String icsContent, {
    required String familyId,
    required String userId,
    required String externalCalendarId,
  }) {
    final events = <CalendarEvent>[];
    // RFC 5545: unfold lines that are continued with a leading space/tab
    final unfolded = icsContent.replaceAll(RegExp(r'\r?\n[ \t]'), '');
    final lines = unfolded.split('\n').map((l) => l.trim()).toList();

    int i = 0;
    while (i < lines.length) {
      if (lines[i] == 'BEGIN:VEVENT') {
        String? uid;
        String? summary;
        String? description;
        String? location;
        DateTime? dtStart;
        DateTime? dtEnd;

        i++;
        while (i < lines.length && lines[i] != 'END:VEVENT') {
          final line = lines[i];
          if (line.startsWith('UID:')) {
            uid = line.substring(4);
          } else if (line.startsWith('SUMMARY:')) {
            summary = _unescapeIcs(line.substring(8));
          } else if (line.startsWith('DESCRIPTION:')) {
            description = _unescapeIcs(line.substring(12));
          } else if (line.startsWith('LOCATION:')) {
            location = _unescapeIcs(line.substring(9));
          } else if (line.startsWith('DTSTART')) {
            dtStart = _parseIcsDate(line);
          } else if (line.startsWith('DTEND')) {
            dtEnd = _parseIcsDate(line);
          }
          i++;
        }

        if (summary != null && dtStart != null) {
          events.add(CalendarEvent(
            id: '${externalCalendarId}_${uid ?? _uuid.v4()}',
            familyId: familyId,
            creatorId: userId,
            title: summary,
            description: description,
            location: location,
            start: dtStart,
            end: dtEnd ?? dtStart.add(const Duration(hours: 1)),
            visibility: Visibility.PRIVATE,
            externalCalendarId: externalCalendarId,
          ));
        }
      }
      i++;
    }

    return events;
  }

  /// Parse an ICS date value from a line like DTSTART:20250101T090000Z
  /// or DTSTART;VALUE=DATE:20250101
  static DateTime? _parseIcsDate(String line) {
    try {
      // Extract the value after the colon
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) return null;
      final value = line.substring(colonIdx + 1).trim();

      if (value.length == 8) {
        // DATE only: YYYYMMDD
        return DateTime(
          int.parse(value.substring(0, 4)),
          int.parse(value.substring(4, 6)),
          int.parse(value.substring(6, 8)),
        );
      } else if (value.length >= 15) {
        // DATETIME: YYYYMMDDTHHmmSS or YYYYMMDDTHHmmSSZ
        final year = int.parse(value.substring(0, 4));
        final month = int.parse(value.substring(4, 6));
        final day = int.parse(value.substring(6, 8));
        final hour = int.parse(value.substring(9, 11));
        final minute = int.parse(value.substring(11, 13));
        final second = int.parse(value.substring(13, 15));

        if (value.endsWith('Z')) {
          return DateTime.utc(year, month, day, hour, minute, second).toLocal();
        }
        return DateTime(year, month, day, hour, minute, second);
      }
    } catch (e) {
      debugPrint('ICS date parse error: $e for line: $line');
    }
    return null;
  }

  /// Unescape ICS text values.
  static String _unescapeIcs(String text) {
    return text
        .replaceAll('\\n', '\n')
        .replaceAll('\\,', ',')
        .replaceAll('\\;', ';')
        .replaceAll('\\\\', '\\');
  }
}

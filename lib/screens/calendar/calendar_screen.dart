// lib/screens/calendar/calendar_screen.dart
// Calendar screen for Huddle

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Visibility;
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../config/cloud_sync_scope.dart';
import '../../config/module_config.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../services/calendar_external_links.dart';
import '../../services/calendar_sync_service.dart';
import '../../services/notification_service.dart';
import '../../services/outlook_calendar_edge_service.dart';
import '../../services/weather_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/huddle_module_scaffold.dart';
import '../../widgets/huddle_page_layout.dart';
import '../../widgets/subscription_modal.dart';
import '../../utils/debounce.dart';
import '../../utils/cloud_pull.dart';
import '../../utils/user_facing_errors.dart';
import '../../utils/sync_after_save.dart';

enum _EventRsvpChoice { yes, no, maybe, clear }

/// One extracted event row in the flyer preview sheet (before saving).
class _FlyerEventDraft {
  bool selected;
  String title;
  DateTime start;
  DateTime end;
  String location;
  String description;

  _FlyerEventDraft({
    required this.selected,
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    required this.description,
  });
}

// ─── CalendarScreen ───────────────────────────────────────────────────────────

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calFormat = CalendarFormat.month;
  bool _isSyncing = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  final _searchDebounce = Debouncer();
  /// Hide events from these layers: `'__family__'` = only family-created events; else [ExternalCalendar.id].
  final Set<String> _hiddenCalendarLayers = {};

  // AI Event Strategist
  final _aiController = TextEditingController();
  bool _isAiLoading = false;
  String? _aiError;

  @override
  void dispose() {
    _searchDebounce.dispose();
    _aiController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleAiQuickPlan() async {
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.calendar)) return;
    final input = _aiController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe what to plan'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final provider = context.read<AppProvider>();
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) return;

    setState(() {
      _isAiLoading = true;
      _aiError = null;
    });

    try {
      final result = await AiService.generateEventItinerary(
        input,
        familyId: family.id,
      );

      if (!mounted) return;
      if (result == null) {
        setState(() {
          _isAiLoading = false;
          _aiError = 'AI failed to create itinerary. Please try again.';
        });
        return;
      }
      provider.saveAiHistory(module: 'calendar', prompt: 'Generate event itinerary: "$input"', response: jsonEncode(result));

      final itinerary = result['itinerary'] as String? ?? '';
      final checklist = (result['checklist'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [];

      final now = DateTime.now();
      final event = CalendarEvent(
        id: const Uuid().v4(),
        familyId: family.id,
        creatorId: user.id,
        title: input,
        description: itinerary,
        start: now,
        end: now.add(const Duration(days: 1)),
        visibility: Visibility.FAMILY,
        checklist: checklist,
      );

      final db = provider.db;
      await saveAndSyncWithImmediatePush(
        provider,
        db.copyWith(events: [...db.events, event]),
        pushTableScope: CloudSyncScope.calendarBundle,
      );

      _aiController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created AI itinerary for "$input"')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aiError = 'AI failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isAiLoading = false);
    }
  }

  void _showEventPlannerWizard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _EventPlannerWizard(),
    );
  }

  Future<void> _shareFamilyAgenda(BuildContext context) async {
    final provider = context.read<AppProvider>();
    final familyId = provider.activeFamily?.id;
    if (familyId == null) return;
    final now = DateTime.now();
    final until = now.add(const Duration(days: 14));
    final evs = provider.db.events
        .where((e) =>
            e.familyId == familyId &&
            e.externalCalendarId == null &&
            e.start.isAfter(now.subtract(const Duration(days: 1))) &&
            e.start.isBefore(until))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (evs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No family events in the next two weeks'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final buf = StringBuffer();
    buf.writeln('Family agenda (next 2 weeks)');
    buf.writeln('');
    for (final e in evs) {
      buf.write(DateFormat('EEE MMM d, h:mm a').format(e.start));
      buf.write(' — ${e.title}');
      if (e.location != null && e.location!.trim().isNotEmpty) {
        buf.write(' @ ${e.location!.trim()}');
      }
      buf.writeln();
    }
    await Share.share(buf.toString().trim(), subject: 'Family agenda');
  }

  // ── Google Calendar ──────────────────────────────────────────────────────

  Future<void> _connectGoogleCalendar() async {
    final account = await CalendarSyncService.signInGoogle();
    if (account == null || !mounted) return;

    setState(() => _isSyncing = true);
    try {
      final calendars = await CalendarSyncService.fetchGoogleCalendarList();
      if (!mounted) return;

      if (calendars.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Google Calendars found')),
        );
        setState(() => _isSyncing = false);
        return;
      }

      // Show calendar picker
      final selected = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _GoogleCalendarPicker(calendars: calendars),
      );

      if (selected == null || selected.isEmpty) {
        if (mounted) setState(() => _isSyncing = false);
        return;
      }
      if (!mounted) return;

      final provider = context.read<AppProvider>();
      final user = provider.activeUser!;
      final family = provider.activeFamily!;
      var db = provider.db;

      for (final calId in selected) {
        final cal = calendars.where((c) => c.id == calId).firstOrNull;
        if (cal == null) continue;
        final extCal = ExternalCalendar(
          id: const Uuid().v4(),
          familyId: family.id,
          userId: user.id,
          type: ExternalCalendarType.google,
          name: cal.summary ?? 'Google Calendar',
          googleCalendarId: calId,
          color: cal.backgroundColor,
          enabled: true,
        );

        // Check if already connected
        final existing = db.externalCalendars.where(
          (e) => e.googleCalendarId == calId && e.userId == user.id,
        );
        if (existing.isNotEmpty) continue;

        db = db.copyWith(
          externalCalendars: [...db.externalCalendars, extCal],
        );

        // Fetch events from this calendar
        final events = await CalendarSyncService.fetchGoogleCalendarEvents(
          googleCalendarId: calId,
          familyId: family.id,
          userId: user.id,
          externalCalendarId: extCal.id,
        );
        if (!mounted) return;

        // Merge: remove old events from this external calendar, add new
        final existingEvents = db.events
            .where((e) => e.externalCalendarId != extCal.id)
            .toList();
        db = db.copyWith(events: [...existingEvents, ...events]);
      }

      await saveAndSyncWithImmediatePush(
        provider,
        db,
        pushTableScope: CloudSyncScope.calendarBundle,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synced ${selected.length} calendar(s) from Google')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _syncExternalCalendar(ExternalCalendar cal) async {
    setState(() => _isSyncing = true);
    try {
      final provider = context.read<AppProvider>();
      final user = provider.activeUser!;
      final family = provider.activeFamily!;

      List<CalendarEvent> newEvents;
      if (cal.type == ExternalCalendarType.google && cal.googleCalendarId != null) {
        // Re-auth silently
        await CalendarSyncService.silentSignIn();
        if (!mounted) return;
        newEvents = await CalendarSyncService.fetchGoogleCalendarEvents(
          googleCalendarId: cal.googleCalendarId!,
          familyId: family.id,
          userId: user.id,
          externalCalendarId: cal.id,
        );
      } else if (cal.type == ExternalCalendarType.icsUrl && cal.icsUrl != null) {
        newEvents = await CalendarSyncService.fetchIcsEvents(
          url: cal.icsUrl!,
          familyId: family.id,
          userId: user.id,
          externalCalendarId: cal.id,
        );
      } else if (cal.type == ExternalCalendarType.microsoft) {
        final token = Supabase.instance.client.auth.currentSession?.providerToken;
        if (token == null || token.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Microsoft sign-in required. Use Continue with Microsoft, then sync again.')),
            );
          }
          setState(() => _isSyncing = false);
          return;
        }
        final raw = await OutlookCalendarEdgeService.fetchOutlookEvents(
          accessToken: token,
          familyId: family.id,
        );
        newEvents = raw == null
            ? <CalendarEvent>[]
            : OutlookCalendarEdgeService.normalizedToEvents(
                rawEvents: raw,
                familyId: family.id,
                userId: user.id,
                externalCalendarId: cal.id,
              );
      } else {
        setState(() => _isSyncing = false);
        return;
      }
      if (!mounted) return;

      // Replace old events from this calendar
      final db = provider.db;
      final otherEvents = db.events
          .where((e) => e.externalCalendarId != cal.id)
          .toList();
      final updatedCal = cal.copyWith(lastSyncedAt: DateTime.now());
      final updatedCalendars = db.externalCalendars
          .map((c) => c.id == cal.id ? updatedCal : c)
          .toList();

      await saveAndSyncWithImmediatePush(
        provider,
        db.copyWith(
          events: [...otherEvents, ...newEvents],
          externalCalendars: updatedCalendars,
        ),
        pushTableScope: CloudSyncScope.calendarBundle,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synced ${newEvents.length} events from ${cal.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _removeExternalCalendar(ExternalCalendar cal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove calendar'),
        content: Text('Remove "${cal.name}" and all its imported events?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final provider = context.read<AppProvider>();
    final db = provider.db;
    await saveAndSyncWithImmediatePush(
      provider,
      db.copyWith(
        externalCalendars: db.externalCalendars.where((c) => c.id != cal.id).toList(),
        events: db.events.where((e) => e.externalCalendarId != cal.id).toList(),
      ),
      pushTableScope: CloudSyncScope.calendarBundle,
    );
    if (!mounted) return;
  }

  Future<void> _connectOutlookCalendar() async {
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.calendar)) return;
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.providerToken;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in with Microsoft first, then tap Outlook sync again.')),
      );
      return;
    }

    final provider = context.read<AppProvider>();
    final user = provider.activeUser!;
    final family = provider.activeFamily!;

    final existingMs = provider.db.externalCalendars.where(
      (c) => c.userId == user.id && c.type == ExternalCalendarType.microsoft,
    ).toList();

    if (existingMs.isNotEmpty) {
      await _syncExternalCalendar(existingMs.first);
      return;
    }

    setState(() => _isSyncing = true);
    try {
      final raw = await OutlookCalendarEdgeService.fetchOutlookEvents(
        accessToken: token,
        familyId: family.id,
      );
      if (!mounted) return;
      if (raw == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load Outlook events. Check Microsoft permissions.')),
        );
        return;
      }

      final db = provider.db;

      final extCal = ExternalCalendar(
        id: const Uuid().v4(),
        familyId: family.id,
        userId: user.id,
        type: ExternalCalendarType.microsoft,
        name: 'Outlook',
        enabled: true,
      );

      final eventsWithLayer = OutlookCalendarEdgeService.normalizedToEvents(
        rawEvents: raw,
        familyId: family.id,
        userId: user.id,
        externalCalendarId: extCal.id,
      );

      await provider.saveAndSync(
        db.copyWith(
          externalCalendars: [...db.externalCalendars, extCal],
          events: [...db.events, ...eventsWithLayer],
        ),
        pushTableScope: CloudSyncScope.calendarBundle,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${eventsWithLayer.length} Outlook events')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Outlook sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<XFile?> _pickFlyerImage() async {
    final picker = ImagePicker();
    if (kIsWeb) {
      return picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 3200,
        imageQuality: 92,
      );
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return null;
    return picker.pickImage(
      source: source,
      maxWidth: 3200,
      imageQuality: 92,
    );
  }

  Future<void> _scanFlyerForEvents() async {
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.calendar)) return;
    final img = await _pickFlyerImage();
    if (img == null || !mounted) return;

    setState(() => _isSyncing = true);
    try {
      final bytes = await img.readAsBytes();
      if (!mounted) return;
      final b64 = base64Encode(bytes);
      final mime = img.mimeType ?? 'image/jpeg';

      final provider = context.read<AppProvider>();
      final family = provider.activeFamily;
      final user = provider.activeUser;
      if (family == null || user == null) return;

      final decoded = await AiService.extractEventsFromImage(
        familyId: family.id,
        imageBase64: b64,
        mimeType: mime,
      );
      if (!mounted) return;
      if (decoded == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We could not read a response from the flyer scan. Check your connection, try again, or use Take photo / a full-resolution image from your library.',
            ),
          ),
        );
        return;
      }
      final rawList = decoded['events'];
      if (rawList is! List || rawList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No events found on this flyer.')),
        );
        return;
      }

      final drafts = <_FlyerEventDraft>[];
      for (final item in rawList) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final title = m['title']?.toString().trim() ?? 'Event';
        final start = DateTime.tryParse(m['start']?.toString() ?? '') ?? DateTime.now();
        var end = DateTime.tryParse(m['end']?.toString() ?? '') ?? start.add(const Duration(hours: 1));
        if (!end.isAfter(start)) end = start.add(const Duration(hours: 1));
        drafts.add(_FlyerEventDraft(
          selected: true,
          title: title,
          start: start,
          end: end,
          location: m['location']?.toString() ?? '',
          description: m['description']?.toString() ?? '',
        ));
      }

      if (drafts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No usable events to preview.')),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _isSyncing = false);

      final confirmed = await showModalBottomSheet<List<_FlyerEventDraft>?>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _FlyerEventsPreviewSheet(
          imageBytes: bytes,
          drafts: drafts,
        ),
      );

      if (!mounted || confirmed == null) return;

      setState(() => _isSyncing = true);
      final newEvents = <CalendarEvent>[];
      for (final d in confirmed) {
        if (!d.selected) continue;
        final title = d.title.trim().isEmpty ? 'Event' : d.title.trim();
        var end = d.end;
        if (!end.isAfter(d.start)) end = d.start.add(const Duration(hours: 1));
        final loc = d.location.trim();
        final desc = [d.description.trim(), 'Imported from flyer scan']
            .where((s) => s.isNotEmpty)
            .join('\n\n');
        final description = desc.isEmpty ? 'Imported from flyer scan' : desc;
        newEvents.add(CalendarEvent(
          id: const Uuid().v4(),
          familyId: family.id,
          creatorId: user.id,
          title: title,
          description: description,
          location: loc.isEmpty ? null : loc,
          start: d.start,
          end: end,
          visibility: Visibility.FAMILY,
        ));
      }

      if (newEvents.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No events selected.')),
          );
        }
        return;
      }

      final db = provider.db;
      await provider.saveAndSync(
        db.copyWith(events: [...db.events, ...newEvents]),
        pushTableScope: CloudSyncScope.calendarBundle,
      );
      provider.saveAiHistory(module: 'calendar', prompt: 'Flyer scan', response: jsonEncode(decoded));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${newEvents.length} event(s) from flyer')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Flyer scan failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // ── ICS URL Import ───────────────────────────────────────────────────────

  Future<void> _showSubscribeUrlSheet() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _IcsUrlSheet(),
    );
    if (result == null || !mounted) return;

    final url = result['url']!;
    final name = result['name'] ?? 'External Calendar';

    setState(() => _isSyncing = true);
    try {
      final provider = context.read<AppProvider>();
      final user = provider.activeUser!;
      final family = provider.activeFamily!;

      final extCal = ExternalCalendar(
        id: const Uuid().v4(),
        familyId: family.id,
        userId: user.id,
        type: ExternalCalendarType.icsUrl,
        name: name,
        icsUrl: url,
        enabled: true,
      );

      final events = await CalendarSyncService.fetchIcsEvents(
        url: url,
        familyId: family.id,
        userId: user.id,
        externalCalendarId: extCal.id,
      );
      if (!mounted) return;

      final db = provider.db;
      await provider.saveAndSync(
        db.copyWith(
          externalCalendars: [...db.externalCalendars, extCal],
          events: [...db.events, ...events],
        ),
        pushTableScope: CloudSyncScope.calendarBundle,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${events.length} events from $name')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(humanizeForSnackBar('Import failed: $e')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // ── My Calendars Sheet ───────────────────────────────────────────────────

  void _showMyCalendars() {
    final provider = context.read<AppProvider>();
    final user = provider.activeUser;
    if (user == null) return;

    final myCalendars = provider.db.externalCalendars
        .where((c) => c.userId == user.id)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MyCalendarsSheet(
        calendars: myCalendars,
        onSync: _syncExternalCalendar,
        onRemove: _removeExternalCalendar,
        onConnectGoogle: _connectGoogleCalendar,
        onSubscribeUrl: _showSubscribeUrlSheet,
      ),
    );
  }

  bool _eventLayerVisible(CalendarEvent e) {
    final key = e.externalCalendarId ?? '__family__';
    return !_hiddenCalendarLayers.contains(key);
  }

  bool _canAccessEvent(CalendarEvent event, String? userId) {
    if (event.externalCalendarId != null) return true;
    if (userId == null) return false;
    if (event.creatorId == userId) return true;
    switch (event.visibility) {
      case Visibility.FAMILY:
        return true;
      case Visibility.PRIVATE:
        return false;
      case Visibility.SPECIFIC:
        return event.sharedWith.contains(userId);
    }
  }

  bool _canManageEvent(CalendarEvent event, String? userId) {
    if (event.externalCalendarId != null || userId == null) return false;
    return event.creatorId == userId;
  }

  List<CalendarEvent> _eventsForDay(
      AppProvider provider, DateTime day) {
    final familyId = provider.activeFamily?.id;
    final userId = provider.activeUser?.id;
    if (familyId == null) return [];
    return provider.db.events
        .where((e) {
          if (e.familyId != familyId || !isSameDay(e.startDate, day)) return false;
          if (!_eventLayerVisible(e)) return false;
          if (!_canAccessEvent(e, userId)) return false;
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            if (!e.title.toLowerCase().contains(q) &&
                !(e.description?.toLowerCase().contains(q) ?? false) &&
                !(e.location?.toLowerCase().contains(q) ?? false)) {
              return false;
            }
          }
          return true;
        })
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  Map<DateTime, List<CalendarEvent>> _buildEventMap(
      AppProvider provider) {
    final familyId = provider.activeFamily?.id;
    final userId = provider.activeUser?.id;
    if (familyId == null) return {};
    final map = <DateTime, List<CalendarEvent>>{};
    for (final e in provider.db.events) {
      if (e.familyId != familyId) continue;
      if (!_eventLayerVisible(e)) continue;
      if (!_canAccessEvent(e, userId)) continue;
      final key = DateTime(
          e.startDate.year, e.startDate.month, e.startDate.day);
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  void _showAddEventSheet(BuildContext context, {CalendarEvent? event}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _EventFormSheet(
        editEvent: event,
        initialDate: _selectedDay,
      ),
    );
  }

  Future<void> _deleteEvent(AppProvider provider, CalendarEvent event) async {
    if (!_canManageEvent(event, provider.activeUser?.id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can only delete events you created.')),
        );
      }
      return;
    }
    final db = provider.db;
    final events = db.events.where((e) => e.id != event.id).toList();
    await saveAndSyncWithImmediatePush(
      provider,
      db.copyWith(events: events),
      pushTableScope: CloudSyncScope.calendarBundle,
    );
  }

  Future<void> _saveEventRsvp(CalendarEvent event, String userId, _EventRsvpChoice choice) async {
    if (event.externalCalendarId != null) return;
    final provider = context.read<AppProvider>();
    final db = provider.db;
    var yes = List<String>.from(event.rsvpYesIds);
    var no = List<String>.from(event.rsvpNoIds);
    var maybe = List<String>.from(event.rsvpMaybeIds);
    yes.remove(userId);
    no.remove(userId);
    maybe.remove(userId);
    switch (choice) {
      case _EventRsvpChoice.yes:
        yes.add(userId);
        break;
      case _EventRsvpChoice.no:
        no.add(userId);
        break;
      case _EventRsvpChoice.maybe:
        maybe.add(userId);
        break;
      case _EventRsvpChoice.clear:
        break;
    }
    final updated = event.copyWith(
      rsvpYesIds: yes,
      rsvpNoIds: no,
      rsvpMaybeIds: maybe,
      updatedAt: DateTime.now(),
    );
    final events = db.events.map((e) => e.id == event.id ? updated : e).toList();
    await saveAndSyncWithImmediatePush(
      provider,
      db.copyWith(events: events),
      pushTableScope: CloudSyncScope.calendarBundle,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        if (provider.activeUser == null || provider.activeFamily == null) {
          return const ModuleFamilyLoadingScaffold();
        }
        final now = DateTime.now();
        final todayDate = DateTime(now.year, now.month, now.day);
        final selectedEvents = _eventsForDay(provider, _selectedDay);
        final eventMap = _buildEventMap(provider);
        final weekAgenda = List.generate(7, (i) {
          final d = todayDate.add(Duration(days: i));
          return (day: d, events: _eventsForDay(provider, d));
        });

        // Upcoming events (next 7 days)
        final weekEnd = todayDate.add(const Duration(days: 7));
        final upcomingEvents = provider.db.events
            .where((e) =>
                e.familyId == provider.activeFamily?.id &&
                _eventLayerVisible(e) &&
                _canAccessEvent(e, provider.activeUser?.id) &&
                e.startDate.isAfter(todayDate) &&
                e.startDate.isBefore(weekEnd))
            .toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));

        return HuddleModuleScaffold(
          modulePath: '/calendar',
          enterPullTables: CloudSyncScope.calendarBundle,
          drawer: const AppDrawer(),
          appBar: const MainAppBar(),
          child: RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: () => pullCloudLatestWithHaptic(context),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
              // Page Header
              PageHeader(
                title: screenTitleForModulePath('/calendar'),
                subtitle: 'Shared schedule with RSVPs — everyone sees who’s coming.',
                actions: [
                  ActionChipButton(
                    icon: Icons.calendar_month_outlined,
                    label: 'My Calendars',
                    onTap: _showMyCalendars,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  ActionChipButton(
                    icon: Icons.sync_rounded,
                    label: _isSyncing ? 'Syncing...' : 'Google Sync',
                    onTap: _isSyncing ? () {} : _connectGoogleCalendar,
                    isPrimary: true,
                  ),
                  ActionChipButton(
                    icon: Icons.document_scanner_outlined,
                    label: _isSyncing ? '…' : 'Scan flyer',
                    onTap: _isSyncing ? () {} : _scanFlyerForEvents,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  ActionChipButton(
                    icon: Icons.mail_outline_rounded,
                    label: _isSyncing ? '…' : 'Outlook',
                    onTap: _isSyncing ? () {} : _connectOutlookCalendar,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  ActionChipButton(
                    icon: Icons.share_rounded,
                    label: 'Share agenda',
                    onTap: () => _shareFamilyAgenda(context),
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                ],
              ),

              // Layer visibility (family vs connected calendars)
              Builder(builder: (ctx) {
                final uid = provider.activeUser?.id;
                final ext = uid == null
                    ? <ExternalCalendar>[]
                    : provider.db.externalCalendars
                        .where((c) => c.userId == uid)
                        .toList();
                if (ext.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SHOW LAYERS',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          FilterChip(
                            label: const Text('Family', style: TextStyle(fontFamily: 'Inter', fontSize: 12)),
                            selected: !_hiddenCalendarLayers.contains('__family__'),
                            onSelected: (v) => setState(() {
                              if (v) {
                                _hiddenCalendarLayers.remove('__family__');
                              } else {
                                _hiddenCalendarLayers.add('__family__');
                              }
                            }),
                          ),
                          ...ext.map((c) => FilterChip(
                                label: Text(c.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 12)),
                                selected: !_hiddenCalendarLayers.contains(c.id),
                                onSelected: (v) => setState(() {
                                  if (v) {
                                    _hiddenCalendarLayers.remove(c.id);
                                  } else {
                                    _hiddenCalendarLayers.add(c.id);
                                  }
                                }),
                              )),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              // Add event + AI plan row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showAddEventSheet(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.stone800,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, size: 18, color: Colors.white),
                              SizedBox(width: 8),
                              Text('New Event', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _showEventPlannerWizard,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFC026D3)]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text('AI Plan', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Event search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) {
                    _searchDebounce.run(() {
                      if (!mounted) return;
                      setState(() => _searchQuery = v);
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search events...',
                    hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.stone400),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () { _searchDebounce.cancel(); _searchCtrl.clear(); setState(() => _searchQuery = ''); })
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // AI Event Strategist card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF7C3AED), Color(0xFFC026D3)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'AI Event Strategist',
                                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      'Quick event or use ',
                                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                                    ),
                                    GestureDetector(
                                      onTap: _showEventPlannerWizard,
                                      child: const Text(
                                        'Plan Event',
                                        style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white),
                                      ),
                                    ),
                                    Text(
                                      ' for full wizard',
                                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _aiController,
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'e.g., Birthday party for Alex next Saturday...',
                                hintStyle: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.15),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                prefixIcon: Icon(Icons.edit_outlined, size: 16, color: Colors.white.withValues(alpha: 0.6)),
                              ),
                              onSubmitted: (_) => _handleAiQuickPlan(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _isAiLoading ? null : _handleAiQuickPlan,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: _isAiLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(Color(0xFF7C3AED)),
                                      ),
                                    )
                                  : const Text(
                                      'Quick Plan',
                                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF7C3AED)),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      if (_aiError != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _aiError!,
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Calendar in a white card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.stone100),
                  ),
                  child: Column(
                    children: [
                      // Today button row
                      if (!isSameDay(_focusedDay, DateTime.now()))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _focusedDay = DateTime.now();
                                _selectedDay = DateTime.now();
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.today_rounded, size: 14, color: AppTheme.primary),
                                    SizedBox(width: 4),
                                    Text('Today', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      RepaintBoundary(
                    child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: TableCalendar<CalendarEvent>(
                      firstDay: DateTime.utc(2020, 1, 1),
                      lastDay: DateTime.utc(2030, 12, 31),
                      focusedDay: _focusedDay,
                      calendarFormat: _calFormat,
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDay, day),
                      eventLoader: (day) {
                        final key = DateTime(day.year, day.month, day.day);
                        return eventMap[key] ?? [];
                      },
                      onDaySelected: (selected, focused) {
                        setState(() {
                          _selectedDay = selected;
                          _focusedDay = focused;
                        });
                      },
                      onFormatChanged: (format) {
                        setState(() => _calFormat = format);
                      },
                      onPageChanged: (focused) {
                        _focusedDay = focused;
                      },
                      calendarStyle: CalendarStyle(
                        selectedDecoration: const BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                        ),
                        todayDecoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        todayTextStyle: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                        ),
                        selectedTextStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                        ),
                        defaultTextStyle: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppTheme.stone800,
                        ),
                        weekendTextStyle: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppTheme.stone600,
                        ),
                        outsideTextStyle: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppTheme.stone300,
                        ),
                        markerDecoration: const BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                        ),
                        markerSize: 6,
                        markersMaxCount: 3,
                      ),
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: true,
                        titleCentered: true,
                        formatButtonDecoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius:
                              BorderRadius.all(Radius.circular(12)),
                        ),
                        formatButtonTextStyle: TextStyle(
                          color: AppTheme.primary,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        titleTextStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppTheme.stone900,
                        ),
                        leftChevronIcon: Icon(Icons.chevron_left,
                            color: AppTheme.stone600),
                        rightChevronIcon: Icon(Icons.chevron_right,
                            color: AppTheme.stone600),
                      ),
                      daysOfWeekStyle: const DaysOfWeekStyle(
                        weekdayStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: AppTheme.stone500,
                        ),
                        weekendStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: AppTheme.stone400,
                        ),
                      ),
                    ),
                  ),
                ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Week agenda (mobile-friendly)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'THIS WEEK',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.stone400,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${weekAgenda.fold<int>(0, (s, x) => s + x.events.length)} events',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.stone300,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...weekAgenda.map((row) {
                      final d = row.day;
                      final evs = row.events;
                      final isSel = isSameDay(d, _selectedDay);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() {
                              _selectedDay = d;
                              _focusedDay = d;
                            }),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSel ? AppTheme.primary : AppTheme.stone100,
                                  width: isSel ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        isSameDay(d, todayDate)
                                            ? 'Today'
                                            : DateFormat('EEE, MMM d').format(d),
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: isSel ? AppTheme.primary : AppTheme.stone800,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (evs.isNotEmpty)
                                        Text(
                                          '${evs.length}',
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.stone400,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (evs.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        'Nothing scheduled',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 12,
                                          color: AppTheme.stone400.withValues(alpha: 0.9),
                                        ),
                                      ),
                                    )
                                  else
                                    ...evs.take(4).map((e) => Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                DateFormat('h:mm a').format(e.startDate),
                                                style: const TextStyle(
                                                  fontFamily: 'Inter',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.stone500,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  e.title,
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme.stone800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )),
                                  if (evs.length > 4)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        '+ ${evs.length - 4} more',
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // External calendars section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EXTERNAL CALENDARS',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 8),
                    // Connected calendars
                    ..._buildConnectedCalendars(provider),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.stone100),
                      ),
                      child: Column(
                        children: [
                          _buildImportOption(
                            Icons.account_circle_rounded,
                            'Connect Google Calendar',
                            'Sync events from your Google account',
                            onTap: _isSyncing ? null : _connectGoogleCalendar,
                          ),
                          const Divider(height: 1),
                          _buildImportOption(
                            Icons.link_rounded,
                            'Subscribe via URL',
                            'Import from an .ics calendar feed',
                            onTap: _showSubscribeUrlSheet,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Selected day events
              HuddlePagePadding(
                horizontal: 20,
                child: HuddleSectionHeader(
                  overline: isSameDay(_selectedDay, todayDate) ? 'Today' : 'Selected',
                  title: DateFormat('EEEE, MMMM d').format(_selectedDay),
                  trailing: selectedEvents.isNotEmpty
                      ? Text(
                          '${selectedEvents.length}',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.stone300,
                              ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    if (selectedEvents.isEmpty)
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.stone100),
                        ),
                        child: CatalogModuleEmptyState(
                          modulePath: '/calendar',
                          title: 'Nothing scheduled',
                          subtitle:
                              'Add an event for this day, or connect a calendar above.',
                          compact: true,
                          emojiSize: 40,
                          actionLabel: 'New event',
                          onAction: () => _showAddEventSheet(context),
                        ),
                      )
                    else
                      ...selectedEvents.map((event) => _EventCard(
                        event: event,
                        provider: provider,
                        currentUserId: provider.activeUser?.id,
                        canManage: _canManageEvent(event, provider.activeUser?.id),
                        onEdit: () => _showAddEventSheet(context, event: event),
                        onDelete: () => _deleteEvent(provider, event),
                        onRsvp: provider.activeUser?.id != null
                            ? (choice) => _saveEventRsvp(event, provider.activeUser!.id, choice)
                            : null,
                      )),
                  ],
                ),
              ),

              // Upcoming events
              if (upcomingEvents.isNotEmpty) ...[
                const SizedBox(height: 20),
                HuddlePagePadding(
                  horizontal: 20,
                  child: HuddleSectionHeader(
                    overline: 'This week',
                    title: 'Coming up',
                    trailing: Text(
                      '${upcomingEvents.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.stone300,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: upcomingEvents.map((event) => _EventCard(
                      event: event,
                      provider: provider,
                      currentUserId: provider.activeUser?.id,
                      canManage: _canManageEvent(event, provider.activeUser?.id),
                      onEdit: () => _showAddEventSheet(context, event: event),
                      onDelete: () => _deleteEvent(provider, event),
                      showDate: true,
                      onRsvp: provider.activeUser?.id != null
                          ? (choice) => _saveEventRsvp(event, provider.activeUser!.id, choice)
                          : null,
                    )).toList(),
                  ),
                ),
              ],

              const SizedBox(height: 100),
            ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildConnectedCalendars(AppProvider provider) {
    final user = provider.activeUser;
    if (user == null) return [];
    final calendars = provider.db.externalCalendars
        .where((c) => c.userId == user.id)
        .toList();
    if (calendars.isEmpty) return [];

    return [
      ...calendars.map((cal) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(children: [
          Builder(builder: (_) {
            final (Color bg, Color fg, IconData ic) = switch (cal.type) {
              ExternalCalendarType.google => (
                  const Color(0xFF4285F4).withValues(alpha: 0.1),
                  const Color(0xFF4285F4),
                  Icons.account_circle_rounded,
                ),
              ExternalCalendarType.microsoft => (
                  const Color(0xFF0078D4).withValues(alpha: 0.12),
                  const Color(0xFF0078D4),
                  Icons.mail_outline_rounded,
                ),
              ExternalCalendarType.icsUrl => (
                  AppTheme.primary.withValues(alpha: 0.1),
                  AppTheme.primary,
                  Icons.link_rounded,
                ),
            };
            return Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(ic, size: 18, color: fg),
            );
          }),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cal.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone800)),
              Text(
                'Last synced ${_timeAgo(cal.lastSyncedAt)}',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400),
              ),
            ],
          )),
          GestureDetector(
            onTap: _isSyncing ? null : () => _syncExternalCalendar(cal),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.sync_rounded, size: 18, color: _isSyncing ? AppTheme.stone300 : AppTheme.primary),
            ),
          ),
          GestureDetector(
            onTap: () => _removeExternalCalendar(cal),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close_rounded, size: 18, color: AppTheme.stone400),
            ),
          ),
        ]),
      )),
      const SizedBox(height: 4),
    ];
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildImportOption(IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.stone50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppTheme.stone500),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.stone300),
          ],
        ),
      ),
    );
  }
}

class _FlyerEventsPreviewSheet extends StatefulWidget {
  const _FlyerEventsPreviewSheet({
    required this.imageBytes,
    required this.drafts,
  });

  final Uint8List imageBytes;
  final List<_FlyerEventDraft> drafts;

  @override
  State<_FlyerEventsPreviewSheet> createState() => _FlyerEventsPreviewSheetState();
}

class _FlyerEventsPreviewSheetState extends State<_FlyerEventsPreviewSheet> {
  late List<_FlyerEventDraft> _rows;
  final List<TextEditingController> _titleCtrls = [];
  final List<TextEditingController> _locCtrls = [];

  @override
  void initState() {
    super.initState();
    _rows = widget.drafts
        .map(
          (d) => _FlyerEventDraft(
            selected: d.selected,
            title: d.title,
            start: d.start,
            end: d.end,
            location: d.location,
            description: d.description,
          ),
        )
        .toList();
    for (final r in _rows) {
      _titleCtrls.add(TextEditingController(text: r.title));
      _locCtrls.add(TextEditingController(text: r.location));
    }
  }

  @override
  void dispose() {
    for (final c in _titleCtrls) {
      c.dispose();
    }
    for (final c in _locCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllersToRows() {
    for (var i = 0; i < _rows.length; i++) {
      _rows[i].title = _titleCtrls[i].text;
      _rows[i].location = _locCtrls[i].text;
    }
  }

  List<_FlyerEventDraft> _collectRows() {
    _syncControllersToRows();
    return _rows;
  }

  String _rangeLabel(_FlyerEventDraft d) {
    final a = DateFormat.yMMMd().add_jm().format(d.start);
    final b = DateFormat.jm().format(d.end);
    return '$a – $b';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        minChildSize: 0.45,
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Review flyer events',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    widget.imageBytes,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Uncheck any row you do not want on the calendar. You can edit titles and locations.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: _rows.length,
                  itemBuilder: (ctx, i) {
                    final r = _rows[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: r.selected,
                              onChanged: (v) => setState(() => r.selected = v ?? false),
                              controlAffinity: ListTileControlAffinity.leading,
                              title: TextField(
                                controller: _titleCtrls[i],
                                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15),
                                decoration: const InputDecoration(
                                  hintText: 'Event title',
                                  isDense: true,
                                  border: InputBorder.none,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _rangeLabel(r),
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone600),
                                ),
                              ),
                            ),
                            if (r.description.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 52, bottom: 6),
                                child: Text(
                                  r.description.trim(),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(left: 52),
                              child: TextField(
                                controller: _locCtrls[i],
                                decoration: const InputDecoration(
                                  labelText: 'Location',
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context, _collectRows());
                    },
                    child: const Text('Add selected to calendar'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Event card ───────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  final CalendarEvent event;
  final AppProvider provider;
  final String? currentUserId;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<void> Function(_EventRsvpChoice choice)? onRsvp;
  final bool showDate;

  const _EventCard({
    required this.event,
    required this.provider,
    this.currentUserId,
    this.canManage = false,
    required this.onEdit,
    required this.onDelete,
    this.onRsvp,
    this.showDate = false,
  });

  Color _visibilityColor() {
    if (event.externalCalendarId != null) return const Color(0xFF4285F4);
    return event.visibility == Visibility.PRIVATE
        ? AppTheme.primary
        : const Color(0xFF8B5CF6);
  }

  String _timeLabel() {
    if (event.allDay) return 'All day';
    final start = DateFormat('h:mm a').format(event.startDate);
    if (isSameDay(event.startDate, event.endDate)) {
      final end = DateFormat('h:mm a').format(event.endDate);
      return '$start - $end';
    }
    return start;
  }

  Widget _rsvpChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required String semanticsLabel,
  }) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.stone50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.stone200,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? AppTheme.primary : AppTheme.stone600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creator = provider.userById(event.createdBy);
    final color = _visibilityColor();
    final isExternal = event.externalCalendarId != null;
    final uid = currentUserId;
    final showRsvp = !isExternal && uid != null && onRsvp != null && event.visibility == Visibility.FAMILY;
    _EventRsvpChoice? myChoice;
    if (showRsvp) {
      if (event.rsvpYesIds.contains(uid)) {
        myChoice = _EventRsvpChoice.yes;
      } else if (event.rsvpNoIds.contains(uid)) {
        myChoice = _EventRsvpChoice.no;
      } else if (event.rsvpMaybeIds.contains(uid)) {
        myChoice = _EventRsvpChoice.maybe;
      }
    }
    final yesCount = event.rsvpYesIds.length;
    final noCount = event.rsvpNoIds.length;
    final maybeCount = event.rsvpMaybeIds.length;

    return Dismissible(
      key: Key(event.id),
      direction: (!isExternal && canManage)
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Delete', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.error)),
            SizedBox(width: 8),
            Icon(Icons.delete_outline_rounded, color: AppTheme.error),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        if (!canManage) return false;
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Event'),
            content: Text('Delete "${event.title}"?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: (!isExternal && canManage) ? onEdit : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.stone100),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Color bar
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                event.title,
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.stone900),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isExternal
                                    ? 'Synced'
                                    : event.visibility == Visibility.PRIVATE ? 'Personal' : 'Family',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color, fontFamily: 'Inter'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            if (showDate)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today_outlined, size: 12, color: AppTheme.stone400),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat('MMM d').format(event.startDate),
                                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                                  ),
                                ],
                              ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time_rounded, size: 12, color: AppTheme.stone400),
                                const SizedBox(width: 4),
                                Text(_timeLabel(), style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
                              ],
                            ),
                            if (event.location != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 12, color: AppTheme.stone400),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      event.location!,
                                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        if (event.description != null && event.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            event.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                          ),
                        ],
                        if (event.location != null && event.location!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _EventWeatherRow(query: event.location!.trim(), day: event.startDate),
                        ],
                        if (!isExternal && canManage) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 0,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () async {
                                  final u = Uri.parse(CalendarExternalLinks.googleCalendarComposeUrl(event));
                                  if (await canLaunchUrl(u)) {
                                    await launchUrl(u, mode: LaunchMode.externalApplication);
                                  }
                                },
                                icon: const Icon(Icons.event_available_outlined, size: 14),
                                label: const Text('Google', style: TextStyle(fontFamily: 'Inter', fontSize: 11)),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () async {
                                  final u = Uri.parse(CalendarExternalLinks.outlookComposeUrl(event));
                                  if (await canLaunchUrl(u)) {
                                    await launchUrl(u, mode: LaunchMode.externalApplication);
                                  }
                                },
                                icon: const Icon(Icons.mail_outline, size: 14),
                                label: const Text('Outlook', style: TextStyle(fontFamily: 'Inter', fontSize: 11)),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () async {
                                  final u = Uri.parse(
                                    CalendarExternalLinks.openTableSearchUrl('${event.title} ${event.location ?? ''}'),
                                  );
                                  if (await canLaunchUrl(u)) {
                                    await launchUrl(u, mode: LaunchMode.externalApplication);
                                  }
                                },
                                icon: const Icon(Icons.restaurant_outlined, size: 14),
                                label: const Text('Reserve', style: TextStyle(fontFamily: 'Inter', fontSize: 11)),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () async {
                                  final gid = await CalendarSyncService.insertPrimaryGoogleEvent(event);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        gid != null
                                            ? 'Saved to your Google Calendar (id: ${gid.substring(0, gid.length > 8 ? 8 : gid.length)}…)'
                                            : 'Could not save to Google. Sign in to Google Calendar from My Calendars first.',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.cloud_upload_outlined, size: 14),
                                label: const Text('Push GCal', style: TextStyle(fontFamily: 'Inter', fontSize: 11)),
                              ),
                            ],
                          ),
                        ],
                        if (creator != null && !isExternal) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              AvatarInitials(name: creator.name, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                creator.name.split(' ').first,
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400),
                              ),
                            ],
                          ),
                        ],
                        if (showRsvp) ...[
                          const SizedBox(height: 10),
                          Text(
                            'RSVP · $yesCount going · $maybeCount maybe · $noCount can\'t',
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.stone500),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _rsvpChip(
                                label: 'Going',
                                selected: myChoice == _EventRsvpChoice.yes,
                                semanticsLabel: 'RSVP going for ${event.title}',
                                onTap: () => onRsvp!(_EventRsvpChoice.yes),
                              ),
                              _rsvpChip(
                                label: 'Maybe',
                                selected: myChoice == _EventRsvpChoice.maybe,
                                semanticsLabel: 'RSVP maybe for ${event.title}',
                                onTap: () => onRsvp!(_EventRsvpChoice.maybe),
                              ),
                              _rsvpChip(
                                label: 'Can\'t',
                                selected: myChoice == _EventRsvpChoice.no,
                                semanticsLabel: 'RSVP can\'t go for ${event.title}',
                                onTap: () => onRsvp!(_EventRsvpChoice.no),
                              ),
                              if (myChoice != null)
                                _rsvpChip(
                                  label: 'Clear',
                                  selected: false,
                                  semanticsLabel: 'Clear RSVP for ${event.title}',
                                  onTap: () => onRsvp!(_EventRsvpChoice.clear),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Family members see responses here — updates sync for everyone.',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              height: 1.35,
                              color: AppTheme.stone400.withValues(alpha: 0.95),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Event form bottom sheet ──────────────────────────────────────────────────

class _EventFormSheet extends StatefulWidget {
  final CalendarEvent? editEvent;
  final DateTime initialDate;

  const _EventFormSheet({this.editEvent, required this.initialDate});

  @override
  State<_EventFormSheet> createState() => _EventFormSheetState();
}

class _EventFormSheetState extends State<_EventFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _locationCtrl;

  late DateTime _startDate;
  late DateTime _endDate;
  bool _allDay = false;
  Visibility _visibility = Visibility.FAMILY;
  List<String> _sharedWith = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editEvent;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');

    if (e != null) {
      _startDate = e.startDate;
      _endDate = e.endDate;
      _allDay = e.allDay;
      _visibility = e.visibility;
      _sharedWith = List.from(e.sharedWith);
    } else {
      final base = DateTime(widget.initialDate.year,
          widget.initialDate.month, widget.initialDate.day, 9, 0);
      _startDate = base;
      _endDate = base.add(const Duration(hours: 1));
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (pickedDate == null) return;

    if (_allDay) {
      setState(() {
        if (isStart) {
          _startDate = pickedDate;
          if (_endDate.isBefore(_startDate)) _endDate = _startDate;
        } else {
          _endDate = pickedDate;
        }
      });
      return;
    }

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          isStart ? _startDate : _endDate),
    );
    if (pickedTime == null) return;

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      if (isStart) {
        _startDate = combined;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate.add(const Duration(hours: 1));
        }
      } else {
        _endDate = combined;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      final provider = context.read<AppProvider>();
      final db = provider.db;
      const uuid = Uuid();

      final event = CalendarEvent(
        id: widget.editEvent?.id ?? uuid.v4(),
        familyId: provider.activeFamily!.id,
        creatorId: widget.editEvent?.creatorId ??
            provider.activeUser!.id,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        location: _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        start: _startDate,
        end: _allDay ? _startDate : _endDate,
        visibility: _visibility,
        sharedWith: _sharedWith,
      );

      List<CalendarEvent> events;
      if (widget.editEvent != null) {
        events = db.events
            .map((e) => e.id == event.id ? event : e)
            .toList();
      } else {
        events = [...db.events, event];
      }
      await saveAndSyncWithImmediatePush(
        provider,
        db.copyWith(events: events),
        pushTableScope: CloudSyncScope.calendarBundle,
      );
      if (widget.editEvent == null) {
        NotificationService.notifyFamilyActivityWithDb(
          provider.db,
          title: 'New calendar event',
          body: '${provider.activeUser?.name ?? "Someone"} added ${event.title} in ${AppConfig.appName}.',
          path: '/calendar',
          familyId: provider.activeFamily?.id,
          excludeUserId: provider.activeUser?.id,
        );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            widget.editEvent != null ? Icons.edit_outlined : Icons.event_rounded,
                            size: 18,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          widget.editEvent != null ? 'Edit Event' : 'New Event',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _titleCtrl,
                      autofocus: widget.editEvent == null,
                      textCapitalization: TextCapitalization.sentences,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                      decoration: const InputDecoration(labelText: 'Event title'),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'What is this event about?',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _locationCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        hintText: 'Where is it?',
                        prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Schedule section
                    const Text('Schedule', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700)),
                    const SizedBox(height: 8),

                    // All day toggle
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.stone50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.stone200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wb_sunny_outlined, size: 16, color: AppTheme.stone500),
                          const SizedBox(width: 8),
                          const Text('All day', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.stone700)),
                          const Spacer(),
                          Switch(
                            value: _allDay,
                            onChanged: (v) => setState(() => _allDay = v),
                            activeThumbColor: AppTheme.surface, // FIXED: activeColor deprecated
                            activeTrackColor: AppTheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Start
                    _dateTimeRow(
                      label: 'Start',
                      dateTime: _startDate,
                      onTap: () => _pickDateTime(isStart: true),
                    ),
                    const SizedBox(height: 8),

                    // End
                    if (!_allDay)
                      _dateTimeRow(
                        label: 'End',
                        dateTime: _endDate,
                        onTap: () => _pickDateTime(isStart: false),
                      ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 12),

                    // Visibility section
                    const Text('Visibility', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700)),
                    const SizedBox(height: 8),
                    SharePicker(
                      members: context.read<AppProvider>().familyMembers
                          .map((m) => SharePickerMember(id: m.id, name: m.name))
                          .toList(),
                      initialVisibility: _visibility,
                      initialSharedWith: _sharedWith,
                      onChanged: (result) => setState(() {
                        _visibility = result.visibility;
                        _sharedWith = result.sharedWith;
                      }),
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: _loading ? null : _save,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                    Colors.white),
                              ),
                            )
                          : Text(widget.editEvent != null ? 'Save Changes' : 'Create Event'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateTimeRow({
    required String label,
    required DateTime dateTime,
    required VoidCallback onTap,
  }) {
    final dateStr = DateFormat('EEE, MMM d').format(dateTime);
    final timeStr = _allDay ? '' : DateFormat('h:mm a').format(dateTime);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.stone50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.stone200),
        ),
        child: Row(
          children: [
            Icon(
              label == 'Start' ? Icons.play_circle_outline_rounded : Icons.stop_circle_outlined,
              size: 16, color: AppTheme.stone500,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _allDay ? dateStr : '$dateStr at $timeStr',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone800),
              ),
            ),
            const Icon(Icons.edit_outlined, size: 14, color: AppTheme.stone400),
          ],
        ),
      ),
    );
  }
}

// ─── Google Calendar Picker ──────────────────────────────────────────────────

class _GoogleCalendarPicker extends StatefulWidget {
  final List<dynamic> calendars; // gcal.CalendarListEntry items

  const _GoogleCalendarPicker({required this.calendars});

  @override
  State<_GoogleCalendarPicker> createState() => _GoogleCalendarPickerState();
}

class _GoogleCalendarPickerState extends State<_GoogleCalendarPicker> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(children: [
              const Expanded(
                child: Text(
                  'Select Google Calendars',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                ),
              ),
              TextButton(
                onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.toList()),
                child: Text(
                  'Import (${_selected.length})',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    color: _selected.isEmpty ? AppTheme.stone300 : AppTheme.primary,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              itemCount: widget.calendars.length,
              itemBuilder: (ctx, i) {
                final cal = widget.calendars[i];
                final calId = (cal as dynamic).id as String? ?? '';
                final name = (cal as dynamic).summary as String? ?? 'Calendar';
                final isSelected = _selected.contains(calId);

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selected.remove(calId);
                      } else {
                        _selected.add(calId);
                      }
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary.withValues(alpha: 0.05) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppTheme.primary : AppTheme.stone100,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4285F4).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF4285F4)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800),
                        ),
                      ),
                      Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                        color: isSelected ? AppTheme.primary : AppTheme.stone300,
                        size: 22,
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── ICS URL Subscribe Sheet ─────────────────────────────────────────────────

class _IcsUrlSheet extends StatefulWidget {
  const _IcsUrlSheet();

  @override
  State<_IcsUrlSheet> createState() => _IcsUrlSheetState();
}

class _IcsUrlSheetState extends State<_IcsUrlSheet> {
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a calendar URL'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (!url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('webcal://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid URL')),
      );
      return;
    }

    final normalizedUrl = url.replaceFirst('webcal://', 'https://');
    setState(() => _loading = true);

    String name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      try {
        final response = await http.get(Uri.parse(normalizedUrl));
        if (response.statusCode == 200) {
          name = CalendarSyncService.extractIcsCalendarName(response.body) ?? 'External Calendar';
        } else {
          name = 'External Calendar';
        }
      } catch (_) {
        name = 'External Calendar';
      }
    }

    if (mounted) {
      Navigator.pop(context, {'url': normalizedUrl, 'name': name});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Subscribe via URL',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Paste an .ics calendar feed URL to import events. Supports Google Calendar, Outlook, Apple Calendar, and other iCal feeds.',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _urlCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Calendar URL *',
                      hintText: 'https://calendar.google.com/.../.ics',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Calendar Name (optional)',
                      hintText: 'Work Calendar',
                      prefixIcon: Icon(Icons.label_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(_loading ? 'Importing...' : 'Import Calendar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── My Calendars Sheet ──────────────────────────────────────────────────────

class _MyCalendarsSheet extends StatelessWidget {
  final List<ExternalCalendar> calendars;
  final Future<void> Function(ExternalCalendar) onSync;
  final Future<void> Function(ExternalCalendar) onRemove;
  final VoidCallback onConnectGoogle;
  final VoidCallback onSubscribeUrl;

  const _MyCalendarsSheet({
    required this.calendars,
    required this.onSync,
    required this.onRemove,
    required this.onConnectGoogle,
    required this.onSubscribeUrl,
  });

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              const Expanded(
                child: Text(
                  'My Calendars',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.stone400),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                // Local calendar
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.calendar_today_rounded, size: 18, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Huddle Calendar', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.stone900)),
                        Text('Local events', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                      ],
                    )),
                    Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.primary),
                  ]),
                ),

                // External calendars
                ...calendars.map((cal) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.stone100),
                  ),
                  child: Row(children: [
                    Builder(builder: (_) {
                      final (Color bg, Color fg, IconData ic) = switch (cal.type) {
                        ExternalCalendarType.google => (
                            const Color(0xFF4285F4).withValues(alpha: 0.1),
                            const Color(0xFF4285F4),
                            Icons.account_circle_rounded,
                          ),
                        ExternalCalendarType.microsoft => (
                            const Color(0xFF0078D4).withValues(alpha: 0.12),
                            const Color(0xFF0078D4),
                            Icons.mail_outline_rounded,
                          ),
                        ExternalCalendarType.icsUrl => (
                            AppTheme.primary.withValues(alpha: 0.1),
                            AppTheme.primary,
                            Icons.link_rounded,
                          ),
                      };
                      return Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(ic, size: 18, color: fg),
                      );
                    }),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cal.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800)),
                        Text(
                          '${switch (cal.type) {
                            ExternalCalendarType.google => 'Google',
                            ExternalCalendarType.microsoft => 'Outlook',
                            ExternalCalendarType.icsUrl => 'URL feed',
                          }} \u00b7 Synced ${_timeAgo(cal.lastSyncedAt)}',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400),
                        ),
                      ],
                    )),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        onSync(cal);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.sync_rounded, size: 18, color: AppTheme.primary),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        onRemove(cal);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
                      ),
                    ),
                  ]),
                )),

                const SizedBox(height: 16),
                const Text(
                  'ADD CALENDAR',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onConnectGoogle();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.stone100),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4285F4).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.account_circle_rounded, size: 18, color: Color(0xFF4285F4)),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Google Calendar', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800)),
                          Text('Sign in and sync your Google calendars', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                        ],
                      )),
                      const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppTheme.stone400),
                    ]),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onSubscribeUrl();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.stone100),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.link_rounded, size: 18, color: AppTheme.primary),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Subscribe via URL', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800)),
                          Text('Import from .ics calendar feed', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                        ],
                      )),
                      const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppTheme.stone400),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Event Planner Wizard ────────────────────────────────────────────────────

class _EventPlannerWizard extends StatefulWidget {
  const _EventPlannerWizard();

  @override
  State<_EventPlannerWizard> createState() => _EventPlannerWizardState();
}

const _eventTemplates = [
  {'id': 'birthday', 'label': 'Birthday Party', 'icon': Icons.cake_rounded, 'color': Color(0xFFFCE7F3), 'iconColor': Color(0xFFDB2777)},
  {'id': 'bbq', 'label': 'BBQ / Cookout', 'icon': Icons.outdoor_grill_rounded, 'color': Color(0xFFFFF7ED), 'iconColor': Color(0xFFEA580C)},
  {'id': 'game-night', 'label': 'Game Night', 'icon': Icons.sports_esports_rounded, 'color': Color(0xFFF3E8FF), 'iconColor': Color(0xFF9333EA)},
  {'id': 'holiday', 'label': 'Holiday Gathering', 'icon': Icons.park_rounded, 'color': Color(0xFFF0FDF4), 'iconColor': Color(0xFF16A34A)},
  {'id': 'baby-shower', 'label': 'Baby Shower', 'icon': Icons.child_care_rounded, 'color': Color(0xFFF0F9FF), 'iconColor': Color(0xFF0284C7)},
  {'id': 'graduation', 'label': 'Graduation', 'icon': Icons.school_rounded, 'color': Color(0xFFFFFBEB), 'iconColor': Color(0xFFD97706)},
  {'id': 'anniversary', 'label': 'Anniversary', 'icon': Icons.favorite_rounded, 'color': Color(0xFFFEF2F2), 'iconColor': Color(0xFFDC2626)},
  {'id': 'other', 'label': 'Other Event', 'icon': Icons.people_rounded, 'color': Color(0xFFF5F5F4), 'iconColor': Color(0xFF57534E)},
];

class _EventPlannerWizardState extends State<_EventPlannerWizard> {
  int _step = 0; // 0 = template, 1 = details, 2 = results
  String _selectedTemplate = '';

  final _nameCtrl = TextEditingController();
  final _guestCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _eventDate = DateTime.now().add(const Duration(days: 7));

  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _planResult;
  int _createdTaskCount = 0;
  int _createdListCount = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _guestCtrl.dispose();
    _budgetCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _selectTemplate(Map<String, Object> template) {
    setState(() {
      _selectedTemplate = template['id'] as String;
      if (_nameCtrl.text.isEmpty && _selectedTemplate != 'other') {
        _nameCtrl.text = template['label'] as String;
      }
      _step = 1;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _eventDate = picked);
  }

  Future<void> _generatePlan() async {
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.calendar)) return;
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an event name'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final provider = context.read<AppProvider>();
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await AiService.planFullEvent(
        template: _selectedTemplate,
        eventName: _nameCtrl.text.trim(),
        date: DateFormat('yyyy-MM-dd').format(_eventDate),
        guestCount: _guestCtrl.text.trim(),
        budget: _budgetCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        familyId: family.id,
      );

      if (!mounted) return;
      if (result == null) {
        setState(() {
          _isLoading = false;
          _error = 'AI event planning failed. Please try again.';
        });
        return;
      }
      provider.saveAiHistory(module: 'calendar', prompt: 'Plan event: "${_nameCtrl.text.trim()}"', response: jsonEncode(result));

      // Create calendar event
      final eventDate = DateTime(_eventDate.year, _eventDate.month, _eventDate.day, 12);
      final event = CalendarEvent(
        id: const Uuid().v4(),
        familyId: family.id,
        creatorId: user.id,
        title: _nameCtrl.text.trim(),
        description: result['description']?.toString() ?? '',
        location: result['location_suggestion']?.toString(),
        start: eventDate,
        end: eventDate.add(const Duration(hours: 4)),
        visibility: Visibility.FAMILY,
      );

      // Create tasks from AI result
      final aiTasks = (result['tasks'] as List<dynamic>?) ?? [];
      final eventTag = _nameCtrl.text.trim();
      final newTasks = aiTasks.map((t) {
        final taskMap = t as Map<String, dynamic>;
        final daysBefore = (taskMap['daysBefore'] as num?)?.toInt() ?? 0;
        final priorityStr = taskMap['priority']?.toString().toUpperCase() ?? 'MEDIUM';
        return Task(
          id: const Uuid().v4(),
          familyId: family.id,
          creatorId: user.id,
          title: taskMap['title']?.toString() ?? '',
          dueDate: eventDate.subtract(Duration(days: daysBefore)),
          priority: priorityStr == 'HIGH' ? Priority.HIGH : priorityStr == 'LOW' ? Priority.LOW : Priority.MEDIUM,
          completed: false,
          visibility: Visibility.FAMILY,
          assignees: [user.id],
          tags: [eventTag, 'Event'],
        );
      }).toList();

      // Create lists from AI result
      final aiLists = (result['lists'] as List<dynamic>?) ?? [];
      final newLists = aiLists.map((l) {
        final listMap = l as Map<String, dynamic>;
        final aiItems = (listMap['items'] as List<dynamic>?) ?? [];
        return ShoppingList(
          id: const Uuid().v4(),
          familyId: family.id,
          creatorId: user.id,
          title: '${_nameCtrl.text.trim()}: ${listMap['title'] ?? 'List'}',
          category: listMap['category']?.toString().toUpperCase() == 'GROCERY'
              ? ListCategory.GROCERY
              : ListCategory.OTHER,
          visibility: Visibility.FAMILY,
          items: aiItems.map((item) {
            final itemMap = item as Map<String, dynamic>;
            return ListItem(
              id: const Uuid().v4(),
              text: itemMap['text']?.toString() ?? '',
              quantity: itemMap['quantity']?.toString(),
            );
          }).toList(),
        );
      }).toList();

      final db = provider.db;
      await provider.saveAndSync(
        db.copyWith(
          events: [...db.events, event],
          tasks: [...db.tasks, ...newTasks],
          lists: [...db.lists, ...newLists],
        ),
        pushTableScope: CloudSyncScope.eventPlannerAiBundle,
      );

      if (!mounted) return;
      setState(() {
        _planResult = result;
        _createdTaskCount = newTasks.length;
        _createdListCount = newLists.length;
        _step = 2;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Planning failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFFC026D3)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Event Planner Wizard',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                            ),
                            Text(
                              _step == 0 ? 'Choose an event type' : _step == 1 ? 'Fill in the details' : 'Your plan is ready!',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500),
                            ),
                          ],
                        ),
                      ),
                      // Step indicator
                      Row(
                        children: List.generate(3, (i) => Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i <= _step ? const Color(0xFF7C3AED) : AppTheme.stone200,
                          ),
                        )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (_step == 0) _buildTemplateStep(),
                  if (_step == 1) _buildDetailsStep(),
                  if (_step == 2) _buildResultsStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateStep() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _eventTemplates.map((t) {
        return GestureDetector(
          onTap: () => _selectTemplate(t),
          child: Container(
            width: (MediaQuery.of(context).size.width - 60) / 2,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t['color'] as Color,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: (t['iconColor'] as Color).withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(t['icon'] as IconData, size: 22, color: t['iconColor'] as Color),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    t['label'] as String,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: t['iconColor'] as Color),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDetailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Event Name *',
            hintText: "What's the occasion?",
            prefixIcon: Icon(Icons.celebration_rounded),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickDate,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.stone50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.stone200),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 18, color: AppTheme.stone500),
                const SizedBox(width: 12),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(_eventDate),
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone800),
                ),
                const Spacer(),
                const Icon(Icons.edit_outlined, size: 16, color: AppTheme.stone400),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _guestCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Guests',
                  hintText: '20',
                  prefixIcon: Icon(Icons.people_rounded),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _budgetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Budget',
                  hintText: '\$200',
                  prefixIcon: Icon(Icons.attach_money_rounded),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notesCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Additional Notes',
            hintText: 'Dietary restrictions, theme ideas...',
            alignLabelWithHint: true,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_error!, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.error)),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _step = 0),
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _generatePlan,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_isLoading ? 'AI is planning...' : 'Generate Plan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultsStep() {
    final tips = (_planResult?['tips'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final description = _planResult?['description'] as String? ?? '';
    final locationSuggestion = _planResult?['location_suggestion'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: Column(
            children: [
              const Icon(Icons.check_circle_rounded, size: 32, color: Color(0xFF16A34A)),
              const SizedBox(height: 8),
              Text(
                '"${_nameCtrl.text.trim()}" is planned!',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF166534)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _statChip(Icons.event_rounded, '1 Event'),
                  const SizedBox(width: 8),
                  _statChip(Icons.task_alt_rounded, '$_createdTaskCount Tasks'),
                  const SizedBox(width: 8),
                  _statChip(Icons.checklist_rounded, '$_createdListCount Lists'),
                ],
              ),
            ],
          ),
        ),

        if (description.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('DESCRIPTION', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone700)),
        ],

        if (locationSuggestion.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.stone500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(locationSuggestion, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone600)),
              ),
            ],
          ),
        ],

        if (tips.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('TIPS', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
          const SizedBox(height: 6),
          ...tips.map((tip) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline_rounded, size: 16, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tip, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone600)),
                ),
              ],
            ),
          )),
        ],

        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF16A34A)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF166534))),
        ],
      ),
    );
  }
}

class _EventWeatherRow extends StatefulWidget {
  final String query;
  final DateTime day;

  const _EventWeatherRow({required this.query, required this.day});

  @override
  State<_EventWeatherRow> createState() => _EventWeatherRowState();
}

class _EventWeatherRowState extends State<_EventWeatherRow> {
  String? _line;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final locs = await locationFromAddress(widget.query);
      if (!mounted || locs.isEmpty) return;
      final line = await WeatherService.daySummaryForLocation(
        latitude: locs.first.latitude,
        longitude: locs.first.longitude,
        day: widget.day,
      );
      if (mounted) setState(() => _line = line);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_line == null) return const SizedBox.shrink();
    return Row(
      children: [
        const Icon(Icons.wb_cloudy_outlined, size: 12, color: AppTheme.stone400),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _line!,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone500),
          ),
        ),
      ],
    );
  }
}

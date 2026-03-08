// lib/screens/calendar/calendar_screen.dart
// Calendar screen for FamilyHub
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart' hide Visibility;
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/calendar_sync_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

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

      if (selected == null || selected.isEmpty || !mounted) {
        setState(() => _isSyncing = false);
        return;
      }

      final provider = context.read<AppProvider>();
      final user = provider.activeUser!;
      final family = provider.activeFamily!;
      var db = provider.db;

      for (final calId in selected) {
        final cal = calendars.firstWhere((c) => c.id == calId);
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

        // Merge: remove old events from this external calendar, add new
        final existingEvents = db.events
            .where((e) => e.externalCalendarId != extCal.id)
            .toList();
        db = db.copyWith(events: [...existingEvents, ...events]);
      }

      await provider.saveAndSync(db);
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
      } else {
        setState(() => _isSyncing = false);
        return;
      }

      // Replace old events from this calendar
      final db = provider.db;
      final otherEvents = db.events
          .where((e) => e.externalCalendarId != cal.id)
          .toList();
      final updatedCal = cal.copyWith(lastSyncedAt: DateTime.now());
      final updatedCalendars = db.externalCalendars
          .map((c) => c.id == cal.id ? updatedCal : c)
          .toList();

      await provider.saveAndSync(db.copyWith(
        events: [...otherEvents, ...newEvents],
        externalCalendars: updatedCalendars,
      ));

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
    await provider.saveAndSync(db.copyWith(
      externalCalendars: db.externalCalendars.where((c) => c.id != cal.id).toList(),
      events: db.events.where((e) => e.externalCalendarId != cal.id).toList(),
    ));
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

      final db = provider.db;
      await provider.saveAndSync(db.copyWith(
        externalCalendars: [...db.externalCalendars, extCal],
        events: [...db.events, ...events],
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${events.length} events from $name')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
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

  List<CalendarEvent> _eventsForDay(
      AppProvider provider, DateTime day) {
    final familyId = provider.activeFamily?.id;
    if (familyId == null) return [];
    return provider.db.events
        .where((e) =>
            e.familyId == familyId && isSameDay(e.startDate, day))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  Map<DateTime, List<CalendarEvent>> _buildEventMap(
      AppProvider provider) {
    final familyId = provider.activeFamily?.id;
    if (familyId == null) return {};
    final map = <DateTime, List<CalendarEvent>>{};
    for (final e in provider.db.events) {
      if (e.familyId != familyId) continue;
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

  Future<void> _deleteEvent(
      BuildContext context, AppProvider provider, CalendarEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event'),
        content: Text('Delete "${event.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final db = provider.db;
      final events =
          db.events.where((e) => e.id != event.id).toList();
      await provider.saveAndSync(db.copyWith(events: events));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final selectedEvents = _eventsForDay(provider, _selectedDay);
        final eventMap = _buildEventMap(provider);

        // Upcoming events (next 7 days)
        final now = DateTime.now();
        final todayDate = DateTime(now.year, now.month, now.day);
        final weekEnd = todayDate.add(const Duration(days: 7));
        final upcomingEvents = provider.db.events
            .where((e) =>
                e.familyId == provider.activeFamily?.id &&
                e.startDate.isAfter(todayDate) &&
                e.startDate.isBefore(weekEnd))
            .toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));

        return Scaffold(
          drawer: const AppDrawer(),
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: AppTheme.stone700),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 20, color: AppTheme.primary),
                const SizedBox(width: 6),
                const Text('FamilyHub', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary)),
              ],
            ),
            centerTitle: false,
            titleSpacing: 0,
            actions: [
              IconButton(icon: const Icon(Icons.menu_rounded, color: AppTheme.stone500), onPressed: () {}),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Page Header
              PageHeader(
                title: 'Family Calendar',
                subtitle: 'Coordinate schedules and plan life together.',
                actions: [
                  ActionChipButton(
                    icon: Icons.calendar_month_outlined,
                    label: 'My Calendars',
                    onTap: _showMyCalendars,
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.stone700,
                  ),
                  ActionChipButton(
                    icon: Icons.sync_rounded,
                    label: _isSyncing ? 'Syncing...' : 'Google Sync',
                    onTap: _isSyncing ? () {} : _connectGoogleCalendar,
                    isPrimary: true,
                  ),
                  ActionChipButton(
                    icon: Icons.add,
                    label: 'Add Event',
                    onTap: () => _showAddEventSheet(context),
                    backgroundColor: AppTheme.stone800,
                  ),
                ],
              ),

              // AI Event Strategist card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
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
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Event Strategist',
                                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                                ),
                                Text(
                                  'Quick event planning with smart suggestions',
                                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 16, color: Colors.white.withOpacity(0.6)),
                            const SizedBox(width: 10),
                            Text(
                              'Describe an event to plan...',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white.withOpacity(0.6)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Quick Plan',
                            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF7C3AED)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Calendar in a white card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.stone100),
                  ),
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
                          color: AppTheme.primary.withOpacity(0.15),
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

              // Coming Up section
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          DateFormat('EEEE, MMM d').format(_selectedDay),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.stone700,
                          ),
                        ),
                        const Spacer(),
                        if (selectedEvents.isNotEmpty)
                          Text(
                            '${selectedEvents.length} event${selectedEvents.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppTheme.stone400,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (selectedEvents.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.stone100),
                        ),
                        child: Column(
                          children: [
                            const Text('📅', style: TextStyle(fontSize: 32)),
                            const SizedBox(height: 8),
                            const Text(
                              'Nothing scheduled',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone500),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Tap + Add Event to add an event for this day',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      ...selectedEvents.map((event) => _EventCard(
                        event: event,
                        provider: provider,
                        onEdit: () => _showAddEventSheet(context, event: event),
                        onDelete: () => _deleteEvent(context, provider, event),
                      )),
                  ],
                ),
              ),

              // Upcoming events
              if (upcomingEvents.isNotEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Text(
                    'COMING UP',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: upcomingEvents.map((event) => _EventCard(
                      event: event,
                      provider: provider,
                      onEdit: () => _showAddEventSheet(context, event: event),
                      onDelete: () => _deleteEvent(context, provider, event),
                    )).toList(),
                  ),
                ),
              ],

              const SizedBox(height: 32),
            ],
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
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cal.type == ExternalCalendarType.google
                  ? const Color(0xFF4285F4).withOpacity(0.1)
                  : AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              cal.type == ExternalCalendarType.google
                  ? Icons.account_circle_rounded
                  : Icons.link_rounded,
              size: 18,
              color: cal.type == ExternalCalendarType.google
                  ? const Color(0xFF4285F4)
                  : AppTheme.primary,
            ),
          ),
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

// ─── Event card ───────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  final CalendarEvent event;
  final AppProvider provider;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EventCard({
    required this.event,
    required this.provider,
    required this.onEdit,
    required this.onDelete,
  });

  Color _visibilityColor() {
    return event.visibility == Visibility.PRIVATE
        ? AppTheme.primary
        : const Color(0xFF8B5CF6);
  }

  String _timeLabel() {
    if (event.allDay) return 'All day';
    final start = DateFormat('h:mm a').format(event.startDate);
    if (isSameDay(event.startDate, event.endDate)) {
      final end = DateFormat('h:mm a').format(event.endDate);
      return '$start – $end';
    }
    return start;
  }

  @override
  Widget build(BuildContext context) {
    final creator = provider.userById(event.createdBy);
    final color = _visibilityColor();

    return GestureDetector(
      onLongPress: onEdit,
      child: Dismissible(
        key: Key(event.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child:
              const Icon(Icons.delete_outline, color: AppTheme.error),
        ),
        confirmDismiss: (_) async {
          onDelete();
          return false;
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.stone100),
          ),
          child: Row(
            children: [
              // Color bar
              Container(
                width: 5,
                height: 80,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(20)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.title,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.stone900,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              event.visibility ==
                                      Visibility.PRIVATE
                                  ? 'Personal'
                                  : 'Family',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: color,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time_outlined,
                              size: 13, color: AppTheme.stone400),
                          const SizedBox(width: 4),
                          Text(
                            _timeLabel(),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppTheme.stone500,
                            ),
                          ),
                        ],
                      ),
                      if (event.location != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 13,
                                color: AppTheme.stone400),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.location!,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: AppTheme.stone500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (creator != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            AvatarInitials(
                                name: creator.name, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              creator.name.split(' ').first,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: AppTheme.stone400,
                              ),
                            ),
                          ],
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
      await provider.saveAndSync(db.copyWith(events: events));
      if (widget.editEvent == null) {
        NotificationService.notifyFamilyActivity(
          title: 'New Calendar Event',
          body: '${provider.activeUser?.name ?? "Someone"} added: ${event.title}',
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
                    Text(
                      widget.editEvent != null
                          ? 'Edit Event'
                          : 'New Event',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.stone900,
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _titleCtrl,
                      autofocus: true,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Title is required'
                              : null,
                      decoration: const InputDecoration(
                          labelText: 'Event title *'),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _locationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // All day toggle
                    Row(
                      children: [
                        const Text('All day',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.stone700)),
                        const Spacer(),
                        Switch(
                          value: _allDay,
                          onChanged: (v) => setState(() => _allDay = v),
                          activeColor: AppTheme.primary,
                        ),
                      ],
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

                    // Share with
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
                          : Text(widget.editEvent != null
                              ? 'Save Changes'
                              : 'Add Event'),
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
    final dateStr = DateFormat('EEE, MMM d yyyy').format(dateTime);
    final timeStr =
        _allDay ? '' : '  ·  ${DateFormat('h:mm a').format(dateTime)}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.stone50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.stone200),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.stone600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$dateStr$timeStr',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppTheme.stone800,
                ),
              ),
            ),
            const Icon(Icons.edit_outlined,
                size: 16, color: AppTheme.stone400),
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
                      color: isSelected ? AppTheme.primary.withOpacity(0.05) : Colors.white,
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
                          color: const Color(0xFF4285F4).withOpacity(0.1),
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
    if (url.isEmpty) return;

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
                    color: AppTheme.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.calendar_today_rounded, size: 18, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('FamilyHub Calendar', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.stone900)),
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
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: cal.type == ExternalCalendarType.google
                            ? const Color(0xFF4285F4).withOpacity(0.1)
                            : AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        cal.type == ExternalCalendarType.google
                            ? Icons.account_circle_rounded
                            : Icons.link_rounded,
                        size: 18,
                        color: cal.type == ExternalCalendarType.google
                            ? const Color(0xFF4285F4)
                            : AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cal.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800)),
                        Text(
                          '${cal.type == ExternalCalendarType.google ? 'Google' : 'URL'} \u00b7 Synced ${_timeAgo(cal.lastSyncedAt)}',
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
                          color: const Color(0xFF4285F4).withOpacity(0.1),
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
                          color: AppTheme.primary.withOpacity(0.1),
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

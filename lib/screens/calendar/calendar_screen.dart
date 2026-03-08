// lib/screens/calendar/calendar_screen.dart
// Calendar screen for FamilyHub

import 'package:flutter/material.dart' hide Visibility;
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
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
                    onTap: () {},
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.stone700,
                  ),
                  ActionChipButton(
                    icon: Icons.auto_awesome,
                    label: 'Plan Event',
                    onTap: () {},
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

              // Import External Calendar section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'IMPORT EXTERNAL CALENDAR',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.stone100),
                      ),
                      child: Column(
                        children: [
                          _buildImportOption(Icons.upload_file_rounded, 'Upload .ics File', 'Import events from a calendar file'),
                          const Divider(height: 1),
                          _buildImportOption(Icons.link_rounded, 'Subscribe via URL', 'Sync with an external calendar feed'),
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

  Widget _buildImportOption(IconData icon, String title, String subtitle) {
    return Padding(
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

                    // Visibility
                    const Text(
                      'Visibility',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.stone700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: Visibility.values.map((v) {
                        final selected = _visibility == v;
                        final label = v == Visibility.FAMILY
                            ? 'Family'
                            : 'Personal';
                        return Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _visibility = v),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppTheme.primary
                                          .withOpacity(0.1)
                                      : AppTheme.stone50,
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? AppTheme.primary
                                        : AppTheme.stone200,
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Inter',
                                    color: selected
                                        ? AppTheme.primary
                                        : AppTheme.stone500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
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

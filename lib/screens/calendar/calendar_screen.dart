// lib/screens/calendar/calendar_screen.dart
// Calendar screen for FamilyHub

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
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

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Column(
            children: [
              // ─── Header ──────────────────────────────────────────────
              const GradientHeader(
                title: 'Calendar',
                subtitle: 'Family schedule & events',
                startColor: Color(0xFF8B5CF6),
                endColor: Color(0xFFEC4899),
              ),

              // ─── Calendar ─────────────────────────────────────────────
              Container(
                color: Colors.white,
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

              const Divider(height: 1),

              // ─── Events list for selected day ─────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
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
              ),

              Expanded(
                child: selectedEvents.isEmpty
                    ? EmptyState(
                        emoji: '📅',
                        title: 'Nothing scheduled',
                        subtitle:
                            'Tap + to add an event for this day',
                        actionLabel: 'Add Event',
                        onAction: () =>
                            _showAddEventSheet(context),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                            16, 0, 16, 100),
                        itemCount: selectedEvents.length,
                        itemBuilder: (ctx, i) {
                          return _EventCard(
                            event: selectedEvents[i],
                            provider: provider,
                            onEdit: () => _showAddEventSheet(
                                context,
                                event: selectedEvents[i]),
                            onDelete: () => _deleteEvent(
                                context,
                                provider,
                                selectedEvents[i]),
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddEventSheet(context),
            child: const Icon(Icons.add),
          ),
        );
      },
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
    return event.visibility == EventVisibility.personal
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
                                      EventVisibility.personal
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
  EventVisibility _visibility = EventVisibility.family;
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
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        location: _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        startDate: _startDate,
        endDate: _allDay ? _startDate : _endDate,
        allDay: _allDay,
        visibility: _visibility,
        createdBy: widget.editEvent?.createdBy ??
            provider.activeUser!.id,
        createdAt: widget.editEvent?.createdAt ?? DateTime.now(),
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
                      children: EventVisibility.values.map((v) {
                        final selected = _visibility == v;
                        final label = v == EventVisibility.family
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

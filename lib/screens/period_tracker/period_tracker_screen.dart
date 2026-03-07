// lib/screens/period_tracker/period_tracker_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class PeriodTrackerScreen extends StatefulWidget {
  const PeriodTrackerScreen({super.key});

  @override
  State<PeriodTrackerScreen> createState() => _PeriodTrackerScreenState();
}

class _PeriodTrackerScreenState extends State<PeriodTrackerScreen> {
  void _showLogSheet({PeriodEntry? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PeriodLogSheet(
        existing: existing,
        onSave: (entry) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          List<PeriodEntry> updated;
          if (existing != null) {
            updated = db.periodEntries.map((e) => e.id == entry.id ? entry : e).toList();
          } else {
            updated = [...db.periodEntries, entry];
          }
          await provider.saveAndSync(db.copyWith(periodEntries: updated));
        },
      ),
    );
  }

  Future<void> _deleteEntry(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      periodEntries: db.periodEntries.where((e) => e.id != id).toList(),
    ));
  }

  int? _cycleLengthDays(List<PeriodEntry> entries) {
    if (entries.length < 2) return null;
    final sorted = [...entries]..sort((a, b) => a.startDate.compareTo(b.startDate));
    int total = 0;
    for (int i = 1; i < sorted.length; i++) {
      total += sorted[i].startDate.difference(sorted[i - 1].startDate).inDays;
    }
    return total ~/ (sorted.length - 1);
  }

  int? _daysUntilNext(List<PeriodEntry> entries) {
    final avg = _cycleLengthDays(entries);
    if (avg == null) return null;
    final sorted = [...entries]..sort((a, b) => b.startDate.compareTo(a.startDate));
    final nextDate = sorted.first.startDate.add(Duration(days: avg));
    return nextDate.difference(DateTime.now()).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Only show current user's data - PRIVATE
    final entries = provider.db.periodEntries
        .where((e) => e.familyId == family.id && e.userId == user.id)
        .toList();
    entries.sort((a, b) => b.startDate.compareTo(a.startDate));

    final avgCycle = _cycleLengthDays(entries);
    final daysUntil = _daysUntilNext(entries);

    return Scaffold(
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showLogSheet(),
        child: const Icon(Icons.add_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(title: Text('Period Tracker'), floating: true),
          // Stats
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                Expanded(child: StatCard(
                  label: 'Avg cycle length',
                  value: avgCycle != null ? '$avgCycle days' : '—',
                  emoji: '📅',
                  color: const Color(0xFFEC4899),
                )),
                const SizedBox(width: 10),
                Expanded(child: StatCard(
                  label: daysUntil != null && daysUntil >= 0 ? 'Days until next' : 'Days since due',
                  value: daysUntil != null ? '${daysUntil.abs()}' : '—',
                  emoji: '🌸',
                  color: const Color(0xFFEC4899),
                )),
                const SizedBox(width: 10),
                Expanded(child: StatCard(
                  label: 'Entries logged',
                  value: '${entries.length}',
                  emoji: '📊',
                  color: const Color(0xFFA855F7),
                )),
              ]),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: AppTheme.stone400),
                SizedBox(width: 6),
                Text('Your data is private to you', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
              ]),
            ),
          ),
          entries.isEmpty
              ? SliverFillRemaining(
                  child: EmptyState(
                    emoji: '🌸',
                    title: 'No entries yet',
                    subtitle: 'Track your period and symptoms privately.',
                    actionLabel: 'Log Period',
                    onAction: () => _showLogSheet(),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final entry = entries[i];
                        final duration = entry.endDate != null
                            ? entry.endDate!.difference(entry.startDate).inDays + 1
                            : null;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Dismissible(
                            key: Key(entry.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
                              child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                            ),
                            onDismissed: (_) => _deleteEntry(entry.id),
                            child: GestureDetector(
                              onTap: () => _showLogSheet(existing: entry),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.stone100),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    const Text('🌸', style: TextStyle(fontSize: 20)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        DateFormat('MMMM d, y').format(entry.startDate),
                                        style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900),
                                      ),
                                    ),
                                    if (duration != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: const Color(0xFFFCE7F3), borderRadius: BorderRadius.circular(8)),
                                        child: Text('$duration days', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEC4899))),
                                      ),
                                  ]),
                                  if (entry.symptoms.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(spacing: 6, runSpacing: 4, children: entry.symptoms.map((s) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: const Color(0xFFFDF4FF), borderRadius: BorderRadius.circular(8)),
                                      child: Text(s, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFFA855F7))),
                                    )).toList()),
                                  ],
                                  if (entry.flowLevel != null) ...[
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      const Text('Flow: ', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
                                      ...List.generate(5, (j) => Icon(
                                        j < (entry.flowLevel ?? 0) ? Icons.circle : Icons.circle_outlined,
                                        size: 10,
                                        color: const Color(0xFFEC4899),
                                      )),
                                    ]),
                                  ],
                                  if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(entry.notes!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ],
                                ]),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: entries.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Log period sheet
// ─────────────────────────────────────────────

class _PeriodLogSheet extends StatefulWidget {
  final PeriodEntry? existing;
  final Future<void> Function(PeriodEntry) onSave;
  const _PeriodLogSheet({this.existing, required this.onSave});

  @override
  State<_PeriodLogSheet> createState() => _PeriodLogSheetState();
}

class _PeriodLogSheetState extends State<_PeriodLogSheet> {
  late DateTime _startDate;
  DateTime? _endDate;
  List<String> _symptoms = [];
  int? _flowLevel;
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;
  final _uuid = const Uuid();

  static const _symptomOptions = ['Cramps', 'Headache', 'Bloating', 'Fatigue', 'Mood Swings', 'Nausea', 'Backache', 'Spotting'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _startDate = e?.startDate ?? DateTime.now();
    _endDate = e?.endDate;
    _symptoms = List.from(e?.symptoms ?? []);
    _flowLevel = e?.flowLevel;
    _notesCtrl.text = e?.notes ?? '';
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : (_endDate ?? _startDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) {
      setState(() {
        if (isStart) _startDate = d;
        else _endDate = d;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final entry = PeriodEntry(
      id: widget.existing?.id ?? _uuid.v4(),
      familyId: provider.activeFamily!.id,
      userId: provider.activeUser!.id,
      startDate: _startDate,
      endDate: _endDate,
      flowLevel: _flowLevel,
      symptoms: _symptoms,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await widget.onSave(entry);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(widget.existing != null ? 'Edit Entry' : 'Log Period', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
              TextButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
              // Dates
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(true),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.stone200)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('START DATE', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.stone400, letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        Text(DateFormat('MMM d').format(_startDate), style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFFEC4899))),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(false),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.stone200)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('END DATE', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.stone400, letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        Text(
                          _endDate != null ? DateFormat('MMM d').format(_endDate!) : 'Ongoing',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: _endDate != null ? const Color(0xFFEC4899) : AppTheme.stone400),
                        ),
                      ]),
                    ),
                  ),
                ),
              ]),
              if (_endDate != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => setState(() => _endDate = null), child: const Text('Clear end date')),
                ),
              const SizedBox(height: 20),
              // Flow level
              const Text('Flow Level', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone600)),
              const SizedBox(height: 8),
              Row(children: List.generate(5, (i) {
                final level = i + 1;
                final isSelected = _flowLevel == level;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _flowLevel = isSelected ? null : level),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEC4899).withOpacity(0.15) : AppTheme.stone50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? const Color(0xFFEC4899) : AppTheme.stone200, width: isSelected ? 2 : 1),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('$level', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: isSelected ? const Color(0xFFEC4899) : AppTheme.stone500)),
                        ]),
                      ),
                    ),
                  ),
                );
              })),
              const SizedBox(height: 20),
              // Symptoms
              const Text('Symptoms', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _symptomOptions.map((s) {
                final isSelected = _symptoms.contains(s);
                return GestureDetector(
                  onTap: () => setState(() { isSelected ? _symptoms.remove(s) : _symptoms.add(s); }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFCE7F3) : AppTheme.stone50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? const Color(0xFFEC4899) : AppTheme.stone200, width: isSelected ? 1.5 : 1),
                    ),
                    child: Text(s, style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? const Color(0xFFEC4899) : AppTheme.stone600)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 16),
              TextField(controller: _notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true)),
            ]),
          ),
        ]),
      ),
    );
  }
}

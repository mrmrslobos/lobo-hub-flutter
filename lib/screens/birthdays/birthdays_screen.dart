// lib/screens/birthdays/birthdays_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class BirthdaysScreen extends StatefulWidget {
  const BirthdaysScreen({super.key});

  @override
  State<BirthdaysScreen> createState() => _BirthdaysScreenState();
}

class _BirthdaysScreenState extends State<BirthdaysScreen> {
  // Calculate days until next occurrence of a date
  int _daysUntil(Occasion occasion) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Use the occasion date; if it has already passed this year, use next year
    DateTime next = DateTime(now.year, occasion.date.month, occasion.date.day);
    if (next.isBefore(today)) {
      next = DateTime(now.year + 1, occasion.date.month, occasion.date.day);
    }
    return next.difference(today).inDays;
  }

  int? _age(Occasion occasion) {
    final now = DateTime.now();
    if (!occasion.recurring) return null;
    // We can't know birth year from the Occasion model directly
    // date.year will be used as birth year if it's not a recurring-only date
    if (occasion.date.year < 1900 || occasion.date.year > now.year) return null;
    int age = now.year - occasion.date.year;
    final birthdayThisYear = DateTime(now.year, occasion.date.month, occasion.date.day);
    if (birthdayThisYear.isAfter(now)) age--;
    return age;
  }

  Future<void> _deleteOccasion(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      occasions: db.occasions.where((o) => o.id != id).toList(),
    ));
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OccasionFormSheet(
        onSave: (occasion) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(occasions: [...db.occasions, occasion]));
        },
      ),
    );
  }

  Color _badgeColor(int days) {
    if (days <= 7) return AppTheme.success;
    if (days <= 30) return AppTheme.warning;
    return AppTheme.stone400;
  }

  String _typeEmoji(String type) {
    switch (type.toLowerCase()) {
      case 'birthday': return '🎂';
      case 'anniversary': return '💍';
      case 'holiday': return '🎉';
      case 'memorial': return '🕊️';
      default: return '⭐';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final family = provider.activeFamily;
    if (family == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final occasions = provider.db.occasions
        .where((o) => o.familyId == family.id)
        .toList();
    occasions.sort((a, b) => _daysUntil(a).compareTo(_daysUntil(b)));

    final upcoming = occasions.where((o) => _daysUntil(o) <= 30).toList();
    final later = occasions.where((o) => _daysUntil(o) > 30).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: const AppDrawer(),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page Header ──
            PageHeader(
              title: '\u{1F389} Occasions',
              subtitle: 'Birthdays, anniversaries & special dates',
              actions: [
                ActionChipButton(
                  icon: Icons.add_rounded,
                  label: 'Add Occasion',
                  onTap: _showAddSheet,
                  isPrimary: true,
                ),
              ],
            ),

            // ── Stats row ──
            if (occasions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.stone100),
                        ),
                        child: Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.upcoming_rounded, size: 18, color: AppTheme.success),
                          ),
                          const SizedBox(width: 10),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${upcoming.length}', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.stone900)),
                            const Text('Within 30 days', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone500)),
                          ]),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.stone100),
                        ),
                        child: Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.celebration_rounded, size: 18, color: AppTheme.primary),
                          ),
                          const SizedBox(width: 10),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${occasions.length}', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.stone900)),
                            const Text('Total', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone500)),
                          ]),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Content ──
            if (occasions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OnboardingCard(
                  emoji: '\u{1F389}',
                  title: 'Track Special Dates',
                  bullets: ['Never miss a birthday or anniversary', 'Get reminders for upcoming occasions', 'Keep all special dates in one place'],
                  actionLabel: '+ Add Occasion',
                  onAction: _showAddSheet,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (upcoming.isNotEmpty) ...[
                      const Text('COMING UP', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
                      const SizedBox(height: 8),
                      ...upcoming.map((o) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _OccasionCard(
                              occasion: o,
                              daysUntil: _daysUntil(o),
                              age: _age(o),
                              emoji: _typeEmoji(o.type.name.toLowerCase()),
                              badgeColor: _badgeColor(_daysUntil(o)),
                              onDelete: () => _deleteOccasion(o.id),
                            ),
                          )),
                    ],
                    if (later.isNotEmpty) ...[
                      if (upcoming.isNotEmpty) const SizedBox(height: 12),
                      const Text('UPCOMING', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
                      const SizedBox(height: 8),
                      ...later.map((o) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _OccasionCard(
                              occasion: o,
                              daysUntil: _daysUntil(o),
                              age: _age(o),
                              emoji: _typeEmoji(o.type.name.toLowerCase()),
                              badgeColor: _badgeColor(_daysUntil(o)),
                              onDelete: () => _deleteOccasion(o.id),
                            ),
                          )),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OccasionCard extends StatelessWidget {
  final Occasion occasion;
  final int daysUntil;
  final int? age;
  final String emoji;
  final Color badgeColor;
  final VoidCallback onDelete;

  const _OccasionCard({
    required this.occasion,
    required this.daysUntil,
    required this.age,
    required this.emoji,
    required this.badgeColor,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(occasion.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Occasion'),
          content: Text('Delete "${occasion.title}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: daysUntil <= 7 ? AppTheme.success.withOpacity(0.3) : AppTheme.stone100),
        ),
        child: Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: badgeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(occasion.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900)),
            const SizedBox(height: 2),
            Row(children: [
              Text(occasion.type.name.toLowerCase(), style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
              if (age != null) ...[
                const Text(' · ', style: TextStyle(color: AppTheme.stone400)),
                Text('Turns $age', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
              ],
              if (occasion.recurring) ...[
                const Text(' · ', style: TextStyle(color: AppTheme.stone400)),
                const Icon(Icons.repeat_rounded, size: 12, color: AppTheme.stone400),
              ],
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: badgeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(
                daysUntil == 0 ? 'TODAY! 🎉' : daysUntil == 1 ? 'Tomorrow' : 'in $daysUntil days',
                style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: badgeColor),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Add occasion form
// ─────────────────────────────────────────────

class _OccasionFormSheet extends StatefulWidget {
  final Future<void> Function(Occasion) onSave;
  const _OccasionFormSheet({required this.onSave});

  @override
  State<_OccasionFormSheet> createState() => _OccasionFormSheetState();
}

class _OccasionFormSheetState extends State<_OccasionFormSheet> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _type = 'birthday';
  DateTime _date = DateTime.now();
  bool _recurring = true;
  bool _isSaving = false;
  final _uuid = const Uuid();

  static const _types = ['birthday', 'anniversary', 'holiday', 'memorial', 'custom'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final occasion = Occasion(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      creatorId: provider.activeUser!.id,
      title: _titleCtrl.text.trim(),
      typeStr: _type,
      date: _date,
      recurring: _recurring,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await widget.onSave(occasion);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('New Occasion', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
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
              TextField(controller: _titleCtrl, autofocus: true, textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name *', prefixIcon: Icon(Icons.person_outline_rounded))),
              const SizedBox(height: 20),
              const Text('Type', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _types.map((t) {
                final isSelected = t == _type;
                return GestureDetector(
                  onTap: () => setState(() => _type = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryLight : AppTheme.stone50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.stone200, width: isSelected ? 2 : 1),
                    ),
                    child: Text(t, style: TextStyle(fontFamily: 'Inter', fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, fontSize: 13, color: isSelected ? AppTheme.primary : AppTheme.stone600)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.stone200)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.stone500),
                    const SizedBox(width: 10),
                    Text('${_date.month}/${_date.day}/${_date.year}', style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone800)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Recurring yearly', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Repeat this event each year', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              TextField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true)),
            ]),
          ),
        ]),
      ),
    );
  }
}

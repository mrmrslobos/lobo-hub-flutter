// lib/screens/health/health_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  String? _selectedUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AppProvider>();
    if (_selectedUserId == null && provider.activeUser != null) {
      _selectedUserId = provider.activeUser!.id;
    }
  }

  Future<void> _deleteRecord(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      healthRecords: db.healthRecords.where((r) => r.id != id).toList(),
    ));
  }

  void _showAddRecordSheet(String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HealthRecordSheet(
        userId: userId,
        onSave: (record) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(healthRecords: [...db.healthRecords, record]));
        },
      ),
    );
  }

  String _typeEmoji(String type) {
    switch (type.toLowerCase()) {
      case 'weight': return '⚖️';
      case 'blood_pressure': return '🩸';
      case 'medication': return '💊';
      case 'appointment': return '📅';
      case 'note': return '📝';
      case 'allergy': return '🌿';
      case 'condition': return '🏥';
      default: return '❤️';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final members = provider.familyMembers;
    _selectedUserId ??= user.id;

    final selectedUser = members.cast<User?>().firstWhere((m) => m?.id == _selectedUserId, orElse: () => null) ?? user;

    final records = provider.db.healthRecords
        .where((r) => r.familyId == family.id && r.userId == _selectedUserId)
        .toList();
    records.sort((a, b) => b.date.compareTo(a.date));

    // Group by type
    final grouped = <String, List<HealthRecord>>{};
    for (final r in records) {
      grouped.putIfAbsent(r.type, () => []).add(r);
    }

    return Scaffold(
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddRecordSheet(_selectedUserId!),
        child: const Icon(Icons.add_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(title: Text('Health Records'), floating: true),
          // Member selector
          if (members.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  children: members.map((m) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(m.name.split(' ').first),
                      selected: _selectedUserId == m.id,
                      onSelected: (_) => setState(() => _selectedUserId = m.id),
                      showCheckmark: false,
                      avatar: UserAvatarWidget(name: m.name, radius: 10),
                    ),
                  )).toList(),
                ),
              ),
            ),
          // Member header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  UserAvatarWidget(name: selectedUser.name, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(selectedUser.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                    Text('${records.length} record${records.length == 1 ? '' : 's'}', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
                  ])),
                  const Text('❤️', style: TextStyle(fontSize: 28)),
                ]),
              ),
            ),
          ),
          records.isEmpty
              ? SliverFillRemaining(
                  child: EmptyState(
                    emoji: '❤️',
                    title: 'No health records',
                    subtitle: 'Add health info for ${selectedUser.name.split(' ').first}.',
                    actionLabel: 'Add Record',
                    onAction: () => _showAddRecordSheet(_selectedUserId!),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      ...grouped.entries.map((entry) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(children: [
                            Text(_typeEmoji(entry.key), style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Text(entry.key.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
                          ]),
                        ),
                        ...entry.value.map((record) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _RecordCard(record: record, emoji: _typeEmoji(record.type), onDelete: () => _deleteRecord(record.id)),
                        )),
                      ])).toList(),
                    ]),
                  ),
                ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final HealthRecord record;
  final String emoji;
  final VoidCallback onDelete;

  const _RecordCard({required this.record, required this.emoji, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Record'),
          content: Text('Delete "${record.title}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(record.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone900)),
            if (record.notes != null && record.notes!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(record.notes!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (record.data.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(record.data.entries.take(2).map((e) => '${e.key}: ${e.value}').join(' · '), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
            ],
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(DateFormat('MMM d').format(record.date), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
            Text(DateFormat('y').format(record.date), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone300)),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Add health record
// ─────────────────────────────────────────────

class _HealthRecordSheet extends StatefulWidget {
  final String userId;
  final Future<void> Function(HealthRecord) onSave;
  const _HealthRecordSheet({required this.userId, required this.onSave});

  @override
  State<_HealthRecordSheet> createState() => _HealthRecordSheetState();
}

class _HealthRecordSheetState extends State<_HealthRecordSheet> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _dataKeyCtrl = TextEditingController();
  final _dataValueCtrl = TextEditingController();
  String _type = 'note';
  DateTime _date = DateTime.now();
  Map<String, dynamic> _data = {};
  bool _isSaving = false;
  final _uuid = const Uuid();

  static const _types = ['note', 'weight', 'blood_pressure', 'medication', 'appointment', 'allergy', 'condition'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _dataKeyCtrl.dispose();
    _dataValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(1900), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d != null) setState(() => _date = d);
  }

  void _addDataEntry() {
    final k = _dataKeyCtrl.text.trim();
    final v = _dataValueCtrl.text.trim();
    if (k.isNotEmpty && v.isNotEmpty) {
      setState(() { _data[k] = v; _dataKeyCtrl.clear(); _dataValueCtrl.clear(); });
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final record = HealthRecord(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      userId: widget.userId,
      type: _type,
      title: _titleCtrl.text.trim(),
      data: Map.from(_data),
      date: _date,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await widget.onSave(record);
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
              const Text('New Record', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
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
              // Type
              const Text('Type', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone600)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _types.map((t) {
                    final isSelected = t == _type;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _type = t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primaryLight : AppTheme.stone50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.stone200, width: isSelected ? 2 : 1),
                          ),
                          child: Text(t.replaceAll('_', ' '), style: TextStyle(fontFamily: 'Inter', fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, fontSize: 12, color: isSelected ? AppTheme.primary : AppTheme.stone600)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(controller: _titleCtrl, autofocus: true, textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Title *', prefixIcon: Icon(Icons.label_outline_rounded))),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.stone200)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.stone500),
                    const SizedBox(width: 10),
                    Text(DateFormat('EEE, MMM d, y').format(_date), style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone800)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              // Data fields
              const Text('Data (optional)', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone600)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: TextField(controller: _dataKeyCtrl, decoration: const InputDecoration(labelText: 'Field', hintText: 'e.g. value'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _dataValueCtrl, decoration: const InputDecoration(labelText: 'Value'))),
                const SizedBox(width: 8),
                IconButton(onPressed: _addDataEntry, icon: const Icon(Icons.add_circle_rounded, color: AppTheme.primary)),
              ]),
              if (_data.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: _data.entries.map((e) => Chip(
                  label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 11)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                  onDeleted: () => setState(() => _data.remove(e.key)),
                )).toList()),
              ],
              const SizedBox(height: 12),
              TextField(controller: _notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true)),
            ]),
          ),
        ]),
      ),
    );
  }
}

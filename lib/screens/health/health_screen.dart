// lib/screens/health/health_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';

const _healthUuid = Uuid();

// ─────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  String? _selectedUserId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final db = provider.db;
    final familyId = provider.activeFamily?.id ?? '';
    final currentUserId = provider.activeUser?.id ?? '';

    // Get family member user IDs for this family
    final memberUserIds = db.familyMembers
        .where((m) => m.familyId == familyId)
        .map((m) => m.userId)
        .toList();

    // Get user objects for those members
    final members = db.users
        .where((u) => memberUserIds.contains(u.id))
        .toList();

    // Default to current user
    final selectedId = _selectedUserId ?? currentUserId;

    // Get health records for selected member
    final records = db.healthRecords
        .where((r) => r.familyId == familyId && r.userId == selectedId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(title: const Text('Health Records')),
      drawer: const AppDrawer(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Member selector
          if (members.isNotEmpty) ...[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: members.map((u) {
                    final selected = u.id == selectedId;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(u.name),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _selectedUserId = u.id),
                        selectedColor: const Color(0xFF4F46E5).withOpacity(0.15),
                        checkmarkColor: const Color(0xFF4F46E5),
                        labelStyle: TextStyle(
                          color: selected
                              ? const Color(0xFF4F46E5)
                              : const Color(0xFF44403C),
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const Divider(height: 1),
          ],
          // Records list
          Expanded(
            child: records.isEmpty
                ? _buildEmpty(context, provider, familyId, selectedId)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) => _HealthRecordCard(
                      record: records[i],
                      provider: provider,
                      db: db,
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            _showAddSheet(context, provider, familyId, selectedId),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, AppProvider provider,
      String familyId, String userId) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🏥', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          const Text('No health records yet',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 8),
          const Text('Add medical records, medications, and more',
              style: TextStyle(color: Color(0xFF78716C)),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () =>
                _showAddSheet(context, provider, familyId, userId),
            icon: const Icon(Icons.add),
            label: const Text('Add Record'),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context, AppProvider provider,
      String familyId, String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddHealthRecordSheet(
        provider: provider,
        familyId: familyId,
        userId: userId,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Health Record Card
// ─────────────────────────────────────────────

class _HealthRecordCard extends StatelessWidget {
  const _HealthRecordCard({
    required this.record,
    required this.provider,
    required this.db,
  });
  final HealthRecord record;
  final AppProvider provider;
  final AppDB db;

  String _emojiForType(String type) {
    switch (type) {
      case 'weight':
        return '⚖️';
      case 'blood_pressure':
        return '💓';
      case 'medication':
        return '💊';
      case 'appointment':
        return '📅';
      case 'allergy':
        return '🤧';
      case 'condition':
        return '🩺';
      default:
        return '📋';
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'weight':
        return const Color(0xFF6366F1);
      case 'blood_pressure':
        return const Color(0xFFDC2626);
      case 'medication':
        return const Color(0xFF16A34A);
      case 'appointment':
        return const Color(0xFF0891B2);
      case 'allergy':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF78716C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForType(record.type);
    final dateStr =
        '${record.date.month}/${record.date.day}/${record.date.year}';

    return Dismissible(
      key: Key(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFDC2626),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        provider.saveAndSync(db.copyWith(
            healthRecords:
                db.healthRecords.where((r) => r.id != record.id).toList()));
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7E5E4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(_emojiForType(record.type),
                  style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          record.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
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
                          record.type.replaceAll('_', ' '),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: color),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF78716C)),
                  ),
                  // Show data fields
                  if (record.data.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: record.data.entries
                          .where((e) => e.value != null &&
                              e.value.toString().isNotEmpty)
                          .map((e) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F4),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${e.key}: ${e.value}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF44403C)),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                  if (record.notes != null && record.notes!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      record.notes!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFA8A29E)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
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

// ─────────────────────────────────────────────
// Add Health Record Sheet
// ─────────────────────────────────────────────

class _AddHealthRecordSheet extends StatefulWidget {
  const _AddHealthRecordSheet({
    required this.provider,
    required this.familyId,
    required this.userId,
  });
  final AppProvider provider;
  final String familyId;
  final String userId;

  @override
  State<_AddHealthRecordSheet> createState() => _AddHealthRecordSheetState();
}

class _AddHealthRecordSheetState extends State<_AddHealthRecordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _value2Ctrl = TextEditingController();

  String _type = 'note';
  DateTime _date = DateTime.now();

  static const _types = [
    'note',
    'weight',
    'blood_pressure',
    'medication',
    'appointment',
    'allergy',
    'condition',
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _valueCtrl.dispose();
    _value2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (ctx, scroll) => Form(
        key: _formKey,
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          children: [
            const Text('Add Health Record',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            // Type chips
            const Text('Type',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _types.map((t) {
                final selected = _type == t;
                return ChoiceChip(
                  label:
                      Text(t[0].toUpperCase() + t.substring(1).replaceAll('_', ' ')),
                  selected: selected,
                  onSelected: (_) => setState(() => _type = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title *'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            // Dynamic value fields based on type
            if (_type == 'weight') ...[
              TextFormField(
                controller: _valueCtrl,
                decoration:
                    const InputDecoration(labelText: 'Weight', suffixText: 'lbs'),
                keyboardType: TextInputType.number,
              ),
            ] else if (_type == 'blood_pressure') ...[
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _valueCtrl,
                    decoration: const InputDecoration(labelText: 'Systolic'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _value2Ctrl,
                    decoration: const InputDecoration(labelText: 'Diastolic'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ]),
            ] else if (_type == 'medication') ...[
              TextFormField(
                controller: _valueCtrl,
                decoration: const InputDecoration(
                    labelText: 'Dosage', hintText: 'e.g. 10mg'),
              ),
            ],
            const SizedBox(height: 14),
            // Date picker
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD6D3D1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 18, color: Color(0xFF78716C)),
                    const SizedBox(width: 10),
                    Text(
                      '${_date.month}/${_date.day}/${_date.year}',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesCtrl,
              decoration:
                  const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: const Text('Save Record'),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    // Build data map based on type
    final Map<String, dynamic> data = {};
    if (_type == 'weight' && _valueCtrl.text.isNotEmpty) {
      data['weight'] = _valueCtrl.text.trim();
      data['unit'] = 'lbs';
    } else if (_type == 'blood_pressure') {
      if (_valueCtrl.text.isNotEmpty) data['systolic'] = _valueCtrl.text.trim();
      if (_value2Ctrl.text.isNotEmpty) {
        data['diastolic'] = _value2Ctrl.text.trim();
      }
    } else if (_type == 'medication' && _valueCtrl.text.isNotEmpty) {
      data['dosage'] = _valueCtrl.text.trim();
    }

    final db = widget.provider.db;
    final record = HealthRecord(
      id: _healthUuid.v4(),
      familyId: widget.familyId,
      userId: widget.userId,
      type: _type,
      title: _titleCtrl.text.trim(),
      data: data,
      date: _date,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    widget.provider.saveAndSync(
        db.copyWith(healthRecords: [...db.healthRecords, record]));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Health record saved!')));
  }
}

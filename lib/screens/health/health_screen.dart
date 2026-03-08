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
      grouped.putIfAbsent(r.type ?? 'Other', () => []).add(r);
    }

    // Blood type options
    const bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Unknown'];

    // Find blood type record for selected user
    final bloodTypeRecord = records.where((r) => r.type == 'blood_type').toList();
    final currentBloodType = bloodTypeRecord.isNotEmpty ? (bloodTypeRecord.first.data['value'] ?? 'Unknown') : 'Unknown';

    // Section records
    final emergencyContacts = records.where((r) => r.type == 'emergency_contact').toList();
    final allergies = records.where((r) => r.type == 'allergy').toList();
    final medications = records.where((r) => r.type == 'medication').toList();
    final conditions = records.where((r) => r.type == 'condition').toList();
    final immunizations = records.where((r) => r.type == 'immunization').toList();
    final doctorInsurance = records.where((r) => r.type == 'doctor_insurance' || r.type == 'appointment').toList();

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
              title: '\u2764\uFE0F Health Records',
              subtitle: 'Allergies, medications & emergency info',
              actions: [
                ActionChipButton(
                  icon: Icons.add_rounded,
                  label: 'Add Record',
                  onTap: () => _showAddRecordSheet(_selectedUserId!),
                  isPrimary: true,
                ),
              ],
            ),

            // ── Horizontal scrollable member avatars ──
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: members.map((m) {
                  final isSelected = _selectedUserId == m.id;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedUserId = m.id),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? AppTheme.primary : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: AvatarInitials(name: m.name, size: 48),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            m.name.split(' ').first,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? AppTheme.primary : AppTheme.stone600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 8),

            // ── Blood Type Section ──
            _buildExpandableSection(
              icon: Icons.bloodtype_rounded,
              title: 'Blood Type',
              initiallyExpanded: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: bloodTypes.map((bt) {
                    final isSelected = currentBloodType == bt;
                    return GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primary : AppTheme.stone50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.stone200),
                        ),
                        child: Text(
                          bt,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 13,
                            color: isSelected ? Colors.white : AppTheme.stone600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // ── Emergency Contacts Section ──
            _buildExpandableSection(
              icon: Icons.emergency_rounded,
              title: 'Emergency Contacts',
              count: emergencyContacts.length,
              child: Column(
                children: [
                  ...emergencyContacts.map((r) => Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: _RecordCard(record: r, emoji: '🚨', onDelete: () => _deleteRecord(r.id)),
                  )),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: GestureDetector(
                      onTap: () => _showAddRecordSheet(_selectedUserId!),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.stone200, style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_rounded, size: 16, color: AppTheme.stone400),
                            SizedBox(width: 4),
                            Text('Add Contact', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Allergies Section ──
            _buildExpandableSection(
              icon: Icons.warning_amber_rounded,
              title: 'Allergies',
              count: allergies.length,
              child: Column(
                children: [
                  ...allergies.map((r) => Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: _RecordCard(record: r, emoji: '🌿', onDelete: () => _deleteRecord(r.id)),
                  )),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: GestureDetector(
                      onTap: () => _showAddRecordSheet(_selectedUserId!),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.stone200, style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_rounded, size: 16, color: AppTheme.stone400),
                            SizedBox(width: 4),
                            Text('Add Allergy', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Medications Section ──
            _buildExpandableSection(
              icon: Icons.medication_rounded,
              title: 'Medications',
              count: medications.length,
              child: Column(
                children: [
                  ...medications.map((r) => Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: _RecordCard(record: r, emoji: '💊', onDelete: () => _deleteRecord(r.id)),
                  )),
                  if (medications.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Text('No medications recorded.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
                    ),
                ],
              ),
            ),

            // ── Medical Conditions Section ──
            _buildExpandableSection(
              icon: Icons.local_hospital_rounded,
              title: 'Medical Conditions',
              count: conditions.length,
              child: Column(
                children: [
                  ...conditions.map((r) => Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: _RecordCard(record: r, emoji: '🏥', onDelete: () => _deleteRecord(r.id)),
                  )),
                  if (conditions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Text('No conditions recorded.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
                    ),
                ],
              ),
            ),

            // ── Immunizations Section ──
            _buildExpandableSection(
              icon: Icons.vaccines_rounded,
              title: 'Immunizations',
              count: immunizations.length,
              child: Column(
                children: [
                  ...immunizations.map((r) => Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: _RecordCard(record: r, emoji: '💉', onDelete: () => _deleteRecord(r.id)),
                  )),
                  if (immunizations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Text('No immunizations recorded.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
                    ),
                ],
              ),
            ),

            // ── Doctor & Insurance Section ──
            _buildExpandableSection(
              icon: Icons.medical_information_rounded,
              title: 'Doctor & Insurance',
              count: doctorInsurance.length,
              child: Column(
                children: [
                  ...doctorInsurance.map((r) => Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: _RecordCard(record: r, emoji: '📋', onDelete: () => _deleteRecord(r.id)),
                  )),
                  if (doctorInsurance.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Text('No doctor or insurance info recorded.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
                    ),
                ],
              ),
            ),

            // ── Last updated footer ──
            if (records.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(
                  'Last updated ${DateFormat('MMM d, y').format(records.first.date)}',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableSection({
    required IconData icon,
    required String title,
    int? count,
    bool initiallyExpanded = false,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: Icon(icon, size: 20, color: AppTheme.stone600),
            title: Row(
              children: [
                Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone800)),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.stone100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$count', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone500)),
                  ),
                ],
              ],
            ),
            children: [
              const Divider(height: 1, color: AppTheme.stone100),
              child,
            ],
          ),
        ),
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
            Text(record.title ?? '', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone900)),
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
      updatedAt: _date,
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

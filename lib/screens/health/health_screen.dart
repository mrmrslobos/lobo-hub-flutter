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

const _uuid = Uuid();
String _uid() => _uuid.v4().substring(0, 9);

String _bloodTypeLabel(BloodType bt) {
  switch (bt) {
    case BloodType.Aplus: return 'A+';
    case BloodType.Aminus: return 'A-';
    case BloodType.Bplus: return 'B+';
    case BloodType.Bminus: return 'B-';
    case BloodType.ABplus: return 'AB+';
    case BloodType.ABminus: return 'AB-';
    case BloodType.Oplus: return 'O+';
    case BloodType.Ominus: return 'O-';
    case BloodType.Unknown: return 'Unknown';
  }
}

const _bloodTypes = BloodType.values;

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  String? _selectedMemberId;
  final Set<String> _expandedSections = {'allergies', 'emergency'};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AppProvider>();
    if (_selectedMemberId == null && provider.activeUser != null) {
      _selectedMemberId = provider.activeUser!.id;
    }
  }

  /// Get or create a stable health record for a member.
  HealthRecord _getRecord(AppProvider provider, String memberId) {
    final family = provider.activeFamily!;
    final records = provider.db.healthRecords
        .where((r) => r.familyId == family.id && r.userId == memberId)
        .toList();
    if (records.isNotEmpty) return records.first;
    return HealthRecord(
      id: 'health_${family.id}_$memberId',
      familyId: family.id,
      userId: memberId,
      updatedBy: provider.activeUser!.id,
    );
  }

  Future<void> _saveRecord(HealthRecord updated) async {
    final provider = context.read<AppProvider>();
    final family = provider.activeFamily!;
    final db = provider.db;
    final filtered = db.healthRecords
        .where((r) => !(r.familyId == family.id && r.userId == updated.userId))
        .toList();
    final withTimestamp = HealthRecord(
      id: updated.id,
      familyId: updated.familyId,
      userId: updated.userId,
      updatedBy: provider.activeUser!.id,
      bloodType: updated.bloodType,
      allergies: updated.allergies,
      medications: updated.medications,
      conditions: updated.conditions,
      immunizations: updated.immunizations,
      emergencyContacts: updated.emergencyContacts,
      doctorName: updated.doctorName,
      doctorPhone: updated.doctorPhone,
      insuranceProvider: updated.insuranceProvider,
      insurancePolicyNumber: updated.insurancePolicyNumber,
      notes: updated.notes,
      updatedAt: DateTime.now(),
    );
    await provider.saveAndSync(db.copyWith(healthRecords: [...filtered, withTimestamp]));
  }

  void _toggleSection(String section) {
    setState(() {
      if (_expandedSections.contains(section)) {
        _expandedSections.remove(section);
      } else {
        _expandedSections.add(section);
      }
    });
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
    _selectedMemberId ??= user.id;
    final record = _getRecord(provider, _selectedMemberId!);
    final selectedName = provider.memberDisplayName(
      members.firstWhere((m) => m.id == _selectedMemberId, orElse: () => members.first),
    );

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
            // ── Header ──
            const PageHeader(
              title: 'Health Records',
              subtitle: 'Allergies, medications & emergency info',
            ),

            // ── Member selector ──
            if (members.length > 1)
              SizedBox(
                height: 90,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: members.map((m) {
                    final isSelected = _selectedMemberId == m.id;
                    final name = provider.memberDisplayName(m);
                    return GestureDetector(
                      onTap: () => setState(() => _selectedMemberId = m.id),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? AppTheme.primary : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: AvatarInitials(name: name, size: 48),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name.split(' ').first,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? AppTheme.primary : AppTheme.stone600,
                            ),
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 8),

            // ── Blood Type ──
            _buildSection(
              icon: Icons.bloodtype_rounded,
              title: 'Blood Type',
              section: 'blood',
              initiallyExpanded: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _bloodTypes.map((bt) {
                    final isSelected = record.bloodType == bt;
                    return GestureDetector(
                      onTap: () => _saveRecord(HealthRecord(
                        id: record.id, familyId: record.familyId, userId: record.userId,
                        updatedBy: user.id, bloodType: bt,
                        allergies: record.allergies, medications: record.medications,
                        conditions: record.conditions, immunizations: record.immunizations,
                        emergencyContacts: record.emergencyContacts,
                        doctorName: record.doctorName, doctorPhone: record.doctorPhone,
                        insuranceProvider: record.insuranceProvider,
                        insurancePolicyNumber: record.insurancePolicyNumber,
                        notes: record.notes,
                      )),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFF43F5E) : AppTheme.stone50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? const Color(0xFFF43F5E) : AppTheme.stone200),
                        ),
                        child: Text(
                          _bloodTypeLabel(bt),
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

            // ── Allergies ──
            _buildSection(
              icon: Icons.warning_amber_rounded,
              title: 'Allergies',
              section: 'allergies',
              count: record.allergies.length,
              child: _AllergiesSection(record: record, onSave: _saveRecord),
            ),

            // ── Medications ──
            _buildSection(
              icon: Icons.medication_rounded,
              title: 'Medications',
              section: 'medications',
              count: record.medications.length,
              child: _MedicationsSection(record: record, onSave: _saveRecord),
            ),

            // ── Medical Conditions ──
            _buildSection(
              icon: Icons.local_hospital_rounded,
              title: 'Medical Conditions',
              section: 'conditions',
              count: record.conditions.length,
              child: _ConditionsSection(record: record, onSave: _saveRecord),
            ),

            // ── Immunizations ──
            _buildSection(
              icon: Icons.vaccines_rounded,
              title: 'Immunizations',
              section: 'immunizations',
              count: record.immunizations.length,
              child: _ImmunizationsSection(record: record, onSave: _saveRecord),
            ),

            // ── Emergency Contacts ──
            _buildSection(
              icon: Icons.emergency_rounded,
              title: 'Emergency Contacts',
              section: 'emergency',
              count: record.emergencyContacts.length,
              child: _EmergencySection(record: record, onSave: _saveRecord),
            ),

            // ── Doctor & Insurance ──
            _buildSection(
              icon: Icons.medical_information_rounded,
              title: 'Doctor & Insurance',
              section: 'info',
              child: _DoctorInsuranceSection(record: record, onSave: _saveRecord),
            ),

            // ── Last updated ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                'Viewing: $selectedName \u00B7 Updated ${DateFormat('MMM d, y').format(record.updatedAt)}',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String section,
    int? count,
    bool initiallyExpanded = false,
    required Widget child,
  }) {
    final isExpanded = _expandedSections.contains(section);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Column(children: [
          GestureDetector(
            onTap: () => _toggleSection(section),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: AppTheme.primary),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone800)),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$count', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                  ),
                ],
                const Spacer(),
                Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: AppTheme.stone400),
              ]),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: AppTheme.stone100),
            child,
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Allergies Section
// ─────────────────────────────────────────────

class _AllergiesSection extends StatefulWidget {
  final HealthRecord record;
  final Future<void> Function(HealthRecord) onSave;
  const _AllergiesSection({required this.record, required this.onSave});

  @override
  State<_AllergiesSection> createState() => _AllergiesSectionState();
}

class _AllergiesSectionState extends State<_AllergiesSection> {
  final _nameCtrl = TextEditingController();
  final _reactionCtrl = TextEditingController();
  AllergySeverity _severity = AllergySeverity.MILD;

  @override
  void dispose() { _nameCtrl.dispose(); _reactionCtrl.dispose(); super.dispose(); }

  void _add() {
    if (_nameCtrl.text.trim().isEmpty) return;
    final allergy = HealthAllergy(
      id: _uid(), name: _nameCtrl.text.trim(),
      severity: _severity,
      reaction: _reactionCtrl.text.trim().isEmpty ? null : _reactionCtrl.text.trim(),
    );
    final r = widget.record;
    widget.onSave(HealthRecord(
      id: r.id, familyId: r.familyId, userId: r.userId, updatedBy: r.updatedBy,
      bloodType: r.bloodType, allergies: [...r.allergies, allergy],
      medications: r.medications, conditions: r.conditions,
      immunizations: r.immunizations, emergencyContacts: r.emergencyContacts,
      doctorName: r.doctorName, doctorPhone: r.doctorPhone,
      insuranceProvider: r.insuranceProvider, insurancePolicyNumber: r.insurancePolicyNumber,
      notes: r.notes,
    ));
    _nameCtrl.clear(); _reactionCtrl.clear();
    setState(() => _severity = AllergySeverity.MILD);
  }

  void _remove(String id) {
    final r = widget.record;
    widget.onSave(HealthRecord(
      id: r.id, familyId: r.familyId, userId: r.userId, updatedBy: r.updatedBy,
      bloodType: r.bloodType, allergies: r.allergies.where((a) => a.id != id).toList(),
      medications: r.medications, conditions: r.conditions,
      immunizations: r.immunizations, emergencyContacts: r.emergencyContacts,
      doctorName: r.doctorName, doctorPhone: r.doctorPhone,
      insuranceProvider: r.insuranceProvider, insurancePolicyNumber: r.insurancePolicyNumber,
      notes: r.notes,
    ));
  }

  Color _severityColor(AllergySeverity s) {
    switch (s) {
      case AllergySeverity.MILD: return const Color(0xFFF59E0B);
      case AllergySeverity.MODERATE: return const Color(0xFFF97316);
      case AllergySeverity.SEVERE: return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(children: [
        ...widget.record.allergies.map((a) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Text('\u{1F33F}', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800)),
              if (a.reaction != null)
                Text(a.reaction!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _severityColor(a.severity).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(a.severity.name, style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: _severityColor(a.severity))),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _remove(a.id),
              child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone300),
            ),
          ]),
        )),
        // Add form
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.stone200, style: BorderStyle.solid)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(hintText: 'Allergy name', isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reactionCtrl,
              decoration: const InputDecoration(hintText: 'Reaction (optional)', isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500),
            ),
            const SizedBox(height: 10),
            Row(children: [
              ...AllergySeverity.values.map((s) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _severity = s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _severity == s ? _severityColor(s).withValues(alpha: 0.15) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _severity == s ? _severityColor(s) : AppTheme.stone200),
                    ),
                    child: Text(s.name, style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: _severity == s ? _severityColor(s) : AppTheme.stone500)),
                  ),
                ),
              )),
              const Spacer(),
              GestureDetector(
                onTap: _add,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Add', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Medications Section
// ─────────────────────────────────────────────

class _MedicationsSection extends StatefulWidget {
  final HealthRecord record;
  final Future<void> Function(HealthRecord) onSave;
  const _MedicationsSection({required this.record, required this.onSave});

  @override
  State<_MedicationsSection> createState() => _MedicationsSectionState();
}

class _MedicationsSectionState extends State<_MedicationsSection> {
  final _nameCtrl = TextEditingController();
  final _doseCtrl = TextEditingController();
  final _freqCtrl = TextEditingController();

  @override
  void dispose() { _nameCtrl.dispose(); _doseCtrl.dispose(); _freqCtrl.dispose(); super.dispose(); }

  void _add() {
    if (_nameCtrl.text.trim().isEmpty) return;
    final med = HealthMedication(
      id: _uid(), name: _nameCtrl.text.trim(),
      dose: _doseCtrl.text.trim().isEmpty ? null : _doseCtrl.text.trim(),
      frequency: _freqCtrl.text.trim().isEmpty ? null : _freqCtrl.text.trim(),
    );
    final r = widget.record;
    widget.onSave(HealthRecord(
      id: r.id, familyId: r.familyId, userId: r.userId, updatedBy: r.updatedBy,
      bloodType: r.bloodType, allergies: r.allergies,
      medications: [...r.medications, med], conditions: r.conditions,
      immunizations: r.immunizations, emergencyContacts: r.emergencyContacts,
      doctorName: r.doctorName, doctorPhone: r.doctorPhone,
      insuranceProvider: r.insuranceProvider, insurancePolicyNumber: r.insurancePolicyNumber,
      notes: r.notes,
    ));
    _nameCtrl.clear(); _doseCtrl.clear(); _freqCtrl.clear();
  }

  void _remove(String id) {
    final r = widget.record;
    widget.onSave(HealthRecord(
      id: r.id, familyId: r.familyId, userId: r.userId, updatedBy: r.updatedBy,
      bloodType: r.bloodType, allergies: r.allergies,
      medications: r.medications.where((m) => m.id != id).toList(),
      conditions: r.conditions, immunizations: r.immunizations,
      emergencyContacts: r.emergencyContacts,
      doctorName: r.doctorName, doctorPhone: r.doctorPhone,
      insuranceProvider: r.insuranceProvider, insurancePolicyNumber: r.insurancePolicyNumber,
      notes: r.notes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(children: [
        ...widget.record.medications.map((m) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Text('\u{1F48A}', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800)),
              if (m.dose != null || m.frequency != null)
                Text([m.dose, m.frequency].where((s) => s != null).join(' \u00B7 '),
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
            ])),
            GestureDetector(
              onTap: () => _remove(m.id),
              child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone300),
            ),
          ]),
        )),
        if (widget.record.medications.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No medications recorded.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
          ),
        _InlineAddRow(
          fields: [
            _InlineField(controller: _nameCtrl, hint: 'Medication name'),
            _InlineField(controller: _doseCtrl, hint: 'Dose'),
            _InlineField(controller: _freqCtrl, hint: 'Frequency'),
          ],
          onAdd: _add,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Conditions Section
// ─────────────────────────────────────────────

class _ConditionsSection extends StatefulWidget {
  final HealthRecord record;
  final Future<void> Function(HealthRecord) onSave;
  const _ConditionsSection({required this.record, required this.onSave});

  @override
  State<_ConditionsSection> createState() => _ConditionsSectionState();
}

class _ConditionsSectionState extends State<_ConditionsSection> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void dispose() { _nameCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  void _add() {
    if (_nameCtrl.text.trim().isEmpty) return;
    final cond = HealthCondition(
      id: _uid(), name: _nameCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    final r = widget.record;
    widget.onSave(HealthRecord(
      id: r.id, familyId: r.familyId, userId: r.userId, updatedBy: r.updatedBy,
      bloodType: r.bloodType, allergies: r.allergies, medications: r.medications,
      conditions: [...r.conditions, cond],
      immunizations: r.immunizations, emergencyContacts: r.emergencyContacts,
      doctorName: r.doctorName, doctorPhone: r.doctorPhone,
      insuranceProvider: r.insuranceProvider, insurancePolicyNumber: r.insurancePolicyNumber,
      notes: r.notes,
    ));
    _nameCtrl.clear(); _notesCtrl.clear();
  }

  void _remove(String id) {
    final r = widget.record;
    widget.onSave(HealthRecord(
      id: r.id, familyId: r.familyId, userId: r.userId, updatedBy: r.updatedBy,
      bloodType: r.bloodType, allergies: r.allergies, medications: r.medications,
      conditions: r.conditions.where((c) => c.id != id).toList(),
      immunizations: r.immunizations, emergencyContacts: r.emergencyContacts,
      doctorName: r.doctorName, doctorPhone: r.doctorPhone,
      insuranceProvider: r.insuranceProvider, insurancePolicyNumber: r.insurancePolicyNumber,
      notes: r.notes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(children: [
        ...widget.record.conditions.map((c) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Text('\u{1F3E5}', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800)),
              if (c.notes != null)
                Text(c.notes!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
            ])),
            GestureDetector(
              onTap: () => _remove(c.id),
              child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone300),
            ),
          ]),
        )),
        if (widget.record.conditions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No conditions recorded.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
          ),
        _InlineAddRow(
          fields: [
            _InlineField(controller: _nameCtrl, hint: 'Condition name'),
            _InlineField(controller: _notesCtrl, hint: 'Notes (optional)'),
          ],
          onAdd: _add,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Immunizations Section
// ─────────────────────────────────────────────

class _ImmunizationsSection extends StatefulWidget {
  final HealthRecord record;
  final Future<void> Function(HealthRecord) onSave;
  const _ImmunizationsSection({required this.record, required this.onSave});

  @override
  State<_ImmunizationsSection> createState() => _ImmunizationsSectionState();
}

class _ImmunizationsSectionState extends State<_ImmunizationsSection> {
  final _nameCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();

  @override
  void dispose() { _nameCtrl.dispose(); _dateCtrl.dispose(); super.dispose(); }

  void _add() {
    if (_nameCtrl.text.trim().isEmpty) return;
    final immu = HealthImmunization(
      id: _uid(), name: _nameCtrl.text.trim(),
      date: DateTime.tryParse(_dateCtrl.text.trim()),
    );
    final r = widget.record;
    widget.onSave(HealthRecord(
      id: r.id, familyId: r.familyId, userId: r.userId, updatedBy: r.updatedBy,
      bloodType: r.bloodType, allergies: r.allergies, medications: r.medications,
      conditions: r.conditions, immunizations: [...r.immunizations, immu],
      emergencyContacts: r.emergencyContacts,
      doctorName: r.doctorName, doctorPhone: r.doctorPhone,
      insuranceProvider: r.insuranceProvider, insurancePolicyNumber: r.insurancePolicyNumber,
      notes: r.notes,
    ));
    _nameCtrl.clear(); _dateCtrl.clear();
  }

  void _remove(String id) {
    final r = widget.record;
    widget.onSave(HealthRecord(
      id: r.id, familyId: r.familyId, userId: r.userId, updatedBy: r.updatedBy,
      bloodType: r.bloodType, allergies: r.allergies, medications: r.medications,
      conditions: r.conditions,
      immunizations: r.immunizations.where((i) => i.id != id).toList(),
      emergencyContacts: r.emergencyContacts,
      doctorName: r.doctorName, doctorPhone: r.doctorPhone,
      insuranceProvider: r.insuranceProvider, insurancePolicyNumber: r.insurancePolicyNumber,
      notes: r.notes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(children: [
        ...widget.record.immunizations.map((i) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Text('\u{1F489}', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800)),
              if (i.date != null)
                Text(DateFormat('MMM d, y').format(i.date!), style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
            ])),
            GestureDetector(
              onTap: () => _remove(i.id),
              child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone300),
            ),
          ]),
        )),
        if (widget.record.immunizations.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No immunizations recorded.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
          ),
        _InlineAddRow(
          fields: [
            _InlineField(controller: _nameCtrl, hint: 'Vaccine name'),
            _InlineField(controller: _dateCtrl, hint: 'Date (YYYY-MM-DD)'),
          ],
          onAdd: _add,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Emergency Contacts Section
// ─────────────────────────────────────────────

class _EmergencySection extends StatefulWidget {
  final HealthRecord record;
  final Future<void> Function(HealthRecord) onSave;
  const _EmergencySection({required this.record, required this.onSave});

  @override
  State<_EmergencySection> createState() => _EmergencySectionState();
}

class _EmergencySectionState extends State<_EmergencySection> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _relationCtrl = TextEditingController();

  @override
  void dispose() { _nameCtrl.dispose(); _phoneCtrl.dispose(); _relationCtrl.dispose(); super.dispose(); }

  void _add() {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) return;
    final ec = EmergencyContact(
      id: _uid(), name: _nameCtrl.text.trim(), phone: _phoneCtrl.text.trim(),
      relation: _relationCtrl.text.trim().isEmpty ? null : _relationCtrl.text.trim(),
    );
    final r = widget.record;
    widget.onSave(HealthRecord(
      id: r.id, familyId: r.familyId, userId: r.userId, updatedBy: r.updatedBy,
      bloodType: r.bloodType, allergies: r.allergies, medications: r.medications,
      conditions: r.conditions, immunizations: r.immunizations,
      emergencyContacts: [...r.emergencyContacts, ec],
      doctorName: r.doctorName, doctorPhone: r.doctorPhone,
      insuranceProvider: r.insuranceProvider, insurancePolicyNumber: r.insurancePolicyNumber,
      notes: r.notes,
    ));
    _nameCtrl.clear(); _phoneCtrl.clear(); _relationCtrl.clear();
  }

  void _remove(String id) {
    final r = widget.record;
    widget.onSave(HealthRecord(
      id: r.id, familyId: r.familyId, userId: r.userId, updatedBy: r.updatedBy,
      bloodType: r.bloodType, allergies: r.allergies, medications: r.medications,
      conditions: r.conditions, immunizations: r.immunizations,
      emergencyContacts: r.emergencyContacts.where((e) => e.id != id).toList(),
      doctorName: r.doctorName, doctorPhone: r.doctorPhone,
      insuranceProvider: r.insuranceProvider, insurancePolicyNumber: r.insurancePolicyNumber,
      notes: r.notes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(children: [
        ...widget.record.emergencyContacts.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Text('\u{1F6A8}', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800)),
              Text(e.phone, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
              if (e.relation != null)
                Text(e.relation!, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
            ])),
            GestureDetector(
              onTap: () => _remove(e.id),
              child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone300),
            ),
          ]),
        )),
        _InlineAddRow(
          fields: [
            _InlineField(controller: _nameCtrl, hint: 'Contact name'),
            _InlineField(controller: _phoneCtrl, hint: 'Phone number'),
            _InlineField(controller: _relationCtrl, hint: 'Relation (optional)'),
          ],
          onAdd: _add,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Doctor & Insurance Section
// ─────────────────────────────────────────────

class _DoctorInsuranceSection extends StatefulWidget {
  final HealthRecord record;
  final Future<void> Function(HealthRecord) onSave;
  const _DoctorInsuranceSection({required this.record, required this.onSave});

  @override
  State<_DoctorInsuranceSection> createState() => _DoctorInsuranceSectionState();
}

class _DoctorInsuranceSectionState extends State<_DoctorInsuranceSection> {
  late final TextEditingController _doctorNameCtrl;
  late final TextEditingController _doctorPhoneCtrl;
  late final TextEditingController _insurerCtrl;
  late final TextEditingController _policyCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _doctorNameCtrl = TextEditingController(text: widget.record.doctorName ?? '');
    _doctorPhoneCtrl = TextEditingController(text: widget.record.doctorPhone ?? '');
    _insurerCtrl = TextEditingController(text: widget.record.insuranceProvider ?? '');
    _policyCtrl = TextEditingController(text: widget.record.insurancePolicyNumber ?? '');
    _notesCtrl = TextEditingController(text: widget.record.notes ?? '');
  }

  @override
  void didUpdateWidget(covariant _DoctorInsuranceSection old) {
    super.didUpdateWidget(old);
    if (old.record.id != widget.record.id) {
      _doctorNameCtrl.text = widget.record.doctorName ?? '';
      _doctorPhoneCtrl.text = widget.record.doctorPhone ?? '';
      _insurerCtrl.text = widget.record.insuranceProvider ?? '';
      _policyCtrl.text = widget.record.insurancePolicyNumber ?? '';
      _notesCtrl.text = widget.record.notes ?? '';
    }
  }

  @override
  void dispose() { _doctorNameCtrl.dispose(); _doctorPhoneCtrl.dispose(); _insurerCtrl.dispose(); _policyCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  void _flush() {
    final r = widget.record;
    widget.onSave(HealthRecord(
      id: r.id, familyId: r.familyId, userId: r.userId, updatedBy: r.updatedBy,
      bloodType: r.bloodType, allergies: r.allergies, medications: r.medications,
      conditions: r.conditions, immunizations: r.immunizations,
      emergencyContacts: r.emergencyContacts,
      doctorName: _doctorNameCtrl.text.trim().isEmpty ? null : _doctorNameCtrl.text.trim(),
      doctorPhone: _doctorPhoneCtrl.text.trim().isEmpty ? null : _doctorPhoneCtrl.text.trim(),
      insuranceProvider: _insurerCtrl.text.trim().isEmpty ? null : _insurerCtrl.text.trim(),
      insurancePolicyNumber: _policyCtrl.text.trim().isEmpty ? null : _policyCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    ));
  }

  Widget _infoField(String label, TextEditingController ctrl) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone400, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        onEditingComplete: _flush,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.stone200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.stone200)),
        ),
        style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
      ),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(children: [
        _infoField('Doctor Name', _doctorNameCtrl),
        _infoField('Doctor Phone', _doctorPhoneCtrl),
        _infoField('Insurance Provider', _insurerCtrl),
        _infoField('Policy Number', _policyCtrl),
        _infoField('Notes', _notesCtrl),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: _flush,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(10)),
              child: const Text('Save', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// Inline Add Row helper
// ─────────────────────────────────────────────

class _InlineField {
  final TextEditingController controller;
  final String hint;
  const _InlineField({required this.controller, required this.hint});
}

class _InlineAddRow extends StatelessWidget {
  final List<_InlineField> fields;
  final VoidCallback onAdd;
  const _InlineAddRow({required this.fields, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.stone50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.stone200, style: BorderStyle.solid),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...fields.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: TextField(
            controller: f.controller,
            decoration: InputDecoration(hintText: f.hint, isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
            style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
          ),
        )),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(8)),
              child: const Text('Add', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
            ),
          ),
        ),
      ]),
    );
  }
}

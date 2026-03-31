// lib/screens/health/health_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../utils/debounce.dart';

const _uuid = Uuid();
String _uid() => _uuid.v4().substring(0, 9);

String _bloodTypeLabel(BloodType bt) {
  switch (bt) {
    case BloodType.Aplus: return 'A+';
    case BloodType.Aminus: return 'A\u2212';
    case BloodType.Bplus: return 'B+';
    case BloodType.Bminus: return 'B\u2212';
    case BloodType.ABplus: return 'AB+';
    case BloodType.ABminus: return 'AB\u2212';
    case BloodType.Oplus: return 'O+';
    case BloodType.Ominus: return 'O\u2212';
    case BloodType.Unknown: return '?';
  }
}

const _bloodTypes = BloodType.values;

// ─── Shared helper: styled remove confirmation ────────────────────────────────

Future<bool> _confirmRemove(BuildContext context, String title, String message) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: const TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800))),
      ]),
      content: Text(message, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppTheme.stone500)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Remove', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppTheme.error)),
        ),
      ],
    ),
  );
  return confirmed == true;
}

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

// ─── Styled input decoration ──────────────────────────────────────────────────

HealthRecord _healthRecordFilteredForSearch(HealthRecord r, String rawQ) {
  final q = rawQ.trim().toLowerCase();
  if (q.isEmpty) return r;
  bool m(String s) => s.toLowerCase().contains(q);
  bool emOk(EmergencyContact c) =>
      m(c.name) || m(c.phone) || (c.relation != null && m(c.relation!));
  return HealthRecord(
    id: r.id,
    familyId: r.familyId,
    userId: r.userId,
    updatedBy: r.updatedBy,
    bloodType: r.bloodType,
    allergies: r.allergies
        .where((a) => m(a.name) || (a.reaction != null && m(a.reaction!)))
        .toList(),
    medications: r.medications
        .where((med) =>
            m(med.name) ||
            (med.dose != null && m(med.dose!)) ||
            (med.frequency != null && m(med.frequency!)))
        .toList(),
    conditions: r.conditions
        .where((c) => m(c.name) || (c.notes != null && m(c.notes!)))
        .toList(),
    immunizations: r.immunizations.where((i) {
      if (m(i.name)) return true;
      if (i.date == null) return false;
      return m(DateFormat('MMM d, y').format(i.date!));
    }).toList(),
    emergencyContacts: r.emergencyContacts.where(emOk).toList(),
    doctorName: r.doctorName,
    doctorPhone: r.doctorPhone,
    insuranceProvider: r.insuranceProvider,
    insurancePolicyNumber: r.insurancePolicyNumber,
    notes: r.notes,
    updatedAt: r.updatedAt,
    type: r.type,
    title: r.title,
    data: r.data,
  );
}

InputDecoration _styledInput(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: AppTheme.stone300, fontFamily: 'Inter', fontSize: 13),
  filled: true,
  fillColor: Colors.white,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: AppTheme.stone200),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: AppTheme.stone200),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
  ),
);

// ─── Health Screen ────────────────────────────────────────────────────────────

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  String? _selectedMemberId;
  final Set<String> _expandedSections = {'allergies', 'emergency'};
  final _healthSearchCtrl = TextEditingController();
  final _healthSearchDebounce = Debouncer();
  String _healthSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _healthSearchCtrl.addListener(() {
      final t = _healthSearchCtrl.text;
      _healthSearchDebounce.run(() {
        if (mounted) setState(() => _healthSearchQuery = t);
      });
    });
  }

  @override
  void dispose() {
    _healthSearchCtrl.dispose();
    _healthSearchDebounce.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AppProvider>();
    if (_selectedMemberId == null && provider.activeUser != null) {
      _selectedMemberId = provider.activeUser!.id;
    }
  }

  HealthRecord _getRecord(AppProvider provider, String memberId) {
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) {
      return HealthRecord(id: 'health_unknown_$memberId', familyId: '', userId: memberId, updatedBy: '');
    }
    final records = provider.db.healthRecords
        .where((r) => r.familyId == family.id && r.userId == memberId)
        .toList();
    if (records.isNotEmpty) return records.first;
    return HealthRecord(
      id: 'health_${family.id}_$memberId',
      familyId: family.id,
      userId: memberId,
      updatedBy: user.id,
    );
  }

  Future<void> _saveRecord(HealthRecord updated) async {
    final provider = context.read<AppProvider>();
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) return;
    final db = provider.db;
    final filtered = db.healthRecords
        .where((r) => !(r.familyId == family.id && r.userId == updated.userId))
        .toList();
    final withTimestamp = HealthRecord(
      id: updated.id,
      familyId: updated.familyId,
      userId: updated.userId,
      updatedBy: user.id,
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

  void _shareEmergencyCard(HealthRecord record, String name) {
    final buf = StringBuffer();
    buf.writeln('EMERGENCY MEDICAL CARD');
    buf.writeln('Name: $name');
    buf.writeln('Blood Type: ${_bloodTypeLabel(record.bloodType)}');
    buf.writeln('');

    if (record.allergies.isNotEmpty) {
      buf.writeln('ALLERGIES');
      for (final a in record.allergies) {
        buf.writeln('  \u2022 ${a.name}${a.severity != null ? ' (${a.severity})' : ''}');
      }
      buf.writeln('');
    }

    if (record.medications.isNotEmpty) {
      buf.writeln('MEDICATIONS');
      for (final m in record.medications) {
        buf.writeln('  \u2022 ${m.name}${m.dose != null ? ' — ${m.dose}' : ''}');
      }
      buf.writeln('');
    }

    if (record.conditions.isNotEmpty) {
      buf.writeln('CONDITIONS');
      for (final c in record.conditions) {
        buf.writeln('  \u2022 ${c.name}');
      }
      buf.writeln('');
    }

    if (record.emergencyContacts.isNotEmpty) {
      buf.writeln('EMERGENCY CONTACTS');
      for (final c in record.emergencyContacts) {
        buf.writeln('  \u2022 ${c.name}${c.relation != null ? ' (${c.relation})' : ''}: ${c.phone}');
      }
      buf.writeln('');
    }

    if (record.doctorName != null && record.doctorName!.isNotEmpty) {
      buf.writeln('DOCTOR: ${record.doctorName}');
      if (record.doctorPhone != null) buf.writeln('  Phone: ${record.doctorPhone}');
    }
    if (record.insuranceProvider != null && record.insuranceProvider!.isNotEmpty) {
      buf.writeln('INSURANCE: ${record.insuranceProvider}');
      if (record.insurancePolicyNumber != null) buf.writeln('  Policy: ${record.insurancePolicyNumber}');
    }

    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Emergency card copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
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
    final filteredRecord =
        _healthRecordFilteredForSearch(record, _healthSearchQuery);
    final selectedName = provider.memberDisplayName(
      members.firstWhere((m) => m.id == _selectedMemberId, orElse: () => members.first),
    );

    // Stats
    final totalItems = record.allergies.length + record.medications.length +
        record.conditions.length + record.immunizations.length;
    final emergencyCount = record.emergencyContacts.length;

    return Scaffold(
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const FamilyHubAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ──────────────────────────────────────────
            PageHeader(
              title: '\u{1FA7A} Health Records',
              subtitle: 'Allergies, medications & emergency info',
              actions: [
                ActionChipButton(
                  icon: Icons.share_rounded,
                  label: 'Emergency Card',
                  onTap: () => _shareEmergencyCard(record, selectedName),
                  isPrimary: true,
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFFA8A29E)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'For informational purposes only. Not a substitute for professional medical advice. Always consult your doctor.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFFA8A29E),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ─── Stat cards ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(children: [
                _MiniStat(
                  icon: Icons.favorite_rounded,
                  iconColor: const Color(0xFFF43F5E),
                  value: _bloodTypeLabel(record.bloodType),
                  label: 'Blood Type',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.medical_services_rounded,
                  iconColor: AppTheme.primary,
                  value: '$totalItems',
                  label: 'Records',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.emergency_rounded,
                  iconColor: const Color(0xFFD97706),
                  value: '$emergencyCount',
                  label: 'Contacts',
                ),
              ]),
            ),

            // ─── Member selector ─────────────────────────────────
            if (members.length > 1)
              SizedBox(
                height: 90,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: members.map((m) {
                    final isSelected = _selectedMemberId == m.id;
                    final name = provider.memberDisplayName(m);
                    return Semantics(
                      button: true,
                      label: 'View health record for $name',
                      selected: isSelected,
                      child: GestureDetector(
                      onTap: () => setState(() => _selectedMemberId = m.id),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
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
                    ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                controller: _healthSearchCtrl,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search allergies, meds, conditions…',
                  hintStyle: const TextStyle(fontFamily: 'Inter', color: AppTheme.stone400),
                  prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.stone400),
                  suffixIcon: _healthSearchQuery.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.stone400),
                          onPressed: () {
                            _healthSearchCtrl.clear();
                            setState(() => _healthSearchQuery = '');
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.stone200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.stone200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // ─── Blood Type ──────────────────────────────────────
            _buildSection(
              icon: Icons.bloodtype_rounded,
              iconColor: const Color(0xFFF43F5E),
              title: 'Blood Type',
              section: 'blood',
              initiallyExpanded: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _bloodTypes.map((bt) {
                    final isSelected = record.bloodType == bt;
                    return GestureDetector(
                      onTap: () {
                        final r = record;
                        _saveRecord(HealthRecord(
                          id: r.id, familyId: r.familyId, userId: r.userId,
                          updatedBy: user.id, bloodType: bt,
                          allergies: r.allergies, medications: r.medications,
                          conditions: r.conditions, immunizations: r.immunizations,
                          emergencyContacts: r.emergencyContacts,
                          doctorName: r.doctorName, doctorPhone: r.doctorPhone,
                          insuranceProvider: r.insuranceProvider,
                          insurancePolicyNumber: r.insurancePolicyNumber,
                          notes: r.notes,
                        ));
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFF43F5E) : AppTheme.stone50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFF43F5E) : AppTheme.stone200,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          _bloodTypeLabel(bt),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 14,
                            color: isSelected ? Colors.white : AppTheme.stone600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // ─── Allergies ───────────────────────────────────────
            _buildSection(
              icon: Icons.warning_amber_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: 'Allergies',
              section: 'allergies',
              count: filteredRecord.allergies.length,
              child: _AllergiesSection(record: record, displayRecord: filteredRecord, onSave: _saveRecord),
            ),

            // ─── Medications ─────────────────────────────────────
            _buildSection(
              icon: Icons.medication_rounded,
              iconColor: const Color(0xFF3B82F6),
              title: 'Medications',
              section: 'medications',
              count: filteredRecord.medications.length,
              child: _MedicationsSection(record: record, displayRecord: filteredRecord, onSave: _saveRecord),
            ),

            // ─── Medical Conditions ──────────────────────────────
            _buildSection(
              icon: Icons.local_hospital_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: 'Medical Conditions',
              section: 'conditions',
              count: filteredRecord.conditions.length,
              child: _ConditionsSection(record: record, displayRecord: filteredRecord, onSave: _saveRecord),
            ),

            // ─── Immunizations ───────────────────────────────────
            _buildSection(
              icon: Icons.vaccines_rounded,
              iconColor: const Color(0xFF22C55E),
              title: 'Immunizations',
              section: 'immunizations',
              count: filteredRecord.immunizations.length,
              child: _ImmunizationsSection(record: record, displayRecord: filteredRecord, onSave: _saveRecord),
            ),

            // ─── Emergency Contacts ──────────────────────────────
            _buildSection(
              icon: Icons.emergency_rounded,
              iconColor: const Color(0xFFEF4444),
              title: 'Emergency Contacts',
              section: 'emergency',
              count: filteredRecord.emergencyContacts.length,
              child: _EmergencySection(record: record, displayRecord: filteredRecord, onSave: _saveRecord),
            ),

            // ─── Doctor & Insurance ──────────────────────────────
            _buildSection(
              icon: Icons.medical_information_rounded,
              iconColor: const Color(0xFF0EA5E9),
              title: 'Doctor & Insurance',
              section: 'info',
              child: _DoctorInsuranceSection(record: record, onSave: _saveRecord),
            ),

            // ─── Footer ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.stone50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.person_outline_rounded, size: 14, color: AppTheme.stone400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Viewing: $selectedName \u00B7 Updated ${DateFormat('MMM d, y').format(record.updatedAt)}',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String section,
    int? count,
    bool initiallyExpanded = false,
    required Widget child,
  }) {
    final isExpanded = _expandedSections.contains(section);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isExpanded ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.stone100),
        ),
        child: Column(children: [
          GestureDetector(
            onTap: () => _toggleSection(section),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone800)),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$count', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: iconColor)),
                  ),
                ],
                const Spacer(),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded, size: 20, color: AppTheme.stone400),
                ),
              ]),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(children: [
              const Divider(height: 1, color: AppTheme.stone100),
              child,
            ]),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ]),
      ),
    );
  }
}

// ─── Mini Stat Card ───────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _MiniStat({required this.icon, required this.iconColor, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.stone800,
                )),
                Text(label, style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.stone400,
                )),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Allergies Section ────────────────────────────────────────────────────────

class _AllergiesSection extends StatefulWidget {
  final HealthRecord record;
  final HealthRecord displayRecord;
  final Future<void> Function(HealthRecord) onSave;
  const _AllergiesSection({required this.record, required this.displayRecord, required this.onSave});

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
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnack(context, 'Please enter an allergy name');
      return;
    }
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

  Future<void> _remove(String id) async {
    if (!await _confirmRemove(context, 'Remove Allergy', 'Remove this allergy from the health record?')) return;
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
        // Existing items
        ...widget.displayRecord.allergies.map((a) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: _severityColor(a.severity).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Center(child: Text('\u{1F33F}', style: TextStyle(fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800)),
              if (a.reaction != null)
                Text(a.reaction!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _severityColor(a.severity).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(a.severity.name, style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: _severityColor(a.severity))),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _remove(a.id),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.stone100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.stone400),
              ),
            ),
          ]),
        )),
        if (widget.displayRecord.allergies.isEmpty)
          _emptyHint(widget.record.allergies.isEmpty ? 'No allergies recorded' : 'No matches'),
        // Add form
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.stone50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.stone200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _nameCtrl,
              decoration: _styledInput('Allergy name'),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reactionCtrl,
              decoration: _styledInput('Reaction (optional)'),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(children: [
              ...AllergySeverity.values.map((s) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _severity = s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _severity == s ? _severityColor(s).withValues(alpha: 0.12) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _severity == s ? _severityColor(s) : AppTheme.stone200,
                        width: _severity == s ? 1.5 : 1,
                      ),
                    ),
                    child: Text(s.name, style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: _severity == s ? _severityColor(s) : AppTheme.stone500)),
                  ),
                ),
              )),
              const Spacer(),
              _addButton(onTap: _add),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ─── Medications Section ──────────────────────────────────────────────────────

class _MedicationsSection extends StatefulWidget {
  final HealthRecord record;
  final HealthRecord displayRecord;
  final Future<void> Function(HealthRecord) onSave;
  const _MedicationsSection({required this.record, required this.displayRecord, required this.onSave});

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
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnack(context, 'Please enter a medication name');
      return;
    }
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

  Future<void> _remove(String id) async {
    if (!await _confirmRemove(context, 'Remove Medication', 'Remove this medication from the health record?')) return;
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
        ...widget.displayRecord.medications.map((m) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Center(child: Text('\u{1F48A}', style: TextStyle(fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800)),
              if (m.dose != null || m.frequency != null)
                Text([m.dose, m.frequency].where((s) => s != null).join(' \u00B7 '),
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
            ])),
            GestureDetector(
              onTap: () => _remove(m.id),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: AppTheme.stone100, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.stone400),
              ),
            ),
          ]),
        )),
        if (widget.displayRecord.medications.isEmpty)
          _emptyHint(widget.record.medications.isEmpty ? 'No medications recorded' : 'No matches'),
        _InlineAddRow(
          fields: [
            _InlineField(controller: _nameCtrl, hint: 'Medication name'),
            _InlineField(controller: _doseCtrl, hint: 'Dose (optional)'),
            _InlineField(controller: _freqCtrl, hint: 'Frequency (optional)'),
          ],
          onAdd: _add,
        ),
      ]),
    );
  }
}

// ─── Conditions Section ───────────────────────────────────────────────────────

class _ConditionsSection extends StatefulWidget {
  final HealthRecord record;
  final HealthRecord displayRecord;
  final Future<void> Function(HealthRecord) onSave;
  const _ConditionsSection({required this.record, required this.displayRecord, required this.onSave});

  @override
  State<_ConditionsSection> createState() => _ConditionsSectionState();
}

class _ConditionsSectionState extends State<_ConditionsSection> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void dispose() { _nameCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  void _add() {
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnack(context, 'Please enter a condition name');
      return;
    }
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

  Future<void> _remove(String id) async {
    if (!await _confirmRemove(context, 'Remove Condition', 'Remove this condition from the health record?')) return;
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
        ...widget.displayRecord.conditions.map((c) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Center(child: Text('\u{1F3E5}', style: TextStyle(fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800)),
              if (c.notes != null)
                Text(c.notes!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
            ])),
            GestureDetector(
              onTap: () => _remove(c.id),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: AppTheme.stone100, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.stone400),
              ),
            ),
          ]),
        )),
        if (widget.displayRecord.conditions.isEmpty)
          _emptyHint(widget.record.conditions.isEmpty ? 'No conditions recorded' : 'No matches'),
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

// ─── Immunizations Section ────────────────────────────────────────────────────

class _ImmunizationsSection extends StatefulWidget {
  final HealthRecord record;
  final HealthRecord displayRecord;
  final Future<void> Function(HealthRecord) onSave;
  const _ImmunizationsSection({required this.record, required this.displayRecord, required this.onSave});

  @override
  State<_ImmunizationsSection> createState() => _ImmunizationsSectionState();
}

class _ImmunizationsSectionState extends State<_ImmunizationsSection> {
  final _nameCtrl = TextEditingController();
  DateTime? _selectedDate;

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _add() {
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnack(context, 'Please enter an immunization name');
      return;
    }
    final immu = HealthImmunization(
      id: _uid(), name: _nameCtrl.text.trim(),
      date: _selectedDate,
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
    _nameCtrl.clear();
    setState(() => _selectedDate = null);
  }

  Future<void> _remove(String id) async {
    if (!await _confirmRemove(context, 'Remove Immunization', 'Remove this immunization from the health record?')) return;
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
        ...widget.displayRecord.immunizations.map((i) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Center(child: Text('\u{1F489}', style: TextStyle(fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800)),
              if (i.date != null)
                Row(children: [
                  const Icon(Icons.calendar_today_rounded, size: 11, color: AppTheme.stone400),
                  const SizedBox(width: 4),
                  Text(DateFormat('MMM d, y').format(i.date!), style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
                ]),
            ])),
            GestureDetector(
              onTap: () => _remove(i.id),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: AppTheme.stone100, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.stone400),
              ),
            ),
          ]),
        )),
        if (widget.displayRecord.immunizations.isEmpty)
          _emptyHint(widget.record.immunizations.isEmpty ? 'No immunizations recorded' : 'No matches'),
        // Add form with date picker
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.stone50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.stone200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _nameCtrl,
              decoration: _styledInput('Vaccine name'),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDate,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.stone200),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today_rounded, size: 14, color: _selectedDate != null ? AppTheme.primary : AppTheme.stone400),
                  const SizedBox(width: 8),
                  Text(
                    _selectedDate != null ? DateFormat('MMM d, yyyy').format(_selectedDate!) : 'Date (optional)',
                    style: TextStyle(
                      fontFamily: 'Inter', fontSize: 13,
                      color: _selectedDate != null ? AppTheme.stone800 : AppTheme.stone300,
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: _addButton(onTap: _add)),
          ]),
        ),
      ]),
    );
  }
}

// ─── Emergency Contacts Section ───────────────────────────────────────────────

class _EmergencySection extends StatefulWidget {
  final HealthRecord record;
  final HealthRecord displayRecord;
  final Future<void> Function(HealthRecord) onSave;
  const _EmergencySection({required this.record, required this.displayRecord, required this.onSave});

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
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnack(context, 'Please enter a contact name');
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      _showSnack(context, 'Please enter a phone number');
      return;
    }
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

  Future<void> _remove(String id) async {
    if (!await _confirmRemove(context, 'Remove Contact', 'Remove this emergency contact?')) return;
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
        ...widget.displayRecord.emergencyContacts.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Center(child: Text('\u{1F6A8}', style: TextStyle(fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800)),
              Row(children: [
                const Icon(Icons.phone_rounded, size: 11, color: AppTheme.stone400),
                const SizedBox(width: 4),
                Text(e.phone, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
              ]),
              if (e.relation != null)
                Text(e.relation!, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
            ])),
            GestureDetector(
              onTap: () => _remove(e.id),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: AppTheme.stone100, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.stone400),
              ),
            ),
          ]),
        )),
        if (widget.displayRecord.emergencyContacts.isEmpty)
          _emptyHint(widget.record.emergencyContacts.isEmpty ? 'No emergency contacts' : 'No matches'),
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

// ─── Doctor & Insurance Section ───────────────────────────────────────────────

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
    _showSnack(context, 'Info saved');
  }

  Widget _infoField(String label, TextEditingController ctrl, {TextInputType? keyboardType}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        onEditingComplete: _flush,
        decoration: InputDecoration(
          filled: true,
          fillColor: AppTheme.stone50,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppTheme.stone200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppTheme.stone200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
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
        _infoField('Doctor Phone', _doctorPhoneCtrl, keyboardType: TextInputType.phone),
        _infoField('Insurance Provider', _insurerCtrl),
        _infoField('Policy Number', _policyCtrl),
        _infoField('Notes', _notesCtrl),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _flush,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Save Info', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ]),
    );
  }
}

// ─── Shared Helpers ───────────────────────────────────────────────────────────

Widget _emptyHint(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Row(children: [
    Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: AppTheme.stone100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.stone300),
    ),
    const SizedBox(width: 8),
    Text(text, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.stone400)),
  ]),
);

Widget _addButton({required VoidCallback onTap}) => GestureDetector(
  onTap: onTap,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.primary,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.add_rounded, size: 14, color: Colors.white),
      SizedBox(width: 4),
      Text('Add', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
    ]),
  ),
);

// ─── Inline Add Row helper ────────────────────────────────────────────────────

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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.stone200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...fields.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: f.controller,
            decoration: _styledInput(f.hint),
            style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
          ),
        )),
        Align(
          alignment: Alignment.centerRight,
          child: _addButton(onTap: onAdd),
        ),
      ]),
    );
  }
}

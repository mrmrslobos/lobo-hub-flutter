// lib/models/health_record.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import '_enums.dart';
import 'model_json_helpers.dart';
import 'emergency_contact.dart';
import 'health_allergy.dart';
import 'health_condition.dart';
import 'health_immunization.dart';
import 'health_medication.dart';

class HealthRecord {
  final String id;
  final String familyId;
  final String memberId;
  final String? updatedBy;
  final BloodType bloodType;
  final List<HealthAllergy> allergies;
  final List<HealthMedication> medications;
  final List<HealthCondition> conditions;
  final List<HealthImmunization> immunizations;
  final List<EmergencyContact> emergencyContacts;
  final String? doctorName;
  final String? doctorPhone;
  final String? insuranceProvider;
  final String? insurancePolicyNumber;
  final String? notes;
  final DateTime updatedAt;
  // Extended log-style fields
  final String? type;
  final String? title;
  final Map<String, String> data;

  HealthRecord({
    required this.id,
    required this.familyId,
    String? userId,
    String? memberId,
    this.updatedBy,
    this.bloodType = BloodType.Unknown,
    this.allergies = const [],
    this.medications = const [],
    this.conditions = const [],
    this.immunizations = const [],
    this.emergencyContacts = const [],
    this.doctorName,
    this.doctorPhone,
    this.insuranceProvider,
    this.insurancePolicyNumber,
    this.notes,
    DateTime? updatedAt,
    DateTime? date,
    this.type,
    this.title,
    this.data = const {},
  }) : memberId = userId ?? memberId ?? '',
       updatedAt = updatedAt ?? date ?? DateTime.now();

  // Convenience getters
  String get userId => memberId;
  DateTime get date => updatedAt;

  factory HealthRecord.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return HealthRecord(
      id: j['id'] as String? ?? '',
      familyId: fid,
      memberId: (j['member_id'] ?? j['user_id']) as String? ?? '',
      updatedBy: j['updated_by'] as String?,
      bloodType: bloodTypeFromString(FieldEncryption.decryptField(j['blood_type'] as String?, fid)),
      allergies: parseList(FieldEncryption.decryptJson(j['allergies'], fid), HealthAllergy.fromJson),
      medications: parseList(FieldEncryption.decryptJson(j['medications'], fid), HealthMedication.fromJson),
      conditions: parseList(FieldEncryption.decryptJson(j['conditions'], fid), HealthCondition.fromJson),
      immunizations: parseList(FieldEncryption.decryptJson(j['immunizations'], fid), HealthImmunization.fromJson),
      emergencyContacts: parseList(FieldEncryption.decryptJson(j['emergency_contacts'], fid), EmergencyContact.fromJson),
      doctorName: FieldEncryption.decryptField(j['doctor_name'] as String?, fid),
      doctorPhone: FieldEncryption.decryptField(j['doctor_phone'] as String?, fid),
      insuranceProvider: FieldEncryption.decryptField(j['insurance_provider'] as String?, fid),
      insurancePolicyNumber: FieldEncryption.decryptField(j['insurance_policy_number'] as String?, fid),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      updatedAt: parseDate(j['updated_at']),
      type: j['type'] as String?,
      title: j['title'] as String?,
      data: (j['data'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'family_id': familyId, 'member_id': memberId,
    'updated_by': updatedBy ?? memberId,
    'blood_type': FieldEncryption.encryptField(bloodType.name, familyId),
    'allergies': FieldEncryption.encryptJson(allergies.map((e) => e.toJson()).toList(), familyId),
    'medications': FieldEncryption.encryptJson(medications.map((e) => e.toJson()).toList(), familyId),
    'conditions': FieldEncryption.encryptJson(conditions.map((e) => e.toJson()).toList(), familyId),
    'immunizations': FieldEncryption.encryptJson(immunizations.map((e) => e.toJson()).toList(), familyId),
    'emergency_contacts': FieldEncryption.encryptJson(emergencyContacts.map((e) => e.toJson()).toList(), familyId),
    'doctor_name': FieldEncryption.encryptField(doctorName, familyId),
    'doctor_phone': FieldEncryption.encryptField(doctorPhone, familyId),
    'insurance_provider': FieldEncryption.encryptField(insuranceProvider, familyId),
    'insurance_policy_number': FieldEncryption.encryptField(insurancePolicyNumber, familyId),
    'notes': FieldEncryption.encryptField(notes, familyId),
    'updated_at': updatedAt.toIso8601String(),
  };
}

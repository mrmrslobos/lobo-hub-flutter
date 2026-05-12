// lib/models/period_symptom_log.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import '_enums.dart';
import 'model_json_helpers.dart';

class PeriodSymptomLog {
  final String id;
  final String userId;
  final String familyId;
  final DateTime date;
  final List<String> symptoms;
  final CycleMood? mood;
  final int? painLevel;
  final String? notes;
  final DateTime createdAt;

  const PeriodSymptomLog({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.date,
    this.symptoms = const [],
    this.mood,
    this.painLevel,
    this.notes,
    required this.createdAt,
  });

  factory PeriodSymptomLog.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    // symptoms may be encrypted as a JSON string or legacy plain list
    final rawSymptoms = FieldEncryption.decryptJson(j['symptoms'], fid);
    final moodRaw = j['mood'] ?? j['pain_level'] != null ? j['mood'] : null;
    return PeriodSymptomLog(
      id: j['id'] as String? ?? '',
      userId: j['user_id'] as String? ?? '',
      familyId: fid,
      date: parseDate(j['date']),
      symptoms: rawSymptoms is List ? rawSymptoms.map((e) => e.toString()).toList() : strList(rawSymptoms),
      mood: moodRaw != null ? cycleMoodFromString(FieldEncryption.decryptField(moodRaw as String?, fid)) : null,
      painLevel: FieldEncryption.decryptInt(j['pain_level'] ?? j['painLevel'], fid),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      createdAt: parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'family_id': familyId,
    'date': date.toIso8601String(),
    'symptoms': FieldEncryption.encryptJson(symptoms, familyId),
    'mood': FieldEncryption.encryptField(mood?.name, familyId),
    'pain_level': FieldEncryption.encryptNum(painLevel, familyId),
    'notes': FieldEncryption.encryptField(notes, familyId),
    'created_at': createdAt.toIso8601String(),
  };
}

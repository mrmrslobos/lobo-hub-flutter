// lib/models/savings_goal.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import 'model_json_helpers.dart';

class SavingsGoal {
  final String id;
  final String familyId;
  final String userId;
  final String title;
  final String? icon;
  final String? imageUrl;
  final double targetAmount;
  final double savedAmount;
  final DateTime createdAt;
  final DateTime? completedAt;

  SavingsGoal({
    required this.id,
    required this.familyId,
    String? userId,
    String? createdBy,
    required this.title,
    this.icon,
    String? emoji,
    this.imageUrl,
    this.targetAmount = 0,
    double? savedAmount,
    double? currentAmount,
    required this.createdAt,
    DateTime? completedAt,
    DateTime? deadline,
  }) : userId = userId ?? createdBy ?? '',
       savedAmount = savedAmount ?? currentAmount ?? 0,
       completedAt = completedAt ?? deadline;

  factory SavingsGoal.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return SavingsGoal(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      title: FieldEncryption.decryptField(j['title'] as String?, fid) ?? '',
      icon: j['icon'] as String?,
      imageUrl: j['image_url'] as String?,
      targetAmount: FieldEncryption.decryptDouble(j['target_amount'], fid) ?? 0,
      savedAmount: FieldEncryption.decryptDouble(j['saved_amount'], fid) ?? 0,
      createdAt: parseDate(j['created_at']),
      completedAt: parseDateOpt(j['completed_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'title': FieldEncryption.encryptField(title, familyId),
    'icon': icon,
    'image_url': imageUrl,
    'target_amount': FieldEncryption.encryptNum(targetAmount, familyId),
    'saved_amount': FieldEncryption.encryptNum(savedAmount, familyId),
    'created_at': createdAt.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
  };

  // Convenience getters
  double get currentAmount => savedAmount;
  DateTime? get deadline => completedAt;
  bool get isComplete => completedAt != null;
  String? get emoji => icon;
  double get progress => targetAmount > 0 ? (savedAmount / targetAmount).clamp(0.0, 1.0) : 0.0;

  SavingsGoal copyWith({
    String? id, String? familyId, String? userId, String? title,
    String? icon, String? imageUrl, double? targetAmount, double? savedAmount,
    DateTime? createdAt, DateTime? completedAt,
  }) => SavingsGoal(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    userId: userId ?? this.userId, title: title ?? this.title,
    icon: icon ?? this.icon, imageUrl: imageUrl ?? this.imageUrl,
    targetAmount: targetAmount ?? this.targetAmount,
    savedAmount: savedAmount ?? this.savedAmount,
    createdAt: createdAt ?? this.createdAt,
    completedAt: completedAt ?? this.completedAt,
  );
}

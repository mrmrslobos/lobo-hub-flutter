// lib/models/budget_entry.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import '_enums.dart';
import 'model_json_helpers.dart';

class BudgetEntry {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final double amount;
  final TransactionType type;
  final BudgetCategory category;
  final DateTime date;
  final String? notes;
  final Visibility visibility;

  BudgetEntry({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    required this.title,
    required this.amount,
    TransactionType? type,
    bool? isIncome,
    BudgetCategory? category,
    required this.date,
    this.notes,
    Visibility? visibility,
  }) : creatorId = creatorId ?? createdBy ?? '',
       type = type ?? (isIncome == true ? TransactionType.INCOME : TransactionType.EXPENSE),
       category = category ?? BudgetCategory.other,
       visibility = visibility ?? Visibility.FAMILY;

  bool get isIncome => type == TransactionType.INCOME;

  factory BudgetEntry.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return BudgetEntry(
      id: j['id'] as String? ?? '',
      familyId: fid,
      creatorId: j['creator_id'] as String? ?? '',
      title: FieldEncryption.decryptField(j['title'] as String?, fid) ?? '',
      amount: FieldEncryption.decryptDouble(j['amount'], fid) ?? 0,
      type: transactionTypeFromString(FieldEncryption.decryptField(j['type'] as String?, fid)),
      category: BudgetCategory.values.firstWhere(
        (e) => e.name == (FieldEncryption.decryptField(j['category'] as String?, fid) ?? 'other'),
        orElse: () => BudgetCategory.other,
      ),
      date: parseDate(FieldEncryption.decryptField(j['date'] as String?, fid)),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      visibility: visibilityFromString(j['visibility'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': FieldEncryption.encryptField(title, familyId),
    'amount': FieldEncryption.encryptNum(amount, familyId),
    'type': FieldEncryption.encryptField(type.name, familyId),
    'category': FieldEncryption.encryptField(category.name, familyId),
    'date': FieldEncryption.encryptField(date.toIso8601String(), familyId),
    'notes': FieldEncryption.encryptField(notes, familyId),
    'visibility': visibility.name,
  };

  BudgetEntry copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    double? amount, TransactionType? type, BudgetCategory? category,
    DateTime? date, String? notes, Visibility? visibility,
  }) => BudgetEntry(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, title: title ?? this.title,
    amount: amount ?? this.amount, type: type ?? this.type,
    category: category ?? this.category, date: date ?? this.date,
    notes: notes ?? this.notes, visibility: visibility ?? this.visibility,
  );
}

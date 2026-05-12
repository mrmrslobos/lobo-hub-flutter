// lib/models/transaction.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import '_enums.dart';
import 'model_json_helpers.dart';

class Transaction {
  final String id;
  final String familyId;
  final String creatorId;
  final String categoryId;
  final double amount;
  final TransactionType type;
  final DateTime date;
  final String description;
  final Visibility visibility;

  const Transaction({
    required this.id,
    required this.familyId,
    required this.creatorId,
    this.categoryId = '',
    required this.amount,
    this.type = TransactionType.EXPENSE,
    required this.date,
    this.description = '',
    this.visibility = Visibility.FAMILY,
  });

  factory Transaction.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return Transaction(
      id: j['id'] as String? ?? '',
      familyId: fid,
      creatorId: j['creator_id'] as String? ?? '',
      categoryId: j['category_id'] as String? ?? '',
      amount: FieldEncryption.decryptDouble(j['amount'], fid) ?? 0,
      type: transactionTypeFromString(j['type'] as String?),
      date: parseDate(j['date']),
      description: FieldEncryption.decryptField(j['description'] as String?, fid) ?? '',
      visibility: visibilityFromString(j['visibility'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'category_id': categoryId,
    'amount': FieldEncryption.encryptNum(amount, familyId),
    'type': type.name,
    'date': date.toIso8601String(),
    'description': FieldEncryption.encryptField(description, familyId),
    'visibility': visibility.name,
  };
}

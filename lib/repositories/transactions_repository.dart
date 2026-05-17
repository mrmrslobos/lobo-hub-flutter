import '../models/models.dart';

abstract class TransactionsRepository {
  List<Transaction> transactionsForFamily(String familyId);

  Stream<List<Transaction>> watchTransactionsForFamily(String familyId);

  Future<void> upsert(Transaction item);

  Future<void> softDelete(String id);
}

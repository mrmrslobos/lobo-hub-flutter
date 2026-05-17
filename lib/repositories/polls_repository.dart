import '../models/models.dart';

abstract class PollsRepository {
  List<Poll> pollsForFamily(String familyId);

  Stream<List<Poll>> watchPollsForFamily(String familyId);

  Future<void> upsert(Poll item);

  Future<void> softDelete(String id);
}

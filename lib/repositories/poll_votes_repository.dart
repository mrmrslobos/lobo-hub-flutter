import '../models/models.dart';

abstract class PollVotesRepository {
  List<PollVote> pollVotesForFamily(String familyId);

  Stream<List<PollVote>> watchPollVotesForFamily(String familyId);

  Future<void> upsert(PollVote item);

  Future<void> delete(String id);
}

import '../models/models.dart';

abstract class UserLocationsRepository {
  List<UserLocation> userLocationsForUser(String userId);

  Stream<List<UserLocation>> watchUserLocationsForUser(String userId);

  Future<void> upsert(UserLocation item);

  Future<void> delete(String id);
}

import '../models/models.dart';

abstract class ExternalCalendarsRepository {
  List<ExternalCalendar> externalCalendarsForFamily(String familyId);

  Stream<List<ExternalCalendar>> watchExternalCalendarsForFamily(String familyId);

  Future<void> upsert(ExternalCalendar item);

  Future<void> softDelete(String id);
}

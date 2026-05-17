import '../models/models.dart';

abstract class CalendarEventsRepository {
  List<CalendarEvent> eventsForFamily(String familyId);

  Stream<List<CalendarEvent>> watchEventsForFamily(String familyId);

  Future<void> upsert(CalendarEvent item);

  Future<void> softDelete(String id);
}

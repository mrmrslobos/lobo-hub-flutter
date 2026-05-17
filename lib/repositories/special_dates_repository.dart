import '../models/models.dart';

abstract class SpecialDatesRepository {
  List<SpecialDate> specialDatesForFamily(String familyId);

  Stream<List<SpecialDate>> watchSpecialDatesForFamily(String familyId);

  Future<void> upsert(SpecialDate item);

  Future<void> softDelete(String id);
}

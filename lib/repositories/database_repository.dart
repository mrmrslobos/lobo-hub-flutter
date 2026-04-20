import '../models/models.dart';
import '../services/database_service.dart';

/// Facade for local app database access.
///
/// Today this delegates to [DatabaseService]. When migrating off JSON-in-
/// SharedPreferences (Drift / Isar / sqflite), swap the implementation behind
/// these methods so features can depend on this type instead of statics.
class DatabaseRepository {
  DatabaseRepository._();

  static Future<AppDB> loadLocal() => DatabaseService.loadLocal();

  static Future<void> saveLocal(AppDB db, {AppDB? tombstoneBase}) =>
      DatabaseService.saveLocal(db, tombstoneBase: tombstoneBase);

  static Future<void> clearLocal() => DatabaseService.clearLocal();

  static Future<void> wipeAllLocalStorage() => DatabaseService.wipeAllLocalStorage();
}

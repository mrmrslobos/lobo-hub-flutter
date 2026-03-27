import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// Append a row to [family_activity_logs] (trimmed to last 200 per family).
class FamilyActivityService {
  static const _maxPerFamily = 200;

  static AppDB append(
    AppDB db, {
    required String familyId,
    required String actorUserId,
    required String action,
    String? detail,
    String? relatedUserId,
  }) {
    final entry = FamilyActivityLog(
      id: const Uuid().v4(),
      familyId: familyId,
      actorUserId: actorUserId,
      action: action,
      detail: detail,
      relatedUserId: relatedUserId,
      createdAt: DateTime.now(),
    );
    final others =
        db.familyActivityLogs.where((e) => e.familyId != familyId).toList();
    final thisFam =
        db.familyActivityLogs.where((e) => e.familyId == familyId).toList()
          ..add(entry)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final trimmed = thisFam.take(_maxPerFamily).toList();
    return db.copyWith(familyActivityLogs: [...others, ...trimmed]);
  }
}

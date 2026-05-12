import 'sync_echo_tracker.dart';

/// Shared rules for Supabase upserts (must stay aligned with full sync / bulk paths).
List<Map<String, dynamic>> sanitizeRowsForCloudUpsert(
  List<Map<String, dynamic>> rows,
  String table,
) {
  const keepUpdatedAt = {
    'user_locations',
    'lists',
    'families',
    'tasks',
    'devotional_thoughts',
  };
  return rows.map((r) {
    final m = Map<String, dynamic>.from(r);
    if (keepUpdatedAt.contains(table)) {
      final u = m['updated_at'];
      if (u == null ||
          (u is String && u.isEmpty) ||
          (u is! String && u is! DateTime)) {
        m['updated_at'] = DateTime.now().toUtc().toIso8601String();
      } else if (u is DateTime) {
        m['updated_at'] = u.toUtc().toIso8601String();
      }
    } else {
      m.remove('updated_at');
    }
    final rowId = m['id']?.toString() ?? '';
    if (rowId.isNotEmpty) {
      DateTime? ts;
      final outU = m['updated_at'];
      if (outU is String && outU.isNotEmpty) {
        ts = DateTime.tryParse(outU);
      } else if (outU is DateTime) {
        ts = outU;
      }
      SyncEchoTracker.record(table, rowId, ts ?? DateTime.now().toUtc());
    }
    if (table == 'devotional_thoughts') {
      final nk = m['note_kind'];
      if (nk == null || (nk is String && nk.isEmpty)) {
        m['note_kind'] = 'thought';
      }
    }
    return m;
  }).toList();
}

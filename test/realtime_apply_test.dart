import 'package:flutter_test/flutter_test.dart';
import 'package:lobohub/config/cloud_sync_scope.dart';
import 'package:lobohub/models/models.dart';
import 'package:lobohub/services/database_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('DatabaseService.applyRealtimeRowChange', () {
    test('merges pantry_items INSERT into local AppDB', () {
      const familyId = 'fam-1';
      final local = const AppDB();
      final merged = DatabaseService.applyRealtimeRowChange(
        local: local,
        table: CloudSyncScope.pantryItems,
        familyId: familyId,
        eventType: PostgresChangeEvent.insert,
        newRecord: {
          'id': 'pantry-1',
          'family_id': familyId,
          'name': 'Milk',
          'quantity': '2',
          'unit': 'L',
          'updated_at': '2026-08-17T10:00:00.000Z',
        },
        oldRecord: const {},
      );

      expect(merged, isNotNull);
      expect(merged!.pantryItems, hasLength(1));
      expect(merged.pantryItems.first.name, 'Milk');
    });

    test('returns null for tables outside incremental realtime set', () {
      final merged = DatabaseService.applyRealtimeRowChange(
        local: const AppDB(),
        table: CloudSyncScope.fitnessPlans,
        familyId: 'fam-1',
        eventType: PostgresChangeEvent.insert,
        newRecord: {
          'id': 'plan-1',
          'family_id': 'fam-1',
          'user_id': 'user-1',
        },
        oldRecord: const {},
      );
      expect(merged, isNull);
    });
  });
}

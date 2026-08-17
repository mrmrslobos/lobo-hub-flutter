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

    test('merges family_members INSERT into local AppDB', () {
      const familyId = 'fam-1';
      final merged = DatabaseService.applyRealtimeRowChange(
        local: const AppDB(),
        table: CloudSyncScope.familyMembers,
        familyId: familyId,
        eventType: PostgresChangeEvent.insert,
        newRecord: {
          'user_id': 'user-2',
          'family_id': familyId,
          'role': 'MEMBER',
        },
        oldRecord: const {},
      );

      expect(merged, isNotNull);
      expect(merged!.familyMembers, hasLength(1));
      expect(merged.familyMembers.first.userId, 'user-2');
    });

    test('merges fitness_plans INSERT for active user', () {
      final merged = DatabaseService.applyRealtimeRowChange(
        local: const AppDB(),
        table: CloudSyncScope.fitnessPlans,
        familyId: 'fam-1',
        userId: 'user-1',
        eventType: PostgresChangeEvent.insert,
        newRecord: {
          'id': 'plan-1',
          'user_id': 'user-1',
          'family_id': 'fam-1',
          'plan_id': 'plan-1',
          'summary': 'Week 1',
          'weekly_plan': [],
          'tips': [],
          'profile': {},
          'created_at': '2026-08-17T10:00:00.000Z',
        },
        oldRecord: const {},
      );

      expect(merged, isNotNull);
      expect(merged!.fitnessPlans, hasLength(1));
    });

    test('returns null for tables outside incremental realtime set', () {
      final merged = DatabaseService.applyRealtimeRowChange(
        local: const AppDB(),
        table: 'unknown_table',
        familyId: 'fam-1',
        eventType: PostgresChangeEvent.insert,
        newRecord: const {'id': 'x'},
        oldRecord: const {},
      );
      expect(merged, isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lobohub/models/models.dart';
import 'package:lobohub/services/notification_service.dart';

void main() {
  group('NotificationService', () {
    test('inQuietHours handles same-day and overnight windows', () {
      expect(NotificationService.inQuietHours(null, null), isFalse);
      expect(NotificationService.inQuietHours(22, 7), isA<bool>());
      expect(NotificationService.inQuietHours(9, 9), isFalse);
    });

    test('shouldNotifyForPath respects lists module preference', () {
      final db = const AppDB().copyWith(
        notificationPrefs: [
          const NotificationPrefs(lists: false),
        ],
      );
      expect(NotificationService.shouldNotifyForPath(db, '/lists'), isFalse);
      expect(NotificationService.shouldNotifyForPath(db, '/tasks'), isTrue);
    });
  });
}

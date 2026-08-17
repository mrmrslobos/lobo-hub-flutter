import 'package:flutter_test/flutter_test.dart';
import 'package:lobohub/services/daily_devotional_service.dart';

void main() {
  group('dailyDevotionalStoredUtcToLocalToday', () {
    test('round-trips picker local time through stored UTC values', () {
      final picked = DateTime(2026, 8, 17, 7, 30);
      final utc = picked.toUtc();
      final recovered = dailyDevotionalStoredUtcToLocalToday(
        utc.hour,
        utc.minute,
        day: picked,
      );
      expect(recovered.hour, picked.hour);
      expect(recovered.minute, picked.minute);
    });
  });
}

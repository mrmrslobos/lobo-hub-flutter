// lib/services/reminder_enqueue_service.dart
// Enqueues server-side [reminder_jobs] via Supabase Edge Function (email/SMS/voice).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';
import 'notification_service.dart';

class ReminderEnqueueService {
  ReminderEnqueueService._();

  static DateTime? _taskNotifyUtc({
    required DateTime dueDate,
    required String dueTime,
    required int reminderMinutes,
  }) {
    final parts = dueTime.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final dueLocal = tz.TZDateTime(
      tz.local,
      dueDate.year,
      dueDate.month,
      dueDate.day,
      hour,
      minute,
    );
    final notifyLocal = dueLocal.subtract(Duration(minutes: reminderMinutes));
    if (notifyLocal.isBefore(tz.TZDateTime.now(tz.local))) return null;
    return notifyLocal.toUtc();
  }

  /// Schedules an external reminder when prefs + Supabase allow.
  static Future<void> tryEnqueueTaskReminder({
    required Task task,
    required String familyId,
    required String userId,
    required String userEmail,
    required NotificationPrefs prefs,
  }) async {
    final ch = task.reminderChannel ?? 'push';
    if (ch == 'push') return;
    if (task.dueDate == null || task.dueTime == null || task.reminderMinutes == null) return;

    if (!NotificationService.inQuietHours(prefs.quietHoursStart, prefs.quietHoursEnd)) {
      // still enqueue at exact time; dispatch edge can respect quiet hours later
    }

    final whenUtc = _taskNotifyUtc(
      dueDate: task.dueDate!,
      dueTime: task.dueTime!,
      reminderMinutes: task.reminderMinutes!,
    );
    if (whenUtc == null) return;

    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) return;

      final idem = 'task_${task.id}_${whenUtc.millisecondsSinceEpoch}';
      final bodyText = '${task.title} — due ${task.dueDate} ${task.dueTime}';

      if (ch == 'email' && prefs.reminderEmailEnabled && userEmail.isNotEmpty) {
        await client.functions.invoke(
          'enqueue-reminder',
          body: {
            'family_id': familyId,
            'channel': 'email',
            'scheduled_at': whenUtc.toIso8601String(),
            'idempotency_key': idem,
            'payload': {
              'to_email': userEmail,
              'subject': 'Huddle task reminder',
              'body': bodyText,
              'task_id': task.id,
            },
          },
        );
      } else if (ch == 'sms' && prefs.reminderSmsEnabled && (prefs.reminderSmsPhone ?? '').trim().isNotEmpty) {
        await client.functions.invoke(
          'enqueue-reminder',
          body: {
            'family_id': familyId,
            'channel': 'sms',
            'scheduled_at': whenUtc.toIso8601String(),
            'idempotency_key': idem,
            'payload': {
              'to_phone': prefs.reminderSmsPhone!.trim(),
              'body': bodyText,
              'task_id': task.id,
            },
          },
        );
      } else if (ch == 'voice' && prefs.reminderSmsEnabled && (prefs.reminderSmsPhone ?? '').trim().isNotEmpty) {
        await client.functions.invoke(
          'enqueue-reminder',
          body: {
            'family_id': familyId,
            'channel': 'voice',
            'scheduled_at': whenUtc.toIso8601String(),
            'idempotency_key': idem,
            'payload': {
              'to_phone': prefs.reminderSmsPhone!.trim(),
              'body': bodyText,
              'task_id': task.id,
            },
          },
        );
      }
    } catch (e, st) {
      debugPrint('[ReminderEnqueue] $e\n$st');
    }
  }
}

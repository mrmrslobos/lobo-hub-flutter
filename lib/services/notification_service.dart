import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart' hide Priority;

/// Simple time-of-day container (replaces the removed flutter_local_notifications Time class).
class Time {
  final int hour;
  final int minute;
  final int second;
  const Time(this.hour, [this.minute = 0, this.second = 0]);
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Route to navigate to when a notification is tapped.
  /// Consumers should read and clear this after acting on it.
  static String? pendingRoute;

  /// Called when a local notification is tapped.
  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      pendingRoute = payload;
    }
  }

  /// Called when a FCM notification is tapped (background/terminated).
  static void _onFcmMessageTap(RemoteMessage message) {
    var route = (message.data['path'] ?? message.data['route']) as String?;
    final did = message.data['devotionalId']?.toString();
    if ((route == null || route.isEmpty) &&
        did != null &&
        did.isNotEmpty) {
      route = '/devotional?id=$did';
    }
    if (route != null && route.isNotEmpty) {
      pendingRoute = route;
    }
  }

  static Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request permissions on Android 13+
    await requestPermissions();

    // Try to initialize Firebase and FCM
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Handle foreground FCM messages → show as local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        if (notification != null) {
          showLocal(
            id: notification.hashCode,
            title: notification.title ?? '',
            body: notification.body ?? '',
            payload: () {
              final p = (message.data['path'] ?? message.data['route']) as String?;
              if (p != null && p.isNotEmpty) return p;
              final d = message.data['devotionalId']?.toString();
              if (d != null && d.isNotEmpty) return '/devotional?id=$d';
              return null;
            }(),
          );
        }
      });

      // Handle background/terminated tap on FCM notification
      FirebaseMessaging.onMessageOpenedApp.listen(_onFcmMessageTap);

      // Check if app was opened from a terminated-state FCM notification
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _onFcmMessageTap(initialMessage);
      }
    } catch (e) {
      debugPrint('[NotificationService] Firebase init skipped: $e');
    }

    _initialized = true;
  }

  static Future<void> requestPermissions() async {
    try {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[NotificationService] requestPermissions error: $e');
    }
  }

  static Future<void> showLocal({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'lobohub_general',
      'General Notifications',
      channelDescription: 'General app notifications for LoboHub',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(id, title, body, details, payload: payload);
  }

  static Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required Time time,
  }) async {
    if (!_initialized) await init();

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
      time.second,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'lobohub_daily',
      'Daily Reminders',
      channelDescription: 'Daily scheduled reminders for LoboHub',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Schedule a one-time notification at [when] (local time).
  static Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (!_initialized) await init();

    final scheduledDate = tz.TZDateTime(
      tz.local,
      when.year,
      when.month,
      when.day,
      when.hour,
      when.minute,
      when.second,
    );

    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) return;

    const androidDetails = AndroidNotificationDetails(
      'lobohub_fertility_reminders',
      'Fertility Reminders',
      channelDescription: 'One-time fertility reminders for Flo predictions',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  /// Schedule a task reminder notification at a specific date/time.
  /// The notification ID is derived from the task ID hash for consistency.
  static Future<void> scheduleTaskReminder({
    required String taskId,
    required String taskTitle,
    required DateTime dueDate,
    required String dueTime,
    required int reminderMinutes,
  }) async {
    if (!_initialized) await init();

    // Parse dueTime (HH:mm format)
    final parts = dueTime.split(':');
    if (parts.length < 2) return;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    final dueDateTime = tz.TZDateTime(
      tz.local,
      dueDate.year,
      dueDate.month,
      dueDate.day,
      hour,
      minute,
    );

    final notifyAt = dueDateTime.subtract(Duration(minutes: reminderMinutes));
    if (notifyAt.isBefore(tz.TZDateTime.now(tz.local))) return; // already passed

    final notifId = taskId.hashCode.abs() % 2147483647; // keep within int range

    final body = reminderMinutes == 0
        ? '$taskTitle — due now!'
        : '$taskTitle — due in $reminderMinutes minutes';

    const androidDetails = AndroidNotificationDetails(
      'lobohub_task_reminders',
      'Task Reminders',
      channelDescription: 'Reminders for tasks with due dates',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      notifId,
      'Task Reminder',
      body,
      notifyAt,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'task:$taskId',
    );
  }

  /// Cancel a previously scheduled task reminder.
  static Future<void> cancelTaskReminder(String taskId) async {
    final notifId = taskId.hashCode.abs() % 2147483647;
    await _plugin.cancel(notifId);
  }

  /// True when local time is inside [quietHoursStart]–[quietHoursEnd] (half-open).
  /// Supports windows that cross midnight (e.g. 22 → 7).
  static bool inQuietHours(int? quietHoursStart, int? quietHoursEnd) {
    if (quietHoursStart == null || quietHoursEnd == null) return false;
    final h = DateTime.now().hour;
    if (quietHoursStart == quietHoursEnd) return false;
    if (quietHoursStart < quietHoursEnd) {
      return h >= quietHoursStart && h < quietHoursEnd;
    }
    return h >= quietHoursStart || h < quietHoursEnd;
  }

  /// Notify other family members about an activity (not the actor).
  /// Sends a push notification via the Supabase edge function to all
  /// other devices in the family, excluding the current user.
  static Future<void> notifyFamilyActivity({
    required String title,
    required String body,
    String? familyId,
    String? excludeUserId,
    String? path,
    int? quietHoursStart,
    int? quietHoursEnd,
  }) async {
    if (inQuietHours(quietHoursStart, quietHoursEnd)) {
      debugPrint('[NotificationService] Skipping push (quiet hours)');
      return;
    }
    // Send push notification to other family members via edge function
    try {
      if (familyId != null && excludeUserId != null) {
        await Supabase.instance.client.functions.invoke(
          'notify-family',
          body: {
            'action': 'notify',
            'family_id': familyId,
            'exclude_user_id': excludeUserId,
            'title': title,
            'body': body,
            'path': path ?? '/',
          },
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] notifyFamilyActivity push error: $e');
    }
  }

  /// Whether family push is enabled for this [path] (e.g. `/tasks`).
  static bool shouldNotifyForPath(AppDB db, String? path) {
    NotificationPrefs prefs = const NotificationPrefs();
    for (final p in db.notificationPrefs) {
      prefs = p;
      break;
    }
    if (path == null || path.isEmpty) return true;
    final loc = path.split('?').first;
    if (loc.startsWith('/chat')) return prefs.chat;
    if (loc.startsWith('/tasks')) return prefs.tasks;
    if (loc.startsWith('/calendar')) return prefs.calendar;
    if (loc.startsWith('/chores')) return prefs.chores;
    if (loc.startsWith('/lists')) return prefs.lists;
    if (loc.startsWith('/polls')) return prefs.polls;
    if (loc.startsWith('/meals')) return prefs.meals;
    if (loc.startsWith('/birthdays')) return prefs.birthdays;
    if (loc.startsWith('/photos')) return prefs.photos;
    if (loc.startsWith('/location')) return prefs.location;
    return true;
  }

  /// Like [notifyFamilyActivity] but respects quiet hours from the first
  /// [AppDB.notificationPrefs] row (device-local).
  static Future<void> notifyFamilyActivityWithDb(
    AppDB db, {
    required String title,
    required String body,
    String? familyId,
    String? excludeUserId,
    String? path,
  }) async {
    if (!shouldNotifyForPath(db, path)) {
      debugPrint('[NotificationService] Skipping push (module disabled in settings)');
      return;
    }
    var prefs = const NotificationPrefs();
    for (final p in db.notificationPrefs) {
      prefs = p;
      break;
    }
    await notifyFamilyActivity(
      title: title,
      body: body,
      familyId: familyId,
      excludeUserId: excludeUserId,
      path: path,
      quietHoursStart: prefs.quietHoursStart,
      quietHoursEnd: prefs.quietHoursEnd,
    );
  }

  static Future<String?> getFcmToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('[NotificationService] getFcmToken error: $e');
      return null;
    }
  }

  static Future<void> registerDeviceToken(
      String familyId, String userId) async {
    try {
      final token = await getFcmToken();
      if (token == null) {
        debugPrint('[NotificationService] FCM token is null — skipping registration');
        return;
      }
      debugPrint('[NotificationService] Registering device token for user=$userId family=$familyId');

      // Write directly to device_tokens via REST API (RLS allows users to
      // manage their own rows). This avoids the edge function JWT auth issue.
      await Supabase.instance.client.from('device_tokens').upsert(
        {
          'user_id': userId,
          'family_id': familyId,
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,platform',
      );
      debugPrint('[NotificationService] device token registered successfully');
    } catch (e, st) {
      debugPrint('[NotificationService] registerDeviceToken error: $e\n$st');
    }
  }
}

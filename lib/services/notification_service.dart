import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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
    final route = (message.data['path'] ?? message.data['route']) as String?;
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
            payload: (message.data['path'] ?? message.data['route']) as String?,
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

  /// Notify other family members about an activity (not the actor).
  /// Sends a push notification via the Supabase edge function to all
  /// other devices in the family, excluding the current user.
  static Future<void> notifyFamilyActivity({
    required String title,
    required String body,
    String? familyId,
    String? excludeUserId,
    String? path,
  }) async {
    // Send push notification to other family members via edge function
    try {
      if (familyId != null && excludeUserId != null) {
        await Supabase.instance.client.functions.invoke(
          'notify-family',
          body: {
            'action': 'notify',
            'familyId': familyId,
            'excludeUserId': excludeUserId,
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

      final restUrl = Supabase.instance.client.rest.url;
      final supabaseUrl = restUrl.replaceAll('/rest/v1', '');
      final accessToken =
          Supabase.instance.client.auth.currentSession?.accessToken ?? '';
      final uri = Uri.parse('$supabaseUrl/functions/v1/notify-family');

      final resp = await Supabase.instance.client.functions.invoke(
        'notify-family',
        body: {
          'action': 'register',
          'token': token,
          'familyId': familyId,
          'userId': userId,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
      debugPrint('[NotificationService] register response: ${resp.status} ${resp.data}');
    } catch (e, st) {
      debugPrint('[NotificationService] registerDeviceToken error: $e\n$st');
    }
  }
}

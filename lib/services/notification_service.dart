import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../config/app_config.dart';
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
  static Future<void>? _initFuture;

  /// True after [FlutterLocalNotificationsPlugin.initialize] completes and
  /// Android channels exist — before FCM handlers that may call [showLocal].
  static bool _localNotificationsReady = false;
  static bool _timeZoneBootstrapped = false;

  /// Route to navigate to when a notification is tapped.
  /// Consumers should read and clear this after acting on it.
  static String? pendingRoute;

  static Future<void> ensureReady() {
    _initFuture ??= _initImpl();
    return _initFuture!;
  }

  /// Ensures `package:timezone` [tz.local] matches the device (call from [main]
  /// before any code uses [tz.local]).
  static Future<void> bootstrapTimeZone() async {
    if (_timeZoneBootstrapped) return;
    tz.initializeTimeZones();
    _timeZoneBootstrapped = true;
    if (kIsWeb) return;

    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (e) {
      debugPrint('[NotificationService] TZ name failed, UTC fallback: $e');
      try {
        tz.setLocalLocation(tz.UTC);
      } catch (_) {}
    }
  }

  static void _routeFromTapPayload(String? raw) {
    final p = (raw ?? '').trim();
    if (p.isEmpty) {
      pendingRoute = '/';
      return;
    }
    if (p.startsWith('task:') || p.startsWith('/')) {
      pendingRoute = p;
    } else {
      pendingRoute = '/$p';
    }
  }

  static String? _routeFromRemoteMessageData(Map<String, dynamic> data) {
    final path = data['path'] ?? data['route'];
    final p =
        path is String && path.trim().isNotEmpty ? path.trim() : null;
    if (p != null) return p;
    final did = data['devotionalId']?.toString();
    if (did != null && did.isNotEmpty) return '/devotional?id=$did';
    return '/';
  }

  /// Called when a local notification is tapped.
  static void _onNotificationTap(NotificationResponse response) {
    _routeFromTapPayload(response.payload);
  }

  /// Called when a FCM notification is tapped (background/terminated).
  static void _onFcmMessageTap(RemoteMessage message) {
    final route =
        _routeFromRemoteMessageData(Map<String, dynamic>.from(message.data));
    pendingRoute = route;
  }

  static Future<void> _configureAndroidChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    Future<void> add(AndroidNotificationChannel ch) async {
      await android.createNotificationChannel(ch);
    }

    await add(const AndroidNotificationChannel(
      'default',
      'General',
      description: 'Default channel for Firebase and system notifications.',
      importance: Importance.high,
    ));
    await add(AndroidNotificationChannel(
      'lobohub_general',
      'General Notifications',
      description: 'General app notifications for ${AppConfig.appName}',
      importance: Importance.high,
    ));
    await add(AndroidNotificationChannel(
      'lobohub_daily',
      'Daily Reminders',
      description: 'Daily scheduled reminders for ${AppConfig.appName}',
      importance: Importance.high,
    ));
    await add(const AndroidNotificationChannel(
      'lobohub_task_reminders',
      'Task Reminders',
      description: 'Reminders for tasks with due dates',
      importance: Importance.high,
    ));
    await add(const AndroidNotificationChannel(
      'lobohub_fertility_reminders',
      'Fertility Reminders',
      description: 'One-time fertility reminders',
      importance: Importance.high,
    ));
  }

  static Future<void> _consumeLocalNotificationLaunchTap() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return;
    final payload = details!.notificationResponse?.payload;
    if (payload == null || payload.trim().isEmpty) {
      pendingRoute ??= '/';
      return;
    }
    _routeFromTapPayload(payload);
  }

  static Future<void> _initImpl() async {
    if (_initialized) return;

    await bootstrapTimeZone();

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

    if (!kIsWeb) {
      await _configureAndroidChannels();
    }

    await requestPermissions();

    await _consumeLocalNotificationLaunchTap();

    _localNotificationsReady = true;

    // Try to initialize Firebase and FCM (overrides pending route when the app opened from FCM tap).
    if (!kIsWeb) {
      try {
        await Firebase.initializeApp();
        final messaging = FirebaseMessaging.instance;
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final payload = _routeFromRemoteMessageData(
            Map<String, dynamic>.from(message.data),
          );
          final notification = message.notification;
          if (notification != null) {
            showLocal(
              id: notification.hashCode,
              title: notification.title ?? '',
              body: notification.body ?? '',
              payload: payload,
            );
          } else if (message.data.isNotEmpty) {
            // Data-only / collapsed payload: still show a tappable local notification.
            final title = message.data['title']?.toString() ?? 'Huddle';
            final body = message.data['body']?.toString() ??
                message.data['message']?.toString() ??
                'Open to view';
            showLocal(
              id: message.messageId?.hashCode ?? message.hashCode,
              title: title,
              body: body,
              payload: payload,
            );
          }
        });

        FirebaseMessaging.onMessageOpenedApp.listen(_onFcmMessageTap);

        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null) {
          _onFcmMessageTap(initialMessage);
        }
      } catch (e) {
        debugPrint('[NotificationService] Firebase init skipped: $e');
      }
    }

    _initialized = true;
  }

  static Future<void> requestPermissions() async {
    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();

      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
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
    if (!_localNotificationsReady) {
      await ensureReady();
    }

    final effectivePayload = (payload != null && payload.trim().isNotEmpty)
        ? payload.trim()
        : '/';

    final androidDetails = AndroidNotificationDetails(
      'lobohub_general',
      'General Notifications',
      channelDescription: 'General app notifications for ${AppConfig.appName}',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(id, title, body, details, payload: effectivePayload);
  }

  /// Repeats at the same local time daily (timezone from [flutter_timezone]).
  static Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required Time time,
    String payload = '/devotional',
  }) async {
    await ensureReady();

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

    final androidDetails = AndroidNotificationDetails(
      'lobohub_daily',
      'Daily Reminders',
      channelDescription: 'Daily scheduled reminders for ${AppConfig.appName}',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final tapPayload =
        payload.trim().isNotEmpty ? payload.trim() : '/devotional';

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
      payload: tapPayload,
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
    await ensureReady();

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

    final pl = (payload != null && payload.trim().isNotEmpty)
        ? payload.trim()
        : '/';

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: pl,
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
    await ensureReady();

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
    List<String>? targetUserIds,
    int? quietHoursStart,
    int? quietHoursEnd,
  }) async {
    if (inQuietHours(quietHoursStart, quietHoursEnd)) {
      debugPrint('[NotificationService] Skipping push (quiet hours)');
      return;
    }
    try {
      if (familyId != null && excludeUserId != null) {
        final payload = <String, dynamic>{
          'action': 'notify',
          'familyId': familyId,
          'title': title,
          'body': body,
          'path': path ?? '/',
        };
        final targets = targetUserIds
            ?.where((id) => id.isNotEmpty && id != excludeUserId)
            .toList();
        if (targets != null && targets.isNotEmpty) {
          payload['targetUserIds'] = targets;
        }
        await Supabase.instance.client.functions.invoke(
          'notify-family',
          body: payload,
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
    if (loc.startsWith('/budget')) return prefs.budget;
    if (loc.startsWith('/rewards')) return prefs.rewards;
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
    List<String>? targetUserIds,
  }) async {
    if (!shouldNotifyForPath(db, path)) {
      debugPrint(
          '[NotificationService] Skipping push (module disabled in settings)');
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
      targetUserIds: targetUserIds,
      quietHoursStart: prefs.quietHoursStart,
      quietHoursEnd: prefs.quietHoursEnd,
    );
  }

  static Future<String?> getFcmToken() async {
    if (kIsWeb) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('[NotificationService] getFcmToken error: $e');
      return null;
    }
  }

  static Future<void> registerDeviceToken(
      String familyId, String userId) async {
    if (kIsWeb) return;
    try {
      final token = await getFcmToken();
      if (token == null) {
        debugPrint('[NotificationService] FCM token is null — skipping registration');
        return;
      }
      debugPrint(
          '[NotificationService] Registering device token for user=$userId family=$familyId');

      await Supabase.instance.client.functions.invoke(
        'notify-family',
        body: {
          'action': 'register',
          'familyId': familyId,
          'userId': userId,
          'token': token,
          'platform':
              defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        },
      );
      debugPrint('[NotificationService] device token registered successfully');
    } catch (e, st) {
      debugPrint('[NotificationService] registerDeviceToken error: $e\n$st');
    }
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/daily_devotional_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import 'background_runtime.dart';
import 'background_session_store.dart';
import 'background_tasks.dart';

/// Registers platform background work (Workmanager).
class BackgroundTaskScheduler {
  BackgroundTaskScheduler._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (_initialized) return;
    await Workmanager().initialize(workmanagerCallbackDispatcher);
    _initialized = true;
  }

  /// After login, schedule change, or foreground prep — queue the next prep run.
  static Future<void> syncDailyDevotionalSchedule(AppProvider provider) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    await initialize();

    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) return;

    await BackgroundSessionStore.saveActiveSession(
      userId: user.id,
      familyId: family.id,
    );

    if (!userDailyEnabled(user, family)) {
      await cancelDailyDevotionalPrep();
      return;
    }

    await scheduleDailyDevotionalPrep(user: user, family: family);
  }

  static Future<void> scheduleDailyDevotionalPrep({
    required User user,
    required Family family,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (!userDailyEnabled(user, family)) return;
    await initialize();

    final runAt = _nextPrepRunAt(user, family);
    var delay = runAt.difference(DateTime.now());
    if (delay.isNegative) {
      delay = Duration.zero;
    }

    final inputData = <String, dynamic>{
      'userId': user.id,
      'familyId': family.id,
    };

    final constraints = Constraints(
      networkType: NetworkType.connected,
    );

    if (Platform.isIOS) {
      await Workmanager().registerProcessingTask(
        BackgroundTasks.dailyDevotionalPrepUnique,
        BackgroundTasks.dailyDevotionalPrep,
        initialDelay: delay,
        inputData: inputData,
        constraints: constraints,
      );
    } else {
      await Workmanager().registerOneOffTask(
        BackgroundTasks.dailyDevotionalPrepUnique,
        BackgroundTasks.dailyDevotionalPrep,
        initialDelay: delay,
        inputData: inputData,
        constraints: constraints,
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    }

    debugPrint(
      '[BackgroundTaskScheduler] daily prep in ${delay.inMinutes}m '
      '(target ${runAt.toLocal()})',
    );
  }

  static Future<void> cancelDailyDevotionalPrep() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (!_initialized) return;
    try {
      await Workmanager().cancelByUniqueName(
        BackgroundTasks.dailyDevotionalPrepUnique,
      );
    } catch (e) {
      debugPrint('[BackgroundTaskScheduler] cancel failed: $e');
    }
  }

  static Future<void> clearOnLogout() async {
    await BackgroundSessionStore.clear();
    await cancelDailyDevotionalPrep();
  }

  /// Next local time to generate today's devotional (before delivery).
  static DateTime _nextPrepRunAt(User user, Family family) {
    final delivery = userDailyScheduledLocalToday(user, family);
    final now = DateTime.now();

    var prep = delivery.subtract(BackgroundTasks.prepLeadTime);
    if (now.isBefore(prep)) {
      return prep;
    }

    // Same calendar day: delivery not for long — run soon if still before window ends.
    if (now.isBefore(delivery.add(const Duration(minutes: 45)))) {
      return now.add(const Duration(seconds: 30));
    }

    // Otherwise schedule for tomorrow's prep slot.
    final tomorrowDelivery = delivery.add(const Duration(days: 1));
    return tomorrowDelivery.subtract(BackgroundTasks.prepLeadTime);
  }

  static Future<bool> _executeTask(
    String taskName,
    Map<String, dynamic>? inputData,
  ) async {
    switch (taskName) {
      case BackgroundTasks.dailyDevotionalPrep:
        return _runDailyDevotionalPrep(inputData);
      default:
        debugPrint('[BackgroundTaskScheduler] Unknown task: $taskName');
        return false;
    }
  }

  static Future<bool> _runDailyDevotionalPrep(
    Map<String, dynamic>? inputData,
  ) async {
    try {
      await BackgroundRuntime.ensureReady();
      await NotificationService.ensureReady();

      var userId = inputData?['userId']?.toString();
      var familyId = inputData?['familyId']?.toString();
      if (userId == null || familyId == null) {
        final stored = await BackgroundSessionStore.read();
        if (stored == null) {
          debugPrint('[BackgroundTaskScheduler] No stored session');
          return true;
        }
        userId = stored.userId;
        familyId = stored.familyId;
      }

      var db = await DatabaseService.loadLocal();
      User? user;
      for (final u in db.users) {
        if (u.id == userId) {
          user = u;
          break;
        }
      }
      Family? family;
      for (final f in db.families) {
        if (f.id == familyId) {
          family = f;
          break;
        }
      }
      if (user == null || family == null) {
        debugPrint('[BackgroundTaskScheduler] User/family not in local DB');
        return true;
      }

      if (!userDailyEnabled(user, family)) {
        await cancelDailyDevotionalPrep();
        return true;
      }

      final entry = await DailyDevotionalService.ensureTodayInBackground(
        db: db,
        user: user,
        family: family,
        syncCloudFirst: true,
        generateIfMissing: true,
      );
      db = await DatabaseService.loadLocal();

      await DailyDevotionalService.rescheduleNotificationFor(
        user: user,
        family: family,
        db: db,
        entry: entry,
      );

      await scheduleDailyDevotionalPrep(user: user, family: family);
      return true;
    } catch (e, st) {
      debugPrint(
        '[BackgroundTaskScheduler] daily_devotional_prep failed: $e\n$st',
      );
      return false;
    }
  }
}

/// Top-level entry point for Workmanager (separate isolate).
@pragma('vm:entry-point')
void workmanagerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    return BackgroundTaskScheduler._executeTask(taskName, inputData);
  });
}

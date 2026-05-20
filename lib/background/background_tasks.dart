/// Workmanager task names and platform identifiers.
abstract final class BackgroundTasks {
  /// Returned to [workmanager_callback] as [taskName].
  static const dailyDevotionalPrep = 'daily_devotional_prep';

  /// Android unique work name / iOS BGTaskScheduler identifier.
  static const dailyDevotionalPrepUnique =
      'com.opensolutions.huddle.daily_devotional_prep';

  /// Generate today's devotional this long before the user's delivery time.
  static const prepLeadTime = Duration(minutes: 15);
}

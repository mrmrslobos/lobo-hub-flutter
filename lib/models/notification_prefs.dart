// lib/models/notification_prefs.dart
// ignore_for_file: constant_identifier_names
class NotificationPrefs {
  final bool chat;
  final bool tasks;
  final bool calendar;
  final bool chores;
  final bool lists;
  final bool polls;
  final bool meals;
  final bool birthdays;
  final bool photos;
  final bool location;
  final bool weeklyDigest;
  final bool webPushEnabled;
  /// Local hour 0–23 when quiet hours start (inclusive). Both null = disabled.
  final int? quietHoursStart;
  /// Local hour 0–23 when quiet hours end (exclusive).
  final int? quietHoursEnd;
  /// When true, server may send task/event reminders to the account email (requires Supabase cron + provider).
  final bool reminderEmailEnabled;
  final bool reminderSmsEnabled;
  final String? reminderSmsPhone;

  const NotificationPrefs({
    this.chat = true,
    this.tasks = true,
    this.calendar = true,
    this.chores = true,
    this.lists = true,
    this.polls = true,
    this.meals = false,
    this.birthdays = true,
    this.photos = false,
    this.location = false,
    this.weeklyDigest = true,
    this.webPushEnabled = false,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.reminderEmailEnabled = false,
    this.reminderSmsEnabled = false,
    this.reminderSmsPhone,
  });

  /// Stable id for local merge (single row per device).
  String get id => '_notification_prefs';
  String get mergeKey => id;

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) => NotificationPrefs(
    chat: (j['chat'] ?? true) as bool,
    tasks: (j['tasks'] ?? true) as bool,
    calendar: (j['calendar'] ?? true) as bool,
    chores: (j['chores'] ?? true) as bool,
    lists: (j['lists'] ?? true) as bool,
    polls: (j['polls'] ?? true) as bool,
    meals: (j['meals'] ?? false) as bool,
    birthdays: (j['birthdays'] ?? true) as bool,
    photos: (j['photos'] ?? false) as bool,
    location: (j['location'] ?? false) as bool,
    weeklyDigest: (j['weekly_digest'] ?? true) as bool,
    webPushEnabled: (j['web_push_enabled'] ?? false) as bool,
    quietHoursStart: (j['quiet_hours_start'] as num?)?.toInt(),
    quietHoursEnd: (j['quiet_hours_end'] as num?)?.toInt(),
    reminderEmailEnabled: (j['reminder_email_enabled'] ?? false) as bool,
    reminderSmsEnabled: (j['reminder_sms_enabled'] ?? false) as bool,
    reminderSmsPhone: j['reminder_sms_phone'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'chat': chat,
    'tasks': tasks,
    'calendar': calendar,
    'chores': chores,
    'lists': lists,
    'polls': polls,
    'meals': meals,
    'birthdays': birthdays,
    'photos': photos,
    'location': location,
    'weekly_digest': weeklyDigest,
    'web_push_enabled': webPushEnabled,
    'quiet_hours_start': quietHoursStart,
    'quiet_hours_end': quietHoursEnd,
    'reminder_email_enabled': reminderEmailEnabled,
    'reminder_sms_enabled': reminderSmsEnabled,
    'reminder_sms_phone': reminderSmsPhone,
  };

  NotificationPrefs copyWith({
    bool? chat, bool? tasks, bool? calendar, bool? chores, bool? lists,
    bool? polls, bool? meals, bool? birthdays, bool? photos, bool? location,
    bool? weeklyDigest, bool? webPushEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
    bool? reminderEmailEnabled,
    bool? reminderSmsEnabled,
    String? reminderSmsPhone,
  }) => NotificationPrefs(
    chat: chat ?? this.chat,
    tasks: tasks ?? this.tasks,
    calendar: calendar ?? this.calendar,
    chores: chores ?? this.chores,
    lists: lists ?? this.lists,
    polls: polls ?? this.polls,
    meals: meals ?? this.meals,
    birthdays: birthdays ?? this.birthdays,
    photos: photos ?? this.photos,
    location: location ?? this.location,
    weeklyDigest: weeklyDigest ?? this.weeklyDigest,
    webPushEnabled: webPushEnabled ?? this.webPushEnabled,
    quietHoursStart: quietHoursStart ?? this.quietHoursStart,
    quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
    reminderEmailEnabled: reminderEmailEnabled ?? this.reminderEmailEnabled,
    reminderSmsEnabled: reminderSmsEnabled ?? this.reminderSmsEnabled,
    reminderSmsPhone: reminderSmsPhone ?? this.reminderSmsPhone,
  );
}

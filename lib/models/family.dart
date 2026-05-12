// lib/models/family.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';

class Family {
  final String id;
  final String name;
  final String ownerId;
  final String joinCode;
  final String? announcement;
  final String? announcementAuthor;
  final SubscriptionTier subscriptionTier;
  final DateTime? trialStartDate;
  final String currency; // ISO 4217: AUD, USD, GBP, CAD, INR
  final List<String> enabledModules;
  final DateTime createdAt;
  final bool welcomeDismissed;
  final bool weeklyDigest;
  final int weeklyDigestDay;   // 0=Sun … 6=Sat (UTC)
  final int weeklyDigestHour;  // 0–23 (UTC)
  final bool dailyDevotionalEnabled;
  final int dailyDevotionalHour;   // 0–23 (local)
  final int dailyDevotionalMinute; // 0–59
  /// Flexible JSON (food budget caps, simple debt list, integrations flags). Synced when `settings` column exists in DB.
  final Map<String, dynamic> settings;
  /// Bumped on family metadata edits for last-write-wins merge across devices.
  final DateTime updatedAt;

  Family({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.joinCode,
    this.announcement,
    this.announcementAuthor,
    this.subscriptionTier = SubscriptionTier.trial,
    this.trialStartDate,
    this.currency = 'AUD',
    this.enabledModules = const [],
    required this.createdAt,
    this.welcomeDismissed = false,
    this.weeklyDigest = true,
    this.weeklyDigestDay = 0,
    this.weeklyDigestHour = 8,
    this.dailyDevotionalEnabled = false,
    this.dailyDevotionalHour = 7,
    this.dailyDevotionalMinute = 0,
    this.settings = const {},
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory Family.fromJson(Map<String, dynamic> j) {
    final created = parseDate(j['created_at']);
    return Family(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    ownerId: j['owner_id'] as String? ?? '',
    joinCode: j['join_code'] as String? ?? '',
    announcement: j['announcement'] as String?,
    announcementAuthor: j['announcement_author'] as String?,
    subscriptionTier: subscriptionTierFromString(j['subscription_tier'] as String?),
    trialStartDate: parseDateOpt(j['trial_start_date']),
    currency: (j['currency'] as String?) ?? 'AUD',
    enabledModules: strList(j['enabled_modules']),
    createdAt: created,
    welcomeDismissed: (j['welcome_dismissed'] ?? false) as bool,
    weeklyDigest: (j['weekly_digest'] ?? true) as bool,
    weeklyDigestDay: (j['weekly_digest_day'] as num?)?.toInt() ?? 0,
    weeklyDigestHour: (j['weekly_digest_hour'] as num?)?.toInt() ?? 8,
    dailyDevotionalEnabled: (j['daily_devotional_enabled'] ?? false) as bool,
    dailyDevotionalHour: (j['daily_devotional_hour'] as num?)?.toInt() ?? 7,
    dailyDevotionalMinute: (j['daily_devotional_minute'] as num?)?.toInt() ?? 0,
    settings: j['settings'] is Map
        ? Map<String, dynamic>.from(j['settings'] as Map)
        : const {},
    updatedAt: parseDateOpt(j['updated_at']) ?? created,
  );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'owner_id': ownerId,
    'join_code': joinCode,
    'announcement': announcement,
    'announcement_author': announcementAuthor,
    'subscription_tier': subscriptionTier.name,
    'trial_start_date': trialStartDate?.toIso8601String(),
    'currency': currency,
    'enabled_modules': enabledModules,
    'created_at': createdAt.toIso8601String(),
    'welcome_dismissed': welcomeDismissed,
    'weekly_digest': weeklyDigest,
    'weekly_digest_day': weeklyDigestDay,
    'weekly_digest_hour': weeklyDigestHour,
    'daily_devotional_enabled': dailyDevotionalEnabled,
    'daily_devotional_hour': dailyDevotionalHour,
    'daily_devotional_minute': dailyDevotionalMinute,
    'settings': settings,
    'updated_at': updatedAt.toIso8601String(),
  };

  Family copyWith({
    String? id, String? name, String? ownerId, String? joinCode,
    String? announcement, String? announcementAuthor,
    SubscriptionTier? subscriptionTier, DateTime? trialStartDate, String? currency, List<String>? enabledModules,
    DateTime? createdAt, bool? welcomeDismissed, bool? weeklyDigest,
    int? weeklyDigestDay, int? weeklyDigestHour,
    bool? dailyDevotionalEnabled, int? dailyDevotionalHour, int? dailyDevotionalMinute,
    Map<String, dynamic>? settings,
    DateTime? updatedAt,
  }) {
    final anyChange = id != null ||
        name != null ||
        ownerId != null ||
        joinCode != null ||
        announcement != null ||
        announcementAuthor != null ||
        subscriptionTier != null ||
        trialStartDate != null ||
        currency != null ||
        enabledModules != null ||
        createdAt != null ||
        welcomeDismissed != null ||
        weeklyDigest != null ||
        weeklyDigestDay != null ||
        weeklyDigestHour != null ||
        dailyDevotionalEnabled != null ||
        dailyDevotionalHour != null ||
        dailyDevotionalMinute != null ||
        settings != null;
    return Family(
    id: id ?? this.id,
    name: name ?? this.name,
    ownerId: ownerId ?? this.ownerId,
    joinCode: joinCode ?? this.joinCode,
    announcement: announcement ?? this.announcement,
    announcementAuthor: announcementAuthor ?? this.announcementAuthor,
    subscriptionTier: subscriptionTier ?? this.subscriptionTier,
    trialStartDate: trialStartDate ?? this.trialStartDate,
    currency: currency ?? this.currency,
    enabledModules: enabledModules ?? this.enabledModules,
    createdAt: createdAt ?? this.createdAt,
    welcomeDismissed: welcomeDismissed ?? this.welcomeDismissed,
    weeklyDigest: weeklyDigest ?? this.weeklyDigest,
    weeklyDigestDay: weeklyDigestDay ?? this.weeklyDigestDay,
    weeklyDigestHour: weeklyDigestHour ?? this.weeklyDigestHour,
    dailyDevotionalEnabled: dailyDevotionalEnabled ?? this.dailyDevotionalEnabled,
    dailyDevotionalHour: dailyDevotionalHour ?? this.dailyDevotionalHour,
    dailyDevotionalMinute: dailyDevotionalMinute ?? this.dailyDevotionalMinute,
    settings: settings ?? this.settings,
    updatedAt: updatedAt ?? (anyChange ? DateTime.now() : this.updatedAt),
  );
  }

  // ── Trial helpers ──────────────────────────────────────────────────────
  static const trialDays = 14;

  /// The effective trial start: explicit field or family creation date.
  DateTime get effectiveTrialStart => trialStartDate ?? createdAt;

  /// Whether the 14-day free trial has expired (only applies while [subscriptionTier] is [SubscriptionTier.trial]).
  bool get isTrialExpired {
    if (subscriptionTier != SubscriptionTier.trial) return false;
    return DateTime.now().difference(effectiveTrialStart) >= const Duration(days: trialDays);
  }

  /// Days remaining in the trial (0 if expired or not on trial).
  int get trialDaysRemaining {
    if (subscriptionTier != SubscriptionTier.trial) return 0;
    final remaining = trialDays - DateTime.now().difference(effectiveTrialStart).inDays;
    return remaining.clamp(0, trialDays);
  }

  /// Modules available on the free/expired tier (tasks, lists, calendar only).
  static const freeModules = {'tasks', 'lists', 'calendar'};

  /// Whether a given module route is accessible on the current plan.
  bool isModuleAccessible(String route) {
    if (subscriptionTier != SubscriptionTier.trial) return true;
    if (!isTrialExpired) return true; // trial still active → full access
    return freeModules.contains(route.replaceAll('/', ''));
  }

  /// Whether AI features are available on the current plan.
  /// AI is available during trial, and on ai / ai_family tiers — NOT on base.
  bool get hasAIAccess {
    switch (subscriptionTier) {
      case SubscriptionTier.ai:
      case SubscriptionTier.ai_family:
        return true;
      case SubscriptionTier.trial:
        return !isTrialExpired; // AI during trial, not after
      case SubscriptionTier.base:
        return false;
    }
  }

  /// Synced custom task folder names (stored in [settings] for multi-device).
  static const kTaskCustomFoldersSettingsKey = 'task_custom_folders';

  List<String> get taskCustomFolderNames {
    final v = settings[kTaskCustomFoldersSettingsKey];
    if (v is! List) return const [];
    return v
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Family withTaskCustomFolders(List<String> names) {
    final sorted = names.map((e) => e.trim()).where((s) => s.isNotEmpty).toList()..sort();
    final nextSettings = Map<String, dynamic>.from(settings)
      ..[kTaskCustomFoldersSettingsKey] = sorted;
    return copyWith(settings: nextSettings);
  }
}

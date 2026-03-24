// lib/models/models.dart
// FamilyHub - Complete data models

// ignore_for_file: constant_identifier_names

import '../services/field_encryption_service.dart';

typedef PrayerRequest = PrayerWallEntry;
typedef AIHistoryEntry = AIHistory;
typedef PeriodEntry = PeriodCycle;
typedef LocationShare = UserLocation;
typedef Occasion = SpecialDate;
typedef Photo = FamilyPhoto;
typedef Message = ChatMessage;
typedef ShoppingListItem = ListItem;
typedef MealPlan = MealPlanEntry;

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum Role { OWNER, ADMIN, MEMBER }

/// How someone is treated in the home (parent presets, module access hints).
enum HouseholdRole { parent, teen, child, other }

HouseholdRole householdRoleFromString(String? s) {
  switch (s?.toLowerCase()) {
    case 'teen':
      return HouseholdRole.teen;
    case 'child':
      return HouseholdRole.child;
    case 'other':
      return HouseholdRole.other;
    default:
      return HouseholdRole.parent;
  }
}

enum Visibility { PRIVATE, FAMILY, SPECIFIC }

enum SubscriptionTier { trial, base, ai, ai_family }

enum Recurrence { NONE, DAILY, WEEKLY, MONTHLY }

enum Priority { LOW, MEDIUM, HIGH }

enum MealType { BREAKFAST, LUNCH, DINNER }

enum ListCategory { GROCERY, HARDWARE, PACKING, OTHER }

enum ChoreFrequency { DAILY, WEEKLY, CUSTOM }

enum PollStatus { open, closed }

enum ApprovalStatus { PENDING, APPROVED, REJECTED }

enum RedemptionStatus { PENDING, APPROVED, DENIED }

enum FlowLevel { LIGHT, MEDIUM, HEAVY }

enum CycleMood { GREAT, GOOD, OKAY, LOW, ROUGH }

enum PrayerWallType { GRATITUDE, REQUEST, ANSWERED }

enum BloodType { Aplus, Aminus, Bplus, Bminus, ABplus, ABminus, Oplus, Ominus, Unknown }

enum AllergySeverity { MILD, MODERATE, SEVERE }

enum SpecialDateType { BIRTHDAY, ANNIVERSARY, MEMORIAL, OTHER }

enum TransactionType { INCOME, EXPENSE }

enum BudgetCategory { housing, food, transport, entertainment, utilities, healthcare, education, savings, other }

enum MessageType { text, image, audio, system }

enum EventVisibility { family, private, specific }

enum TaskPriority { low, medium, high }

enum TaskRecurrence { none, daily, weekly, monthly }

// ─────────────────────────────────────────────────────────────────────────────
// Enum helpers
// ─────────────────────────────────────────────────────────────────────────────

Role roleFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'OWNER': return Role.OWNER;
    case 'ADMIN': return Role.ADMIN;
    default: return Role.MEMBER;
  }
}

Visibility visibilityFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'PRIVATE': return Visibility.PRIVATE;
    case 'SPECIFIC': return Visibility.SPECIFIC;
    default: return Visibility.FAMILY;
  }
}

SubscriptionTier subscriptionTierFromString(String? s) {
  switch (s) {
    case 'base': return SubscriptionTier.base;
    case 'ai': return SubscriptionTier.ai;
    case 'ai_family': return SubscriptionTier.ai_family;
    default: return SubscriptionTier.trial;
  }
}

Recurrence recurrenceFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'DAILY': return Recurrence.DAILY;
    case 'WEEKLY': return Recurrence.WEEKLY;
    case 'MONTHLY': return Recurrence.MONTHLY;
    default: return Recurrence.NONE;
  }
}

Priority priorityFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'HIGH': return Priority.HIGH;
    case 'MEDIUM': return Priority.MEDIUM;
    default: return Priority.LOW;
  }
}

MealType mealTypeFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'LUNCH': return MealType.LUNCH;
    case 'DINNER': return MealType.DINNER;
    default: return MealType.BREAKFAST;
  }
}

ListCategory listCategoryFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'HARDWARE': return ListCategory.HARDWARE;
    case 'PACKING': return ListCategory.PACKING;
    case 'OTHER': return ListCategory.OTHER;
    default: return ListCategory.GROCERY;
  }
}

ChoreFrequency choreFrequencyFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'WEEKLY': return ChoreFrequency.WEEKLY;
    case 'CUSTOM': return ChoreFrequency.CUSTOM;
    default: return ChoreFrequency.DAILY;
  }
}

PollStatus pollStatusFromString(String? s) {
  switch (s?.toLowerCase()) {
    case 'closed': return PollStatus.closed;
    default: return PollStatus.open;
  }
}

ApprovalStatus approvalStatusFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'APPROVED': return ApprovalStatus.APPROVED;
    case 'REJECTED': return ApprovalStatus.REJECTED;
    default: return ApprovalStatus.PENDING;
  }
}

RedemptionStatus redemptionStatusFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'APPROVED': return RedemptionStatus.APPROVED;
    case 'DENIED': return RedemptionStatus.DENIED;
    default: return RedemptionStatus.PENDING;
  }
}

FlowLevel flowLevelFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'HEAVY': return FlowLevel.HEAVY;
    case 'MEDIUM': return FlowLevel.MEDIUM;
    default: return FlowLevel.LIGHT;
  }
}

CycleMood cycleMoodFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'GREAT': return CycleMood.GREAT;
    case 'GOOD': return CycleMood.GOOD;
    case 'LOW': return CycleMood.LOW;
    case 'ROUGH': return CycleMood.ROUGH;
    default: return CycleMood.OKAY;
  }
}

PrayerWallType prayerWallTypeFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'GRATITUDE': return PrayerWallType.GRATITUDE;
    case 'ANSWERED': return PrayerWallType.ANSWERED;
    default: return PrayerWallType.REQUEST;
  }
}

BloodType bloodTypeFromString(String? s) {
  switch (s) {
    case 'A+': case 'Aplus': return BloodType.Aplus;
    case 'A-': case 'Aminus': return BloodType.Aminus;
    case 'B+': case 'Bplus': return BloodType.Bplus;
    case 'B-': case 'Bminus': return BloodType.Bminus;
    case 'AB+': case 'ABplus': return BloodType.ABplus;
    case 'AB-': case 'ABminus': return BloodType.ABminus;
    case 'O+': case 'Oplus': return BloodType.Oplus;
    case 'O-': case 'Ominus': return BloodType.Ominus;
    default: return BloodType.Unknown;
  }
}

AllergySeverity allergySeverityFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'MODERATE': return AllergySeverity.MODERATE;
    case 'SEVERE': return AllergySeverity.SEVERE;
    default: return AllergySeverity.MILD;
  }
}

SpecialDateType specialDateTypeFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'ANNIVERSARY': return SpecialDateType.ANNIVERSARY;
    case 'MEMORIAL': return SpecialDateType.MEMORIAL;
    case 'OTHER': return SpecialDateType.OTHER;
    default: return SpecialDateType.BIRTHDAY;
  }
}

TransactionType transactionTypeFromString(String? s) {
  switch (s?.toUpperCase()) {
    case 'EXPENSE': return TransactionType.EXPENSE;
    default: return TransactionType.INCOME;
  }
}

Priority? _taskPriorityToPriority(TaskPriority? tp) {
  if (tp == null) return null;
  switch (tp) {
    case TaskPriority.high: return Priority.HIGH;
    case TaskPriority.medium: return Priority.MEDIUM;
    case TaskPriority.low: return Priority.LOW;
  }
}

Recurrence? _taskRecurrenceToRecurrence(TaskRecurrence? tr) {
  if (tr == null) return null;
  switch (tr) {
    case TaskRecurrence.daily: return Recurrence.DAILY;
    case TaskRecurrence.weekly: return Recurrence.WEEKLY;
    case TaskRecurrence.monthly: return Recurrence.MONTHLY;
    case TaskRecurrence.none: return Recurrence.NONE;
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// User
// ─────────────────────────────────────────────────────────────────────────────

class User {
  final String id;
  final String name;
  final String email;
  final String? avatar;
  /// Per-device prefs (e.g. Health sync). Not all backends persist every key.
  final Map<String, dynamic> settings;

  const User({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
    this.settings = const {},
    DateTime? createdAt,
  });

  String get initials {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  String? get avatarUrl => avatar;

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    email: j['email'] as String? ?? '',
    avatar: j['avatar'] as String?,
    settings: j['settings'] is Map
        ? Map<String, dynamic>.from(j['settings'] as Map)
        : const {},
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'avatar': avatar,
    'settings': settings,
  };

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? avatar,
    Map<String, dynamic>? settings,
  }) =>
    User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      settings: settings ?? this.settings,
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Family
// ─────────────────────────────────────────────────────────────────────────────

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
    final created = _parseDate(j['created_at']);
    return Family(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    ownerId: j['owner_id'] as String? ?? '',
    joinCode: j['join_code'] as String? ?? '',
    announcement: j['announcement'] as String?,
    announcementAuthor: j['announcement_author'] as String?,
    subscriptionTier: subscriptionTierFromString(j['subscription_tier'] as String?),
    trialStartDate: _parseDateOpt(j['trial_start_date']),
    currency: (j['currency'] as String?) ?? 'AUD',
    enabledModules: _strList(j['enabled_modules']),
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
    updatedAt: _parseDateOpt(j['updated_at']) ?? created,
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

// ─────────────────────────────────────────────────────────────────────────────
// FamilyMember
// ─────────────────────────────────────────────────────────────────────────────

class FamilyMember {
  final String userId;
  final String familyId;
  final Role role;
  final List<String>? moduleAccess;
  final String? displayName;
  final HouseholdRole householdRole;

  const FamilyMember({
    required this.userId,
    required this.familyId,
    this.role = Role.MEMBER,
    this.moduleAccess,
    this.displayName,
    this.householdRole = HouseholdRole.parent,
  });

  // Convenience getters
  String get id => userId;
  /// Composite key for dedup in merge operations.
  String get mergeKey => '${userId}_$familyId';
  String get name => displayName ?? userId;

  factory FamilyMember.fromJson(Map<String, dynamic> j) => FamilyMember(
    userId: j['user_id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    role: roleFromString(j['role'] as String?),
    moduleAccess: j['module_access'] != null
        ? _strList(j['module_access'])
        : null,
    displayName: (j['display_name'] ?? j['name']) as String?,
    householdRole: householdRoleFromString(j['household_role'] as String?),
  );

  FamilyMember copyWith({
    String? userId,
    String? familyId,
    Role? role,
    List<String>? moduleAccess,
    String? displayName,
    HouseholdRole? householdRole,
  }) => FamilyMember(
    userId: userId ?? this.userId,
    familyId: familyId ?? this.familyId,
    role: role ?? this.role,
    moduleAccess: moduleAccess ?? this.moduleAccess,
    displayName: displayName ?? this.displayName,
    householdRole: householdRole ?? this.householdRole,
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'family_id': familyId,
    'role': role.name,
    'module_access': moduleAccess,
    'display_name': displayName,
    'household_role': householdRole.name,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Task
// ─────────────────────────────────────────────────────────────────────────────

class Task {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String? notes;
  final DateTime? dueDate;
  final String? dueTime;
  final int? reminderMinutes;
  final Priority priority;
  final bool completed;
  final String? completedBy;
  final String? updatedBy;
  final Visibility visibility;
  final List<String> assignees;
  final List<String> tags;
  final Recurrence recurrence;
  /// Monotonic sync version — bump on every user edit so other devices pull the latest.
  final DateTime updatedAt;

  Task({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    required this.title,
    this.notes,
    this.dueDate,
    this.dueTime,
    this.reminderMinutes,
    Priority? priority,
    TaskPriority? taskPriority,
    this.completed = false,
    this.completedBy,
    this.updatedBy,
    this.visibility = Visibility.FAMILY,
    List<String>? assignees,
    List<String>? assigneeIds,
    this.tags = const [],
    Recurrence? recurrence,
    TaskRecurrence? taskRecurrence,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? createdBy ?? '',
       assignees = assignees ?? assigneeIds ?? const [],
       priority = priority ?? _taskPriorityToPriority(taskPriority) ?? Priority.MEDIUM,
       recurrence = recurrence ?? _taskRecurrenceToRecurrence(taskRecurrence) ?? Recurrence.NONE;

  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    notes: j['notes'] as String?,
    dueDate: _parseDateOpt(j['due_date']),
    dueTime: j['due_time'] as String?,
    reminderMinutes: (j['reminder_minutes'] as num?)?.toInt() ?? (j['reminderMinutes'] as num?)?.toInt(),
    priority: priorityFromString(j['priority'] as String?),
    completed: (j['completed'] ?? false) as bool,
    completedBy: j['completed_by'] as String?,
    updatedBy: j['updated_by'] as String?,
    visibility: visibilityFromString(j['visibility'] as String?),
    assignees: _strList(j['assignees']),
    tags: _strList(j['tags']),
    recurrence: recurrenceFromString(j['recurrence'] as String?),
    updatedAt: _parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'notes': notes,
    'due_date': (dueDate ?? DateTime.now()).toIso8601String(),
    'due_time': dueTime,
    'reminder_minutes': reminderMinutes,
    'priority': priority.name,
    'completed': completed,
    'completed_by': completedBy,
    'updated_by': updatedBy,
    'visibility': visibility.name,
    'assignees': assignees,
    'tags': tags,
    'recurrence': recurrence.name,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getters for screen compatibility
  List<String> get assigneeIds => assignees;
  String get createdBy => creatorId;
  bool get isOverdue => !completed && dueDate != null && dueDate!.isBefore(DateTime.now());

  Task copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    String? notes, DateTime? dueDate, String? dueTime, int? reminderMinutes,
    Priority? priority, bool? completed, String? completedBy, String? updatedBy,
    Visibility? visibility, List<String>? assignees, List<String>? tags,
    Recurrence? recurrence, DateTime? updatedAt,
  }) => Task(
    id: id ?? this.id,
    familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    dueDate: dueDate ?? this.dueDate,
    dueTime: dueTime ?? this.dueTime,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    priority: priority ?? this.priority,
    completed: completed ?? this.completed,
    completedBy: completedBy ?? this.completedBy,
    updatedBy: updatedBy ?? this.updatedBy,
    visibility: visibility ?? this.visibility,
    assignees: assignees ?? this.assignees,
    tags: tags ?? this.tags,
    recurrence: recurrence ?? this.recurrence,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CalendarEvent
// ─────────────────────────────────────────────────────────────────────────────

class CalendarEvent {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String? description;
  final String? location;
  final DateTime start;
  final DateTime end;
  final Visibility visibility;
  final List<String> sharedWith;
  final List<String> checklist;
  final double? budgetEstimate;
  final String? externalCalendarId;
  final Recurrence recurrence;
  final DateTime updatedAt;

  CalendarEvent({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    required this.title,
    this.description,
    this.location,
    DateTime? start,
    DateTime? startDate,
    DateTime? end,
    DateTime? endDate,
    bool? allDay,
    DateTime? createdAt,
    this.visibility = Visibility.FAMILY,
    this.sharedWith = const [],
    this.checklist = const [],
    this.budgetEstimate,
    this.externalCalendarId,
    this.recurrence = Recurrence.NONE,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? createdBy ?? '',
       start = start ?? startDate ?? DateTime.now(),
       end = end ?? endDate ?? (startDate ?? DateTime.now()).add(const Duration(hours: 1));

  factory CalendarEvent.fromJson(Map<String, dynamic> j) => CalendarEvent(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    location: j['location'] as String?,
    start: _parseDate(j['start']),
    end: _parseDate(j['end']),
    visibility: visibilityFromString(j['visibility'] as String?),
    sharedWith: _strList(j['shared_with']),
    checklist: _strList(j['checklist']),
    budgetEstimate: j['budget_estimate'] != null
        ? (j['budget_estimate'] as num).toDouble()
        : null,
    externalCalendarId: j['external_calendar_id'] as String?,
    recurrence: recurrenceFromString(j['recurrence'] as String?),
    updatedAt: _parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'description': description,
    'location': location,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'visibility': visibility.name,
    'shared_with': sharedWith,
    'checklist': checklist,
    'budget_estimate': budgetEstimate,
    'external_calendar_id': externalCalendarId,
    'recurrence': recurrence.name,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getters
  DateTime get startDate => start;
  DateTime get endDate => end;
  bool get allDay => start.hour == 0 && start.minute == 0 && end.hour == 0 && end.minute == 0;
  String get createdBy => creatorId;
  DateTime get createdAt => start; // fallback - use start as proxy

  CalendarEvent copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    String? description, String? location, DateTime? start, DateTime? end,
    Visibility? visibility, List<String>? sharedWith, List<String>? checklist,
    double? budgetEstimate, String? externalCalendarId, Recurrence? recurrence,
    DateTime? updatedAt,
  }) => CalendarEvent(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, title: title ?? this.title,
    description: description ?? this.description, location: location ?? this.location,
    start: start ?? this.start, end: end ?? this.end,
    visibility: visibility ?? this.visibility, sharedWith: sharedWith ?? this.sharedWith,
    checklist: checklist ?? this.checklist,
    budgetEstimate: budgetEstimate ?? this.budgetEstimate,
    externalCalendarId: externalCalendarId ?? this.externalCalendarId,
    recurrence: recurrence ?? this.recurrence,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ExternalCalendar
// ─────────────────────────────────────────────────────────────────────────────

enum ExternalCalendarType { google, icsUrl }

ExternalCalendarType externalCalendarTypeFromString(String? s) {
  switch (s) {
    case 'google': return ExternalCalendarType.google;
    case 'icsUrl': return ExternalCalendarType.icsUrl;
    default: return ExternalCalendarType.icsUrl;
  }
}

class ExternalCalendar {
  final String id;
  final String familyId;
  final String creatorId;
  final ExternalCalendarType type;
  final String name;
  final String? googleCalendarId;
  final String? icsUrl;
  final String? color;
  final bool enabled;
  final DateTime lastSyncedAt;
  final DateTime createdAt;

  ExternalCalendar({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? userId,
    required this.type,
    required this.name,
    this.googleCalendarId,
    this.icsUrl,
    this.color,
    this.enabled = true,
    DateTime? lastSyncedAt,
    DateTime? createdAt,
  }) : creatorId = creatorId ?? userId ?? '',
       lastSyncedAt = lastSyncedAt ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now();

  // Convenience alias for screens that reference userId
  String get userId => creatorId;

  factory ExternalCalendar.fromJson(Map<String, dynamic> j) => ExternalCalendar(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: (j['creator_id'] ?? j['user_id']) as String? ?? '',
    type: externalCalendarTypeFromString(j['type'] as String?),
    name: j['name'] as String? ?? '',
    googleCalendarId: (j['google_calendar_id'] ?? (j['type'] == 'GOOGLE' ? j['url'] : null)) as String?,
    icsUrl: (j['ics_url'] ?? (j['type'] != 'GOOGLE' ? j['url'] : null)) as String?,
    color: j['color'] as String?,
    enabled: j['enabled'] as bool? ?? true,
    lastSyncedAt: _parseDate(j['last_synced'] ?? j['last_synced_at']),
    createdAt: _parseDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'type': type.name,
    'name': name,
    'url': googleCalendarId ?? icsUrl,
    'color': color,
    'enabled': enabled,
    'last_synced': lastSyncedAt.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  ExternalCalendar copyWith({
    String? id, String? familyId, String? creatorId, ExternalCalendarType? type,
    String? name, String? googleCalendarId, String? icsUrl, String? color,
    bool? enabled, DateTime? lastSyncedAt, DateTime? createdAt,
  }) => ExternalCalendar(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, type: type ?? this.type,
    name: name ?? this.name, googleCalendarId: googleCalendarId ?? this.googleCalendarId,
    icsUrl: icsUrl ?? this.icsUrl, color: color ?? this.color,
    enabled: enabled ?? this.enabled, lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    createdAt: createdAt ?? this.createdAt,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Recipe
// ─────────────────────────────────────────────────────────────────────────────

class Recipe {
  final String id;
  final String familyId;
  final String title;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
  final int servings;
  final List<String> tags;
  final String? image;
  final int? prepMinutes;
  final int? cookMinutes;
  /// Per full recipe (not per serving) unless noted in UI.
  final int? kcal;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final DateTime updatedAt;

  Recipe({
    required this.id,
    required this.familyId,
    required this.title,
    List<RecipeIngredient>? ingredients,
    this.steps = const [],
    int? servings,
    this.tags = const [],
    this.image,
    this.prepMinutes,
    this.cookMinutes,
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    // Accept but ignore extra fields from screen
    String? description,
    String? sourceUrl,
    String? createdBy,
    String? creatorId,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        servings = servings ?? 4,
       ingredients = ingredients ?? const [];

  factory Recipe.fromJson(Map<String, dynamic> j) {
    final rawIngs = j['ingredients'];
    final List<RecipeIngredient> ingredients;
    if (rawIngs is List) {
      ingredients = rawIngs.map((e) {
        if (e is String) return RecipeIngredient.fromString(e);
        if (e is Map<String, dynamic>) return RecipeIngredient.fromJson(e);
        return RecipeIngredient.fromString(e.toString());
      }).toList();
    } else {
      ingredients = const [];
    }
    return Recipe(
      id: j['id'] as String? ?? '',
      familyId: j['family_id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      ingredients: ingredients,
      steps: _strList(j['steps']),
      servings: (j['servings'] as num?)?.toInt() ?? 4,
      tags: _strList(j['tags']),
      image: j['image'] as String?,
      prepMinutes: (j['prep_minutes'] ?? j['prepMinutes']) as int?,
      cookMinutes: (j['cook_minutes'] ?? j['cookMinutes']) as int?,
      kcal: (j['kcal'] as num?)?.toInt(),
      proteinG: (j['protein_g'] as num?)?.toDouble() ?? (j['proteinG'] as num?)?.toDouble(),
      carbsG: (j['carbs_g'] as num?)?.toDouble() ?? (j['carbsG'] as num?)?.toDouble(),
      fatG: (j['fat_g'] as num?)?.toDouble() ?? (j['fatG'] as num?)?.toDouble(),
      fiberG: (j['fiber_g'] as num?)?.toDouble() ?? (j['fiberG'] as num?)?.toDouble(),
      updatedAt: _parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'title': title,
    'ingredients': ingredients.map((e) => e.toJson()).toList(),
    'steps': steps,
    'servings': servings,
    'tags': tags,
    'image': image,
    if (prepMinutes != null) 'prepMinutes': prepMinutes,
    if (cookMinutes != null) 'cookMinutes': cookMinutes,
    'kcal': kcal,
    'protein_g': proteinG,
    'carbs_g': carbsG,
    'fat_g': fatG,
    'fiber_g': fiberG,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getters
  String? get imageUrl => image;
  String? get description => null;

  Recipe copyWith({
    String? id, String? familyId, String? title, List<RecipeIngredient>? ingredients,
    List<String>? steps, int? servings, List<String>? tags, String? image,
    int? prepMinutes, int? cookMinutes, int? kcal, double? proteinG,
    double? carbsG, double? fatG, double? fiberG, DateTime? updatedAt,
  }) => Recipe(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    title: title ?? this.title, ingredients: ingredients ?? this.ingredients,
    steps: steps ?? this.steps, servings: servings ?? this.servings,
    tags: tags ?? this.tags, image: image ?? this.image,
    prepMinutes: prepMinutes ?? this.prepMinutes,
    cookMinutes: cookMinutes ?? this.cookMinutes,
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
    fiberG: fiberG ?? this.fiberG,
    updatedAt: updatedAt ??
        ((title != null || ingredients != null || steps != null || servings != null ||
                tags != null || image != null || prepMinutes != null || cookMinutes != null ||
                kcal != null || proteinG != null || carbsG != null || fatG != null || fiberG != null)
            ? DateTime.now()
            : this.updatedAt),
  );
}

class RecipeIngredient {
  final String name;
  final String? quantity;
  final String? unit;

  RecipeIngredient({required this.name, String? quantity, String? amount, this.unit})
      : quantity = quantity ?? amount;

  // Convenience alias used by screens
  String? get amount => quantity;

  factory RecipeIngredient.fromString(String s) => RecipeIngredient(name: s);

  factory RecipeIngredient.fromJson(Map<String, dynamic> j) => RecipeIngredient(
    name: j['name'] as String? ?? '',
    quantity: j['quantity'] as String?,
    unit: j['unit'] as String?,
  );

  Map<String, dynamic> toJson() => {'name': name, 'quantity': quantity, 'unit': unit};

  @override
  String toString() => quantity != null ? '$quantity${unit != null ? ' $unit' : ''} $name' : name;
}

// ─────────────────────────────────────────────────────────────────────────────
// MealPlanEntry
// ─────────────────────────────────────────────────────────────────────────────

class MealPlanEntry {
  final String id;
  final String familyId;
  final DateTime date;
  final String mealType; // stored as lowercase string ('breakfast','lunch','dinner','snack')
  final String? recipeId;
  final String? customMeal;
  final String? notes;
  final int? servings;
  final String? prepNotes;
  /// `weekly_same_slot` | `daily` | null
  final String? repeatRule;
  final String? sourceMealPlanId;
  final String? leftoverMealPlanId;
  final DateTime updatedAt;

  MealPlanEntry({
    required this.id,
    required this.familyId,
    required this.date,
    required this.mealType,
    this.recipeId,
    this.customMeal,
    this.notes,
    this.servings,
    this.prepNotes,
    this.repeatRule,
    this.sourceMealPlanId,
    this.leftoverMealPlanId,
    String? title,
    String? createdBy,
    String? creatorId,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory MealPlanEntry.fromJson(Map<String, dynamic> j) => MealPlanEntry(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    date: _parseDate(j['date']),
    mealType: (j['meal_type'] as String? ?? 'breakfast').toLowerCase(),
    recipeId: j['recipe_id'] as String?,
    customMeal: j['custom_meal'] as String?,
    notes: j['notes'] as String?,
    servings: (j['servings'] as num?)?.toInt(),
    prepNotes: j['prep_notes'] as String?,
    repeatRule: j['repeat_rule'] as String?,
    sourceMealPlanId: j['source_meal_plan_id'] as String?,
    leftoverMealPlanId: j['leftover_meal_plan_id'] as String?,
    updatedAt: _parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'date': date.toIso8601String(),
    'meal_type': mealType,
    'recipe_id': recipeId,
    'custom_meal': customMeal,
    'notes': notes,
    'servings': servings,
    'prep_notes': prepNotes,
    'repeat_rule': repeatRule,
    'source_meal_plan_id': sourceMealPlanId,
    'leftover_meal_plan_id': leftoverMealPlanId,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getters
  String get title => customMeal ?? '';

  MealPlanEntry copyWith({
    String? id, String? familyId, DateTime? date, String? mealType,
    String? recipeId, String? customMeal, String? notes, int? servings,
    String? prepNotes, String? repeatRule, String? sourceMealPlanId,
    String? leftoverMealPlanId, DateTime? updatedAt,
  }) => MealPlanEntry(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    date: date ?? this.date, mealType: mealType ?? this.mealType,
    recipeId: recipeId ?? this.recipeId, customMeal: customMeal ?? this.customMeal,
    notes: notes ?? this.notes,
    servings: servings ?? this.servings,
    prepNotes: prepNotes ?? this.prepNotes,
    repeatRule: repeatRule ?? this.repeatRule,
    sourceMealPlanId: sourceMealPlanId ?? this.sourceMealPlanId,
    leftoverMealPlanId: leftoverMealPlanId ?? this.leftoverMealPlanId,
    updatedAt: updatedAt ??
        ((date != null || mealType != null || recipeId != null || customMeal != null || notes != null || servings != null || prepNotes != null || repeatRule != null || sourceMealPlanId != null || leftoverMealPlanId != null)
            ? DateTime.now()
            : this.updatedAt),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ListItem & ShoppingList
// ─────────────────────────────────────────────────────────────────────────────

class ListItem {
  final String id;
  final String text;
  final String? quantity;
  final bool checked;
  final String? notes;
  final String? aiCategory;

  ListItem({
    required this.id,
    String? text,
    String? name,
    String? quantity,
    dynamic rawQuantity,
    this.checked = false,
    this.notes,
    this.aiCategory,
  }) : text = text ?? name ?? '',
       quantity = quantity ?? rawQuantity?.toString();

  factory ListItem.fromJson(Map<String, dynamic> j) => ListItem(
    id: j['id'] as String? ?? '',
    text: j['text'] as String? ?? '',
    quantity: j['quantity'] as String?,
    checked: (j['checked'] ?? false) as bool,
    notes: j['notes'] as String?,
    aiCategory: j['ai_category'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'quantity': quantity,
    'checked': checked,
    'notes': notes,
    'ai_category': aiCategory,
  };

  ListItem copyWith({
    String? id, String? text, String? quantity, bool? checked,
    String? notes, String? aiCategory,
  }) => ListItem(
    id: id ?? this.id,
    text: text ?? this.text,
    quantity: quantity ?? this.quantity,
    checked: checked ?? this.checked,
    notes: notes ?? this.notes,
    aiCategory: aiCategory ?? this.aiCategory,
  );

  // Convenience alias
  String get name => text;
}

class ShoppingList {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final List<ListItem> items;
  final ListCategory category;
  final Visibility visibility;
  final List<String> sharedWith;
  final DateTime updatedAt;

  ShoppingList({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    String? title,
    String? name,
    this.items = const [],
    this.category = ListCategory.GROCERY,
    this.visibility = Visibility.FAMILY,
    this.sharedWith = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? createdBy ?? '',
       title = title ?? name ?? '';

  factory ShoppingList.fromJson(Map<String, dynamic> j) => ShoppingList(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    items: _parseList(j['items'], ListItem.fromJson),
    category: listCategoryFromString(j['category'] as String?),
    visibility: visibilityFromString(j['visibility'] as String?),
    sharedWith: _strList(j['shared_with']),
    updatedAt: _parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'items': items.map((e) => e.toJson()).toList(),
    'category': category.name,
    'visibility': visibility.name,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getters
  String get name => title;

  ShoppingList copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    List<ListItem>? items, ListCategory? category, Visibility? visibility,
    List<String>? sharedWith, DateTime? updatedAt,
  }) => ShoppingList(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, title: title ?? this.title,
    items: items ?? this.items, category: category ?? this.category,
    visibility: visibility ?? this.visibility,
    sharedWith: sharedWith ?? this.sharedWith,
    updatedAt: updatedAt ??
        ((title != null || items != null || category != null || visibility != null || sharedWith != null)
            ? DateTime.now()
            : this.updatedAt),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// DevotionalEntry
// ─────────────────────────────────────────────────────────────────────────────

class DevotionalEntry {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String? scripture;
  final String? content;
  final List<String> reflectionPrompts;
  final String? prayer;
  final String? userPrayer;
  final List<String> tags;
  final DateTime date;
  final Visibility visibility;
  final bool isFavorited;
  final DateTime updatedAt;

  DevotionalEntry({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? userId,
    required this.title,
    this.scripture,
    this.content,
    this.reflectionPrompts = const [],
    this.prayer,
    this.userPrayer,
    this.tags = const [],
    DateTime? date,
    this.visibility = Visibility.FAMILY,
    this.isFavorited = false,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? userId ?? '',
       date = date ?? DateTime.now();

  factory DevotionalEntry.fromJson(Map<String, dynamic> j) => DevotionalEntry(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    scripture: j['scripture'] as String?,
    content: j['content'] as String?,
    reflectionPrompts: _strList(j['reflection_prompts']),
    prayer: j['prayer'] as String?,
    userPrayer: j['user_prayer'] as String?,
    tags: _strList(j['tags']),
    date: _parseDate(j['date']),
    visibility: visibilityFromString(j['visibility'] as String?),
    isFavorited: (j['is_favorited'] ?? false) as bool,
    updatedAt: _parseDateOpt(j['updated_at']) ?? _parseDate(j['date']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'scripture': scripture,
    'content': content,
    'reflection_prompts': reflectionPrompts,
    'prayer': prayer,
    'user_prayer': userPrayer,
    'tags': tags,
    'date': date.toIso8601String(),
    'visibility': visibility.name,
    'is_favorited': isFavorited,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getter
  String get userId => creatorId;

  DevotionalEntry copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    String? scripture, String? content, List<String>? reflectionPrompts,
    String? prayer, String? userPrayer, List<String>? tags,
    DateTime? date, Visibility? visibility, bool? isFavorited, DateTime? updatedAt,
  }) => DevotionalEntry(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, title: title ?? this.title,
    scripture: scripture ?? this.scripture, content: content ?? this.content,
    reflectionPrompts: reflectionPrompts ?? this.reflectionPrompts,
    prayer: prayer ?? this.prayer, userPrayer: userPrayer ?? this.userPrayer,
    tags: tags ?? this.tags, date: date ?? this.date,
    visibility: visibility ?? this.visibility,
    isFavorited: isFavorited ?? this.isFavorited,
    updatedAt: updatedAt ??
        ((title != null ||
                content != null ||
                isFavorited != null ||
                visibility != null)
            ? DateTime.now()
            : this.updatedAt),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FitnessMetric
// ─────────────────────────────────────────────────────────────────────────────

class FitnessMetric {
  final String id;
  final String userId;
  final String type;
  final double value;
  final DateTime date;
  final String? notes;

  const FitnessMetric({
    required this.id,
    required this.userId,
    required this.type,
    required this.value,
    required this.date,
    this.notes,
  });

  factory FitnessMetric.fromJson(Map<String, dynamic> j) => FitnessMetric(
    id: j['id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    type: j['type'] as String? ?? '',
    value: ((j['value'] as num?) ?? 0).toDouble(),
    date: _parseDate(j['date']),
    notes: j['notes'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'type': type,
    'value': value,
    'date': date.toIso8601String(),
    'notes': notes,
  };
}

class FitnessLog {
  final String id;
  final String familyId;
  final String userId;
  final String activity;
  final int durationMinutes;
  final int? caloriesBurned;
  final String? notes;
  final DateTime date;

  const FitnessLog({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.activity,
    this.durationMinutes = 0,
    this.caloriesBurned,
    this.notes,
    required this.date,
  });

  factory FitnessLog.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return FitnessLog(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      activity: FieldEncryption.decryptField(j['activity'] as String?, fid) ?? '',
      durationMinutes: FieldEncryption.decryptInt(j['duration_minutes'], fid) ?? 0,
      caloriesBurned: FieldEncryption.decryptInt(j['calories_burned'], fid),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      date: _parseDate(j['date']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'activity': FieldEncryption.encryptField(activity, familyId) ?? activity,
    'duration_minutes': FieldEncryption.encryptNum(durationMinutes, familyId) ?? durationMinutes.toString(),
    'calories_burned': FieldEncryption.encryptNum(caloriesBurned, familyId),
    'notes': FieldEncryption.encryptField(notes, familyId),
    'date': date.toIso8601String(),
  };

  FitnessLog copyWith({
    String? id, String? familyId, String? userId, String? activity,
    int? durationMinutes, int? caloriesBurned, String? notes, DateTime? date,
  }) => FitnessLog(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    userId: userId ?? this.userId, activity: activity ?? this.activity,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    caloriesBurned: caloriesBurned ?? this.caloriesBurned,
    notes: notes ?? this.notes, date: date ?? this.date,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Strong integration: WorkoutSession / WorkoutExercise / WorkoutSet
// ─────────────────────────────────────────────────────────────────────────────

class WorkoutSession {
  final String id;
  final String familyId;
  final String userId;
  final String title;
  final DateTime date;
  final int durationMinutes;
  final String? notes;
  /// When this session was written to Apple Health / Health Connect (if enabled).
  final DateTime? healthSyncedAt;
  final DateTime createdAt;

  const WorkoutSession({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.title,
    required this.date,
    this.durationMinutes = 0,
    this.notes,
    this.healthSyncedAt,
    required this.createdAt,
  });

  factory WorkoutSession.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return WorkoutSession(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      title: FieldEncryption.decryptField(j['title'] as String?, fid) ?? '',
      date: _parseDate(j['date']),
      durationMinutes: ((j['duration_minutes'] as num?) ?? 0).toInt(),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      healthSyncedAt: _parseDateOpt(j['health_synced_at']),
      createdAt: _parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'user_id': userId,
        'title': FieldEncryption.encryptField(title, familyId) ?? title,
        'date': date.toIso8601String(),
        'duration_minutes': durationMinutes,
        'notes': FieldEncryption.encryptField(notes, familyId),
        if (healthSyncedAt != null)
          'health_synced_at': healthSyncedAt!.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  WorkoutSession copyWith({
    String? id,
    String? familyId,
    String? userId,
    String? title,
    DateTime? date,
    int? durationMinutes,
    String? notes,
    DateTime? healthSyncedAt,
    DateTime? createdAt,
  }) =>
      WorkoutSession(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        userId: userId ?? this.userId,
        title: title ?? this.title,
        date: date ?? this.date,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        notes: notes ?? this.notes,
        healthSyncedAt: healthSyncedAt ?? this.healthSyncedAt,
        createdAt: createdAt ?? this.createdAt,
      );
}

class WorkoutExercise {
  final String id;
  final String familyId;
  final String userId;
  final String sessionId;
  final String exerciseName;
  final int order;
  final int restSeconds;
  final String? notes;
  /// Step-by-step how-to (AI or user). Prefer text over video for cost.
  final String? techniqueNotes;
  /// Optional link to a free demo (e.g. YouTube / ExRx).
  final String? referenceUrl;
  /// Illustration URL (e.g. wger.de) — not encrypted (public CDN).
  final String? techniqueImageUrl;
  /// ExerciseDB exercise id when [techniqueImageUrl] is their GIF URL.
  final String? exerciseDbId;
  final DateTime createdAt;

  const WorkoutExercise({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.sessionId,
    required this.exerciseName,
    this.order = 0,
    this.restSeconds = 60,
    this.notes,
    this.techniqueNotes,
    this.referenceUrl,
    this.techniqueImageUrl,
    this.exerciseDbId,
    required this.createdAt,
  });

  factory WorkoutExercise.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return WorkoutExercise(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      sessionId: j['session_id'] as String? ?? '',
      exerciseName:
          FieldEncryption.decryptField(j['exercise_name'] as String?, fid) ??
              '',
      order: ((j['order'] as num?) ?? 0).toInt(),
      restSeconds: ((j['rest_seconds'] as num?) ?? 60).toInt(),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      techniqueNotes:
          FieldEncryption.decryptField(j['technique_notes'] as String?, fid),
      referenceUrl:
          FieldEncryption.decryptField(j['reference_url'] as String?, fid),
      techniqueImageUrl: j['technique_image_url'] as String?,
      exerciseDbId: j['exercise_db_id'] as String?,
      createdAt: _parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'user_id': userId,
        'session_id': sessionId,
        'exercise_name': FieldEncryption.encryptField(exerciseName, familyId) ??
            exerciseName,
        'order': order,
        'rest_seconds': restSeconds,
        'notes': FieldEncryption.encryptField(notes, familyId),
        'technique_notes':
            FieldEncryption.encryptField(techniqueNotes, familyId),
        'reference_url': FieldEncryption.encryptField(referenceUrl, familyId),
        if (techniqueImageUrl != null) 'technique_image_url': techniqueImageUrl,
        if (exerciseDbId != null) 'exercise_db_id': exerciseDbId,
        'created_at': createdAt.toIso8601String(),
      };

  WorkoutExercise copyWith({
    String? id,
    String? familyId,
    String? userId,
    String? sessionId,
    String? exerciseName,
    int? order,
    int? restSeconds,
    String? notes,
    String? techniqueNotes,
    String? referenceUrl,
    String? techniqueImageUrl,
    String? exerciseDbId,
    DateTime? createdAt,
  }) =>
      WorkoutExercise(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        userId: userId ?? this.userId,
        sessionId: sessionId ?? this.sessionId,
        exerciseName: exerciseName ?? this.exerciseName,
        order: order ?? this.order,
        restSeconds: restSeconds ?? this.restSeconds,
        notes: notes ?? this.notes,
        techniqueNotes: techniqueNotes ?? this.techniqueNotes,
        referenceUrl: referenceUrl ?? this.referenceUrl,
        techniqueImageUrl: techniqueImageUrl ?? this.techniqueImageUrl,
        exerciseDbId: exerciseDbId ?? this.exerciseDbId,
        createdAt: createdAt ?? this.createdAt,
      );
}

class WorkoutSet {
  final String id;
  final String familyId;
  final String userId;
  final String exerciseId;
  final int setNumber;
  final String reps; // stored as encrypted text in DB
  final String? weight; // stored as encrypted text in DB
  final bool completed;
  final String? notes;
  final DateTime createdAt;

  const WorkoutSet({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.exerciseId,
    required this.setNumber,
    required this.reps,
    this.weight,
    this.completed = false,
    this.notes,
    required this.createdAt,
  });

  factory WorkoutSet.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return WorkoutSet(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      exerciseId: j['exercise_id'] as String? ?? '',
      setNumber: ((j['set_number'] as num?) ?? 0).toInt(),
      reps: FieldEncryption.decryptField(j['reps'] as String?, fid) ?? '',
      weight: FieldEncryption.decryptField(j['weight'] as String?, fid),
      completed: (j['completed'] as bool?) ?? false,
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      createdAt: _parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'user_id': userId,
        'exercise_id': exerciseId,
        'set_number': setNumber,
        'reps': FieldEncryption.encryptField(reps, familyId) ?? reps,
        'weight': FieldEncryption.encryptField(weight, familyId),
        'completed': completed,
        'notes': FieldEncryption.encryptField(notes, familyId),
        'created_at': createdAt.toIso8601String(),
      };

  WorkoutSet copyWith({
    String? id,
    String? familyId,
    String? userId,
    String? exerciseId,
    int? setNumber,
    String? reps,
    String? weight,
    bool? completed,
    String? notes,
    DateTime? createdAt,
  }) =>
      WorkoutSet(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        userId: userId ?? this.userId,
        exerciseId: exerciseId ?? this.exerciseId,
        setNumber: setNumber ?? this.setNumber,
        reps: reps ?? this.reps,
        weight: weight ?? this.weight,
        completed: completed ?? this.completed,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
      );
}

/// Best-known set stats per user + normalized exercise name (family-scoped for sync).
class ExercisePR {
  final String id;
  final String userId;
  final String familyId;
  final String exerciseKey;
  final double? bestVolume;
  final String? bestWeight;
  final int? bestReps;
  final String? sessionId;
  final String? exerciseId;
  final DateTime achievedAt;
  final DateTime createdAt;

  const ExercisePR({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.exerciseKey,
    this.bestVolume,
    this.bestWeight,
    this.bestReps,
    this.sessionId,
    this.exerciseId,
    required this.achievedAt,
    required this.createdAt,
  });

  String get mergeKey => id;

  factory ExercisePR.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return ExercisePR(
      id: j['id'] as String? ?? '',
      userId: j['user_id'] as String? ?? '',
      familyId: fid,
      exerciseKey: j['exercise_key'] as String? ?? '',
      bestVolume: (j['best_volume'] as num?)?.toDouble(),
      bestWeight: FieldEncryption.decryptField(j['best_weight'] as String?, fid),
      bestReps: (j['best_reps'] as num?)?.toInt(),
      sessionId: j['session_id'] as String?,
      exerciseId: j['exercise_id'] as String?,
      achievedAt: _parseDate(j['achieved_at']),
      createdAt: _parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'family_id': familyId,
        'exercise_key': exerciseKey,
        'best_volume': bestVolume,
        'best_weight': FieldEncryption.encryptField(bestWeight, familyId),
        'best_reps': bestReps,
        'session_id': sessionId,
        'exercise_id': exerciseId,
        'achieved_at': achievedAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  ExercisePR copyWith({
    String? id,
    String? userId,
    String? familyId,
    String? exerciseKey,
    double? bestVolume,
    String? bestWeight,
    int? bestReps,
    String? sessionId,
    String? exerciseId,
    DateTime? achievedAt,
    DateTime? createdAt,
  }) =>
      ExercisePR(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        familyId: familyId ?? this.familyId,
        exerciseKey: exerciseKey ?? this.exerciseKey,
        bestVolume: bestVolume ?? this.bestVolume,
        bestWeight: bestWeight ?? this.bestWeight,
        bestReps: bestReps ?? this.bestReps,
        sessionId: sessionId ?? this.sessionId,
        exerciseId: exerciseId ?? this.exerciseId,
        achievedAt: achievedAt ?? this.achievedAt,
        createdAt: createdAt ?? this.createdAt,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// BudgetCategory
// ─────────────────────────────────────────────────────────────────────────────

class BudgetCategoryRecord {
  final String id;
  final String familyId;
  final String creatorId;
  final String name;
  final double limit;
  final String color;
  final Visibility visibility;

  const BudgetCategoryRecord({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.name,
    this.limit = 0,
    this.color = '#6366f1',
    this.visibility = Visibility.FAMILY,
  });

  factory BudgetCategoryRecord.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return BudgetCategoryRecord(
      id: j['id'] as String? ?? '',
      familyId: fid,
      creatorId: j['creator_id'] as String? ?? '',
      name: FieldEncryption.decryptField(j['name'] as String?, fid) ?? '',
      limit: FieldEncryption.decryptDouble(j['limit'], fid) ?? 0,
      color: j['color'] as String? ?? '#6366f1',
      visibility: visibilityFromString(j['visibility'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'name': FieldEncryption.encryptField(name, familyId),
    'limit': FieldEncryption.encryptNum(limit, familyId),
    'color': color,
    'visibility': visibility.name,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction
// ─────────────────────────────────────────────────────────────────────────────

class Transaction {
  final String id;
  final String familyId;
  final String creatorId;
  final String categoryId;
  final double amount;
  final TransactionType type;
  final DateTime date;
  final String description;
  final Visibility visibility;

  const Transaction({
    required this.id,
    required this.familyId,
    required this.creatorId,
    this.categoryId = '',
    required this.amount,
    this.type = TransactionType.EXPENSE,
    required this.date,
    this.description = '',
    this.visibility = Visibility.FAMILY,
  });

  factory Transaction.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return Transaction(
      id: j['id'] as String? ?? '',
      familyId: fid,
      creatorId: j['creator_id'] as String? ?? '',
      categoryId: j['category_id'] as String? ?? '',
      amount: FieldEncryption.decryptDouble(j['amount'], fid) ?? 0,
      type: transactionTypeFromString(j['type'] as String?),
      date: _parseDate(j['date']),
      description: FieldEncryption.decryptField(j['description'] as String?, fid) ?? '',
      visibility: visibilityFromString(j['visibility'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'category_id': categoryId,
    'amount': FieldEncryption.encryptNum(amount, familyId),
    'type': type.name,
    'date': date.toIso8601String(),
    'description': FieldEncryption.encryptField(description, familyId),
    'visibility': visibility.name,
  };
}

class BudgetEntry {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final double amount;
  final TransactionType type;
  final BudgetCategory category;
  final DateTime date;
  final String? notes;
  final Visibility visibility;

  BudgetEntry({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    required this.title,
    required this.amount,
    TransactionType? type,
    bool? isIncome,
    BudgetCategory? category,
    required this.date,
    this.notes,
    Visibility? visibility,
  }) : creatorId = creatorId ?? createdBy ?? '',
       type = type ?? (isIncome == true ? TransactionType.INCOME : TransactionType.EXPENSE),
       category = category ?? BudgetCategory.other,
       visibility = visibility ?? Visibility.FAMILY;

  bool get isIncome => type == TransactionType.INCOME;

  factory BudgetEntry.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return BudgetEntry(
      id: j['id'] as String? ?? '',
      familyId: fid,
      creatorId: j['creator_id'] as String? ?? '',
      title: FieldEncryption.decryptField(j['title'] as String?, fid) ?? '',
      amount: FieldEncryption.decryptDouble(j['amount'], fid) ?? 0,
      type: transactionTypeFromString(FieldEncryption.decryptField(j['type'] as String?, fid)),
      category: BudgetCategory.values.firstWhere(
        (e) => e.name == (FieldEncryption.decryptField(j['category'] as String?, fid) ?? 'other'),
        orElse: () => BudgetCategory.other,
      ),
      date: _parseDate(FieldEncryption.decryptField(j['date'] as String?, fid)),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      visibility: visibilityFromString(j['visibility'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': FieldEncryption.encryptField(title, familyId),
    'amount': FieldEncryption.encryptNum(amount, familyId),
    'type': FieldEncryption.encryptField(type.name, familyId),
    'category': FieldEncryption.encryptField(category.name, familyId),
    'date': FieldEncryption.encryptField(date.toIso8601String(), familyId),
    'notes': FieldEncryption.encryptField(notes, familyId),
    'visibility': visibility.name,
  };

  BudgetEntry copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    double? amount, TransactionType? type, BudgetCategory? category,
    DateTime? date, String? notes, Visibility? visibility,
  }) => BudgetEntry(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, title: title ?? this.title,
    amount: amount ?? this.amount, type: type ?? this.type,
    category: category ?? this.category, date: date ?? this.date,
    notes: notes ?? this.notes, visibility: visibility ?? this.visibility,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// AIHistory
// ─────────────────────────────────────────────────────────────────────────────

class AIHistory {
  final String id;
  final String userId;
  final String familyId;
  final String module;
  final String prompt;
  final String response;
  final DateTime createdAt;

  const AIHistory({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.module,
    required this.prompt,
    required this.response,
    required this.createdAt,
  });

  factory AIHistory.fromJson(Map<String, dynamic> j) => AIHistory(
    id: j['id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    module: j['module'] as String? ?? '',
    prompt: j['prompt'] as String? ?? '',
    response: j['response'] as String? ?? '',
    createdAt: _parseDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'family_id': familyId,
    'module': module,
    'prompt': prompt,
    'response': response,
    'created_at': createdAt.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// DailyHabit & DailyHabitCompletion
// ─────────────────────────────────────────────────────────────────────────────

class DailyHabit {
  final String id;
  final String userId;
  final String? familyId;
  final String label;
  final String? icon;
  final String? color;
  final String? description;
  final bool isShared;
  final String? frequency;
  final num? targetValue;
  final String? targetUnit;
  final DateTime createdAt;
  final int order;

  DailyHabit({
    required this.id,
    required this.userId,
    this.familyId,
    String? label,
    String? title,
    String? icon,
    String? emoji,
    this.color,
    this.description,
    this.isShared = false,
    this.frequency,
    this.targetValue,
    this.targetUnit,
    DateTime? createdAt,
    this.order = 0,
  }) : label = label ?? title ?? '',
       icon = icon ?? emoji,
       createdAt = createdAt ?? DateTime.now();

  // Convenience aliases
  String get title => label;
  String get emoji => icon ?? '';

  DailyHabit copyWith({
    String? id, String? userId, String? familyId, String? label, String? icon,
    String? color, String? description, bool? isShared, String? frequency,
    num? targetValue, String? targetUnit, DateTime? createdAt, int? order,
  }) => DailyHabit(
    id: id ?? this.id, userId: userId ?? this.userId, familyId: familyId ?? this.familyId,
    label: label ?? this.label, icon: icon ?? this.icon, color: color ?? this.color,
    description: description ?? this.description, isShared: isShared ?? this.isShared,
    frequency: frequency ?? this.frequency, targetValue: targetValue ?? this.targetValue,
    targetUnit: targetUnit ?? this.targetUnit, createdAt: createdAt ?? this.createdAt,
    order: order ?? this.order,
  );

  factory DailyHabit.fromJson(Map<String, dynamic> j) => DailyHabit(
    id: j['id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    familyId: j['family_id'] as String?,
    label: j['label'] as String? ?? '',
    icon: j['icon'] as String?,
    color: j['color'] as String?,
    description: j['description'] as String?,
    isShared: (j['is_shared'] ?? false) as bool,
    frequency: j['frequency'] as String?,
    targetValue: j['target_value'] as num?,
    targetUnit: j['target_unit'] as String?,
    createdAt: _parseDate(j['created_at']),
    order: (j['order'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'user_id': userId, 'family_id': familyId,
    'label': label, 'icon': icon ?? '', 'color': color ?? '#6366f1',
    'description': description, 'is_shared': isShared,
    'frequency': frequency, 'target_value': targetValue, 'target_unit': targetUnit,
    'created_at': createdAt.toIso8601String(), 'order': order,
  };
}

class DailyHabitCompletion {
  final String id;
  final String habitId;
  final String userId;
  final DateTime date;
  final DateTime completedAt;

  DailyHabitCompletion({
    required this.id,
    required this.habitId,
    required this.userId,
    required this.date,
    DateTime? completedAt,
    DateTime? createdAt,
  }) : completedAt = completedAt ?? createdAt ?? DateTime.now();

  factory DailyHabitCompletion.fromJson(Map<String, dynamic> j) =>
      DailyHabitCompletion(
    id: j['id'] as String? ?? '',
    habitId: j['habit_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    date: _parseDate(j['date']),
    completedAt: _parseDate(j['completed_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'habit_id': habitId,
    'user_id': userId,
    'date': date.toIso8601String(),
    'completed_at': completedAt.toIso8601String(),
  };

  // Convenience alias - screens use createdAt
  DateTime get createdAt => completedAt;
}

// ─────────────────────────────────────────────────────────────────────────────
// Chore & ChoreCompletion
// ─────────────────────────────────────────────────────────────────────────────

class Chore {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String? description;
  final String? icon;
  final int points;
  final double? reward;
  final ChoreFrequency frequency;
  final List<int> daysOfWeek;
  final List<String> assignees;
  final String? color;
  final Visibility visibility;
  final DateTime createdAt;
  final bool requiresApproval;
  /// When true and multiple assignees exist, the next completion advances who is "up next".
  final bool rotationEnabled;
  /// Index into [assignees] for round-robin (persisted per chore).
  final int rotationCursor;
  final DateTime updatedAt;

  Chore({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    required this.title,
    this.description,
    this.icon,
    this.points = 0,
    this.reward,
    this.frequency = ChoreFrequency.DAILY,
    this.daysOfWeek = const [],
    List<String>? assignees,
    List<String>? assigneeIds,
    this.color,
    this.visibility = Visibility.FAMILY,
    DateTime? createdAt,
    this.requiresApproval = false,
    this.rotationEnabled = false,
    this.rotationCursor = 0,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? createdBy ?? '',
       assignees = assignees ?? assigneeIds ?? const [],
       createdAt = createdAt ?? DateTime.now();

  factory Chore.fromJson(Map<String, dynamic> j) => Chore(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    icon: j['icon'] as String?,
    points: (j['points'] as num?)?.toInt() ?? 0,
    reward: (j['reward'] as num?)?.toDouble(),
    frequency: choreFrequencyFromString(j['frequency'] as String?),
    daysOfWeek: _intList(j['days_of_week']),
    assignees: _strList(j['assignees']),
    color: j['color'] as String?,
    visibility: visibilityFromString(j['visibility'] as String?),
    createdAt: _parseDate(j['created_at']),
    requiresApproval: (j['requires_approval'] ?? false) as bool,
    rotationEnabled: (j['rotation_enabled'] ?? false) as bool,
    rotationCursor: (j['rotation_cursor'] as num?)?.toInt() ?? 0,
    updatedAt: _parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'description': description,
    'icon': icon,
    'points': points,
    'reward': reward,
    'frequency': frequency.name,
    'days_of_week': daysOfWeek,
    'assignees': assignees,
    'color': color,
    'visibility': visibility.name,
    'created_at': createdAt.toIso8601String(),
    'requires_approval': requiresApproval,
    'rotation_enabled': rotationEnabled,
    'rotation_cursor': rotationCursor,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getters
  List<String> get assigneeIds => assignees;
  DateTime? get lastCompletedAt => null; // populated from ChoreCompletion records

  Chore copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    String? description, String? icon, int? points, double? reward,
    ChoreFrequency? frequency, List<int>? daysOfWeek, List<String>? assignees,
    String? color, Visibility? visibility, DateTime? createdAt, bool? requiresApproval,
    bool? rotationEnabled, int? rotationCursor,
    DateTime? updatedAt,
  }) => Chore(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, title: title ?? this.title,
    description: description ?? this.description, icon: icon ?? this.icon,
    points: points ?? this.points, reward: reward ?? this.reward,
    frequency: frequency ?? this.frequency, daysOfWeek: daysOfWeek ?? this.daysOfWeek,
    assignees: assignees ?? this.assignees, color: color ?? this.color,
    visibility: visibility ?? this.visibility, createdAt: createdAt ?? this.createdAt,
    requiresApproval: requiresApproval ?? this.requiresApproval,
    rotationEnabled: rotationEnabled ?? this.rotationEnabled,
    rotationCursor: rotationCursor ?? this.rotationCursor,
    updatedAt: updatedAt ??
        ((title != null || description != null || points != null || frequency != null ||
                daysOfWeek != null || assignees != null || requiresApproval != null ||
                rotationEnabled != null || rotationCursor != null)
            ? DateTime.now()
            : this.updatedAt),
  );
}

class ChoreCompletion {
  final String id;
  final String choreId;
  final String userId;
  final String familyId;
  final DateTime date;
  final DateTime completedAt;
  final ApprovalStatus approvalStatus;
  final String? approvedBy;
  final DateTime? approvedAt;

  const ChoreCompletion({
    required this.id,
    required this.choreId,
    required this.userId,
    required this.familyId,
    required this.date,
    required this.completedAt,
    this.approvalStatus = ApprovalStatus.PENDING,
    this.approvedBy,
    this.approvedAt,
  });

  factory ChoreCompletion.fromJson(Map<String, dynamic> j) => ChoreCompletion(
    id: j['id'] as String? ?? '',
    choreId: j['chore_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    date: _parseDate(j['date']),
    completedAt: _parseDate(j['completed_at']),
    approvalStatus: approvalStatusFromString(j['approval_status'] as String?),
    approvedBy: j['approved_by'] as String?,
    approvedAt: _parseDateOpt(j['approved_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'chore_id': choreId,
    'user_id': userId,
    'family_id': familyId,
    'date': date.toIso8601String(),
    'completed_at': completedAt.toIso8601String(),
    'approval_status': approvalStatus.name,
    'approved_by': approvedBy,
    'approved_at': approvedAt?.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// RewardItem & RewardRedemption
// ─────────────────────────────────────────────────────────────────────────────

class RewardItem {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String? description;
  final int cost;
  final String? icon;
  final bool active;
  final DateTime createdAt;

  const RewardItem({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.title,
    this.description,
    this.cost = 0,
    this.icon,
    this.active = true,
    required this.createdAt,
  });

  factory RewardItem.fromJson(Map<String, dynamic> j) => RewardItem(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    cost: ((j['cost'] as num?) ?? 0).toInt(),
    icon: j['icon'] as String?,
    active: (j['active'] ?? true) as bool,
    createdAt: _parseDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'description': description,
    'cost': cost,
    'icon': icon,
    'active': active,
    'created_at': createdAt.toIso8601String(),
  };
}

class RewardRedemption {
  final String id;
  final String familyId;
  final String userId;
  final String rewardId;
  final String rewardTitle;
  final int amount;
  final RedemptionStatus status;
  final DateTime requestedAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolvedNote;

  const RewardRedemption({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.rewardId,
    required this.rewardTitle,
    this.amount = 0,
    this.status = RedemptionStatus.PENDING,
    required this.requestedAt,
    this.resolvedAt,
    this.resolvedBy,
    this.resolvedNote,
  });

  factory RewardRedemption.fromJson(Map<String, dynamic> j) => RewardRedemption(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    rewardId: j['reward_id'] as String? ?? '',
    rewardTitle: j['reward_title'] as String? ?? '',
    amount: ((j['amount'] as num?) ?? 0).toInt(),
    status: redemptionStatusFromString(j['status'] as String?),
    requestedAt: _parseDate(j['requested_at']),
    resolvedAt: _parseDateOpt(j['resolved_at']),
    resolvedBy: j['resolved_by'] as String?,
    resolvedNote: j['resolved_note'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'reward_id': rewardId,
    'reward_title': rewardTitle,
    'amount': amount,
    'status': status.name,
    'requested_at': requestedAt.toIso8601String(),
    'resolved_at': resolvedAt?.toIso8601String(),
    'resolved_by': resolvedBy,
    'resolved_note': resolvedNote,
  };

  RewardRedemption copyWith({
    String? id,
    String? familyId,
    String? userId,
    String? rewardId,
    String? rewardTitle,
    int? amount,
    RedemptionStatus? status,
    DateTime? requestedAt,
    DateTime? resolvedAt,
    String? resolvedBy,
    String? resolvedNote,
  }) => RewardRedemption(
    id: id ?? this.id,
    familyId: familyId ?? this.familyId,
    userId: userId ?? this.userId,
    rewardId: rewardId ?? this.rewardId,
    rewardTitle: rewardTitle ?? this.rewardTitle,
    amount: amount ?? this.amount,
    status: status ?? this.status,
    requestedAt: requestedAt ?? this.requestedAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    resolvedBy: resolvedBy ?? this.resolvedBy,
    resolvedNote: resolvedNote ?? this.resolvedNote,
  );
}

class Reward {
  final String id;
  final String familyId;
  final String title;
  final int pointCost;
  final String? description;
  final List<String> redeemedBy;

  const Reward({
    required this.id,
    required this.familyId,
    required this.title,
    this.pointCost = 0,
    this.description,
    this.redeemedBy = const [],
  });

  factory Reward.fromJson(Map<String, dynamic> j) => Reward(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    pointCost: ((j['point_cost'] ?? j['cost']) as int?) ?? 0,
    description: j['description'] as String?,
    redeemedBy: _strList(j['redeemed_by']),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'family_id': familyId, 'title': title,
    'point_cost': pointCost, 'description': description, 'redeemed_by': redeemedBy,
  };

  Reward copyWith({
    String? id, String? familyId, String? title, int? pointCost,
    String? description, List<String>? redeemedBy,
  }) => Reward(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    title: title ?? this.title, pointCost: pointCost ?? this.pointCost,
    description: description ?? this.description, redeemedBy: redeemedBy ?? this.redeemedBy,
  );
}

class ReadingPlan {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String description;
  final int totalDays;
  final List<dynamic> days;
  final List<String> entryIds;
  final DateTime createdAt;

  const ReadingPlan({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.title,
    this.description = '',
    this.totalDays = 0,
    this.days = const [],
    this.entryIds = const [],
    required this.createdAt,
  });

  factory ReadingPlan.fromJson(Map<String, dynamic> j) {
    final daysList = (j['days'] is List) ? (j['days'] as List) : <dynamic>[];
    final fromExplicit = _strList(j['entry_ids']);
    final fromDays = <String>[];
    for (final x in daysList) {
      if (x is Map) {
        final id = x['devotional_id']?.toString();
        if (id != null && id.isNotEmpty) fromDays.add(id);
      }
    }
    final ids = fromExplicit.isNotEmpty ? fromExplicit : fromDays;
    final td = (j['total_days'] as num?)?.toInt() ?? 0;
    final total = td > 0 ? td : (ids.isNotEmpty ? ids.length : daysList.length);
    return ReadingPlan(
      id: j['id'] as String? ?? '',
      familyId: j['family_id'] as String? ?? '',
      creatorId: j['creator_id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      description: j['description'] as String? ?? '',
      totalDays: total,
      days: daysList,
      entryIds: ids,
      createdAt: _parseDate(j['created_at']),
    );
  }

  /// Persist day→devotional links for local disk + Supabase (jsonb `days`).
  List<dynamic> _daysPayload() {
    if (days.isNotEmpty) return List<dynamic>.from(days);
    return [
      for (var i = 0; i < entryIds.length; i++)
        <String, dynamic>{'devotional_id': entryIds[i], 'day': i + 1},
    ];
  }

  int _totalDaysPayload() {
    if (totalDays > 0) return totalDays;
    if (entryIds.isNotEmpty) return entryIds.length;
    if (days.isNotEmpty) return days.length;
    return 0;
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'family_id': familyId, 'creator_id': creatorId,
    'title': title, 'description': description,
    'total_days': _totalDaysPayload(),
    'days': _daysPayload(),
    // entryIds are encoded inside [days][].devotional_id (no entry_ids DB column)
    'created_at': createdAt.toIso8601String(),
  };

  // Convenience getter - entries are stored in entryIds; screens may hold them in-memory
  List<ReadingPlanEntry> get entries => const [];
  int get completedCount => 0;
  double get progress => 0.0;

  ReadingPlan copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    String? description, int? totalDays, List<dynamic>? days,
    List<String>? entryIds, DateTime? createdAt,
    List<ReadingPlanEntry>? entries,
  }) => ReadingPlan(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, title: title ?? this.title,
    description: description ?? this.description,
    totalDays: totalDays ?? this.totalDays,
    days: days ?? this.days,
    entryIds: entries?.map((e) => e.id).toList() ?? entryIds ?? this.entryIds,
    createdAt: createdAt ?? this.createdAt,
  );
}

class ReadingPlanEntry {
  final String id;
  final String planId;
  final String devotionalId;
  final int dayNumber;
  final bool completed;

  ReadingPlanEntry({
    String? id,
    String? planId,
    String? devotionalId,
    int? dayNumber,
    int? day,
    String? title,
    String? scripture,
    String? content,
    this.completed = false,
  }) : id = id ?? '',
       planId = planId ?? '',
       devotionalId = devotionalId ?? title ?? '',
       dayNumber = day ?? dayNumber ?? 0;

  factory ReadingPlanEntry.fromJson(Map<String, dynamic> j) => ReadingPlanEntry(
    id: j['id'] as String? ?? '',
    planId: j['plan_id'] as String? ?? '',
    devotionalId: j['devotional_id'] as String? ?? '',
    dayNumber: (j['day_number'] as int?) ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'plan_id': planId, 'devotional_id': devotionalId, 'day_number': dayNumber,
  };

  // Convenience getters
  int get day => dayNumber;
  String get title => devotionalId;
  String? get scripture => null;

  ReadingPlanEntry copyWith({
    String? id, String? planId, String? devotionalId, int? dayNumber,
    bool? completed, int? day, String? title, String? scripture,
  }) => ReadingPlanEntry(
    id: id ?? this.id, planId: planId ?? this.planId,
    devotionalId: title ?? devotionalId ?? this.devotionalId,
    dayNumber: day ?? dayNumber ?? this.dayNumber,
    completed: completed ?? this.completed,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SavingsGoal
// ─────────────────────────────────────────────────────────────────────────────

class SavingsGoal {
  final String id;
  final String familyId;
  final String userId;
  final String title;
  final String? icon;
  final String? imageUrl;
  final double targetAmount;
  final double savedAmount;
  final DateTime createdAt;
  final DateTime? completedAt;

  SavingsGoal({
    required this.id,
    required this.familyId,
    String? userId,
    String? createdBy,
    required this.title,
    this.icon,
    String? emoji,
    this.imageUrl,
    this.targetAmount = 0,
    double? savedAmount,
    double? currentAmount,
    required this.createdAt,
    DateTime? completedAt,
    DateTime? deadline,
  }) : userId = userId ?? createdBy ?? '',
       savedAmount = savedAmount ?? currentAmount ?? 0,
       completedAt = completedAt ?? deadline;

  factory SavingsGoal.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return SavingsGoal(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      title: FieldEncryption.decryptField(j['title'] as String?, fid) ?? '',
      icon: j['icon'] as String?,
      imageUrl: j['image_url'] as String?,
      targetAmount: FieldEncryption.decryptDouble(j['target_amount'], fid) ?? 0,
      savedAmount: FieldEncryption.decryptDouble(j['saved_amount'], fid) ?? 0,
      createdAt: _parseDate(j['created_at']),
      completedAt: _parseDateOpt(j['completed_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'title': FieldEncryption.encryptField(title, familyId),
    'icon': icon,
    'image_url': imageUrl,
    'target_amount': FieldEncryption.encryptNum(targetAmount, familyId),
    'saved_amount': FieldEncryption.encryptNum(savedAmount, familyId),
    'created_at': createdAt.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
  };

  // Convenience getters
  double get currentAmount => savedAmount;
  DateTime? get deadline => completedAt;
  bool get isComplete => completedAt != null;
  String? get emoji => icon;
  double get progress => targetAmount > 0 ? (savedAmount / targetAmount).clamp(0.0, 1.0) : 0.0;

  SavingsGoal copyWith({
    String? id, String? familyId, String? userId, String? title,
    String? icon, String? imageUrl, double? targetAmount, double? savedAmount,
    DateTime? createdAt, DateTime? completedAt,
  }) => SavingsGoal(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    userId: userId ?? this.userId, title: title ?? this.title,
    icon: icon ?? this.icon, imageUrl: imageUrl ?? this.imageUrl,
    targetAmount: targetAmount ?? this.targetAmount,
    savedAmount: savedAmount ?? this.savedAmount,
    createdAt: createdAt ?? this.createdAt,
    completedAt: completedAt ?? this.completedAt,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Poll, PollOption, PollVote
// ─────────────────────────────────────────────────────────────────────────────

class PollOption {
  final String id;
  final String text;
  final List<String> voterIds;

  const PollOption({required this.id, required this.text, this.voterIds = const []});

  PollOption copyWith({String? id, String? text, List<String>? voterIds}) =>
      PollOption(id: id ?? this.id, text: text ?? this.text, voterIds: voterIds ?? this.voterIds);

  factory PollOption.fromJson(Map<String, dynamic> j) => PollOption(
    id: j['id'] as String? ?? '',
    text: j['text'] as String? ?? '',
    voterIds: _strList(j['voter_ids']),
  );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'voter_ids': voterIds};
}

class Poll {
  final String id;
  final String familyId;
  final String creatorId;
  final String question;
  final List<PollOption> options;
  final bool allowMultiple;
  final bool anonymous;
  final PollStatus status;
  final DateTime? deadline;
  final Visibility visibility;
  final DateTime createdAt;
  final DateTime updatedAt;

  Poll({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    required this.question,
    this.options = const [],
    this.allowMultiple = false,
    this.anonymous = false,
    this.status = PollStatus.open,
    DateTime? deadline,
    DateTime? expiresAt,
    this.visibility = Visibility.FAMILY,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? createdBy ?? '',
       deadline = deadline ?? expiresAt,
       createdAt = createdAt ?? DateTime.now();

  factory Poll.fromJson(Map<String, dynamic> j) => Poll(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    question: j['question'] as String? ?? '',
    options: _parseList(j['options'], PollOption.fromJson),
    allowMultiple: (j['allow_multiple'] ?? false) as bool,
    anonymous: (j['anonymous'] ?? false) as bool,
    status: pollStatusFromString(j['status'] as String?),
    deadline: _parseDateOpt(j['deadline']),
    visibility: visibilityFromString(j['visibility'] as String?),
    createdAt: _parseDate(j['created_at']),
    updatedAt: _parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'question': question,
    'options': options.map((o) => o.toJson()).toList(),
    'allow_multiple': allowMultiple,
    'anonymous': anonymous,
    'status': status.name,
    'deadline': deadline?.toIso8601String(),
    'visibility': visibility.name,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience aliases
  String get createdBy => creatorId;
  DateTime? get expiresAt => deadline;
  int get totalVotes => options.fold(0, (sum, o) => sum + o.voterIds.length);

  Poll copyWith({
    String? id, String? familyId, String? creatorId, String? question,
    List<PollOption>? options, bool? allowMultiple, bool? anonymous,
    PollStatus? status, DateTime? deadline, Visibility? visibility, DateTime? createdAt,
    DateTime? updatedAt,
  }) => Poll(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, question: question ?? this.question,
    options: options ?? this.options, allowMultiple: allowMultiple ?? this.allowMultiple,
    anonymous: anonymous ?? this.anonymous, status: status ?? this.status,
    deadline: deadline ?? this.deadline, visibility: visibility ?? this.visibility,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ??
        ((question != null || options != null || status != null || deadline != null)
            ? DateTime.now()
            : this.updatedAt),
  );
}

class PollVote {
  final String id;
  final String pollId;
  final String optionId;
  final String userId;
  final String familyId;
  final DateTime votedAt;

  const PollVote({
    required this.id,
    required this.pollId,
    required this.optionId,
    required this.userId,
    required this.familyId,
    required this.votedAt,
  });

  factory PollVote.fromJson(Map<String, dynamic> j) => PollVote(
    id: j['id'] as String? ?? '',
    pollId: j['poll_id'] as String? ?? '',
    optionId: j['option_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    votedAt: _parseDate(j['voted_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'poll_id': pollId,
    'option_id': optionId,
    'user_id': userId,
    'family_id': familyId,
    'voted_at': votedAt.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Reaction & PrayerWallEntry
// ─────────────────────────────────────────────────────────────────────────────

class Reaction {
  final String userId;
  final String emoji;

  const Reaction({required this.userId, required this.emoji});

  factory Reaction.fromJson(Map<String, dynamic> j) => Reaction(
    userId: j['user_id'] as String? ?? '',
    emoji: j['emoji'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'user_id': userId, 'emoji': emoji};
}

class PrayerWallEntry {
  final String id;
  final String familyId;
  final String creatorId;
  final PrayerWallType type;
  final String text;
  final String? originalRequestId;
  final List<Reaction> reactions;
  final List<String> prayedByIds;
  final DateTime date;
  final DateTime? answeredAt;
  final Visibility visibility;

  PrayerWallEntry({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? userId,
    this.type = PrayerWallType.REQUEST,
    String? text,
    String? title,
    String? body,
    this.originalRequestId,
    this.reactions = const [],
    this.prayedByIds = const [],
    DateTime? date,
    DateTime? createdAt,
    this.answeredAt,
    bool? answered,
    this.visibility = Visibility.FAMILY,
  }) : creatorId = creatorId ?? userId ?? '',
       text = text ?? (title != null ? (body != null ? '$title\n$body' : title) : body ?? ''),
       date = date ?? createdAt ?? DateTime.now();

  PrayerWallEntry copyWith({
    String? id, String? familyId, String? creatorId, PrayerWallType? type,
    String? text, String? originalRequestId, List<Reaction>? reactions,
    List<String>? prayedByIds, DateTime? date, DateTime? answeredAt, Visibility? visibility,
  }) => PrayerWallEntry(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, type: type ?? this.type,
    text: text ?? this.text, originalRequestId: originalRequestId ?? this.originalRequestId,
    reactions: reactions ?? this.reactions, prayedByIds: prayedByIds ?? this.prayedByIds,
    date: date ?? this.date, answeredAt: answeredAt ?? this.answeredAt,
    visibility: visibility ?? this.visibility,
  );

  factory PrayerWallEntry.fromJson(Map<String, dynamic> j) => PrayerWallEntry(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    type: prayerWallTypeFromString(j['type'] as String?),
    text: j['text'] as String? ?? '',
    originalRequestId: j['original_request_id'] as String?,
    reactions: _parseList(j['reactions'], Reaction.fromJson),
    prayedByIds: _strList(j['prayed_by_ids']),
    date: _parseDate(j['date']),
    answeredAt: _parseDateOpt(j['answered_at']),
    visibility: visibilityFromString(j['visibility'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'family_id': familyId, 'creator_id': creatorId,
    'type': type.name, 'text': text,
    'original_request_id': originalRequestId,
    'reactions': reactions.map((r) => r.toJson()).toList(),
    'prayed_by_ids': prayedByIds,
    'date': date.toIso8601String(),
    'answered_at': answeredAt?.toIso8601String(),
    'visibility': visibility.name,
  };

  // Convenience getters
  bool get answered => answeredAt != null || type == PrayerWallType.ANSWERED;
  DateTime get createdAt => date;
  String get userId => creatorId;
  String get title => text.contains('\n') ? text.split('\n').first : text;
  String? get body => text.contains('\n') ? text.substring(text.indexOf('\n') + 1) : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatMessage
// ─────────────────────────────────────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String familyId;
  final String userId;
  final String text;
  final String? replyToId;
  final Map<String, List<String>> reactions;
  final DateTime? editedAt;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.text,
    this.replyToId,
    this.reactions = const {},
    this.editedAt,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    // Reactions may be encrypted as a JSON string or legacy plain map
    final rawReactions = FieldEncryption.decryptJson(j['reactions'], fid);
    Map<String, List<String>> parsedReactions = {};
    if (rawReactions is Map) {
      rawReactions.forEach((k, v) {
        parsedReactions[k.toString()] = (v is List) ? v.map((e) => e.toString()).toList() : <String>[];
      });
    }
    return ChatMessage(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      text: FieldEncryption.decryptField(j['text'] as String?, fid) ?? '',
      replyToId: j['reply_to_id'] as String?,
      reactions: parsedReactions,
      editedAt: _parseDateOpt(j['edited_at']),
      createdAt: _parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'text': FieldEncryption.encryptField(text, familyId),
    'reply_to_id': replyToId,
    'reactions': FieldEncryption.encryptJson(reactions, familyId),
    'edited_at': editedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  // Convenience getters
  String get senderId => userId;
  String get content => text;
  MessageType get type => MessageType.text;

  ChatMessage copyWith({
    String? id, String? familyId, String? userId, String? text,
    String? replyToId, Map<String, List<String>>? reactions,
    DateTime? editedAt, DateTime? createdAt,
  }) => ChatMessage(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    userId: userId ?? this.userId, text: text ?? this.text,
    replyToId: replyToId ?? this.replyToId,
    reactions: reactions ?? this.reactions,
    editedAt: editedAt ?? this.editedAt,
    createdAt: createdAt ?? this.createdAt,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SpecialDate
// ─────────────────────────────────────────────────────────────────────────────

class SpecialDate {
  final String id;
  final String familyId;
  final String creatorId;
  final String name;
  final SpecialDateType type;
  final int month;
  final int day;
  final int? year;
  final String? emoji;
  final String? notes;
  final List<int> reminderDays;
  final Visibility visibility;
  final DateTime createdAt;

  SpecialDate({
    required this.id,
    required this.familyId,
    required this.creatorId,
    String? name,
    String? title,
    SpecialDateType? type,
    String? typeStr,
    int? month,
    int? day,
    int? year,
    DateTime? date,
    bool? recurring,
    this.emoji,
    this.notes,
    this.reminderDays = const [7],
    this.visibility = Visibility.FAMILY,
    DateTime? createdAt,
  }) : name = name ?? title ?? '',
       type = type ?? (typeStr != null ? specialDateTypeFromString(typeStr) : SpecialDateType.BIRTHDAY),
       month = month ?? date?.month ?? 1,
       day = day ?? date?.day ?? 1,
       year = (recurring == true) ? null : (year ?? date?.year),
       createdAt = createdAt ?? DateTime.now();

  factory SpecialDate.fromJson(Map<String, dynamic> j) => SpecialDate(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    type: specialDateTypeFromString(j['type'] as String?),
    month: (j['month'] as num?)?.toInt() ?? 1,
    day: (j['day'] as num?)?.toInt() ?? 1,
    year: (j['year'] as num?)?.toInt(),
    emoji: j['emoji'] as String?,
    notes: j['notes'] as String?,
    reminderDays: _intList(j['reminder_days']),
    visibility: visibilityFromString(j['visibility'] as String?),
    createdAt: _parseDate(j['created_at']),
  );

  /// DB column `emoji` is NOT NULL — use when local/cloud row has no emoji.
  static String defaultEmojiForType(SpecialDateType t) {
    switch (t) {
      case SpecialDateType.BIRTHDAY:
        return '🎂';
      case SpecialDateType.ANNIVERSARY:
        return '💝';
      case SpecialDateType.MEMORIAL:
        return '🕯️';
      case SpecialDateType.OTHER:
        return '📅';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'name': name,
    'type': type.name,
    'month': month,
    'day': day,
    'year': year,
    'emoji': emoji ?? defaultEmojiForType(type),
    'notes': notes,
    'reminder_days': reminderDays,
    'visibility': visibility.name,
    'created_at': createdAt.toIso8601String(),
  };

  // Convenience getters
  DateTime get date => DateTime(year ?? DateTime.now().year, month, day);
  bool get recurring => year == null;
  String get title => name;

  SpecialDate copyWith({
    String? id, String? familyId, String? creatorId, String? name,
    SpecialDateType? type, int? month, int? day, int? year,
    String? emoji, String? notes, List<int>? reminderDays,
    Visibility? visibility, DateTime? createdAt,
  }) => SpecialDate(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    creatorId: creatorId ?? this.creatorId, name: name ?? this.name,
    type: type ?? this.type, month: month ?? this.month, day: day ?? this.day,
    year: year ?? this.year, emoji: emoji ?? this.emoji, notes: notes ?? this.notes,
    reminderDays: reminderDays ?? this.reminderDays, visibility: visibility ?? this.visibility,
    createdAt: createdAt ?? this.createdAt,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FamilyPhoto & Milestone
// ─────────────────────────────────────────────────────────────────────────────

class FamilyPhoto {
  final String id;
  final String familyId;
  final String uploaderId;
  final String url;
  final String? caption;
  final DateTime? takenAt;
  final DateTime createdAt;
  final List<Reaction> reactions;
  final String? milestoneId;
  final List<String> tags;
  final Visibility visibility;

  FamilyPhoto({
    required this.id,
    required this.familyId,
    String? uploaderId,
    String? uploadedBy,
    required this.url,
    this.caption,
    this.takenAt,
    DateTime? createdAt,
    this.reactions = const [],
    this.milestoneId,
    this.tags = const [],
    this.visibility = Visibility.FAMILY,
  }) : uploaderId = uploaderId ?? uploadedBy ?? '',
       createdAt = createdAt ?? DateTime.now();

  factory FamilyPhoto.fromJson(Map<String, dynamic> j) => FamilyPhoto(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    uploaderId: j['uploader_id'] as String? ?? '',
    url: j['url'] as String? ?? '',
    caption: j['caption'] as String?,
    takenAt: _parseDateOpt(j['taken_at']),
    createdAt: _parseDate(j['created_at']),
    reactions: _parseList(j['reactions'], Reaction.fromJson),
    milestoneId: j['milestone_id'] as String?,
    tags: _strList(j['tags']),
    visibility: visibilityFromString(j['visibility'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'uploader_id': uploaderId,
    'url': url,
    'caption': caption,
    'taken_at': (takenAt ?? createdAt).toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'reactions': reactions.map((r) => r.toJson()).toList(),
    'milestone_id': milestoneId,
    'tags': tags,
    'visibility': visibility.name,
  };

  // Convenience alias
  String get uploadedBy => uploaderId;
}

class Milestone {
  final String id;
  final String familyId;
  final String childId;
  final String title;
  final String? emoji;
  final String? category;
  final DateTime date;
  final String? notes;
  final List<String> photoIds;
  final String? ageLabel;
  final DateTime createdAt;

  const Milestone({
    required this.id,
    required this.familyId,
    this.childId = '',
    required this.title,
    this.emoji,
    this.category,
    required this.date,
    this.notes,
    this.photoIds = const [],
    this.ageLabel,
    required this.createdAt,
  });

  factory Milestone.fromJson(Map<String, dynamic> j) => Milestone(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    childId: j['child_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    emoji: j['emoji'] as String?,
    category: j['category'] as String?,
    date: _parseDate(j['date']),
    notes: j['notes'] as String?,
    photoIds: _strList(j['photo_ids']),
    ageLabel: j['age_label'] as String?,
    createdAt: _parseDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'child_id': childId,
    'title': title,
    'emoji': emoji,
    'category': category,
    'date': date.toIso8601String(),
    'notes': notes,
    'photo_ids': photoIds,
    'age_label': ageLabel,
    'created_at': createdAt.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// UserLocation & SavedPlace
// ─────────────────────────────────────────────────────────────────────────────

class UserLocation {
  final String id;
  final String familyId;
  final String userId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final String? placeName;
  final String? nearPlace;
  final bool isSharing;
  final DateTime updatedAt;

  const UserLocation({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.placeName,
    this.nearPlace,
    this.isSharing = false,
    required this.updatedAt,
  });

  factory UserLocation.fromJson(Map<String, dynamic> j) => UserLocation(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    latitude: ((j['latitude'] as num?) ?? 0).toDouble(),
    longitude: ((j['longitude'] as num?) ?? 0).toDouble(),
    accuracy: (j['accuracy'] as num?)?.toDouble(),
    placeName: j['place_name'] as String?,
    nearPlace: j['near_place'] as String?,
    isSharing: (j['is_sharing'] ?? false) as bool,
    updatedAt: _parseDate(j['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'place_name': placeName,
    'near_place': nearPlace,
    'is_sharing': isSharing,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getter
  String? get address => placeName ?? nearPlace;
}

class SavedPlace {
  final String id;
  final String familyId;
  final String creatorId;
  final String name;
  final String? emoji;
  final double latitude;
  final double longitude;
  final double radiusMetres;
  final DateTime createdAt;

  const SavedPlace({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.name,
    this.emoji,
    required this.latitude,
    required this.longitude,
    this.radiusMetres = 100,
    required this.createdAt,
  });

  factory SavedPlace.fromJson(Map<String, dynamic> j) => SavedPlace(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    emoji: j['emoji'] as String?,
    latitude: ((j['latitude'] as num?) ?? 0).toDouble(),
    longitude: ((j['longitude'] as num?) ?? 0).toDouble(),
    radiusMetres: (j['radius_metres'] as num? ?? 100).toDouble(),
    createdAt: _parseDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'name': name,
    'emoji': emoji,
    'latitude': latitude,
    'longitude': longitude,
    'radius_metres': radiusMetres,
    'created_at': createdAt.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Health sub-models
// ─────────────────────────────────────────────────────────────────────────────

class HealthAllergy {
  final String id;
  final String name;
  final AllergySeverity severity;
  final String? reaction;

  const HealthAllergy({
    required this.id,
    required this.name,
    this.severity = AllergySeverity.MILD,
    this.reaction,
  });

  factory HealthAllergy.fromJson(Map<String, dynamic> j) => HealthAllergy(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    severity: allergySeverityFromString(j['severity'] as String?),
    reaction: j['reaction'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'severity': severity.name,
    'reaction': reaction,
  };
}

class HealthMedication {
  final String id;
  final String name;
  final String? dose;
  final String? frequency;
  final DateTime? startDate;

  const HealthMedication({
    required this.id,
    required this.name,
    this.dose,
    this.frequency,
    this.startDate,
  });

  factory HealthMedication.fromJson(Map<String, dynamic> j) => HealthMedication(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    dose: j['dose'] as String?,
    frequency: j['frequency'] as String?,
    startDate: _parseDateOpt(j['start_date']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'dose': dose,
    'frequency': frequency,
    'start_date': startDate?.toIso8601String(),
  };
}

class HealthCondition {
  final String id;
  final String name;
  final DateTime? diagnosedDate;
  final String? notes;

  const HealthCondition({
    required this.id,
    required this.name,
    this.diagnosedDate,
    this.notes,
  });

  factory HealthCondition.fromJson(Map<String, dynamic> j) => HealthCondition(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    diagnosedDate: _parseDateOpt(j['diagnosed_date']),
    notes: j['notes'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'diagnosed_date': diagnosedDate?.toIso8601String(),
    'notes': notes,
  };
}

class HealthImmunization {
  final String id;
  final String name;
  final DateTime? date;
  final DateTime? nextDue;

  const HealthImmunization({
    required this.id,
    required this.name,
    this.date,
    this.nextDue,
  });

  factory HealthImmunization.fromJson(Map<String, dynamic> j) => HealthImmunization(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    date: _parseDateOpt(j['date']),
    nextDue: _parseDateOpt(j['next_due']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'date': date?.toIso8601String(),
    'next_due': nextDue?.toIso8601String(),
  };
}

class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String? relation;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.relation,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    relation: j['relation'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'relation': relation,
  };
}

class HealthRecord {
  final String id;
  final String familyId;
  final String memberId;
  final String? updatedBy;
  final BloodType bloodType;
  final List<HealthAllergy> allergies;
  final List<HealthMedication> medications;
  final List<HealthCondition> conditions;
  final List<HealthImmunization> immunizations;
  final List<EmergencyContact> emergencyContacts;
  final String? doctorName;
  final String? doctorPhone;
  final String? insuranceProvider;
  final String? insurancePolicyNumber;
  final String? notes;
  final DateTime updatedAt;
  // Extended log-style fields
  final String? type;
  final String? title;
  final Map<String, String> data;

  HealthRecord({
    required this.id,
    required this.familyId,
    String? userId,
    String? memberId,
    this.updatedBy,
    this.bloodType = BloodType.Unknown,
    this.allergies = const [],
    this.medications = const [],
    this.conditions = const [],
    this.immunizations = const [],
    this.emergencyContacts = const [],
    this.doctorName,
    this.doctorPhone,
    this.insuranceProvider,
    this.insurancePolicyNumber,
    this.notes,
    DateTime? updatedAt,
    DateTime? date,
    this.type,
    this.title,
    this.data = const {},
  }) : memberId = userId ?? memberId ?? '',
       updatedAt = updatedAt ?? date ?? DateTime.now();

  // Convenience getters
  String get userId => memberId;
  DateTime get date => updatedAt;

  factory HealthRecord.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return HealthRecord(
      id: j['id'] as String? ?? '',
      familyId: fid,
      memberId: (j['member_id'] ?? j['user_id']) as String? ?? '',
      updatedBy: j['updated_by'] as String?,
      bloodType: bloodTypeFromString(FieldEncryption.decryptField(j['blood_type'] as String?, fid)),
      allergies: _parseList(FieldEncryption.decryptJson(j['allergies'], fid), HealthAllergy.fromJson),
      medications: _parseList(FieldEncryption.decryptJson(j['medications'], fid), HealthMedication.fromJson),
      conditions: _parseList(FieldEncryption.decryptJson(j['conditions'], fid), HealthCondition.fromJson),
      immunizations: _parseList(FieldEncryption.decryptJson(j['immunizations'], fid), HealthImmunization.fromJson),
      emergencyContacts: _parseList(FieldEncryption.decryptJson(j['emergency_contacts'], fid), EmergencyContact.fromJson),
      doctorName: FieldEncryption.decryptField(j['doctor_name'] as String?, fid),
      doctorPhone: FieldEncryption.decryptField(j['doctor_phone'] as String?, fid),
      insuranceProvider: FieldEncryption.decryptField(j['insurance_provider'] as String?, fid),
      insurancePolicyNumber: FieldEncryption.decryptField(j['insurance_policy_number'] as String?, fid),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      updatedAt: _parseDate(j['updated_at']),
      type: j['type'] as String?,
      title: j['title'] as String?,
      data: (j['data'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'family_id': familyId, 'member_id': memberId,
    'updated_by': updatedBy ?? memberId,
    'blood_type': FieldEncryption.encryptField(bloodType.name, familyId),
    'allergies': FieldEncryption.encryptJson(allergies.map((e) => e.toJson()).toList(), familyId),
    'medications': FieldEncryption.encryptJson(medications.map((e) => e.toJson()).toList(), familyId),
    'conditions': FieldEncryption.encryptJson(conditions.map((e) => e.toJson()).toList(), familyId),
    'immunizations': FieldEncryption.encryptJson(immunizations.map((e) => e.toJson()).toList(), familyId),
    'emergency_contacts': FieldEncryption.encryptJson(emergencyContacts.map((e) => e.toJson()).toList(), familyId),
    'doctor_name': FieldEncryption.encryptField(doctorName, familyId),
    'doctor_phone': FieldEncryption.encryptField(doctorPhone, familyId),
    'insurance_provider': FieldEncryption.encryptField(insuranceProvider, familyId),
    'insurance_policy_number': FieldEncryption.encryptField(insurancePolicyNumber, familyId),
    'notes': FieldEncryption.encryptField(notes, familyId),
    'updated_at': updatedAt.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Period tracking
// ─────────────────────────────────────────────────────────────────────────────

class PeriodCycle {
  final String id;
  final String userId;
  final String familyId;
  final DateTime startDate;
  final DateTime? endDate;
  final FlowLevel flowLevel;
  final String? notes;
  final DateTime createdAt;

  PeriodCycle({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.startDate,
    this.endDate,
    this.flowLevel = FlowLevel.MEDIUM,
    this.notes,
    DateTime? createdAt,
    // Accept but ignore symptoms (stored separately in PeriodSymptomLog)
    List<String>? symptoms,
  }) : createdAt = createdAt ?? DateTime.now();

  factory PeriodCycle.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return PeriodCycle(
      id: j['id'] as String? ?? '',
      userId: j['user_id'] as String? ?? '',
      familyId: fid,
      startDate: _parseDate(j['start_date']),
      endDate: _parseDateOpt(j['end_date']),
      flowLevel: flowLevelFromString(FieldEncryption.decryptField(j['flow_level'] as String?, fid)),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      createdAt: _parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'family_id': familyId,
    'start_date': startDate.toIso8601String(),
    'end_date': endDate?.toIso8601String(),
    'flow_level': FieldEncryption.encryptField(flowLevel.name, familyId),
    'notes': FieldEncryption.encryptField(notes, familyId),
    'created_at': createdAt.toIso8601String(),
  };

  // Convenience getter - symptoms come from PeriodSymptomLog but screens may access directly
  List<String> get symptoms => const [];

  PeriodCycle copyWith({
    String? id, String? userId, String? familyId,
    DateTime? startDate, DateTime? endDate, FlowLevel? flowLevel,
    String? notes, DateTime? createdAt,
  }) => PeriodCycle(
    id: id ?? this.id, userId: userId ?? this.userId,
    familyId: familyId ?? this.familyId,
    startDate: startDate ?? this.startDate, endDate: endDate ?? this.endDate,
    flowLevel: flowLevel ?? this.flowLevel, notes: notes ?? this.notes,
    createdAt: createdAt ?? this.createdAt,
  );
}

class PeriodSymptomLog {
  final String id;
  final String userId;
  final String familyId;
  final DateTime date;
  final List<String> symptoms;
  final CycleMood? mood;
  final int? painLevel;
  final String? notes;
  final DateTime createdAt;

  const PeriodSymptomLog({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.date,
    this.symptoms = const [],
    this.mood,
    this.painLevel,
    this.notes,
    required this.createdAt,
  });

  factory PeriodSymptomLog.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    // symptoms may be encrypted as a JSON string or legacy plain list
    final rawSymptoms = FieldEncryption.decryptJson(j['symptoms'], fid);
    final moodRaw = j['mood'] ?? j['pain_level'] != null ? j['mood'] : null;
    return PeriodSymptomLog(
      id: j['id'] as String? ?? '',
      userId: j['user_id'] as String? ?? '',
      familyId: fid,
      date: _parseDate(j['date']),
      symptoms: rawSymptoms is List ? rawSymptoms.map((e) => e.toString()).toList() : _strList(rawSymptoms),
      mood: moodRaw != null ? cycleMoodFromString(FieldEncryption.decryptField(moodRaw as String?, fid)) : null,
      painLevel: FieldEncryption.decryptInt(j['pain_level'] ?? j['painLevel'], fid),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      createdAt: _parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'family_id': familyId,
    'date': date.toIso8601String(),
    'symptoms': FieldEncryption.encryptJson(symptoms, familyId),
    'mood': FieldEncryption.encryptField(mood?.name, familyId),
    'pain_level': FieldEncryption.encryptNum(painLevel, familyId),
    'notes': FieldEncryption.encryptField(notes, familyId),
    'created_at': createdAt.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// NotificationPrefs
// ─────────────────────────────────────────────────────────────────────────────

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
  };

  NotificationPrefs copyWith({
    bool? chat, bool? tasks, bool? calendar, bool? chores, bool? lists,
    bool? polls, bool? meals, bool? birthdays, bool? photos, bool? location,
    bool? weeklyDigest, bool? webPushEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
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
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PantryItem (staples / pantry for meal planning)
// ─────────────────────────────────────────────────────────────────────────────

class PantryItem {
  final String id;
  final String familyId;
  final String name;
  final String? quantity;
  final String? unit;
  final DateTime updatedAt;

  const PantryItem({
    required this.id,
    required this.familyId,
    required this.name,
    this.quantity,
    this.unit,
    required this.updatedAt,
  });

  String get mergeKey => id;

  factory PantryItem.fromJson(Map<String, dynamic> j) => PantryItem(
        id: j['id'] as String? ?? '',
        familyId: j['family_id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        quantity: j['quantity'] as String?,
        unit: j['unit'] as String?,
        updatedAt: _parseDateOpt(j['updated_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'updated_at': updatedAt.toIso8601String(),
      };

  PantryItem copyWith({
    String? id,
    String? familyId,
    String? name,
    String? quantity,
    String? unit,
    DateTime? updatedAt,
  }) =>
      PantryItem(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// FamilyActivityLog (trust / audit trail for sensitive actions)
// ─────────────────────────────────────────────────────────────────────────────

class FamilyActivityLog {
  final String id;
  final String familyId;
  final String actorUserId;
  final String action;
  final String? detail;
  final String? relatedUserId;
  final DateTime createdAt;

  const FamilyActivityLog({
    required this.id,
    required this.familyId,
    required this.actorUserId,
    required this.action,
    this.detail,
    this.relatedUserId,
    required this.createdAt,
  });

  String get mergeKey => id;

  factory FamilyActivityLog.fromJson(Map<String, dynamic> j) =>
      FamilyActivityLog(
        id: j['id'] as String? ?? '',
        familyId: j['family_id'] as String? ?? '',
        actorUserId: j['actor_user_id'] as String? ?? '',
        action: j['action'] as String? ?? '',
        detail: j['detail'] as String?,
        relatedUserId: j['related_user_id'] as String?,
        createdAt: _parseDate(j['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'actor_user_id': actorUserId,
        'action': action,
        'detail': detail,
        'related_user_id': relatedUserId,
        'created_at': createdAt.toIso8601String(),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// WellnessCheckIn (light daily mood pulse)
// ─────────────────────────────────────────────────────────────────────────────

class WellnessCheckIn {
  final String id;
  final String familyId;
  final String userId;
  /// One of: great, good, ok, low, rough
  final String mood;
  final String? note;
  final DateTime day;
  final DateTime createdAt;

  const WellnessCheckIn({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.mood,
    this.note,
    required this.day,
    required this.createdAt,
  });

  String get mergeKey => id;

  factory WellnessCheckIn.fromJson(Map<String, dynamic> j) => WellnessCheckIn(
        id: j['id'] as String? ?? '',
        familyId: j['family_id'] as String? ?? '',
        userId: j['user_id'] as String? ?? '',
        mood: j['mood'] as String? ?? 'ok',
        note: j['note'] as String?,
        day: _parseDateOpt(j['day']) ?? DateTime.now(),
        createdAt: _parseDate(j['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'user_id': userId,
        'mood': mood,
        'note': note,
        'day': DateTime(day.year, day.month, day.day).toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// AppDB
// ─────────────────────────────────────────────────────────────────────────────

class AppDB {
  final List<User> users;
  final List<Family> families;
  final List<FamilyMember> familyMembers;
  final List<Task> tasks;
  final List<CalendarEvent> events;
  final List<Recipe> recipes;
  final List<MealPlanEntry> mealPlans;
  final List<ShoppingList> lists;
  final List<DevotionalEntry> devotionals;
  final List<FitnessMetric> fitness;
  final List<FitnessLog> fitnessLogs;
  final List<dynamic> fitnessPlans;
  final List<WorkoutSession> workoutSessions;
  final List<WorkoutExercise> workoutExercises;
  final List<WorkoutSet> workoutSets;
  final List<ExercisePR> exercisePrs;
  final List<BudgetCategoryRecord> budgetCategories;
  final List<BudgetEntry> budgetEntries;
  final List<Transaction> transactions;
  final List<AIHistory> aiHistory;
  final List<DailyHabit> dailyHabits;
  final List<DailyHabitCompletion> dailyHabitCompletions;
  final List<Chore> chores;
  final List<ChoreCompletion> choreCompletions;
  final List<Poll> polls;
  final List<PollVote> pollVotes;
  final List<RewardItem> rewardItems;
  final List<Reward> rewards;
  final List<RewardRedemption> rewardRedemptions;
  final List<SavingsGoal> savingsGoals;
  final List<PrayerWallEntry> prayerWall;
  final List<SpecialDate> specialDates;
  final List<FamilyPhoto> familyPhotos;
  final List<Milestone> milestones;
  final List<SavedPlace> savedPlaces;
  final List<UserLocation> userLocations;
  final List<ChatMessage> messages;
  final List<HealthRecord> healthRecords;
  final List<PeriodCycle> periodCycles;
  final List<PeriodSymptomLog> periodSymptoms;
  final List<NotificationPrefs> notificationPrefs;
  final List<ReadingPlan> readingPlans;
  final List<ExternalCalendar> externalCalendars;
  final List<PantryItem> pantryItems;
  final List<FamilyActivityLog> familyActivityLogs;
  final List<WellnessCheckIn> wellnessCheckIns;

  const AppDB({
    this.users = const [],
    this.families = const [],
    this.familyMembers = const [],
    this.tasks = const [],
    this.events = const [],
    this.recipes = const [],
    this.mealPlans = const [],
    this.lists = const [],
    this.devotionals = const [],
    this.fitness = const [],
    this.fitnessLogs = const [],
    this.fitnessPlans = const [],
    this.workoutSessions = const [],
    this.workoutExercises = const [],
    this.workoutSets = const [],
    this.exercisePrs = const [],
    this.budgetCategories = const <BudgetCategoryRecord>[],
    this.budgetEntries = const [],
    this.transactions = const [],
    this.aiHistory = const [],
    this.dailyHabits = const [],
    this.dailyHabitCompletions = const [],
    this.chores = const [],
    this.choreCompletions = const [],
    this.polls = const [],
    this.pollVotes = const [],
    this.rewardItems = const [],
    this.rewards = const [],
    this.rewardRedemptions = const [],
    this.savingsGoals = const [],
    this.prayerWall = const [],
    this.specialDates = const [],
    this.familyPhotos = const [],
    this.milestones = const [],
    this.savedPlaces = const [],
    this.userLocations = const [],
    this.messages = const [],
    this.healthRecords = const [],
    this.periodCycles = const [],
    this.periodSymptoms = const [],
    this.notificationPrefs = const [],
    this.readingPlans = const [],
    this.externalCalendars = const [],
    this.pantryItems = const [],
    this.familyActivityLogs = const [],
    this.wellnessCheckIns = const [],
  });

  factory AppDB.empty() => const AppDB();

  factory AppDB.fromJson(Map<String, dynamic> j) => AppDB(
    users: _parseList(j['users'], User.fromJson),
    families: _parseList(j['families'], Family.fromJson),
    familyMembers: _parseList(j['familyMembers'] ?? j['family_members'], FamilyMember.fromJson),
    tasks: _parseList(j['tasks'], Task.fromJson),
    events: _parseList(j['events'], CalendarEvent.fromJson),
    recipes: _parseList(j['recipes'], Recipe.fromJson),
    mealPlans: _parseList(j['mealPlans'] ?? j['meal_plans'], MealPlanEntry.fromJson),
    lists: _parseList(j['lists'], ShoppingList.fromJson),
    devotionals: _parseList(j['devotionals'], DevotionalEntry.fromJson),
    fitness: _parseList(j['fitness'], FitnessMetric.fromJson),
    fitnessLogs: _parseList(j['fitnessLogs'] ?? j['fitness_logs'], FitnessLog.fromJson),
    fitnessPlans: (j['fitnessPlans'] ?? j['fitness_plans']) is List
        ? (j['fitnessPlans'] ?? j['fitness_plans']) as List
        : [],
    workoutSessions: _parseList(j['workoutSessions'] ?? j['workout_sessions'], WorkoutSession.fromJson),
    workoutExercises: _parseList(j['workoutExercises'] ?? j['workout_exercises'], WorkoutExercise.fromJson),
    workoutSets: _parseList(j['workoutSets'] ?? j['workout_sets'], WorkoutSet.fromJson),
    exercisePrs: _parseList(j['exercisePrs'] ?? j['exercise_prs'], ExercisePR.fromJson),
    budgetCategories: _parseList(j['budgetCategories'] ?? j['budget_categories'], BudgetCategoryRecord.fromJson),
    budgetEntries: _parseList(j['budgetEntries'] ?? j['budget_entries'], BudgetEntry.fromJson),
    transactions: _parseList(j['transactions'], Transaction.fromJson),
    aiHistory: _parseList(j['aiHistory'] ?? j['ai_history'], AIHistory.fromJson),
    dailyHabits: _parseList(j['dailyHabits'] ?? j['daily_habits'], DailyHabit.fromJson),
    dailyHabitCompletions: _parseList(j['dailyHabitCompletions'] ?? j['daily_habit_completions'], DailyHabitCompletion.fromJson),
    chores: _parseList(j['chores'], Chore.fromJson),
    choreCompletions: _parseList(j['choreCompletions'] ?? j['chore_completions'], ChoreCompletion.fromJson),
    polls: _parseList(j['polls'], Poll.fromJson),
    pollVotes: _parseList(j['pollVotes'] ?? j['poll_votes'], PollVote.fromJson),
    rewardItems: _parseList(j['rewardItems'] ?? j['reward_items'], RewardItem.fromJson),
    rewards: _parseList(j['rewards'], Reward.fromJson),
    rewardRedemptions: _parseList(j['rewardRedemptions'] ?? j['reward_redemptions'], RewardRedemption.fromJson),
    savingsGoals: _parseList(j['savingsGoals'] ?? j['savings_goals'], SavingsGoal.fromJson),
    prayerWall: _parseList(j['prayerWall'] ?? j['prayer_wall'], PrayerWallEntry.fromJson),
    specialDates: _parseList(j['specialDates'] ?? j['special_dates'], SpecialDate.fromJson),
    familyPhotos: _parseList(j['familyPhotos'] ?? j['family_photos'], FamilyPhoto.fromJson),
    milestones: _parseList(j['milestones'], Milestone.fromJson),
    savedPlaces: _parseList(j['savedPlaces'] ?? j['saved_places'], SavedPlace.fromJson),
    userLocations: _parseList(j['userLocations'] ?? j['user_locations'], UserLocation.fromJson),
    messages: _parseList(j['messages'], ChatMessage.fromJson),
    healthRecords: _parseList(j['healthRecords'] ?? j['health_records'], HealthRecord.fromJson),
    periodCycles: _parseList(j['periodCycles'] ?? j['period_cycles'], PeriodCycle.fromJson),
    periodSymptoms: _parseList(j['periodSymptoms'] ?? j['period_symptoms'], PeriodSymptomLog.fromJson),
    notificationPrefs: _parseList(j['notificationPrefs'] ?? j['notification_prefs'], NotificationPrefs.fromJson),
    readingPlans: _parseList(j['readingPlans'] ?? j['reading_plans'], ReadingPlan.fromJson),
    externalCalendars: _parseList(j['externalCalendars'] ?? j['external_calendars'], ExternalCalendar.fromJson),
    pantryItems: _parseList(j['pantryItems'] ?? j['pantry_items'], PantryItem.fromJson),
    familyActivityLogs: _parseList(j['familyActivityLogs'] ?? j['family_activity_logs'], FamilyActivityLog.fromJson),
    wellnessCheckIns: _parseList(j['wellnessCheckIns'] ?? j['wellness_check_ins'], WellnessCheckIn.fromJson),
  );

  /// fromCloudJson handles Supabase snake_case table names -> AppDB fields
  factory AppDB.fromCloudJson(Map<String, dynamic> cloud) => AppDB(
    users: _parseList(cloud['users'], User.fromJson),
    families: _parseList(cloud['families'], Family.fromJson),
    familyMembers: _parseList(cloud['family_members'], FamilyMember.fromJson),
    tasks: _parseList(cloud['tasks'], Task.fromJson),
    events: _parseList(cloud['events'], CalendarEvent.fromJson),
    recipes: _parseList(cloud['recipes'], Recipe.fromJson),
    mealPlans: _parseList(cloud['meal_plans'], MealPlanEntry.fromJson),
    lists: _parseList(cloud['lists'], ShoppingList.fromJson),
    devotionals: _parseList(cloud['devotionals'], DevotionalEntry.fromJson),
    fitness: _parseList(cloud['fitness_metrics'], FitnessMetric.fromJson),
    fitnessLogs: _parseList(cloud['fitness_logs'], FitnessLog.fromJson),
    fitnessPlans: cloud['fitness_plans'] is List ? cloud['fitness_plans'] as List : [],
    workoutSessions: _parseList(cloud['workout_sessions'], WorkoutSession.fromJson),
    workoutExercises: _parseList(cloud['workout_exercises'], WorkoutExercise.fromJson),
    workoutSets: _parseList(cloud['workout_sets'], WorkoutSet.fromJson),
    exercisePrs: _parseList(cloud['exercise_prs'], ExercisePR.fromJson),
    budgetCategories: _parseList(cloud['budget_categories'], BudgetCategoryRecord.fromJson),
    budgetEntries: _parseList(cloud['budget_entries'], BudgetEntry.fromJson),
    transactions: _parseList(cloud['transactions'], Transaction.fromJson),
    aiHistory: _parseList(cloud['ai_history'], AIHistory.fromJson),
    dailyHabits: _parseList(cloud['daily_habits'], DailyHabit.fromJson),
    dailyHabitCompletions: _parseList(cloud['daily_habit_completions'], DailyHabitCompletion.fromJson),
    chores: _parseList(cloud['chores'], Chore.fromJson),
    choreCompletions: _parseList(cloud['chore_completions'], ChoreCompletion.fromJson),
    polls: _parseList(cloud['polls'], Poll.fromJson),
    pollVotes: _parseList(cloud['poll_votes'], PollVote.fromJson),
    rewardItems: _parseList(cloud['reward_items'], RewardItem.fromJson),
    rewards: _parseList(cloud['rewards'], Reward.fromJson),
    rewardRedemptions: _parseList(cloud['reward_redemptions'], RewardRedemption.fromJson),
    savingsGoals: _parseList(cloud['savings_goals'], SavingsGoal.fromJson),
    prayerWall: _parseList(cloud['prayer_wall'], PrayerWallEntry.fromJson),
    specialDates: _parseList(cloud['special_dates'], SpecialDate.fromJson),
    familyPhotos: _parseList(cloud['family_photos'], FamilyPhoto.fromJson),
    milestones: _parseList(cloud['milestones'], Milestone.fromJson),
    savedPlaces: _parseList(cloud['saved_places'], SavedPlace.fromJson),
    userLocations: _parseList(cloud['user_locations'], UserLocation.fromJson),
    messages: _parseList(cloud['messages'], ChatMessage.fromJson),
    healthRecords: _parseList(cloud['health_records'], HealthRecord.fromJson),
    periodCycles: _parseList(cloud['period_cycles'], PeriodCycle.fromJson),
    periodSymptoms: _parseList(cloud['period_symptoms'], PeriodSymptomLog.fromJson),
    notificationPrefs: const [],
    readingPlans: _parseList(cloud['reading_plans'], ReadingPlan.fromJson),
    externalCalendars: _parseList(cloud['external_calendars'], ExternalCalendar.fromJson),
    pantryItems: _parseList(cloud['pantry_items'], PantryItem.fromJson),
    familyActivityLogs: _parseList(cloud['family_activity_logs'], FamilyActivityLog.fromJson),
    wellnessCheckIns: _parseList(cloud['wellness_check_ins'], WellnessCheckIn.fromJson),
  );

  Map<String, dynamic> toJson() => {
    'users': users.map((e) => e.toJson()).toList(),
    'families': families.map((e) => e.toJson()).toList(),
    'familyMembers': familyMembers.map((e) => e.toJson()).toList(),
    'tasks': tasks.map((e) => e.toJson()).toList(),
    'events': events.map((e) => e.toJson()).toList(),
    'recipes': recipes.map((e) => e.toJson()).toList(),
    'mealPlans': mealPlans.map((e) => e.toJson()).toList(),
    'lists': lists.map((e) => e.toJson()).toList(),
    'devotionals': devotionals.map((e) => e.toJson()).toList(),
    'fitness': fitness.map((e) => e.toJson()).toList(),
    'fitnessLogs': fitnessLogs.map((e) => e.toJson()).toList(),
    'fitnessPlans': fitnessPlans,
    'workoutSessions': workoutSessions.map((e) => e.toJson()).toList(),
    'workoutExercises': workoutExercises.map((e) => e.toJson()).toList(),
    'workoutSets': workoutSets.map((e) => e.toJson()).toList(),
    'exercisePrs': exercisePrs.map((e) => e.toJson()).toList(),
    'budgetCategories': budgetCategories.map((e) => e.toJson()).toList(),
    'budgetEntries': budgetEntries.map((e) => e.toJson()).toList(),
    'transactions': transactions.map((e) => e.toJson()).toList(),
    'aiHistory': aiHistory.map((e) => e.toJson()).toList(),
    'dailyHabits': dailyHabits.map((e) => e.toJson()).toList(),
    'dailyHabitCompletions': dailyHabitCompletions.map((e) => e.toJson()).toList(),
    'chores': chores.map((e) => e.toJson()).toList(),
    'choreCompletions': choreCompletions.map((e) => e.toJson()).toList(),
    'polls': polls.map((e) => e.toJson()).toList(),
    'pollVotes': pollVotes.map((e) => e.toJson()).toList(),
    'rewardItems': rewardItems.map((e) => e.toJson()).toList(),
    'rewards': rewards.map((e) => e.toJson()).toList(),
    'rewardRedemptions': rewardRedemptions.map((e) => e.toJson()).toList(),
    'savingsGoals': savingsGoals.map((e) => e.toJson()).toList(),
    'prayerWall': prayerWall.map((e) => e.toJson()).toList(),
    'specialDates': specialDates.map((e) => e.toJson()).toList(),
    'familyPhotos': familyPhotos.map((e) => e.toJson()).toList(),
    'milestones': milestones.map((e) => e.toJson()).toList(),
    'savedPlaces': savedPlaces.map((e) => e.toJson()).toList(),
    'userLocations': userLocations.map((e) => e.toJson()).toList(),
    'messages': messages.map((e) => e.toJson()).toList(),
    'healthRecords': healthRecords.map((e) => e.toJson()).toList(),
    'periodCycles': periodCycles.map((e) => e.toJson()).toList(),
    'periodSymptoms': periodSymptoms.map((e) => e.toJson()).toList(),
    'notificationPrefs': notificationPrefs.map((e) => e.toJson()).toList(),
    'readingPlans': readingPlans.map((e) => e.toJson()).toList(),
    'externalCalendars': externalCalendars.map((e) => e.toJson()).toList(),
    'pantryItems': pantryItems.map((e) => e.toJson()).toList(),
    'familyActivityLogs': familyActivityLogs.map((e) => e.toJson()).toList(),
    'wellnessCheckIns': wellnessCheckIns.map((e) => e.toJson()).toList(),
  };

  AppDB copyWith({
    List<User>? users,
    List<Family>? families,
    List<FamilyMember>? familyMembers,
    List<Task>? tasks,
    List<CalendarEvent>? events,
    List<Recipe>? recipes,
    List<MealPlanEntry>? mealPlans,
    List<ShoppingList>? lists,
    List<DevotionalEntry>? devotionals,
    List<FitnessMetric>? fitness,
    List<FitnessLog>? fitnessLogs,
    List<dynamic>? fitnessPlans,
    List<WorkoutSession>? workoutSessions,
    List<WorkoutExercise>? workoutExercises,
    List<WorkoutSet>? workoutSets,
    List<ExercisePR>? exercisePrs,
    List<BudgetCategoryRecord>? budgetCategories,
    List<BudgetEntry>? budgetEntries,
    List<Transaction>? transactions,
    List<AIHistory>? aiHistory,
    List<DailyHabit>? dailyHabits,
    List<DailyHabitCompletion>? dailyHabitCompletions,
    List<Chore>? chores,
    List<ChoreCompletion>? choreCompletions,
    List<Poll>? polls,
    List<PollVote>? pollVotes,
    List<RewardItem>? rewardItems,
    List<Reward>? rewards,
    List<RewardRedemption>? rewardRedemptions,
    List<SavingsGoal>? savingsGoals,
    List<PrayerWallEntry>? prayerWall,
    List<SpecialDate>? specialDates,
    List<FamilyPhoto>? familyPhotos,
    List<Milestone>? milestones,
    List<SavedPlace>? savedPlaces,
    List<UserLocation>? userLocations,
    List<ChatMessage>? messages,
    List<HealthRecord>? healthRecords,
    List<PeriodCycle>? periodCycles,
    List<PeriodSymptomLog>? periodSymptoms,
    List<NotificationPrefs>? notificationPrefs,
    List<ReadingPlan>? readingPlans,
    List<ExternalCalendar>? externalCalendars,
    List<PantryItem>? pantryItems,
    List<FamilyActivityLog>? familyActivityLogs,
    List<WellnessCheckIn>? wellnessCheckIns,
    // Convenience alias params
    List<PrayerWallEntry>? prayerRequests,
    List<PeriodCycle>? periodEntries,
    List<SpecialDate>? occasions,
    List<FamilyPhoto>? photos,
    List<UserLocation>? locationShares,
    List<DailyHabitCompletion>? habitCompletions,
    List<DevotionalEntry>? devotionalEntries,
    List<ShoppingList>? shoppingLists,
  }) => AppDB(
    users: users ?? this.users,
    families: families ?? this.families,
    familyMembers: familyMembers ?? this.familyMembers,
    tasks: tasks ?? this.tasks,
    events: events ?? this.events,
    recipes: recipes ?? this.recipes,
    mealPlans: mealPlans ?? this.mealPlans,
    lists: shoppingLists ?? lists ?? this.lists,
    devotionals: devotionalEntries ?? devotionals ?? this.devotionals,
    fitness: fitness ?? this.fitness,
    fitnessLogs: fitnessLogs ?? this.fitnessLogs,
    fitnessPlans: fitnessPlans ?? this.fitnessPlans,
    workoutSessions: workoutSessions ?? this.workoutSessions,
    workoutExercises: workoutExercises ?? this.workoutExercises,
    workoutSets: workoutSets ?? this.workoutSets,
    exercisePrs: exercisePrs ?? this.exercisePrs,
    budgetCategories: budgetCategories ?? this.budgetCategories,
    budgetEntries: budgetEntries ?? this.budgetEntries,
    transactions: transactions ?? this.transactions,
    aiHistory: aiHistory ?? this.aiHistory,
    dailyHabits: dailyHabits ?? this.dailyHabits,
    dailyHabitCompletions: habitCompletions ?? dailyHabitCompletions ?? this.dailyHabitCompletions,
    chores: chores ?? this.chores,
    choreCompletions: choreCompletions ?? this.choreCompletions,
    polls: polls ?? this.polls,
    pollVotes: pollVotes ?? this.pollVotes,
    rewardItems: rewardItems ?? this.rewardItems,
    rewards: rewards ?? this.rewards,
    rewardRedemptions: rewardRedemptions ?? this.rewardRedemptions,
    savingsGoals: savingsGoals ?? this.savingsGoals,
    prayerWall: prayerRequests ?? prayerWall ?? this.prayerWall,
    specialDates: occasions ?? specialDates ?? this.specialDates,
    familyPhotos: photos ?? familyPhotos ?? this.familyPhotos,
    milestones: milestones ?? this.milestones,
    savedPlaces: savedPlaces ?? this.savedPlaces,
    userLocations: locationShares ?? userLocations ?? this.userLocations,
    messages: messages ?? this.messages,
    healthRecords: healthRecords ?? this.healthRecords,
    periodCycles: periodEntries ?? periodCycles ?? this.periodCycles,
    periodSymptoms: periodSymptoms ?? this.periodSymptoms,
    notificationPrefs: notificationPrefs ?? this.notificationPrefs,
    readingPlans: readingPlans ?? this.readingPlans,
    externalCalendars: externalCalendars ?? this.externalCalendars,
    pantryItems: pantryItems ?? this.pantryItems,
    familyActivityLogs: familyActivityLogs ?? this.familyActivityLogs,
    wellnessCheckIns: wellnessCheckIns ?? this.wellnessCheckIns,
  );

  /// After [FieldEncryption.init], re-decrypt rows that were parsed while the
  /// cipher was not ready (cloud pull / login order bugs).
  AppDB applySensitiveDecryption(String familyId) {
    if (!FieldEncryption.isReady(familyId)) return this;
    String ds(String? s) {
      if (s == null) return '';
      final d = FieldEncryption.decryptField(s, familyId);
      return d ?? s;
    }

    return copyWith(
      messages: messages.map((m) {
        if (m.familyId != familyId) return m;
        return ChatMessage(
          id: m.id,
          familyId: m.familyId,
          userId: m.userId,
          text: ds(m.text),
          replyToId: m.replyToId,
          reactions: m.reactions,
          editedAt: m.editedAt,
          createdAt: m.createdAt,
        );
      }).toList(),
      budgetCategories: budgetCategories.map((c) {
        if (c.familyId != familyId) return c;
        return BudgetCategoryRecord(
          id: c.id,
          familyId: c.familyId,
          creatorId: c.creatorId,
          name: ds(c.name),
          limit: c.limit,
          color: c.color,
          visibility: c.visibility,
        );
      }).toList(),
      budgetEntries: budgetEntries.map((e) {
        if (e.familyId != familyId) return e;
        return BudgetEntry(
          id: e.id,
          familyId: e.familyId,
          creatorId: e.creatorId,
          title: ds(e.title),
          amount: e.amount,
          type: e.type,
          category: e.category,
          date: e.date,
          notes: e.notes != null ? ds(e.notes) : null,
          visibility: e.visibility,
        );
      }).toList(),
      transactions: transactions.map((t) {
        if (t.familyId != familyId) return t;
        return Transaction(
          id: t.id,
          familyId: t.familyId,
          creatorId: t.creatorId,
          categoryId: t.categoryId,
          amount: t.amount,
          type: t.type,
          date: t.date,
          description: ds(t.description),
          visibility: t.visibility,
        );
      }).toList(),
      fitnessLogs: fitnessLogs.map((l) {
        if (l.familyId != familyId) return l;
        return FitnessLog(
          id: l.id,
          familyId: l.familyId,
          userId: l.userId,
          activity: ds(l.activity),
          durationMinutes: l.durationMinutes,
          caloriesBurned: l.caloriesBurned,
          notes: l.notes != null ? ds(l.notes) : null,
          date: l.date,
        );
      }).toList(),
      workoutSessions: workoutSessions.map((s) {
        if (s.familyId != familyId) return s;
        return WorkoutSession(
          id: s.id,
          familyId: s.familyId,
          userId: s.userId,
          title: ds(s.title),
          date: s.date,
          durationMinutes: s.durationMinutes,
          notes: s.notes != null ? ds(s.notes) : null,
          healthSyncedAt: s.healthSyncedAt,
          createdAt: s.createdAt,
        );
      }).toList(),
      workoutExercises: workoutExercises.map((e) {
        if (e.familyId != familyId) return e;
        return WorkoutExercise(
          id: e.id,
          familyId: e.familyId,
          userId: e.userId,
          sessionId: e.sessionId,
          exerciseName: ds(e.exerciseName),
          order: e.order,
          restSeconds: e.restSeconds,
          notes: e.notes != null ? ds(e.notes) : null,
          techniqueNotes:
              e.techniqueNotes != null ? ds(e.techniqueNotes) : null,
          referenceUrl:
              e.referenceUrl != null ? ds(e.referenceUrl) : null,
          techniqueImageUrl: e.techniqueImageUrl,
          exerciseDbId: e.exerciseDbId,
          createdAt: e.createdAt,
        );
      }).toList(),
      workoutSets: workoutSets.map((set) {
        if (set.familyId != familyId) return set;
        return WorkoutSet(
          id: set.id,
          familyId: set.familyId,
          userId: set.userId,
          exerciseId: set.exerciseId,
          setNumber: set.setNumber,
          reps: ds(set.reps),
          weight: set.weight != null ? ds(set.weight) : null,
          completed: set.completed,
          notes: set.notes != null ? ds(set.notes) : null,
          createdAt: set.createdAt,
        );
      }).toList(),
      savingsGoals: savingsGoals.map((g) {
        if (g.familyId != familyId) return g;
        return SavingsGoal(
          id: g.id,
          familyId: g.familyId,
          userId: g.userId,
          title: ds(g.title),
          icon: g.icon,
          imageUrl: g.imageUrl,
          targetAmount: g.targetAmount,
          savedAmount: g.savedAmount,
          createdAt: g.createdAt,
          completedAt: g.completedAt,
        );
      }).toList(),
      healthRecords: healthRecords.map((h) {
        if (h.familyId != familyId) return h;
        return HealthRecord(
          id: h.id,
          familyId: h.familyId,
          userId: h.memberId,
          updatedBy: h.updatedBy,
          bloodType: h.bloodType,
          allergies: h.allergies
              .map((a) => HealthAllergy(
                    id: a.id,
                    name: ds(a.name),
                    severity: a.severity,
                    reaction: a.reaction != null ? ds(a.reaction) : null,
                  ))
              .toList(),
          medications: h.medications
              .map((m) => HealthMedication(
                    id: m.id,
                    name: ds(m.name),
                    dose: m.dose != null ? ds(m.dose) : null,
                    frequency: m.frequency != null ? ds(m.frequency) : null,
                    startDate: m.startDate,
                  ))
              .toList(),
          conditions: h.conditions
              .map((c) => HealthCondition(
                    id: c.id,
                    name: ds(c.name),
                    diagnosedDate: c.diagnosedDate,
                    notes: c.notes != null ? ds(c.notes) : null,
                  ))
              .toList(),
          immunizations: h.immunizations
              .map((i) => HealthImmunization(
                    id: i.id,
                    name: ds(i.name),
                    date: i.date,
                    nextDue: i.nextDue,
                  ))
              .toList(),
          emergencyContacts: h.emergencyContacts
              .map((e) => EmergencyContact(
                    id: e.id,
                    name: ds(e.name),
                    phone: ds(e.phone),
                    relation: e.relation != null ? ds(e.relation) : null,
                  ))
              .toList(),
          doctorName: h.doctorName != null ? ds(h.doctorName) : null,
          doctorPhone: h.doctorPhone != null ? ds(h.doctorPhone) : null,
          insuranceProvider:
              h.insuranceProvider != null ? ds(h.insuranceProvider) : null,
          insurancePolicyNumber:
              h.insurancePolicyNumber != null ? ds(h.insurancePolicyNumber) : null,
          notes: h.notes != null ? ds(h.notes) : null,
          updatedAt: h.updatedAt,
          type: h.type,
          title: h.title,
          data: h.data,
        );
      }).toList(),
      periodCycles: periodCycles.map((p) {
        if (p.familyId != familyId) return p;
        return PeriodCycle(
          id: p.id,
          userId: p.userId,
          familyId: p.familyId,
          startDate: p.startDate,
          endDate: p.endDate,
          flowLevel: p.flowLevel,
          notes: p.notes != null ? ds(p.notes) : null,
          createdAt: p.createdAt,
        );
      }).toList(),
      periodSymptoms: periodSymptoms.map((p) {
        if (p.familyId != familyId) return p;
        return PeriodSymptomLog(
          id: p.id,
          userId: p.userId,
          familyId: p.familyId,
          date: p.date,
          symptoms: p.symptoms.map((s) => ds(s)).toList(),
          mood: p.mood,
          painLevel: p.painLevel,
          notes: p.notes != null ? ds(p.notes) : null,
          createdAt: p.createdAt,
        );
      }).toList(),
    );
  }

  // Convenience alias getters for screen compatibility
  List<PrayerWallEntry> get prayerRequests => prayerWall;
  List<PeriodCycle> get periodEntries => periodCycles;
  List<SpecialDate> get occasions => specialDates;
  List<FamilyPhoto> get photos => familyPhotos;
  List<UserLocation> get locationShares => userLocations;
  List<DailyHabitCompletion> get habitCompletions => dailyHabitCompletions;
  List<DevotionalEntry> get devotionalEntries => devotionals;
  List<ShoppingList> get shoppingLists => lists;
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

List<T> _parseList<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
  if (raw == null) return [];
  if (raw is! List) return [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(fromJson)
      .toList();
}

List<String> _strList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw.map((e) => e.toString()).toList();
  return [];
}

List<int> _intList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw.map((e) => (e as num).toInt()).toList();
  return [];
}

DateTime _parseDate(dynamic raw) {
  if (raw == null) return DateTime.now();
  if (raw is DateTime) return raw;
  try { return DateTime.parse(raw.toString()); } catch (_) { return DateTime.now(); }
}

DateTime? _parseDateOpt(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  try { return DateTime.parse(raw.toString()); } catch (_) { return null; }
}

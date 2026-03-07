// lib/models/models.dart
// FamilyHub - Complete data models

// ignore_for_file: constant_identifier_names

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum Role { OWNER, ADMIN, MEMBER }

enum Visibility { PRIVATE, FAMILY, SPECIFIC }

enum SubscriptionTier { trial, base, ai }

enum Recurrence { NONE, DAILY, WEEKLY, MONTHLY }

enum Priority { LOW, MEDIUM, HIGH }

enum MealType { BREAKFAST, LUNCH, DINNER }

enum ListCategory { GROCERY, HARDWARE, PACKING, OTHER }

enum ChoreFrequency { DAILY, WEEKLY, CUSTOM }

enum PollStatus { OPEN, CLOSED }

enum ApprovalStatus { PENDING, APPROVED, REJECTED }

enum RedemptionStatus { PENDING, APPROVED, DENIED }

enum FlowLevel { LIGHT, MEDIUM, HEAVY }

enum CycleMood { GREAT, GOOD, OKAY, LOW, ROUGH }

enum PrayerWallType { GRATITUDE, REQUEST, ANSWERED }

enum BloodType { Aplus, Aminus, Bplus, Bminus, ABplus, ABminus, Oplus, Ominus, Unknown }

enum AllergySeverity { MILD, MODERATE, SEVERE }

enum SpecialDateType { BIRTHDAY, ANNIVERSARY, MEMORIAL, OTHER }

enum TransactionType { INCOME, EXPENSE }

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
  switch (s?.toUpperCase()) {
    case 'CLOSED': return PollStatus.CLOSED;
    default: return PollStatus.OPEN;
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


// ─────────────────────────────────────────────────────────────────────────────
// User
// ─────────────────────────────────────────────────────────────────────────────

class User {
  final String id;
  final String name;
  final String email;
  final String? avatar;

  const User({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    email: j['email'] as String? ?? '',
    avatar: j['avatar'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'avatar': avatar,
  };

  User copyWith({String? id, String? name, String? email, String? avatar}) =>
    User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
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
  final List<String> enabledModules;
  final DateTime createdAt;
  final bool welcomeDismissed;
  final bool weeklyDigest;

  const Family({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.joinCode,
    this.announcement,
    this.announcementAuthor,
    this.subscriptionTier = SubscriptionTier.trial,
    this.enabledModules = const [],
    required this.createdAt,
    this.welcomeDismissed = false,
    this.weeklyDigest = true,
  });

  factory Family.fromJson(Map<String, dynamic> j) => Family(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    ownerId: (j['owner_id'] ?? j['ownerId']) as String? ?? '',
    joinCode: (j['join_code'] ?? j['joinCode']) as String? ?? '',
    announcement: j['announcement'] as String?,
    announcementAuthor: (j['announcement_author'] ?? j['announcementAuthor']) as String?,
    subscriptionTier: subscriptionTierFromString((j['subscription_tier'] ?? j['subscriptionTier']) as String?),
    enabledModules: _strList(j['enabled_modules'] ?? j['enabledModules']),
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
    welcomeDismissed: (j['welcome_dismissed'] ?? j['welcomeDismissed'] ?? false) as bool,
    weeklyDigest: (j['weekly_digest'] ?? j['weeklyDigest'] ?? true) as bool,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'owner_id': ownerId,
    'join_code': joinCode,
    'announcement': announcement,
    'announcement_author': announcementAuthor,
    'subscription_tier': subscriptionTier.name,
    'enabled_modules': enabledModules,
    'created_at': createdAt.toIso8601String(),
    'welcome_dismissed': welcomeDismissed,
    'weekly_digest': weeklyDigest,
  };

  Family copyWith({
    String? id, String? name, String? ownerId, String? joinCode,
    String? announcement, String? announcementAuthor,
    SubscriptionTier? subscriptionTier, List<String>? enabledModules,
    DateTime? createdAt, bool? welcomeDismissed, bool? weeklyDigest,
  }) => Family(
    id: id ?? this.id,
    name: name ?? this.name,
    ownerId: ownerId ?? this.ownerId,
    joinCode: joinCode ?? this.joinCode,
    announcement: announcement ?? this.announcement,
    announcementAuthor: announcementAuthor ?? this.announcementAuthor,
    subscriptionTier: subscriptionTier ?? this.subscriptionTier,
    enabledModules: enabledModules ?? this.enabledModules,
    createdAt: createdAt ?? this.createdAt,
    welcomeDismissed: welcomeDismissed ?? this.welcomeDismissed,
    weeklyDigest: weeklyDigest ?? this.weeklyDigest,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FamilyMember
// ─────────────────────────────────────────────────────────────────────────────

class FamilyMember {
  final String userId;
  final String familyId;
  final Role role;
  final List<String>? moduleAccess;

  const FamilyMember({
    required this.userId,
    required this.familyId,
    this.role = Role.MEMBER,
    this.moduleAccess,
  });

  factory FamilyMember.fromJson(Map<String, dynamic> j) => FamilyMember(
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    role: roleFromString(j['role'] as String?),
    moduleAccess: j['module_access'] != null
        ? _strList(j['module_access'] ?? j['moduleAccess'])
        : null,
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'family_id': familyId,
    'role': role.name,
    'module_access': moduleAccess,
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

  const Task({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.title,
    this.notes,
    this.dueDate,
    this.dueTime,
    this.reminderMinutes,
    this.priority = Priority.MEDIUM,
    this.completed = false,
    this.completedBy,
    this.updatedBy,
    this.visibility = Visibility.FAMILY,
    this.assignees = const [],
    this.tags = const [],
    this.recurrence = Recurrence.NONE,
  });

  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    title: j['title'] as String? ?? '',
    notes: j['notes'] as String?,
    dueDate: _parseDateOpt(j['due_date'] ?? j['dueDate']),
    dueTime: (j['due_time'] ?? j['dueTime']) as String?,
    reminderMinutes: j['reminder_minutes'] as int? ?? j['reminderMinutes'] as int?,
    priority: priorityFromString(j['priority'] as String?),
    completed: (j['completed'] ?? false) as bool,
    completedBy: (j['completed_by'] ?? j['completedBy']) as String?,
    updatedBy: (j['updated_by'] ?? j['updatedBy']) as String?,
    visibility: visibilityFromString(j['visibility'] as String?),
    assignees: _strList(j['assignees']),
    tags: _strList(j['tags']),
    recurrence: recurrenceFromString(j['recurrence'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'notes': notes,
    'due_date': dueDate?.toIso8601String(),
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
  };

  Task copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    String? notes, DateTime? dueDate, String? dueTime, int? reminderMinutes,
    Priority? priority, bool? completed, String? completedBy, String? updatedBy,
    Visibility? visibility, List<String>? assignees, List<String>? tags,
    Recurrence? recurrence,
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
  final List<String> checklist;
  final double? budgetEstimate;
  final String? externalCalendarId;
  final Recurrence recurrence;

  const CalendarEvent({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.title,
    this.description,
    this.location,
    required this.start,
    required this.end,
    this.visibility = Visibility.FAMILY,
    this.checklist = const [],
    this.budgetEstimate,
    this.externalCalendarId,
    this.recurrence = Recurrence.NONE,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> j) => CalendarEvent(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    location: j['location'] as String?,
    start: _parseDate(j['start']),
    end: _parseDate(j['end']),
    visibility: visibilityFromString(j['visibility'] as String?),
    checklist: _strList(j['checklist']),
    budgetEstimate: (j['budget_estimate'] ?? j['budgetEstimate']) != null
        ? (j['budget_estimate'] ?? j['budgetEstimate'] as num).toDouble()
        : null,
    externalCalendarId: (j['external_calendar_id'] ?? j['externalCalendarId']) as String?,
    recurrence: recurrenceFromString(j['recurrence'] as String?),
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
    'checklist': checklist,
    'budget_estimate': budgetEstimate,
    'external_calendar_id': externalCalendarId,
    'recurrence': recurrence.name,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Recipe
// ─────────────────────────────────────────────────────────────────────────────

class Recipe {
  final String id;
  final String familyId;
  final String title;
  final List<String> ingredients;
  final List<String> steps;
  final int servings;
  final List<String> tags;
  final String? image;

  const Recipe({
    required this.id,
    required this.familyId,
    required this.title,
    this.ingredients = const [],
    this.steps = const [],
    this.servings = 4,
    this.tags = const [],
    this.image,
  });

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    title: j['title'] as String? ?? '',
    ingredients: _strList(j['ingredients']),
    steps: _strList(j['steps']),
    servings: (j['servings'] as int?) ?? 4,
    tags: _strList(j['tags']),
    image: j['image'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'title': title,
    'ingredients': ingredients,
    'steps': steps,
    'servings': servings,
    'tags': tags,
    'image': image,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// MealPlanEntry
// ─────────────────────────────────────────────────────────────────────────────

class MealPlanEntry {
  final String id;
  final String familyId;
  final DateTime date;
  final MealType mealType;
  final String? recipeId;
  final String? customMeal;

  const MealPlanEntry({
    required this.id,
    required this.familyId,
    required this.date,
    required this.mealType,
    this.recipeId,
    this.customMeal,
  });

  factory MealPlanEntry.fromJson(Map<String, dynamic> j) => MealPlanEntry(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    date: _parseDate(j['date']),
    mealType: mealTypeFromString((j['meal_type'] ?? j['mealType']) as String?),
    recipeId: (j['recipe_id'] ?? j['recipeId']) as String?,
    customMeal: (j['custom_meal'] ?? j['customMeal']) as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'date': date.toIso8601String(),
    'meal_type': mealType.name,
    'recipe_id': recipeId,
    'custom_meal': customMeal,
  };
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

  const ListItem({
    required this.id,
    required this.text,
    this.quantity,
    this.checked = false,
    this.notes,
    this.aiCategory,
  });

  factory ListItem.fromJson(Map<String, dynamic> j) => ListItem(
    id: j['id'] as String? ?? '',
    text: j['text'] as String? ?? '',
    quantity: j['quantity'] as String?,
    checked: (j['checked'] ?? false) as bool,
    notes: j['notes'] as String?,
    aiCategory: (j['ai_category'] ?? j['aiCategory']) as String?,
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
}

class ShoppingList {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final List<ListItem> items;
  final ListCategory category;
  final Visibility visibility;

  const ShoppingList({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.title,
    this.items = const [],
    this.category = ListCategory.GROCERY,
    this.visibility = Visibility.FAMILY,
  });

  factory ShoppingList.fromJson(Map<String, dynamic> j) => ShoppingList(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    title: j['title'] as String? ?? '',
    items: _parseList(j['items'], ListItem.fromJson),
    category: listCategoryFromString(j['category'] as String?),
    visibility: visibilityFromString(j['visibility'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'items': items.map((e) => e.toJson()).toList(),
    'category': category.name,
    'visibility': visibility.name,
  };
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

  const DevotionalEntry({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.title,
    this.scripture,
    this.content,
    this.reflectionPrompts = const [],
    this.prayer,
    this.userPrayer,
    this.tags = const [],
    required this.date,
    this.visibility = Visibility.FAMILY,
  });

  factory DevotionalEntry.fromJson(Map<String, dynamic> j) => DevotionalEntry(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    title: j['title'] as String? ?? '',
    scripture: j['scripture'] as String?,
    content: j['content'] as String?,
    reflectionPrompts: _strList(j['reflection_prompts'] ?? j['reflectionPrompts']),
    prayer: j['prayer'] as String?,
    userPrayer: (j['user_prayer'] ?? j['userPrayer']) as String?,
    tags: _strList(j['tags']),
    date: _parseDate(j['date']),
    visibility: visibilityFromString(j['visibility'] as String?),
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
  };
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
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
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

// ─────────────────────────────────────────────────────────────────────────────
// BudgetCategory
// ─────────────────────────────────────────────────────────────────────────────

class BudgetCategory {
  final String id;
  final String familyId;
  final String creatorId;
  final String name;
  final double limit;
  final String? color;
  final Visibility visibility;

  const BudgetCategory({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.name,
    this.limit = 0,
    this.color,
    this.visibility = Visibility.FAMILY,
  });

  factory BudgetCategory.fromJson(Map<String, dynamic> j) => BudgetCategory(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    name: j['name'] as String? ?? '',
    limit: ((j['limit'] as num?) ?? 0).toDouble(),
    color: j['color'] as String?,
    visibility: visibilityFromString(j['visibility'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'name': name,
    'limit': limit,
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
  final String? categoryId;
  final double amount;
  final TransactionType type;
  final DateTime date;
  final String? description;
  final Visibility visibility;

  const Transaction({
    required this.id,
    required this.familyId,
    required this.creatorId,
    this.categoryId,
    required this.amount,
    this.type = TransactionType.EXPENSE,
    required this.date,
    this.description,
    this.visibility = Visibility.FAMILY,
  });

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    categoryId: (j['category_id'] ?? j['categoryId']) as String?,
    amount: ((j['amount'] as num?) ?? 0).toDouble(),
    type: transactionTypeFromString(j['type'] as String?),
    date: _parseDate(j['date']),
    description: j['description'] as String?,
    visibility: visibilityFromString(j['visibility'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'category_id': categoryId,
    'amount': amount,
    'type': type.name,
    'date': date.toIso8601String(),
    'description': description,
    'visibility': visibility.name,
  };
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
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    module: j['module'] as String? ?? '',
    prompt: j['prompt'] as String? ?? '',
    response: j['response'] as String? ?? '',
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
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
  final String label;
  final String? icon;
  final String? color;
  final DateTime createdAt;
  final int order;

  const DailyHabit({
    required this.id,
    required this.userId,
    required this.label,
    this.icon,
    this.color,
    required this.createdAt,
    this.order = 0,
  });

  factory DailyHabit.fromJson(Map<String, dynamic> j) => DailyHabit(
    id: j['id'] as String? ?? '',
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
    label: j['label'] as String? ?? '',
    icon: j['icon'] as String?,
    color: j['color'] as String?,
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
    order: (j['order'] as int?) ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'label': label,
    'icon': icon,
    'color': color,
    'created_at': createdAt.toIso8601String(),
    'order': order,
  };
}

class DailyHabitCompletion {
  final String id;
  final String habitId;
  final String userId;
  final DateTime date;
  final DateTime completedAt;

  const DailyHabitCompletion({
    required this.id,
    required this.habitId,
    required this.userId,
    required this.date,
    required this.completedAt,
  });

  factory DailyHabitCompletion.fromJson(Map<String, dynamic> j) =>
      DailyHabitCompletion(
    id: j['id'] as String? ?? '',
    habitId: (j['habit_id'] ?? j['habitId']) as String? ?? '',
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
    date: _parseDate(j['date']),
    completedAt: _parseDate(j['completed_at'] ?? j['completedAt']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'habit_id': habitId,
    'user_id': userId,
    'date': date.toIso8601String(),
    'completed_at': completedAt.toIso8601String(),
  };
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
  final String? reward;
  final ChoreFrequency frequency;
  final List<int> daysOfWeek;
  final List<String> assignees;
  final String? color;
  final Visibility visibility;
  final DateTime createdAt;
  final bool requiresApproval;

  const Chore({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.title,
    this.description,
    this.icon,
    this.points = 0,
    this.reward,
    this.frequency = ChoreFrequency.DAILY,
    this.daysOfWeek = const [],
    this.assignees = const [],
    this.color,
    this.visibility = Visibility.FAMILY,
    required this.createdAt,
    this.requiresApproval = false,
  });

  factory Chore.fromJson(Map<String, dynamic> j) => Chore(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    icon: j['icon'] as String?,
    points: (j['points'] as int?) ?? 0,
    reward: j['reward'] as String?,
    frequency: choreFrequencyFromString(j['frequency'] as String?),
    daysOfWeek: _intList(j['days_of_week'] ?? j['daysOfWeek']),
    assignees: _strList(j['assignees']),
    color: j['color'] as String?,
    visibility: visibilityFromString(j['visibility'] as String?),
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
    requiresApproval: (j['requires_approval'] ?? j['requiresApproval'] ?? false) as bool,
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
  };
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
    choreId: (j['chore_id'] ?? j['choreId']) as String? ?? '',
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    date: _parseDate(j['date']),
    completedAt: _parseDate(j['completed_at'] ?? j['completedAt']),
    approvalStatus: approvalStatusFromString((j['approval_status'] ?? j['approvalStatus']) as String?),
    approvedBy: (j['approved_by'] ?? j['approvedBy']) as String?,
    approvedAt: _parseDateOpt(j['approved_at'] ?? j['approvedAt']),
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
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    cost: (j['cost'] as int?) ?? 0,
    icon: j['icon'] as String?,
    active: (j['active'] ?? true) as bool,
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
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
  });

  factory RewardRedemption.fromJson(Map<String, dynamic> j) => RewardRedemption(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
    rewardId: (j['reward_id'] ?? j['rewardId']) as String? ?? '',
    rewardTitle: (j['reward_title'] ?? j['rewardTitle']) as String? ?? '',
    amount: (j['amount'] as int?) ?? 0,
    status: redemptionStatusFromString(j['status'] as String?),
    requestedAt: _parseDate(j['requested_at'] ?? j['requestedAt']),
    resolvedAt: _parseDateOpt(j['resolved_at'] ?? j['resolvedAt']),
    resolvedBy: (j['resolved_by'] ?? j['resolvedBy']) as String?,
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
  };
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

  const SavingsGoal({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.title,
    this.icon,
    this.imageUrl,
    this.targetAmount = 0,
    this.savedAmount = 0,
    required this.createdAt,
    this.completedAt,
  });

  factory SavingsGoal.fromJson(Map<String, dynamic> j) => SavingsGoal(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
    title: j['title'] as String? ?? '',
    icon: j['icon'] as String?,
    imageUrl: (j['image_url'] ?? j['imageUrl']) as String?,
    targetAmount: ((j['target_amount'] ?? j['targetAmount'] as num?) ?? 0).toDouble(),
    savedAmount: ((j['saved_amount'] ?? j['savedAmount'] as num?) ?? 0).toDouble(),
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
    completedAt: _parseDateOpt(j['completed_at'] ?? j['completedAt']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'title': title,
    'icon': icon,
    'image_url': imageUrl,
    'target_amount': targetAmount,
    'saved_amount': savedAmount,
    'created_at': createdAt.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Poll, PollOption, PollVote
// ─────────────────────────────────────────────────────────────────────────────

class PollOption {
  final String id;
  final String text;

  const PollOption({required this.id, required this.text});

  factory PollOption.fromJson(Map<String, dynamic> j) => PollOption(
    id: j['id'] as String? ?? '',
    text: j['text'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'text': text};
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

  const Poll({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.question,
    this.options = const [],
    this.allowMultiple = false,
    this.anonymous = false,
    this.status = PollStatus.OPEN,
    this.deadline,
    this.visibility = Visibility.FAMILY,
    required this.createdAt,
  });

  factory Poll.fromJson(Map<String, dynamic> j) => Poll(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    question: j['question'] as String? ?? '',
    options: _parseList(j['options'], PollOption.fromJson),
    allowMultiple: (j['allow_multiple'] ?? j['allowMultiple'] ?? false) as bool,
    anonymous: (j['anonymous'] ?? false) as bool,
    status: pollStatusFromString(j['status'] as String?),
    deadline: _parseDateOpt(j['deadline']),
    visibility: visibilityFromString(j['visibility'] as String?),
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
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
  };
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
    pollId: (j['poll_id'] ?? j['pollId']) as String? ?? '',
    optionId: (j['option_id'] ?? j['optionId']) as String? ?? '',
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    votedAt: _parseDate(j['voted_at'] ?? j['votedAt']),
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
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
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
  final DateTime date;
  final DateTime? answeredAt;
  final Visibility visibility;

  const PrayerWallEntry({
    required this.id,
    required this.familyId,
    required this.creatorId,
    this.type = PrayerWallType.REQUEST,
    required this.text,
    this.originalRequestId,
    this.reactions = const [],
    required this.date,
    this.answeredAt,
    this.visibility = Visibility.FAMILY,
  });

  factory PrayerWallEntry.fromJson(Map<String, dynamic> j) => PrayerWallEntry(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    type: prayerWallTypeFromString(j['type'] as String?),
    text: j['text'] as String? ?? '',
    originalRequestId: (j['original_request_id'] ?? j['originalRequestId']) as String?,
    reactions: _parseList(j['reactions'], Reaction.fromJson),
    date: _parseDate(j['date']),
    answeredAt: _parseDateOpt(j['answered_at'] ?? j['answeredAt']),
    visibility: visibilityFromString(j['visibility'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'type': type.name,
    'text': text,
    'original_request_id': originalRequestId,
    'reactions': reactions.map((r) => r.toJson()).toList(),
    'date': date.toIso8601String(),
    'answered_at': answeredAt?.toIso8601String(),
    'visibility': visibility.name,
  };
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
    final rawReactions = j['reactions'];
    Map<String, List<String>> parsedReactions = {};
    if (rawReactions is Map) {
      rawReactions.forEach((k, v) {
        parsedReactions[k.toString()] = (v as List).map((e) => e.toString()).toList();
      });
    }
    return ChatMessage(
      id: j['id'] as String? ?? '',
      familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
      userId: (j['user_id'] ?? j['userId']) as String? ?? '',
      text: j['text'] as String? ?? '',
      replyToId: (j['reply_to_id'] ?? j['replyToId']) as String?,
      reactions: parsedReactions,
      editedAt: _parseDateOpt(j['edited_at'] ?? j['editedAt']),
      createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'text': text,
    'reply_to_id': replyToId,
    'reactions': reactions,
    'edited_at': editedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };
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
  final int reminderDays;
  final Visibility visibility;
  final DateTime createdAt;

  const SpecialDate({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.name,
    this.type = SpecialDateType.BIRTHDAY,
    required this.month,
    required this.day,
    this.year,
    this.emoji,
    this.notes,
    this.reminderDays = 7,
    this.visibility = Visibility.FAMILY,
    required this.createdAt,
  });

  factory SpecialDate.fromJson(Map<String, dynamic> j) => SpecialDate(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    name: j['name'] as String? ?? '',
    type: specialDateTypeFromString(j['type'] as String?),
    month: (j['month'] as int?) ?? 1,
    day: (j['day'] as int?) ?? 1,
    year: j['year'] as int?,
    emoji: j['emoji'] as String?,
    notes: j['notes'] as String?,
    reminderDays: (j['reminder_days'] ?? j['reminderDays'] as int?) ?? 7,
    visibility: visibilityFromString(j['visibility'] as String?),
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'name': name,
    'type': type.name,
    'month': month,
    'day': day,
    'year': year,
    'emoji': emoji,
    'notes': notes,
    'reminder_days': reminderDays,
    'visibility': visibility.name,
    'created_at': createdAt.toIso8601String(),
  };
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

  const FamilyPhoto({
    required this.id,
    required this.familyId,
    required this.uploaderId,
    required this.url,
    this.caption,
    this.takenAt,
    required this.createdAt,
    this.reactions = const [],
    this.milestoneId,
    this.tags = const [],
    this.visibility = Visibility.FAMILY,
  });

  factory FamilyPhoto.fromJson(Map<String, dynamic> j) => FamilyPhoto(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    uploaderId: (j['uploader_id'] ?? j['uploaderId']) as String? ?? '',
    url: j['url'] as String? ?? '',
    caption: j['caption'] as String?,
    takenAt: _parseDateOpt(j['taken_at'] ?? j['takenAt']),
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
    reactions: _parseList(j['reactions'], Reaction.fromJson),
    milestoneId: (j['milestone_id'] ?? j['milestoneId']) as String?,
    tags: _strList(j['tags']),
    visibility: visibilityFromString(j['visibility'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'uploader_id': uploaderId,
    'url': url,
    'caption': caption,
    'taken_at': takenAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'reactions': reactions.map((r) => r.toJson()).toList(),
    'milestone_id': milestoneId,
    'tags': tags,
    'visibility': visibility.name,
  };
}

class Milestone {
  final String id;
  final String familyId;
  final String? childId;
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
    this.childId,
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
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    childId: (j['child_id'] ?? j['childId']) as String?,
    title: j['title'] as String? ?? '',
    emoji: j['emoji'] as String?,
    category: j['category'] as String?,
    date: _parseDate(j['date']),
    notes: j['notes'] as String?,
    photoIds: _strList(j['photo_ids'] ?? j['photoIds']),
    ageLabel: (j['age_label'] ?? j['ageLabel']) as String?,
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
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
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
    latitude: ((j['latitude'] as num?) ?? 0).toDouble(),
    longitude: ((j['longitude'] as num?) ?? 0).toDouble(),
    accuracy: (j['accuracy'] as num?)?.toDouble(),
    placeName: (j['place_name'] ?? j['placeName']) as String?,
    nearPlace: (j['near_place'] ?? j['nearPlace']) as String?,
    isSharing: (j['is_sharing'] ?? j['isSharing'] ?? false) as bool,
    updatedAt: _parseDate(j['updated_at'] ?? j['updatedAt']),
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
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    creatorId: (j['creator_id'] ?? j['creatorId']) as String? ?? '',
    name: j['name'] as String? ?? '',
    emoji: j['emoji'] as String?,
    latitude: ((j['latitude'] as num?) ?? 0).toDouble(),
    longitude: ((j['longitude'] as num?) ?? 0).toDouble(),
    radiusMetres: ((j['radius_metres'] ?? j['radiusMetres'] as num?) ?? 100).toDouble(),
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
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
    startDate: _parseDateOpt(j['start_date'] ?? j['startDate']),
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
    diagnosedDate: _parseDateOpt(j['diagnosed_date'] ?? j['diagnosedDate']),
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
    nextDue: _parseDateOpt(j['next_due'] ?? j['nextDue']),
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

  const HealthRecord({
    required this.id,
    required this.familyId,
    required this.memberId,
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
    required this.updatedAt,
  });

  factory HealthRecord.fromJson(Map<String, dynamic> j) => HealthRecord(
    id: j['id'] as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    memberId: (j['member_id'] ?? j['memberId']) as String? ?? '',
    updatedBy: (j['updated_by'] ?? j['updatedBy']) as String?,
    bloodType: bloodTypeFromString((j['blood_type'] ?? j['bloodType']) as String?),
    allergies: _parseList(j['allergies'], HealthAllergy.fromJson),
    medications: _parseList(j['medications'], HealthMedication.fromJson),
    conditions: _parseList(j['conditions'], HealthCondition.fromJson),
    immunizations: _parseList(j['immunizations'], HealthImmunization.fromJson),
    emergencyContacts: _parseList(j['emergency_contacts'] ?? j['emergencyContacts'], EmergencyContact.fromJson),
    doctorName: (j['doctor_name'] ?? j['doctorName']) as String?,
    doctorPhone: (j['doctor_phone'] ?? j['doctorPhone']) as String?,
    insuranceProvider: (j['insurance_provider'] ?? j['insuranceProvider']) as String?,
    insurancePolicyNumber: (j['insurance_policy_number'] ?? j['insurancePolicyNumber']) as String?,
    notes: j['notes'] as String?,
    updatedAt: _parseDate(j['updated_at'] ?? j['updatedAt']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'member_id': memberId,
    'updated_by': updatedBy,
    'blood_type': bloodType.name,
    'allergies': allergies.map((e) => e.toJson()).toList(),
    'medications': medications.map((e) => e.toJson()).toList(),
    'conditions': conditions.map((e) => e.toJson()).toList(),
    'immunizations': immunizations.map((e) => e.toJson()).toList(),
    'emergency_contacts': emergencyContacts.map((e) => e.toJson()).toList(),
    'doctor_name': doctorName,
    'doctor_phone': doctorPhone,
    'insurance_provider': insuranceProvider,
    'insurance_policy_number': insurancePolicyNumber,
    'notes': notes,
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

  const PeriodCycle({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.startDate,
    this.endDate,
    this.flowLevel = FlowLevel.MEDIUM,
    this.notes,
    required this.createdAt,
  });

  factory PeriodCycle.fromJson(Map<String, dynamic> j) => PeriodCycle(
    id: j['id'] as String? ?? '',
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    startDate: _parseDate(j['start_date'] ?? j['startDate']),
    endDate: _parseDateOpt(j['end_date'] ?? j['endDate']),
    flowLevel: flowLevelFromString((j['flow_level'] ?? j['flowLevel']) as String?),
    notes: j['notes'] as String?,
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'family_id': familyId,
    'start_date': startDate.toIso8601String(),
    'end_date': endDate?.toIso8601String(),
    'flow_level': flowLevel.name,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
  };
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

  factory PeriodSymptomLog.fromJson(Map<String, dynamic> j) => PeriodSymptomLog(
    id: j['id'] as String? ?? '',
    userId: (j['user_id'] ?? j['userId']) as String? ?? '',
    familyId: (j['family_id'] ?? j['familyId']) as String? ?? '',
    date: _parseDate(j['date']),
    symptoms: _strList(j['symptoms']),
    mood: j['mood'] != null ? cycleMoodFromString(j['mood'] as String?) : null,
    painLevel: j['pain_level'] as int? ?? j['painLevel'] as int?,
    notes: j['notes'] as String?,
    createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'family_id': familyId,
    'date': date.toIso8601String(),
    'symptoms': symptoms,
    'mood': mood?.name,
    'pain_level': painLevel,
    'notes': notes,
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
  });

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
    weeklyDigest: (j['weekly_digest'] ?? j['weeklyDigest'] ?? true) as bool,
    webPushEnabled: (j['web_push_enabled'] ?? j['webPushEnabled'] ?? false) as bool,
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
  };

  NotificationPrefs copyWith({
    bool? chat, bool? tasks, bool? calendar, bool? chores, bool? lists,
    bool? polls, bool? meals, bool? birthdays, bool? photos, bool? location,
    bool? weeklyDigest, bool? webPushEnabled,
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
  );
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
  final List<dynamic> fitnessPlans;
  final List<BudgetCategory> budgetCategories;
  final List<Transaction> transactions;
  final List<AIHistory> aiHistory;
  final List<DailyHabit> dailyHabits;
  final List<DailyHabitCompletion> dailyHabitCompletions;
  final List<Chore> chores;
  final List<ChoreCompletion> choreCompletions;
  final List<Poll> polls;
  final List<PollVote> pollVotes;
  final List<RewardItem> rewardItems;
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
    this.fitnessPlans = const [],
    this.budgetCategories = const [],
    this.transactions = const [],
    this.aiHistory = const [],
    this.dailyHabits = const [],
    this.dailyHabitCompletions = const [],
    this.chores = const [],
    this.choreCompletions = const [],
    this.polls = const [],
    this.pollVotes = const [],
    this.rewardItems = const [],
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
    fitnessPlans: (j['fitnessPlans'] ?? j['fitness_plans']) is List
        ? (j['fitnessPlans'] ?? j['fitness_plans']) as List
        : [],
    budgetCategories: _parseList(j['budgetCategories'] ?? j['budget_categories'], BudgetCategory.fromJson),
    transactions: _parseList(j['transactions'], Transaction.fromJson),
    aiHistory: _parseList(j['aiHistory'] ?? j['ai_history'], AIHistory.fromJson),
    dailyHabits: _parseList(j['dailyHabits'] ?? j['daily_habits'], DailyHabit.fromJson),
    dailyHabitCompletions: _parseList(j['dailyHabitCompletions'] ?? j['daily_habit_completions'], DailyHabitCompletion.fromJson),
    chores: _parseList(j['chores'], Chore.fromJson),
    choreCompletions: _parseList(j['choreCompletions'] ?? j['chore_completions'], ChoreCompletion.fromJson),
    polls: _parseList(j['polls'], Poll.fromJson),
    pollVotes: _parseList(j['pollVotes'] ?? j['poll_votes'], PollVote.fromJson),
    rewardItems: _parseList(j['rewardItems'] ?? j['reward_items'], RewardItem.fromJson),
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
    fitnessPlans: cloud['fitness_plans'] is List ? cloud['fitness_plans'] as List : [],
    budgetCategories: _parseList(cloud['budget_categories'], BudgetCategory.fromJson),
    transactions: _parseList(cloud['transactions'], Transaction.fromJson),
    aiHistory: _parseList(cloud['ai_history'], AIHistory.fromJson),
    dailyHabits: _parseList(cloud['daily_habits'], DailyHabit.fromJson),
    dailyHabitCompletions: _parseList(cloud['daily_habit_completions'], DailyHabitCompletion.fromJson),
    chores: _parseList(cloud['chores'], Chore.fromJson),
    choreCompletions: _parseList(cloud['chore_completions'], ChoreCompletion.fromJson),
    polls: _parseList(cloud['polls'], Poll.fromJson),
    pollVotes: _parseList(cloud['poll_votes'], PollVote.fromJson),
    rewardItems: _parseList(cloud['reward_items'], RewardItem.fromJson),
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
    'fitnessPlans': fitnessPlans,
    'budgetCategories': budgetCategories.map((e) => e.toJson()).toList(),
    'transactions': transactions.map((e) => e.toJson()).toList(),
    'aiHistory': aiHistory.map((e) => e.toJson()).toList(),
    'dailyHabits': dailyHabits.map((e) => e.toJson()).toList(),
    'dailyHabitCompletions': dailyHabitCompletions.map((e) => e.toJson()).toList(),
    'chores': chores.map((e) => e.toJson()).toList(),
    'choreCompletions': choreCompletions.map((e) => e.toJson()).toList(),
    'polls': polls.map((e) => e.toJson()).toList(),
    'pollVotes': pollVotes.map((e) => e.toJson()).toList(),
    'rewardItems': rewardItems.map((e) => e.toJson()).toList(),
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
    List<dynamic>? fitnessPlans,
    List<BudgetCategory>? budgetCategories,
    List<Transaction>? transactions,
    List<AIHistory>? aiHistory,
    List<DailyHabit>? dailyHabits,
    List<DailyHabitCompletion>? dailyHabitCompletions,
    List<Chore>? chores,
    List<ChoreCompletion>? choreCompletions,
    List<Poll>? polls,
    List<PollVote>? pollVotes,
    List<RewardItem>? rewardItems,
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
  }) => AppDB(
    users: users ?? this.users,
    families: families ?? this.families,
    familyMembers: familyMembers ?? this.familyMembers,
    tasks: tasks ?? this.tasks,
    events: events ?? this.events,
    recipes: recipes ?? this.recipes,
    mealPlans: mealPlans ?? this.mealPlans,
    lists: lists ?? this.lists,
    devotionals: devotionals ?? this.devotionals,
    fitness: fitness ?? this.fitness,
    fitnessPlans: fitnessPlans ?? this.fitnessPlans,
    budgetCategories: budgetCategories ?? this.budgetCategories,
    transactions: transactions ?? this.transactions,
    aiHistory: aiHistory ?? this.aiHistory,
    dailyHabits: dailyHabits ?? this.dailyHabits,
    dailyHabitCompletions: dailyHabitCompletions ?? this.dailyHabitCompletions,
    chores: chores ?? this.chores,
    choreCompletions: choreCompletions ?? this.choreCompletions,
    polls: polls ?? this.polls,
    pollVotes: pollVotes ?? this.pollVotes,
    rewardItems: rewardItems ?? this.rewardItems,
    rewardRedemptions: rewardRedemptions ?? this.rewardRedemptions,
    savingsGoals: savingsGoals ?? this.savingsGoals,
    prayerWall: prayerWall ?? this.prayerWall,
    specialDates: specialDates ?? this.specialDates,
    familyPhotos: familyPhotos ?? this.familyPhotos,
    milestones: milestones ?? this.milestones,
    savedPlaces: savedPlaces ?? this.savedPlaces,
    userLocations: userLocations ?? this.userLocations,
    messages: messages ?? this.messages,
    healthRecords: healthRecords ?? this.healthRecords,
    periodCycles: periodCycles ?? this.periodCycles,
    periodSymptoms: periodSymptoms ?? this.periodSymptoms,
    notificationPrefs: notificationPrefs ?? this.notificationPrefs,
  );
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

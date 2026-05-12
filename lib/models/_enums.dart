// lib/models/_enums.dart
// ignore_for_file: constant_identifier_names

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

enum ExternalCalendarType { google, icsUrl, microsoft }

ExternalCalendarType externalCalendarTypeFromString(String? s) {
  switch (s) {
    case 'google': return ExternalCalendarType.google;
    case 'icsUrl': return ExternalCalendarType.icsUrl;
    case 'microsoft': return ExternalCalendarType.microsoft;
    default: return ExternalCalendarType.icsUrl;
  }
}

enum DevotionalNoteKind {
  thought,
  prayer;

  String get wireValue {
    switch (this) {
      case DevotionalNoteKind.thought:
        return 'thought';
      case DevotionalNoteKind.prayer:
        return 'prayer';
    }
  }

  static DevotionalNoteKind fromWire(String? raw) {
    if (raw == 'prayer') return DevotionalNoteKind.prayer;
    return DevotionalNoteKind.thought;
  }
}

/// How [BudgetCategoryRecord.limit] is interpreted for envelope math.
enum BudgetLimitPeriod {
  /// One cap for the whole calendar month (+ rollover).
  monthly,
  /// [limit] is per 7-day bucket; month is split into consecutive buckets (+ rollover).
  weekly,
}

BudgetLimitPeriod budgetLimitPeriodFromString(String? s) {
  switch (s) {
    case 'weekly':
      return BudgetLimitPeriod.weekly;
    default:
      return BudgetLimitPeriod.monthly;
  }
}


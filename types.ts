
export type Role = 'OWNER' | 'ADMIN' | 'MEMBER';
export type Visibility = 'PRIVATE' | 'FAMILY' | 'SPECIFIC';

// Re-export so modules only need to import from types
export type { FamilySettings } from './services/locale';

/**
 * Subscription tier for a family.
 * trial → 14-day free trial, full access
 * base  → $9/month — everything except AI features
 * ai    → $15/month — everything including AI features
 *
 * Families with no tier set default to 'ai' during beta.
 */
export type SubscriptionTier = 'trial' | 'base' | 'ai';

export interface User {
  id: string;
  name: string;
  email: string;
  avatar?: string;
}

export interface Family {
  id: string;
  name: string;
  ownerId: string;
  joinCode: string;
  announcement?: string;
  announcementAuthor?: string;
  /** Subscription tier — undefined defaults to 'ai' during beta */
  subscriptionTier?: SubscriptionTier;
  /**
   * Modules enabled for this family (owner-controlled).
   * undefined = all modules enabled (default / backward compat).
   * Populated = only these route paths are shown in the nav.
   * Dashboard (/) and AI History (/ai/history) are always shown.
   */
  enabledModules?: string[];
  /** Regional/locale settings for the whole family */
  settings?: import('./services/locale').FamilySettings;
  /** ISO timestamp of when the family was created (for trial countdown) */
  createdAt?: string;
  /** Set to true once the owner dismisses the welcome/onboarding banner */
  welcomeDismissed?: boolean;
  /**
   * Controls the weekly digest push notification.
   * undefined / true = send digest (default); false = opted out.
   */
  weeklyDigest?: boolean;
  /**
   * UTC day-of-week (0=Sun … 6=Sat) when the digest fires.
   * Stored as UTC; the UI converts from/to the device's local timezone.
   * Defaults to 0 (Sunday) when not set.
   */
  weeklyDigestDay?: number;
  /**
   * UTC hour (0–23) when the digest fires.
   * Defaults to 8 (08:00 UTC) when not set.
   */
  weeklyDigestHour?: number;
}

export interface FamilyMember {
  userId: string;
  familyId: string;
  role: Role;
  /** undefined = full access; populated array = restricted to these route paths */
  moduleAccess?: string[];
}

export type Recurrence = 'NONE' | 'DAILY' | 'WEEKLY' | 'MONTHLY';

export interface Task {
  id: string;
  familyId: string;
  creatorId: string;
  title: string;
  notes?: string;
  dueDate?: string;
  /** Time of day in HH:MM (24-hour) format, e.g. "14:30" */
  dueTime?: string;
  /** Minutes before dueDate+dueTime to send a reminder notification (0 = at time, undefined = no reminder) */
  reminderMinutes?: number;
  priority: 'LOW' | 'MEDIUM' | 'HIGH';
  completed: boolean;
  /** Set to the userId who completed the task — used for targeted notifications. */
  completedBy?: string;
  /** Set to the userId who last updated the task — used for targeted notifications. */
  updatedBy?: string;
  visibility: Visibility;
  assignees: string[];
  tags: string[];
  recurrence?: Recurrence;
}

export interface CalendarEvent {
  id: string;
  familyId: string;
  creatorId: string;
  title: string;
  description?: string;
  location?: string;
  start: string;
  end: string;
  visibility: Visibility;
  checklist: { id: string; text: string; done: boolean }[];
  budgetEstimate?: number;
  externalCalendarId?: string;
  externalUid?: string;
  recurrence?: Recurrence;
}

export interface ExternalCalendar {
  id: string;
  familyId: string;
  creatorId: string;
  name: string;
  url?: string;
  /** Google Calendar ID for OAuth-connected calendars (no url needed) */
  googleCalendarId?: string;
  color: string;
  type: 'GOOGLE' | 'OUTLOOK' | 'APPLE' | 'OTHER';
  enabled: boolean;
  lastSynced?: string;
  createdAt: string;
}

export interface Recipe {
  id: string;
  familyId: string;
  title: string;
  ingredients: string[];
  steps: string[];
  servings: number;
  tags: string[];
  image?: string;
}

export interface MealPlanEntry {
  id: string;
  familyId: string;
  date: string;
  mealType: 'BREAKFAST' | 'LUNCH' | 'DINNER';
  recipeId?: string;
  customMeal?: string;
}

export interface ListItem {
  id: string;
  text: string;
  quantity?: string;
  checked: boolean;
  notes?: string;
  aiCategory?: string;
}

export interface List {
  id: string;
  familyId: string;
  creatorId: string;
  title: string;
  items: ListItem[];
  category: 'GROCERY' | 'HARDWARE' | 'PACKING' | 'OTHER';
  visibility: Visibility;
}

export interface DevotionalEntry {
  id: string;
  familyId: string;
  creatorId: string;
  title: string;
  scripture: string;
  content: string;
  reflectionPrompts: string[];
  prayer?: string;
  userPrayer?: string;
  tags: string[];
  date: string;
  visibility: Visibility;
}

export interface FitnessMetric {
  id: string;
  userId: string;
  type: 'WEIGHT' | 'STEPS' | 'WORKOUT';
  value: number;
  date: string;
  notes?: string;
}

export interface StoredFitnessPlan {
  id: string;
  userId: string;
  summary: string;
  weeklyPlan: {
    day: string;
    focus: string;
    duration: string;
    exercises: { name: string; detail: string }[];
  }[];
  tips: string[];
  profile: {
    gender: string;
    height: string;
    weight: string;
    level: string;
    location?: string;
    equipment?: string[];
  };
  createdAt: string;
}

export interface BudgetCategory {
  id: string;
  familyId: string;
  creatorId: string;
  name: string;
  limit: number;
  color: string;
  visibility: Visibility;
}

export interface Transaction {
  id: string;
  familyId: string;
  creatorId: string;
  categoryId: string;
  amount: number;
  type: 'INCOME' | 'EXPENSE';
  date: string;
  description: string;
  visibility: Visibility;
}

export interface AIHistory {
  id: string;
  userId: string;
  familyId: string;
  module: string;
  prompt: string;
  response: string;
  createdAt: string;
}

export interface Chore {
  id: string;
  familyId: string;
  creatorId: string;
  title: string;
  description?: string;
  icon: string;
  points: number;
  reward?: number; // AUD per completion (optional)
  frequency: 'DAILY' | 'WEEKLY' | 'CUSTOM';
  daysOfWeek: number[]; // 0=Sun, 1=Mon, ..., 6=Sat (for WEEKLY/CUSTOM)
  assignees: string[]; // user IDs; rotates if multiple
  color: string;
  visibility: Visibility;
  createdAt: string;
  /** If true, a parent/admin must approve completions before points are awarded */
  requiresApproval?: boolean;
}

export interface RewardItem {
  id: string;
  familyId: string;
  creatorId: string;
  title: string;
  description?: string;
  cost: number; // AUD
  icon: string;
  active: boolean;
  createdAt: string;
}

export interface RewardRedemption {
  id: string;
  familyId: string;
  userId: string;
  rewardId?: string;
  rewardTitle: string;
  amount: number;
  status: 'PENDING' | 'APPROVED' | 'DENIED';
  requestedAt: string;
  resolvedAt?: string;
  resolvedBy?: string;
}

export interface SavingsGoal {
  id: string;
  familyId: string;
  userId: string;
  title: string;
  icon: string;
  imageUrl?: string;
  targetAmount: number;
  savedAmount: number;
  createdAt: string;
  completedAt?: string;
}

export interface ChoreCompletion {
  id: string;
  choreId: string;
  userId: string;
  familyId: string;
  date: string; // YYYY-MM-DD
  completedAt: string;
  /** Present only when chore.requiresApproval is true */
  approvalStatus?: 'PENDING' | 'APPROVED' | 'REJECTED';
  approvedBy?: string;
  approvedAt?: string;
}

export interface PollOption {
  id: string;
  text: string;
}

export interface Poll {
  id: string;
  familyId: string;
  creatorId: string;
  question: string;
  options: PollOption[];
  allowMultiple: boolean;
  anonymous: boolean;
  status: 'OPEN' | 'CLOSED';
  deadline?: string; // ISO date string
  visibility: Visibility;
  createdAt: string;
}

export interface PollVote {
  id: string;
  pollId: string;
  optionId: string;
  userId: string;
  familyId: string;
  votedAt: string;
}

export interface DailyHabit {
  id: string;
  userId: string;
  label: string;
  icon: string;
  color: string;
  createdAt: string;
  order: number;
}

export interface DailyHabitCompletion {
  id: string;
  habitId: string;
  userId: string;
  date: string;
  completedAt: string;
}

// ---------------------------------------------------------------------------
// Prayer Wall — Gratitude, Prayer Requests & Answered Prayers
// ---------------------------------------------------------------------------

export type PrayerWallType = 'GRATITUDE' | 'REQUEST' | 'ANSWERED';

export interface PrayerWallEntry {
  id: string;
  familyId: string;
  creatorId: string;
  type: PrayerWallType;
  text: string;
  /** For ANSWERED entries: the original request id this answers */
  originalRequestId?: string;
  reactions: { userId: string; emoji: string }[];
  date: string; // ISO timestamp
  answeredAt?: string; // ISO timestamp — when a REQUEST was marked answered
  visibility: Visibility;
}

// ---------------------------------------------------------------------------
// Reading Plans — Multi-day Scripture & Reflection Plans
// ---------------------------------------------------------------------------

export interface ReadingPlanDay {
  day: number; // 1-indexed
  title: string;
  scripture: string;
  reflection: string;
  discussionQuestion: string;
}

export interface ReadingPlan {
  id: string;
  familyId: string;
  creatorId: string;
  title: string;
  description: string;
  totalDays: number;
  days: ReadingPlanDay[];
  createdAt: string;
}

export interface ReadingPlanProgress {
  id: string;
  planId: string;
  userId: string;
  familyId: string;
  /** Day numbers the user has completed */
  completedDays: number[];
  currentStreak: number;
  longestStreak: number;
  startedAt: string;
  lastCompletedAt?: string;
}

// ---------------------------------------------------------------------------
// Period / Menstrual Cycle Tracker
// ---------------------------------------------------------------------------

export type FlowLevel = 'LIGHT' | 'MEDIUM' | 'HEAVY';
export type CycleMood = 'GREAT' | 'GOOD' | 'OKAY' | 'LOW' | 'ROUGH';

export interface PeriodCycle {
  id: string;
  userId: string;
  familyId: string;
  /** ISO date YYYY-MM-DD */
  startDate: string;
  /** ISO date YYYY-MM-DD — undefined means cycle is ongoing */
  endDate?: string;
  flowLevel?: FlowLevel;
  notes?: string;
  createdAt: string;
}

export const PERIOD_SYMPTOM_OPTIONS = [
  'cramps', 'bloating', 'headache', 'backache', 'breast_tenderness',
  'mood_swings', 'fatigue', 'nausea', 'acne', 'food_cravings',
  'spotting', 'insomnia', 'hot_flashes', 'dizziness',
] as const;

export type PeriodSymptomKey = typeof PERIOD_SYMPTOM_OPTIONS[number];

export const SYMPTOM_LABELS: Record<PeriodSymptomKey, string> = {
  cramps: 'Cramps',
  bloating: 'Bloating',
  headache: 'Headache',
  backache: 'Backache',
  breast_tenderness: 'Breast Tenderness',
  mood_swings: 'Mood Swings',
  fatigue: 'Fatigue',
  nausea: 'Nausea',
  acne: 'Acne',
  food_cravings: 'Food Cravings',
  spotting: 'Spotting',
  insomnia: 'Insomnia',
  hot_flashes: 'Hot Flashes',
  dizziness: 'Dizziness',
};

export interface PeriodSymptomLog {
  id: string;
  userId: string;
  familyId: string;
  /** ISO date YYYY-MM-DD */
  date: string;
  symptoms: PeriodSymptomKey[];
  mood?: CycleMood;
  /** Pain/discomfort level 1–10 */
  painLevel?: number;
  notes?: string;
  createdAt: string;
}

/** Intimate / sexual activity log — private per-user tracking. */
export interface IntimateLog {
  id: string;
  userId: string;
  familyId: string;
  /** ISO date YYYY-MM-DD */
  date: string;
  notes?: string;
  createdAt: string;
}

// ---------------------------------------------------------------------------
// Family Chat
// ---------------------------------------------------------------------------

export interface ChatMessage {
  id: string;
  familyId: string;
  userId: string;
  /** Message text content */
  text: string;
  /** ID of message being replied to */
  replyToId?: string;
  /** emoji → array of userIds who reacted */
  reactions: Record<string, string[]>;
  /** Set if message has been edited */
  editedAt?: string;
  createdAt: string;
}

// ---------------------------------------------------------------------------
// Notification Preferences
// ---------------------------------------------------------------------------

export interface NotificationPrefs {
  chat: boolean;
  tasks: boolean;
  calendar: boolean;
  chores: boolean;
  lists: boolean;
  polls: boolean;
  meals: boolean;
  birthdays: boolean;
  photos: boolean;
  location: boolean;
  weeklyDigest: boolean;
  webPushEnabled: boolean;
}

export const DEFAULT_NOTIFICATION_PREFS: NotificationPrefs = {
  chat: true,
  tasks: true,
  calendar: true,
  chores: true,
  lists: true,
  polls: true,
  meals: false,
  birthdays: true,
  photos: false,
  location: false,
  weeklyDigest: true,
  webPushEnabled: false,
};

// ---------------------------------------------------------------------------
// AI Insights — Monthly Summary & Smart Suggestions
// ---------------------------------------------------------------------------

export interface MonthlySummary {
  id: string;
  familyId: string;
  month: string; // YYYY-MM
  headline: string;
  highlights: { module: string; icon: string; text: string }[];
  encouragement: string;
  faithNote: string;
  topAchievement: string;
  areasToFocus: string[];
  generatedAt: string;
}

export interface SmartSuggestion {
  id: string;
  type: 'meal' | 'devotional' | 'task' | 'wellness' | 'family';
  title: string;
  description: string;
  reason: string; // e.g. "You have a packed Thursday — this takes 15 min"
  timeEstimate?: string; // e.g. "5 min", "15 min"
  actionModule?: string; // route path to link to, e.g. "/meals"
}

// ---------------------------------------------------------------------------
// Birthday & Anniversary Tracker
// ---------------------------------------------------------------------------

export type SpecialDateType = 'BIRTHDAY' | 'ANNIVERSARY' | 'MEMORIAL' | 'OTHER';

export interface SpecialDate {
  id: string;
  familyId: string;
  creatorId: string;
  name: string;           // "Dad", "Grandma & Grandpa", "Our Wedding"
  type: SpecialDateType;
  month: number;          // 1–12
  day: number;            // 1–31
  year?: number;          // optional birth year for age calculation
  emoji: string;
  notes?: string;
  /** Days before the date to send reminders. e.g. [7, 1] */
  reminderDays: number[];
  visibility: Visibility;
  createdAt: string;
}

// ---------------------------------------------------------------------------
// Family Photos & Milestone Tracker
// ---------------------------------------------------------------------------

export interface FamilyPhoto {
  id: string;
  familyId: string;
  uploaderId: string;
  /** Public URL (Supabase Storage) or data: URI for small previews */
  url: string;
  caption?: string;
  /** ISO date the photo was taken (may differ from upload date) */
  takenAt: string;
  createdAt: string;
  reactions: { userId: string; emoji: string }[];
  /** Optional milestone this photo is linked to */
  milestoneId?: string;
  /** Tags for filtering, e.g. "birthday", "school" */
  tags: string[];
  visibility: Visibility;
}

export const MILESTONE_CATEGORIES = [
  'Firsts',
  'Growing Up',
  'School',
  'Activities',
  'Travel',
  'Celebrations',
  'Health',
  'Family',
] as const;

export type MilestoneCategory = typeof MILESTONE_CATEGORIES[number];

export interface Milestone {
  id: string;
  familyId: string;
  /** The family member this milestone belongs to */
  childId: string;
  title: string;
  emoji: string;
  category: MilestoneCategory;
  date: string;           // ISO YYYY-MM-DD
  notes?: string;
  /** Linked photo IDs */
  photoIds: string[];
  /** Human-readable age label, e.g. "6 months", "2 years 3 months" */
  ageLabel?: string;
  createdAt: string;
}

// ---------------------------------------------------------------------------
// Family Location Sharing
// ---------------------------------------------------------------------------

export interface SavedPlace {
  id: string;
  familyId: string;
  creatorId: string;
  name: string;           // "Home", "School", "Work", "Grandma's"
  emoji: string;
  latitude: number;
  longitude: number;
  /** Radius in metres for arrival/departure detection */
  radiusMetres: number;
  createdAt: string;
}

export interface UserLocation {
  id: string;             // userId (one record per user)
  familyId: string;
  userId: string;
  latitude: number;
  longitude: number;
  accuracy?: number;      // metres
  /** Human-readable place name from reverse geocoding */
  placeName?: string;
  /** Matched SavedPlace name if within radius */
  nearPlace?: string;
  /** Whether this user is actively sharing their location */
  isSharing: boolean;
  updatedAt: string;      // ISO timestamp
}

// ---------------------------------------------------------------------------
// Health Records
// ---------------------------------------------------------------------------

export type BloodType = 'A+' | 'A-' | 'B+' | 'B-' | 'AB+' | 'AB-' | 'O+' | 'O-' | 'Unknown';
export type AllergySeverity = 'MILD' | 'MODERATE' | 'SEVERE';

export interface HealthAllergy {
  id: string;
  name: string;
  severity: AllergySeverity;
  reaction?: string;
}

export interface HealthMedication {
  id: string;
  name: string;
  dose?: string;
  frequency?: string;
  startDate?: string;
}

export interface HealthCondition {
  id: string;
  name: string;
  diagnosedDate?: string;
  notes?: string;
}

export interface HealthImmunization {
  id: string;
  name: string;
  date?: string;
  nextDue?: string;
}

export interface EmergencyContact {
  id: string;
  name: string;
  phone: string;
  relation: string;
}

export interface HealthRecord {
  id: string;
  familyId: string;
  /** User ID this record belongs to */
  memberId: string;
  updatedBy: string;
  bloodType: BloodType;
  allergies: HealthAllergy[];
  medications: HealthMedication[];
  conditions: HealthCondition[];
  immunizations: HealthImmunization[];
  emergencyContacts: EmergencyContact[];
  doctorName?: string;
  doctorPhone?: string;
  insuranceProvider?: string;
  insurancePolicyNumber?: string;
  notes?: string;
  updatedAt: string;
}

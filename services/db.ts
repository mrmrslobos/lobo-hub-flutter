import { Task, CalendarEvent, Recipe, MealPlanEntry, List, DevotionalEntry, FitnessMetric, StoredFitnessPlan, BudgetCategory, Transaction, AIHistory, User, Family, FamilyMember, DailyHabit, DailyHabitCompletion, Chore, ChoreCompletion, Poll, PollVote, ExternalCalendar, RewardItem, RewardRedemption, SavingsGoal, PrayerWallEntry, ReadingPlan, ReadingPlanProgress, PeriodCycle, PeriodSymptomLog, IntimateLog, ChatMessage, NotificationPrefs, DEFAULT_NOTIFICATION_PREFS, SpecialDate, FamilyPhoto, Milestone, SavedPlace, UserLocation, HealthRecord } from '../types';
import { supabase, isSupabaseConfigured, getCachedSession } from './supabase';
import { broadcastChange, type FamilyBroadcast } from './realtime';
import { idbGet, idbSet } from './idb';

export interface ChangeInfo {
  userId: string;
  userName: string;
  action: string;
  module: string;
  detail: string;
}

const STORAGE_KEY = 'lobohub_db';

/**
 * Set to true once reconcileCloud has completed at least once for the
 * current session. syncToCloud uses this to gate deletions: before a full
 * reconcile the local DB is a partial view (e.g. a new user who just signed
 * up), so running deletions would wipe other users' data from Supabase.
 */
let localDbIsReconciled = false;

/**
 * Serialization chain for syncToCloud. Each invocation chains onto the
 * previous one so that concurrent calls do not interleave their
 * read-upsert-delete cycles and corrupt Supabase data.
 */
let _syncChain: Promise<void> = Promise.resolve();

/**
 * In-memory cache so getDB() stays synchronous after initDB() has been called.
 * Updated on every write; populated from IDB/localStorage at startup.
 */
let _dbCache: DB | null = null;

/**
 * Timestamp of the last LOCAL save (not cloud). Used to debounce
 * postgres_changes callbacks that fire for our own writes and would otherwise
 * briefly show stale data from a cloud fetch that races the in-flight upsert.
 */
let _lastLocalSaveMs = 0;

export function getLastLocalSaveMs(): number {
  return _lastLocalSaveMs;
}

export interface DB {
  users: User[];
  families: Family[];
  familyMembers: FamilyMember[];
  tasks: Task[];
  events: CalendarEvent[];
  recipes: Recipe[];
  mealPlans: MealPlanEntry[];
  lists: List[];
  devotionals: DevotionalEntry[];
  fitness: FitnessMetric[];
  fitnessPlans: StoredFitnessPlan[];
  budgetCategories: BudgetCategory[];
  transactions: Transaction[];
  aiHistory: AIHistory[];
  dailyHabits: DailyHabit[];
  dailyHabitCompletions: DailyHabitCompletion[];
  chores: Chore[];
  choreCompletions: ChoreCompletion[];
  polls: Poll[];
  pollVotes: PollVote[];
  externalCalendars: ExternalCalendar[];
  rewardItems: RewardItem[];
  rewardRedemptions: RewardRedemption[];
  savingsGoals: SavingsGoal[];
  prayerWall: PrayerWallEntry[];
  readingPlans: ReadingPlan[];
  readingPlanProgress: ReadingPlanProgress[];
  periodCycles: PeriodCycle[];
  periodSymptoms: PeriodSymptomLog[];
  intimateLogs: IntimateLog[];
  /** Birthday & anniversary tracker */
  specialDates: SpecialDate[];
  /** Family photo album */
  familyPhotos: FamilyPhoto[];
  /** Child/family milestones */
  milestones: Milestone[];
  /** Saved places for location sharing (Home, School, Work, etc.) */
  savedPlaces: SavedPlace[];
  /**
   * Last known location for each sharing family member.
   * Ephemeral — updated frequently, not included in weekly digest.
   */
  userLocations: UserLocation[];
  /**
   * Family chat messages.
   * Stored locally (IDB) + delivered instantly via Realtime broadcast.
   * Capped at 500 messages locally; full history persisted in Supabase.
   * noDelete=true in TABLE_MAP so the local cap never trims cloud history.
   */
  messages: ChatMessage[];
  /** Health records — one per family member (allergies, medications, emergency contacts, etc.) */
  healthRecords: HealthRecord[];
  /**
   * Per-user notification preferences stored locally.
   * webPushEnabled is set to true after a successful VAPID subscription.
   */
  notificationPrefs: NotificationPrefs;
}

const DEFAULT_DB: DB = {
  users: [],
  families: [],
  familyMembers: [],
  tasks: [],
  events: [],
  recipes: [],
  mealPlans: [],
  lists: [],
  devotionals: [],
  fitness: [],
  fitnessPlans: [],
  budgetCategories: [],
  transactions: [],
  aiHistory: [],
  dailyHabits: [],
  dailyHabitCompletions: [],
  chores: [],
  choreCompletions: [],
  polls: [],
  pollVotes: [],
  externalCalendars: [],
  rewardItems: [],
  rewardRedemptions: [],
  savingsGoals: [],
  prayerWall: [],
  readingPlans: [],
  readingPlanProgress: [],
  periodCycles: [],
  periodSymptoms: [],
  intimateLogs: [],
  specialDates: [],
  familyPhotos: [],
  milestones: [],
  savedPlaces: [],
  userLocations: [],
  messages: [],
  healthRecords: [],
  notificationPrefs: { ...DEFAULT_NOTIFICATION_PREFS },
};

/** Create a fresh default DB (avoids sharing a mutable reference to DEFAULT_DB). */
function freshDB(): DB {
  const copy = {} as Record<string, unknown>;
  for (const key of Object.keys(DEFAULT_DB) as (keyof DB)[]) {
    const val = DEFAULT_DB[key];
    copy[key] = Array.isArray(val) ? [] : (typeof val === 'object' && val ? { ...val } : val);
  }
  return copy as DB;
}

/**
 * Ensure every DB field is a valid array. Protects against malformed
 * storage data or unexpected Supabase responses that could cause
 * .filter()/.map() crashes in components.
 */
function sanitizeDB(raw: Record<string, unknown>): DB {
  const result = { ...DEFAULT_DB };
  for (const key of Object.keys(DEFAULT_DB) as (keyof DB)[]) {
    const val = raw[key];
    if (key === 'notificationPrefs') {
      // Object, not array — merge with defaults so new keys are always present
      (result as any)[key] = (val && typeof val === 'object' && !Array.isArray(val))
        ? { ...DEFAULT_NOTIFICATION_PREFS, ...(val as object) }
        : { ...DEFAULT_NOTIFICATION_PREFS };
    } else {
      (result as any)[key] = Array.isArray(val) ? val : [];
    }
  }
  // Strip any legacy plain-text password field from user rows so it is never
  // written back to storage or synced to Supabase.
  result.users = result.users.map(u => {
    const { password: _stripped, ...clean } = u as any;
    return clean;
  });
  return result;
}

const TABLE_MAP: { key: keyof DB; table: string; onConflict?: string; noDelete?: boolean }[] = [
  { key: 'users', table: 'users', onConflict: 'id' },
  // noDelete=true: each user's local cache is a PARTIAL view of these tables.
  // Deleting remote rows based on local state would wipe other users' data.
  // Explicit membership/family removal must go through direct Supabase calls.
  { key: 'families', table: 'families', onConflict: 'id', noDelete: true },
  { key: 'familyMembers', table: 'family_members', onConflict: 'user_id,family_id', noDelete: true },
  { key: 'tasks', table: 'tasks', onConflict: 'id' },
  { key: 'events', table: 'events', onConflict: 'id' },
  { key: 'recipes', table: 'recipes', onConflict: 'id' },
  { key: 'mealPlans', table: 'meal_plans', onConflict: 'id' },
  { key: 'lists', table: 'lists', onConflict: 'id' },
  { key: 'devotionals', table: 'devotionals', onConflict: 'id' },
  { key: 'fitness', table: 'fitness', onConflict: 'id' },
  { key: 'fitnessPlans', table: 'fitness_plans', onConflict: 'id' },
  { key: 'budgetCategories', table: 'budget_categories', onConflict: 'id' },
  { key: 'transactions', table: 'transactions', onConflict: 'id' },
  { key: 'aiHistory', table: 'ai_history', onConflict: 'id' },
  { key: 'dailyHabits', table: 'daily_habits', onConflict: 'id' },
  { key: 'dailyHabitCompletions', table: 'daily_habit_completions', onConflict: 'id' },
  { key: 'chores', table: 'chores', onConflict: 'id' },
  { key: 'choreCompletions', table: 'chore_completions', onConflict: 'id' },
  { key: 'polls', table: 'polls', onConflict: 'id' },
  { key: 'pollVotes', table: 'poll_votes', onConflict: 'id' },
  { key: 'externalCalendars', table: 'external_calendars', onConflict: 'id' },
  { key: 'rewardItems', table: 'reward_items', onConflict: 'id' },
  { key: 'rewardRedemptions', table: 'reward_redemptions', onConflict: 'id' },
  { key: 'savingsGoals', table: 'savings_goals', onConflict: 'id' },
  { key: 'prayerWall', table: 'prayer_wall', onConflict: 'id' },
  { key: 'readingPlans', table: 'reading_plans', onConflict: 'id' },
  { key: 'readingPlanProgress', table: 'reading_plan_progress', onConflict: 'id' },
  // Period tracker tables (user creates the Supabase tables separately)
  { key: 'periodCycles', table: 'period_cycles', onConflict: 'id' },
  { key: 'periodSymptoms', table: 'period_symptoms', onConflict: 'id' },
  { key: 'intimateLogs', table: 'intimate_logs', onConflict: 'id' },
  // New feature tables
  { key: 'specialDates', table: 'special_dates', onConflict: 'id' },
  { key: 'familyPhotos', table: 'family_photos', onConflict: 'id' },
  { key: 'milestones', table: 'milestones', onConflict: 'id' },
  { key: 'savedPlaces', table: 'saved_places', onConflict: 'id' },
  { key: 'userLocations', table: 'user_locations', onConflict: 'id' },
  { key: 'healthRecords', table: 'health_records', onConflict: 'id' },
  // noDelete=true: local messages are capped at 500 but Supabase keeps full history.
  // Deleting based on local slice would wipe old messages from the cloud.
  { key: 'messages', table: 'messages', onConflict: 'id', noDelete: true },
];

/**
 * Initialize the in-memory DB cache from IndexedDB (primary) or localStorage
 * (fallback). Must be called once at app startup before any other DB access.
 * Returns the loaded DB so the caller can render immediately with real data.
 */
export async function initDB(): Promise<DB> {
  // 1. Try IndexedDB first
  try {
    const stored = await idbGet<Record<string, unknown>>(STORAGE_KEY);
    if (stored) {
      const db = sanitizeDB({ ...DEFAULT_DB, ...stored });
      _dbCache = db;
      // Keep localStorage in sync as a fallback
      try { localStorage.setItem(STORAGE_KEY, JSON.stringify(db)); } catch { /* quota */ }
      return db;
    }
  } catch {
    // IDB unavailable — fall through to localStorage
  }

  // 2. Fall back to localStorage
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      const db = sanitizeDB({ ...DEFAULT_DB, ...parsed });
      _dbCache = db;
      // Migrate to IDB asynchronously
      idbSet(STORAGE_KEY, db).catch(() => {});
      return db;
    }
  } catch {
    console.error('Malformed DB in storage, resetting to default.');
  }

  _dbCache = freshDB();
  return DEFAULT_DB;
}

/**
 * Synchronous DB read — returns the in-memory cache populated by initDB().
 * Falls back to localStorage if initDB() hasn't run yet (should not happen
 * in normal usage but guards against race conditions during SSR/testing).
 */
export const getDB = (): DB => {
  if (_dbCache) return _dbCache;

  // Fallback: read synchronously from localStorage
  try {
    const data = localStorage.getItem(STORAGE_KEY);
    if (data) {
      const parsed = JSON.parse(data);
      _dbCache = sanitizeDB({ ...DEFAULT_DB, ...parsed });
      return _dbCache;
    }
  } catch { /* ignore */ }

  _dbCache = freshDB();
  return _dbCache;
};

export const persistLocalDB = (db: DB, change?: ChangeInfo) => {
  _dbCache = db;
  _lastLocalSaveMs = Date.now();

  // Write to IndexedDB (primary) and localStorage (fallback) asynchronously
  idbSet(STORAGE_KEY, db).catch(() => {});
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(db)); } catch { /* quota */ }

  if (isSupabaseConfigured()) {
    syncToCloud().then(() => {
      // Broadcast after successful sync so other clients fetch fresh data
      if (change) {
        broadcastChange(change);
      }
    }).catch((error) => {
      console.error('Supabase sync failed:', error);
    });
  }
};

export const saveDB = (db: DB, change?: ChangeInfo) => persistLocalDB(db, change);

/**
 * Wipe the local DB cache back to empty defaults without touching Supabase.
 * Call this on logout so stale data never appears on the next login.
 */
export const clearLocalCache = () => {
  _dbCache = freshDB();
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(DEFAULT_DB)); } catch { /* quota */ }
  idbSet(STORAGE_KEY, DEFAULT_DB).catch(() => {});
  // Reset the reconcile gate so the next login doesn't run deletions
  // with a partial DB before reconcileCloud has been called.
  localDbIsReconciled = false;
};

/**
 * Like saveDB but awaits the Supabase sync before resolving.
 * Use this in onboarding flows (e.g. handleModuleSetup) so that
 * reconcileCloud cannot race against an in-flight upsert and
 * overwrite settings (e.g. the selected region) with stale cloud data.
 */
export async function saveDBAndSync(db: DB, change?: ChangeInfo): Promise<void> {
  _dbCache = db;
  _lastLocalSaveMs = Date.now();
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(db)); } catch { /* quota */ }
  idbSet(STORAGE_KEY, db).catch(() => {});
  if (isSupabaseConfigured()) {
    try {
      await syncToCloud();
      if (change) broadcastChange(change);
    } catch (error) {
      console.error('Supabase sync failed:', error);
    }
  }
}

export async function reconcileCloud(localDb: DB): Promise<DB> {
  if (!supabase || !isSupabaseConfigured()) return localDb;

  // Push any locally-pending changes to Supabase BEFORE pulling the fresh
  // state.  Without this, data created offline (syncToCloud failed due to no
  // network) would be silently erased: reconcileCloud overwrites local arrays
  // with cloud data, and if the cloud never received the offline write the
  // item vanishes.  syncToCloud is a no-op when no auth session is cached.
  await syncToCloud();

  try {
    const fetchPromise = Promise.all(
      TABLE_MAP.map(({ table }) => supabase.from(table).select('*'))
    );

    let timer: ReturnType<typeof setTimeout>;
    const timeoutPromise = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('Supabase request timed out')), 5000);
    });

    let results: any[];
    try {
      results = await Promise.race([fetchPromise, timeoutPromise]) as any[];
    } finally {
      clearTimeout(timer!);
    }

    // Re-read the cache after the async fetch: the user may have saved changes
    // while the Supabase round-trip was in flight.
    const current = getDB();
    const merged = { ...localDb } as DB;

    TABLE_MAP.forEach(({ key, table }, idx) => {
      const res = results[idx];
      if (res.error) {
        console.warn(`Cloud read skipped for ${table}:`, res.error.message || res.error);
        return;
      }
      if (res.data && Array.isArray(res.data)) {
        if (key === 'familyMembers') {
          (merged as any)[key] = res.data.map((cloudMember: any) => {
            if ('moduleAccess' in cloudMember) {
              return cloudMember;
            }
            const localMember = (current.familyMembers || []).find(
              (m: any) => m.userId === cloudMember.userId && m.familyId === cloudMember.familyId
            );
            return localMember?.moduleAccess !== undefined
              ? { ...cloudMember, moduleAccess: localMember.moduleAccess }
              : cloudMember;
          });
        } else if (key === 'users') {
          const cloudIds = new Set(res.data.map((u: any) => u.id));
          const localOnly = (current.users || []).filter((u: any) => !cloudIds.has(u.id));
          (merged as any)[key] = [...res.data, ...localOnly];
        } else if (key === 'families') {
          const cloudIds = new Set(res.data.map((f: any) => f.id));
          const localOnly = (current.families || []).filter((f: any) => !cloudIds.has(f.id));
          (merged as any)[key] = [...res.data, ...localOnly];
        } else {
          // Cloud data wins for items in both. Preserve local-only items that
          // haven't synced yet (e.g. saved during this async reconcile window).
          const currentArr = (current as any)[key] as any[];
          if (Array.isArray(currentArr) && currentArr.length > 0) {
            const cloudIds = new Set(res.data.map((r: any) => r.id));
            const localOnly = currentArr.filter((r: any) => r.id && !cloudIds.has(r.id));
            (merged as any)[key] = localOnly.length > 0 ? [...res.data, ...localOnly] : res.data;
          } else {
            (merged as any)[key] = res.data;
          }
        }
      }
    });

    const result = sanitizeDB(merged as unknown as Record<string, unknown>);
    localDbIsReconciled = true;
    return result;
  } catch (err) {
    console.warn('Cloud reconciliation skipped:', err);
    return localDb;
  }
}

function syncToCloud(): Promise<void> {
  _syncChain = _syncChain.catch(() => {}).then(() => syncToCloudImpl(getDB()));
  return _syncChain;
}

async function syncToCloudImpl(db: DB) {
  if (!supabase || !isSupabaseConfigured()) return;

  if (!getCachedSession()) {
    console.warn('[Huddle] syncToCloud: skipping — no active auth session');
    return;
  }

  const activeUserId = getCachedSession()?.user?.id;
  if (!activeUserId) {
    console.warn('[Huddle] syncToCloud: skipping — session missing user id');
    return;
  }

  const memberFamilyIds = new Set(
    (db.familyMembers || [])
      .filter((m: any) => m.userId === activeUserId)
      .map((m: any) => m.familyId)
  );

  let ownershipClaimAttempted = false;

  const filterRowsByScope = (key: keyof DB, rows: Record<string, unknown>[]) => {
    switch (key) {
      case 'users':
        return rows.filter((r: any) => r.id === activeUserId);
      case 'families':
        return rows.filter((r: any) => r.ownerId === activeUserId);
      case 'familyMembers': {
        const privilegedFamilyIds = new Set(
          (db.familyMembers || [])
            .filter((m: any) => m.userId === activeUserId && (m.role === 'OWNER' || m.role === 'ADMIN'))
            .map((m: any) => m.familyId)
        );
        return rows.filter((r: any) =>
          r.userId === activeUserId || privilegedFamilyIds.has(r.familyId)
        );
      }
      case 'fitness':
      case 'fitnessPlans':
      case 'dailyHabits':
      case 'dailyHabitCompletions':
      case 'aiHistory':
      case 'savingsGoals':
      case 'periodCycles':
      case 'periodSymptoms':
      case 'intimateLogs':
        return rows.filter((r: any) => r.userId === activeUserId);
      case 'rewardRedemptions':
      case 'pollVotes':
      case 'choreCompletions':
        return rows.filter((r: any) => r.userId === activeUserId || memberFamilyIds.has(r.familyId));
      default:
        return rows.filter((r: any) => !('familyId' in r) || memberFamilyIds.has(r.familyId));
    }
  };

  for (const { key, table, onConflict, noDelete } of TABLE_MAP) {
    const rows = db[key] as unknown as Record<string, unknown>[];
    if (!Array.isArray(rows)) continue;

    try {
      const idCol = key === 'familyMembers' ? 'user_id' : 'id';
      let remoteQuery = supabase.from(table).select(idCol);
      switch (key) {
        case 'users':
          remoteQuery = remoteQuery.eq('id', activeUserId);
          break;
        case 'families':
          remoteQuery = remoteQuery.eq('owner_id', activeUserId);
          break;
        case 'fitness':
        case 'fitnessPlans':
        case 'dailyHabits':
        case 'dailyHabitCompletions':
        case 'aiHistory':
        case 'savingsGoals':
        case 'periodCycles':
        case 'periodSymptoms':
        case 'intimateLogs':
          remoteQuery = remoteQuery.eq('user_id', activeUserId);
          break;
        case 'rewardRedemptions':
        case 'pollVotes':
        case 'choreCompletions':
          if (memberFamilyIds.size > 0) {
            remoteQuery = remoteQuery.in('family_id', [...memberFamilyIds]);
          }
          break;
        default:
          if (memberFamilyIds.size > 0) {
            remoteQuery = remoteQuery.in('family_id', [...memberFamilyIds]);
          }
          break;
      }
      const { data: remoteRows } = await remoteQuery;

      const scopedRows = filterRowsByScope(key, rows);

      if (scopedRows.length > 0) {
        let rowsToUpsert = scopedRows as Record<string, unknown>[];

        if (table === 'families') {
          rowsToUpsert = rowsToUpsert.map(r => ({
            ...r,
            enabledModules: r.enabledModules ?? [],
          }));
        }

        const tryUpsert = async (r: Record<string, unknown>[]) => {
          const res = await supabase.from(table).upsert(r as any, onConflict ? { onConflict } : undefined);
          return res.error as { message: string } | null;
        };

        let upsertError = await tryUpsert(rowsToUpsert);

        while (
          upsertError &&
          /column.*does not exist|Could not find/i.test(upsertError.message)
        ) {
          const match = upsertError.message.match(
            /column ["']?([\w]+)["']?.*does not exist|Could not find (?:the )?['"]?([\w]+)['"]?/i
          );
          const badCol = match?.[1] || match?.[2];
          if (!badCol) break;

          console.warn(`Stripping unknown column "${badCol}" from "${table}" and retrying sync…`);
          rowsToUpsert = rowsToUpsert.map(r => {
            const clean = { ...r };
            delete clean[badCol];
            return clean;
          });
          upsertError = await tryUpsert(rowsToUpsert);
        }

        if (upsertError && /row-level security policy/i.test(upsertError.message)) {
          if (
            !ownershipClaimAttempted &&
            (table === 'families' || table === 'family_members')
          ) {
            ownershipClaimAttempted = true;
            try {
              await supabase.rpc('claim_owned_families');
              const retryErr = await tryUpsert(rowsToUpsert);
              if (!retryErr) continue;
              upsertError = retryErr;
            } catch {
              // RPC unavailable
            }
          }

          let wroteAny = false;
          for (const row of rowsToUpsert) {
            const rowErr = await tryUpsert([row]);
            if (rowErr) {
              console.warn(`Skipped unauthorized row in "${table}": ${rowErr.message}`);
              continue;
            }
            wroteAny = true;
          }
          if (!wroteAny) {
            console.warn(`Failed writing table "${table}": ${upsertError.message}`);
            continue;
          }
        } else if (upsertError) {
          console.warn(`Failed writing table "${table}": ${upsertError.message}`);
          continue;
        }
      }

      const canDelete = !noDelete
        && localDbIsReconciled
        && remoteRows
        && remoteRows.length > 0
        && scopedRows.length === rows.length;

      if (canDelete) {
        const localIds = new Set(scopedRows.map(r => String(r[idCol])));
        const toDelete = remoteRows
          .map(r => String((r as Record<string, unknown>)[idCol]))
          .filter(id => !localIds.has(id));

        if (toDelete.length > 0) {
          const { error } = await supabase.from(table).delete().in(idCol, toDelete);
          if (error) {
            console.warn(`Failed deleting from "${table}":`, error.message);
          }
        }
      }
    } catch (err) {
      console.warn(`Sync skipped for table "${table}":`, err);
      continue;
    }
  }
}

/**
 * Reset the database – clears local storage and wipes all Supabase tables.
 * After completion the page reloads so the app starts from a clean state.
 */
export const resetDB = async () => {
  const localDbBeforeClear = getDB();

  _dbCache = freshDB();
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(DEFAULT_DB)); } catch { /* quota */ }
  await idbSet(STORAGE_KEY, DEFAULT_DB).catch(() => {});
  localStorage.removeItem('lobohub_active_user_id');

  if (supabase && isSupabaseConfigured()) {
    const session = getCachedSession();
    const userId = session?.user?.id;

    if (userId) {
      const memberFamilyIds = (localDbBeforeClear.familyMembers || [])
        .filter((m: any) => m.userId === userId)
        .map((m: any) => m.familyId as string)
        .filter(Boolean);

      const userScopedTables = [
        'savings_goals', 'fitness_plans', 'fitness', 'daily_habit_completions',
        'daily_habits', 'ai_history', 'period_cycles', 'period_symptoms',
        'user_locations',
      ];
      for (const table of userScopedTables) {
        const { error } = await supabase.from(table).delete().eq('user_id', userId);
        if (error) console.warn(`Failed to clear "${table}":`, error.message);
      }

      if (memberFamilyIds.length > 0) {
        const familyScopedTables = [
          'reading_plan_progress', 'reading_plans', 'prayer_wall',
          'reward_redemptions', 'reward_items', 'external_calendars',
          'poll_votes', 'polls', 'chore_completions', 'chores',
          'transactions', 'budget_categories', 'devotionals', 'lists',
          'meal_plans', 'recipes', 'events', 'tasks',
          'special_dates', 'family_photos', 'milestones', 'saved_places',
          'health_records', 'messages',
        ];
        for (const table of familyScopedTables) {
          const { error } = await supabase.from(table).delete().in('family_id', memberFamilyIds);
          if (error) console.warn(`Failed to clear "${table}":`, error.message);
        }
      }

      await supabase.from('family_members').delete().eq('user_id', userId);
      await supabase.from('families').delete().eq('owner_id', userId);
      await supabase.from('users').delete().eq('id', userId);

      console.info('[Huddle] Supabase tables cleared (scoped to current user).');
    }
  }

  window.location.reload();
};

/**
 * Fetch the latest data from Supabase (or fall back to local storage).
 * Unlike reconcileCloud which merges, this returns the freshest possible DB snapshot.
 */
export async function fetchLatestDB(): Promise<DB> {
  if (!supabase || !isSupabaseConfigured()) return getDB();

  await syncToCloud();

  // Snapshot AFTER sync so any changes made during the sync are captured.
  const local = getDB();

  try {
    let fetchTimer: ReturnType<typeof setTimeout>;
    const results = await Promise.race([
      Promise.all(TABLE_MAP.map(({ table }) => supabase.from(table).select('*'))),
      new Promise<never>((_, reject) => {
        fetchTimer = setTimeout(() => reject(new Error('timeout')), 5000);
      }),
    ]).finally(() => clearTimeout(fetchTimer!)) as any[];

    // Re-read the cache after the async fetch: the user may have saved more
    // changes while the Supabase round-trip was in flight.
    const current = getDB();
    const fresh = { ...local } as DB;
    TABLE_MAP.forEach(({ key }, idx) => {
      const res = results[idx];
      if (!res.error && res.data && Array.isArray(res.data)) {
        if (key === 'familyMembers') {
          (fresh as any)[key] = res.data.map((cloudMember: any) => {
            if ('moduleAccess' in cloudMember) {
              return cloudMember;
            }
            const localMember = (current.familyMembers || []).find(
              (m: any) => m.userId === cloudMember.userId && m.familyId === cloudMember.familyId
            );
            return localMember?.moduleAccess !== undefined
              ? { ...cloudMember, moduleAccess: localMember.moduleAccess }
              : cloudMember;
          });
        } else if (key === 'users') {
          const cloudIds = new Set(res.data.map((u: any) => u.id));
          const localOnly = (current.users || []).filter((u: any) => !cloudIds.has(u.id));
          (fresh as any)[key] = [...res.data, ...localOnly];
        } else if (key === 'families') {
          const cloudIds = new Set(res.data.map((f: any) => f.id));
          const localOnly = (current.families || []).filter((f: any) => !cloudIds.has(f.id));
          (fresh as any)[key] = [...res.data, ...localOnly];
        } else {
          // Cloud data wins for items in both. Preserve local-only items that
          // haven't synced yet (slow network, transient error, etc.) so they
          // are never silently dropped by a cloud fetch that races the upsert.
          const currentArr = (current as any)[key] as any[];
          if (Array.isArray(currentArr) && currentArr.length > 0) {
            const cloudIds = new Set(res.data.map((r: any) => r.id));
            const localOnly = currentArr.filter((r: any) => r.id && !cloudIds.has(r.id));
            (fresh as any)[key] = localOnly.length > 0 ? [...res.data, ...localOnly] : res.data;
          } else {
            (fresh as any)[key] = res.data;
          }
        }
      }
    });

    const safeFresh = sanitizeDB(fresh as unknown as Record<string, unknown>);
    _dbCache = safeFresh;
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(safeFresh)); } catch { /* quota */ }
    idbSet(STORAGE_KEY, safeFresh).catch(() => {});
    return safeFresh;
  } catch {
    return local;
  }
}

// ---------------------------------------------------------------------------
// DB update subscription – allows components to re-read when remote changes
// arrive (e.g. via Supabase Realtime broadcast).
// ---------------------------------------------------------------------------
const dbListeners = new Set<() => void>();

/** Register a callback that fires whenever the DB is externally refreshed. */
export function onDBUpdate(fn: () => void): () => void {
  dbListeners.add(fn);
  return () => dbListeners.delete(fn);
}

/** Notify all listeners that the DB was refreshed (call after fetchLatestDB). */
export function notifyDBUpdate() {
  dbListeners.forEach(fn => fn());
}

/** @deprecated Use resetDB() instead */
export const seedDB = resetDB;

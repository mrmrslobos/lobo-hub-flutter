
import React, { useState, useEffect, useCallback } from 'react';
import { HashRouter as Router, Routes, Route, Navigate, useNavigate } from 'react-router-dom';
import Layout from './components/Layout';
import AuthFlow from './components/AuthFlow';
import BiometricLock, { isLockEnabled } from './components/BiometricLock';
import Dashboard from './modules/Dashboard';
import Tasks from './modules/Tasks';
import Meals from './modules/Meals';
import Budget from './modules/Budget';
import Calendar from './modules/Calendar';
import Lists from './modules/Lists';
import Devotional from './modules/Devotional';
import Fitness from './modules/Fitness';
import AiHistory from './modules/AiHistory';
import Chores from './modules/Chores';
import Rewards from './modules/Rewards';
import Polls from './modules/Polls';
import PrayerWall from './modules/PrayerWall';
import PeriodTracker from './modules/PeriodTracker';
import Chat from './modules/Chat';
import Birthdays from './modules/Birthdays';
import Photos from './modules/Photos';
import Location from './modules/Location';
import Health from './modules/Health';
import {
  getDB, saveDB, saveDBAndSync, reconcileCloud, persistLocalDB,
  fetchLatestDB, notifyDBUpdate, clearLocalCache, initDB, getLastLocalSaveMs, DB,
} from './services/db';
import {
  joinFamilyChannel, leaveFamilyChannel, rejoinFamilyChannel,
  onFamilyChange, onDbRefreshNeeded, type FamilyBroadcast,
} from './services/realtime';
import { setAiProxyContext, clearAiProxyContext } from './services/gemini';
import { Capacitor } from '@capacitor/core';
import { App as CapacitorApp } from '@capacitor/app';
import NotificationToast, { pushToast } from './components/NotificationToast';
import { User, Family } from './types';
import { APP_CONFIG } from './appConfig';
import { LocaleProvider } from './contexts/LocaleContext';
import { supabase, isSupabaseConfigured, setCachedSession, getSupabaseUrl, getSupabaseAnonKey } from './services/supabase';
import {
  initializePushListeners, registerPushNotifications,
  unregisterPushNotifications, onPushReceived, onPushActionPerformed,
  consumePendingNavigationPath, subscribeWebPush, unsubscribeWebPush,
} from './services/pushNotifications';
import { onChatMessage } from './services/realtime';
import { MODULE_GROUPS, getModulePath } from './services/moduleConfig';

// Register push listener immediately at module load so cold-start taps are never missed.
initializePushListeners();

// ---------------------------------------------------------------------------
// Push notification deep-link navigation
// ---------------------------------------------------------------------------
function PushNavigationHandler() {
  const navigate = useNavigate();

  // Native push: consume path buffered before the router mounted (cold-start
  // taps) and subscribe to live dispatches (background-tap taps).
  useEffect(() => {
    const pending = consumePendingNavigationPath();
    if (pending) navigate(pending, { replace: true });
    return onPushActionPerformed((path) => navigate(path, { replace: true }));
  }, [navigate]);

  // Web push: the service worker posts { type: 'NAVIGATE', path } instead of
  // calling client.navigate() to avoid a full page reload that would clear
  // auth state.
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return;
    const handler = (event: MessageEvent) => {
      if (event.data?.type === 'NAVIGATE' && typeof event.data.path === 'string') {
        navigate(event.data.path, { replace: true });
      }
    };
    navigator.serviceWorker.addEventListener('message', handler);
    return () => navigator.serviceWorker.removeEventListener('message', handler);
  }, [navigate]);

  return null;
}

function requestNotificationPermission() {
  if ('Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission();
  }
}

/** Show a browser notification via SW (or fallback to window.Notification). */
function showBrowserNotificationRaw(title: string, body: string, path: string, module: string) {
  if ('serviceWorker' in navigator && navigator.serviceWorker.controller) {
    navigator.serviceWorker.controller.postMessage({ type: 'SHOW_NOTIFICATION', title, body, path, module });
    return;
  }
  if ('Notification' in window && Notification.permission === 'granted') {
    new Notification(title, { body, icon: '/icons/icon-192.svg' });
  }
}

function showBrowserNotification(msg: FamilyBroadcast) {
  if (document.hasFocus()) return;
  const title = `${msg.userName} - ${msg.module}`;
  const body = `${msg.action}${msg.detail ? ': ' + msg.detail : ''}`;
  if ('serviceWorker' in navigator && navigator.serviceWorker.controller) {
    navigator.serviceWorker.controller.postMessage({
      type: 'SHOW_NOTIFICATION', title, body,
      module: msg.module,
      path: getModulePath(msg.module),
    });
    return;
  }
  if ('Notification' in window && Notification.permission === 'granted') {
    new Notification(title, { body, icon: '/icons/icon-192.svg' });
  }
}

// ---------------------------------------------------------------------------
// App component
// ---------------------------------------------------------------------------
const App: React.FC = () => {
  const [activeUser, setActiveUser] = useState<User | null>(null);
  const [activeFamily, setActiveFamily] = useState<Family | null>(null);
  const [db, setDb] = useState<DB>(getDB());
  const [isInitializing, setIsInitializing] = useState(true);
  const [isLocked, setIsLocked] = useState(false);

  // Handle OAuth deep-link callback on native iOS/Android.
  //
  // Flow:
  //   1. User taps "Continue with Google" → signInWithOAuth opens Google in browser
  //   2. After consent, Supabase redirects to com.lobohub.app://login-callback?code=XXX
  //   3. Android intercepts via the AndroidManifest intent filter and fires appUrlOpen
  //   4. We exchange the PKCE code (or implicit tokens) for a Supabase session
  //   5. supabase.auth fires SIGNED_IN → AuthFlow.onAuthStateChange resolves the profile
  useEffect(() => {
    if (!Capacitor.isNativePlatform()) return;
    if (!supabase || !isSupabaseConfigured()) return;

    let listener: Awaited<ReturnType<typeof CapacitorApp.addListener>> | null = null;

    CapacitorApp.addListener('appUrlOpen', async ({ url }) => {
      if (!url.startsWith('com.lobohub.app://')) return;
      try {
        // PKCE flow: Supabase appends ?code=... to the redirect URL
        let code: string | null = null;
        try { code = new URL(url).searchParams.get('code'); } catch { /* bad URL */ }

        if (code) {
          const { data, error } = await supabase!.auth.exchangeCodeForSession(url);
          if (error) console.error('[OAuth] exchangeCodeForSession:', error.message);
          else if (data.session) setCachedSession(data.session);
          return;
        }

        // Implicit flow fallback: tokens are in the hash fragment
        const hash = url.split('#')[1] ?? '';
        const params = new URLSearchParams(hash);
        const access_token = params.get('access_token');
        const refresh_token = params.get('refresh_token');
        if (access_token) {
          const { data, error } = await supabase!.auth.setSession({
            access_token,
            refresh_token: refresh_token ?? '',
          });
          if (error) console.error('[OAuth] setSession:', error.message);
          else if (data.session) setCachedSession(data.session);
        }
      } catch (err) {
        console.error('[OAuth] appUrlOpen handler error:', err);
      }
    }).then(l => { listener = l; });

    return () => { listener?.remove(); };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    async function init() {
      // 0. Handle OAuth redirect: exchange authorization code for session.
      //    Supabase has detectSessionInUrl:false on Capacitor builds, so we
      //    do this manually here for Google / Apple / Microsoft OAuth flows.
      if (supabase && isSupabaseConfigured() && !Capacitor.isNativePlatform()) {
        const urlParams = new URLSearchParams(window.location.search);
        const oauthCode = urlParams.get('code');
        if (oauthCode) {
          try {
            const { data } = await supabase.auth.exchangeCodeForSession(window.location.href);
            if (data.session) setCachedSession(data.session);
          } catch {
            // Ignore — getSession() below will still try the cached session
          }
          // Clean up the code from the URL so it's not processed twice
          window.history.replaceState({}, document.title,
            window.location.pathname + window.location.hash);
        }
      }

      // 1. Load from IndexedDB (primary) / localStorage (fallback)
      const local = await initDB();
      setDb(local);

      let sessionUserId: string | null = null;
      let sessionEmail: string | null = null;
      let alreadyReconciled = false;

      try {
        if (supabase && isSupabaseConfigured()) {
          try {
            const timeout = new Promise<{ data: { session: null } }>(resolve =>
              setTimeout(() => resolve({ data: { session: null } }), 6000)
            );
            const { data: { session } } = await Promise.race([
              supabase.auth.getSession(),
              timeout,
            ]);
            if (session?.user) {
              setCachedSession(session);
              sessionUserId = session.user.id;
              sessionEmail = session.user.email ?? null;
            }
          } catch { /* network error */ }
        } else {
          sessionUserId = localStorage.getItem(APP_CONFIG.activeUserKey);
        }

        if (sessionUserId) {
          let workingDb = local;
          let user = workingDb.users.find(u => u.id === sessionUserId);

          if (!user) {
            try {
              const reconciled = await reconcileCloud(local);
              alreadyReconciled = true;
              if (reconciled !== local) {
                workingDb = reconciled;
                setDb(reconciled);
                persistLocalDB(reconciled);
              }
              user = workingDb.users.find(u => u.id === sessionUserId);
            } catch { /* ignore */ }
          }

          if (!user && sessionEmail) {
            const oldUser = workingDb.users.find(u => u.email === sessionEmail);
            if (oldUser) {
              const oldId = oldUser.id;
              const newId = sessionUserId;
              const migratedDb = {
                ...workingDb,
                users: workingDb.users.map(u => u.id === oldId ? { ...u, id: newId } : u),
                familyMembers: workingDb.familyMembers.map(m => m.userId === oldId ? { ...m, userId: newId } : m),
                families: workingDb.families.map(f => f.ownerId === oldId ? { ...f, ownerId: newId } : f),
                fitness: workingDb.fitness.map(r => (r as any).userId === oldId ? { ...r, userId: newId } : r),
                fitnessPlans: workingDb.fitnessPlans.map(r => (r as any).userId === oldId ? { ...r, userId: newId } : r),
                dailyHabits: workingDb.dailyHabits.map(r => (r as any).userId === oldId ? { ...r, userId: newId } : r),
                dailyHabitCompletions: workingDb.dailyHabitCompletions.map(r => (r as any).userId === oldId ? { ...r, userId: newId } : r),
                aiHistory: workingDb.aiHistory.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
                tasks: workingDb.tasks.map(t => ({
                  ...t,
                  creatorId: t.creatorId === oldId ? newId : t.creatorId,
                  assignees: t.assignees.map(a => a === oldId ? newId : a),
                })),
                chores: workingDb.chores.map(c => ({
                  ...c,
                  creatorId: c.creatorId === oldId ? newId : c.creatorId,
                  assignees: c.assignees.map(a => a === oldId ? newId : a),
                })),
                choreCompletions: workingDb.choreCompletions.map(r => (r as any).userId === oldId ? { ...r, userId: newId } : r),
                rewardRedemptions: workingDb.rewardRedemptions.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
                savingsGoals: workingDb.savingsGoals.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
                pollVotes: workingDb.pollVotes.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
                // --- Previously missing tables ---
                periodCycles: workingDb.periodCycles.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
                periodSymptoms: workingDb.periodSymptoms.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
                readingPlanProgress: workingDb.readingPlanProgress.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
                userLocations: workingDb.userLocations.map(r => r.userId === oldId ? { ...r, id: newId, userId: newId } : r),
                healthRecords: workingDb.healthRecords.map(r => ({
                  ...r,
                  memberId: r.memberId === oldId ? newId : r.memberId,
                  updatedBy: r.updatedBy === oldId ? newId : r.updatedBy,
                })),
                messages: workingDb.messages.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
                devotionals: workingDb.devotionals.map(r => r.creatorId === oldId ? { ...r, creatorId: newId } : r),
                prayerWall: workingDb.prayerWall.map(r => ({
                  ...r,
                  creatorId: r.creatorId === oldId ? newId : r.creatorId,
                  reactions: r.reactions.map(rx => rx.userId === oldId ? { ...rx, userId: newId } : rx),
                })),
              };
              persistLocalDB(migratedDb);
              workingDb = migratedDb;
              setDb(migratedDb);
              user = workingDb.users.find(u => u.id === newId)!;
              console.info('[Auth] Session migration:', oldId, '→', newId);
            }
          }

          if (user) {
            const membership = workingDb.familyMembers.find(m => m.userId === user!.id);
            const family = membership ? workingDb.families.find(f => f.id === membership.familyId) : null;
            if (family) {
              setActiveUser(user);
              setActiveFamily(family);
              if (!supabase || !isSupabaseConfigured()) {
                localStorage.setItem(APP_CONFIG.activeUserKey, user.id);
              }
              registerPushNotifications(user.id, family.id);
    subscribeWebPush(user.id, family.id);
              // Configure AI proxy
              const sbUrl = getSupabaseUrl();
              const sbKey = getSupabaseAnonKey();
              if (sbUrl && sbKey) {
                setAiProxyContext({ supabaseUrl: sbUrl, supabaseAnonKey: sbKey, familyId: family.id });
              }
              if (isLockEnabled()) setIsLocked(true);
            }
          }
        }
      } finally {
        setIsInitializing(false);
      }

      // Background cloud reconciliation
      if (supabase && isSupabaseConfigured() && !alreadyReconciled) {
        try {
          const latestLocal = getDB();
          const reconciled = await reconcileCloud(latestLocal);
          if (reconciled !== latestLocal) {
            setDb(reconciled);
            persistLocalDB(reconciled);
            if (sessionUserId) {
              const user = reconciled.users.find(u => u.id === sessionUserId);
              if (user) {
                setActiveUser(user);
                const membership = reconciled.familyMembers.find(m => m.userId === user.id);
                const family = membership ? reconciled.families.find(f => f.id === membership.familyId) : null;
                if (family) setActiveFamily(family);
              }
            }
          }
        } catch (err) {
          console.warn('Background sync failed:', err);
        }
      }
    }
    init().catch(() => setIsInitializing(false));
  }, []);

  // Sign out when Supabase session expires or user signs out in another tab
  useEffect(() => {
    if (!supabase || !isSupabaseConfigured()) return;
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') {
        setActiveUser(null);
        setActiveFamily(null);
        clearAiProxyContext();
        localStorage.removeItem(APP_CONFIG.activeUserKey);
      }
    });
    return () => subscription.unsubscribe();
  }, []);

  // Unread module badges
  const [unreadModules, setUnreadModules] = useState<Set<string>>(new Set());

  const clearUnreadModule = useCallback((path: string) => {
    setUnreadModules(prev => {
      if (!prev.has(path)) return prev;
      const next = new Set(prev);
      next.delete(path);
      return next;
    });
  }, []);

  const moduleNameToPath: Record<string, string> = {
    'Chat': '/chat', 'Tasks': '/tasks', 'Calendar': '/calendar', 'Chores': '/chores',
    'Lists': '/lists', 'Polls': '/polls', 'Meals': '/meals', 'Occasions': '/birthdays',
    'Fitness': '/fitness', 'Devotional': '/devotional', 'Photos': '/photos',
    'Prayer Wall': '/prayer-wall', 'Budget': '/budget', 'Location': '/location',
    'Rewards': '/rewards', 'Period Tracker': '/period-tracker', 'Health': '/health',
  };

  // Realtime channel management
  useEffect(() => {
    if (!activeUser || !activeFamily) return;

    joinFamilyChannel(activeFamily.id, activeUser.id);
    requestNotificationPermission();

    let appStateListener: Awaited<ReturnType<typeof CapacitorApp.addListener>> | null = null;
    let webVisibilityCleanup: (() => void) | null = null;
    let cleanedUp = false;

    if (Capacitor.isNativePlatform()) {
      CapacitorApp.addListener('appStateChange', async ({ isActive }) => {
        if (!isActive || cleanedUp) return;
        rejoinFamilyChannel();
        try {
          const fresh = await fetchLatestDB();
          setDb(fresh);
          notifyDBUpdate();
        } catch { /* ignore */ }
      }).then(listener => {
        if (cleanedUp) { listener.remove(); } else { appStateListener = listener; }
      });
    } else {
      const handleVisibility = async () => {
        if (document.visibilityState !== 'visible' || cleanedUp) return;
        rejoinFamilyChannel();
        try {
          const fresh = await fetchLatestDB();
          setDb(fresh);
          notifyDBUpdate();
        } catch { /* ignore */ }
      };
      document.addEventListener('visibilitychange', handleVisibility);
      webVisibilityCleanup = () => document.removeEventListener('visibilitychange', handleVisibility);
    }

    const unsubscribe = onFamilyChange(async (msg) => {
      const prefs = getDB().notificationPrefs;
      // Map broadcast module names to NotificationPrefs keys. Multi-word modules
      // (e.g. "Prayer Wall") and renamed modules (Occasions→birthdays) need explicit entries.
      const MODULE_PREF_KEY: Record<string, keyof NotificationPrefs> = {
        Chat: 'chat', Tasks: 'tasks', Calendar: 'calendar', Chores: 'chores',
        Lists: 'lists', Polls: 'polls', Meals: 'meals', Occasions: 'birthdays',
        Photos: 'photos', Location: 'location',
      };
      const prefKey = MODULE_PREF_KEY[msg.module];
      const enabled = !prefKey || prefs[prefKey] !== false; // unmapped modules default to enabled
      if (enabled) {
        pushToast({
          userName: msg.userName, action: msg.action,
          module: msg.module, detail: msg.detail, timestamp: msg.timestamp,
        });
      }
      const badgePath = moduleNameToPath[msg.module];
      if (badgePath) setUnreadModules(prev => new Set([...prev, badgePath]));
      if (enabled) showBrowserNotification(msg);
      try {
        const fresh = await fetchLatestDB();
        setDb(fresh);
        notifyDBUpdate();
      } catch {
        setDb(getDB());
        notifyDBUpdate();
      }
    });

    // Chat message notifications — show toast + browser notification when not on /chat
    const unsubscribeChat = onChatMessage((msg) => {
      const prefs = getDB().notificationPrefs;
      if (!prefs.chat) return;
      const senderName = getDB().users.find(u => u.id === msg.userId)?.name ?? 'Family';
      pushToast({ userName: senderName, action: msg.text, module: 'Chat', detail: '', timestamp: Date.now() });
      setUnreadModules(prev => new Set([...prev, '/chat']));
      if (!document.hasFocus()) {
        showBrowserNotificationRaw(`${senderName} — Chat`, msg.text, '/chat', 'Chat');
      }
    });

    const unsubscribePush = onPushReceived(async () => {
      try {
        const fresh = await fetchLatestDB();
        setDb(fresh);
        notifyDBUpdate();
      } catch {
        setDb(getDB());
      }
    });

    // Postgres Changes backup refresh — fires 1.5s after any DB write.
    // Skip if we recently saved locally (< 3s) to prevent the "task flicker":
    // our own Supabase write triggers postgres_changes, which would call
    // fetchLatestDB before the upsert fully commits, returning stale data.
    const unsubscribePgRefresh = onDbRefreshNeeded(async () => {
      if (cleanedUp) return;
      if (Date.now() - getLastLocalSaveMs() < 3000) return; // own recent write
      try {
        const fresh = await fetchLatestDB();
        setDb(fresh);
        notifyDBUpdate();
      } catch {
        const local = getDB();
        setDb(local);
        notifyDBUpdate();
      }
    });

    return () => {
      cleanedUp = true;
      unsubscribe();
      unsubscribeChat();
      unsubscribePush();
      unsubscribePgRefresh();
      leaveFamilyChannel();
      appStateListener?.remove();
      webVisibilityCleanup?.();
    };
  }, [activeUser?.id, activeFamily?.id]);

  // Schedule browser notification reminders for upcoming calendar events (15 min before).
  // Re-runs whenever the DB changes so newly-added events are picked up immediately.
  useEffect(() => {
    if (!activeUser || !activeFamily) return;
    const prefs = db.notificationPrefs;
    if (!prefs.calendar) return;
    if (!('Notification' in window) || Notification.permission !== 'granted') return;

    const now = Date.now();
    const cutoff = now + 24 * 60 * 60 * 1000; // next 24 hours
    const REMIND_MS = 15 * 60 * 1000; // 15 min before

    const timers: ReturnType<typeof setTimeout>[] = [];
    const scheduled = new Set<string>();

    db.events.filter(ev => ev.familyId === activeFamily.id).forEach(ev => {
      const startMs = new Date(ev.start).getTime();
      const fireMs = startMs - REMIND_MS;
      if (fireMs <= now || startMs > cutoff) return;
      if (scheduled.has(ev.id)) return;
      scheduled.add(ev.id);

      const delay = fireMs - now;
      timers.push(setTimeout(() => {
        showBrowserNotificationRaw('📅 Upcoming Event', `${ev.title} starts in 15 minutes`, '/calendar', 'Calendar');
      }, delay));
    });

    return () => timers.forEach(clearTimeout);
  }, [db.events, activeUser?.id, activeFamily?.id, db.notificationPrefs.calendar]);

  const handleAuthenticated = (user: User, family: Family) => {
    setActiveUser(user);
    setActiveFamily(family);
    const freshDb = getDB();
    setDb(freshDb);
    localStorage.setItem(APP_CONFIG.activeUserKey, user.id);
    registerPushNotifications(user.id, family.id);
    subscribeWebPush(user.id, family.id);

    // Configure AI proxy
    const sbUrl = getSupabaseUrl();
    const sbKey = getSupabaseAnonKey();
    if (sbUrl && sbKey) {
      setAiProxyContext({ supabaseUrl: sbUrl, supabaseAnonKey: sbKey, familyId: family.id });
    }

    if (isLockEnabled()) setIsLocked(true);

    if (supabase && isSupabaseConfigured()) {
      reconcileCloud(freshDb).then(reconciled => {
        if (reconciled !== freshDb) {
          const cloudMemberKeys = new Set(reconciled.familyMembers.map(m => `${m.userId}:${m.familyId}`));
          const localOnlyMembers = freshDb.familyMembers.filter(m => !cloudMemberKeys.has(`${m.userId}:${m.familyId}`));
          const cloudFamilyIds = new Set(reconciled.families.map(f => f.id));
          const localOnlyFamilies = freshDb.families.filter(f => !cloudFamilyIds.has(f.id));
          const mergedFamilies = reconciled.families.map(cloudFam => {
            const localFam = freshDb.families.find(f => f.id === cloudFam.id);
            if (!localFam) return cloudFam;
            return {
              ...cloudFam,
              enabledModules: localFam.enabledModules !== undefined ? localFam.enabledModules : cloudFam.enabledModules,
              settings: localFam.settings ?? cloudFam.settings,
            };
          });
          const finalDb = {
            ...reconciled,
            familyMembers: localOnlyMembers.length > 0 ? [...reconciled.familyMembers, ...localOnlyMembers] : reconciled.familyMembers,
            families: localOnlyFamilies.length > 0 ? [...mergedFamilies, ...localOnlyFamilies] : mergedFamilies,
          };
          persistLocalDB(finalDb);
          setDb(finalDb);
          const updatedUser = finalDb.users.find(u => u.id === user.id);
          if (updatedUser) setActiveUser(updatedUser);
          const updatedFamily = finalDb.families.find(f => f.id === family.id);
          if (updatedFamily) setActiveFamily(updatedFamily);
        } else {
          persistLocalDB(freshDb);
        }
      }).catch(() => {
        persistLocalDB(freshDb);
      });
    }
  };

  const handleLogout = async () => {
    leaveFamilyChannel();
    clearAiProxyContext();
    if (activeUser) {
      await unregisterPushNotifications(activeUser.id);
      await unsubscribeWebPush(activeUser.id);
    }
    if (supabase && isSupabaseConfigured()) await supabase.auth.signOut();
    clearLocalCache();
    localStorage.removeItem(APP_CONFIG.activeUserKey);
    setDb(getDB());
    setActiveUser(null);
    setActiveFamily(null);
    setIsLocked(false);
  };

  const handleFamilySwitch = (id: string) => {
    const isMember = db.familyMembers.some(m => m.userId === activeUser?.id && m.familyId === id);
    if (!isMember) return;
    const family = db.families.find(f => f.id === id);
    if (family) {
      setActiveFamily(family);
      const sbUrl = getSupabaseUrl();
      const sbKey = getSupabaseAnonKey();
      if (sbUrl && sbKey) setAiProxyContext({ supabaseUrl: sbUrl, supabaseAnonKey: sbKey, familyId: id });
    }
  };

  const handleSaveDb = (newDb: DB, broadcast?: boolean) => {
    if (broadcast && activeUser && activeFamily) {
      saveDBAndSync(newDb, {
        userId: activeUser.id,
        userName: activeUser.name,
        action: 'updated member access',
        module: 'Members',
        detail: 'Member access settings changed',
      });
    } else {
      saveDB(newDb);
    }
    setDb(newDb);
  };

  const canAccess = (path: string): boolean => {
    if (!activeUser || !activeFamily) return true;
    const currentFamily = db.families.find(f => f.id === activeFamily.id) ?? activeFamily;
    const enabled = currentFamily.enabledModules;
    if (enabled && enabled.length > 0 && !enabled.includes(path)) return false;
    const m = db.familyMembers.find(m => m.userId === activeUser.id && m.familyId === activeFamily.id);
    if (!m?.moduleAccess || m.moduleAccess.length === 0) return true;
    return m.moduleAccess.includes(path);
  };

  if (isInitializing && !activeUser) return null;
  if (!activeUser || !activeFamily) return <AuthFlow onAuthenticated={handleAuthenticated} />;
  if (isLocked) return <BiometricLock onUnlock={() => setIsLocked(false)} />;

  const currentFamily = db.families.find(f => f.id === activeFamily.id) ?? activeFamily;

  return (
    <LocaleProvider settings={currentFamily.settings}>
      <NotificationToast />
      <Router>
        <PushNavigationHandler />
        <Layout
          user={activeUser}
          family={currentFamily}
          onLogout={handleLogout}
          families={db.families.filter(f => db.familyMembers.some(m => m.userId === activeUser.id && m.familyId === f.id))}
          onFamilySwitch={handleFamilySwitch}
          db={db}
          onSaveDb={handleSaveDb}
          unreadModules={unreadModules}
          onClearUnread={clearUnreadModule}
        >
          <Routes>
            <Route path="/" element={<Dashboard user={activeUser} family={currentFamily} onSwitchUser={handleAuthenticated} />} />
            <Route path="/tasks" element={canAccess('/tasks') ? <Tasks user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/meals" element={canAccess('/meals') ? <Meals user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/budget" element={canAccess('/budget') ? <Budget user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/calendar" element={canAccess('/calendar') ? <Calendar user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/lists" element={canAccess('/lists') ? <Lists user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/devotional" element={canAccess('/devotional') ? <Devotional user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/prayer-wall" element={canAccess('/prayer-wall') ? <PrayerWall user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/fitness" element={canAccess('/fitness') ? <Fitness user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/chores" element={canAccess('/chores') ? <Chores user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/rewards" element={canAccess('/rewards') ? <Rewards user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/polls" element={canAccess('/polls') ? <Polls user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/period-tracker" element={canAccess('/period-tracker') ? <PeriodTracker user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/chat" element={canAccess('/chat') ? <Chat user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/birthdays" element={canAccess('/birthdays') ? <Birthdays user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/photos"    element={canAccess('/photos')    ? <Photos    user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/location"  element={canAccess('/location')  ? <Location  user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/health"    element={canAccess('/health')    ? <Health    user={activeUser} family={currentFamily} /> : <Navigate to="/" replace />} />
            <Route path="/ai/history" element={<AiHistory user={activeUser} family={currentFamily} />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </Layout>
      </Router>
    </LocaleProvider>
  );
};

// Re-export module groups for any code still importing from App.tsx
export { MODULE_GROUPS } from './services/moduleConfig';

export default App;

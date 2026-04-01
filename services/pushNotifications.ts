import { PushNotifications, type Token, type ActionPerformed, type PushNotificationSchema } from '@capacitor/push-notifications';
import { Capacitor } from '@capacitor/core';
import { supabase, isSupabaseConfigured } from './supabase';

// ---------------------------------------------------------------------------
// Foreground push notification subscription (mirrors onFamilyChange pattern)
// ---------------------------------------------------------------------------

type PushReceivedListener = (notification: PushNotificationSchema) => void;
const pushReceivedListeners: Set<PushReceivedListener> = new Set();

/**
 * Subscribe to push notifications that arrive while the app is in the
 * foreground.  Returns an unsubscribe function.
 */
export function onPushReceived(listener: PushReceivedListener): () => void {
  pushReceivedListeners.add(listener);
  return () => pushReceivedListeners.delete(listener);
}

// ---------------------------------------------------------------------------
// Notification tap subscription — for deep-link navigation via React Router
// ---------------------------------------------------------------------------

type PushActionListener = (path: string) => void;
const pushActionListeners: Set<PushActionListener> = new Set();

// Stores a deep-link path that arrived before PushNavigationHandler mounted.
// PushNavigationHandler consumes this on mount so cold-start and
// suspended-then-resumed taps always land on the correct module.
let _pendingNavigationPath: string | null = null;
let _initializedPushActionListener = false;

/**
 * Consume and clear the pending deep-link path set by a notification tap
 * that arrived before the Router was ready.  Call this inside
 * PushNavigationHandler's useEffect on mount.
 */
export function consumePendingNavigationPath(): string | null {
  const path = _pendingNavigationPath;
  _pendingNavigationPath = null;
  return path;
}

/** Dispatch a notification-tap path: to live subscribers or to the pending buffer. */
function dispatchPushPath(path: string): void {
  if (pushActionListeners.size > 0) {
    pushActionListeners.forEach(fn => fn(path));
  } else {
    // React Router hasn't mounted yet — store the path so PushNavigationHandler
    // can pick it up when it mounts, and also set the hash as a belt-and-braces
    // fallback for HashRouter's initial-render read.
    _pendingNavigationPath = path;
    window.location.hash = '#' + path;
  }
}

/**
 * Subscribe to notification taps (app in background or killed).
 * The listener receives the deep-link path (e.g. '/tasks') so the caller
 * can navigate with React Router's useNavigate instead of manipulating
 * the hash directly (which can race against the router's initial render).
 * Returns an unsubscribe function.
 */
export function onPushActionPerformed(listener: PushActionListener): () => void {
  pushActionListeners.add(listener);
  return () => pushActionListeners.delete(listener);
}

/**
 * Registers the pushNotificationActionPerformed listener immediately so
 * cold-start taps (app fully closed when notification is tapped) are never
 * missed.  Must be called at module scope in App.tsx — before any async
 * authentication or DB initialisation — because Capacitor fires this event
 * within milliseconds of the WebView loading, long before the async init()
 * inside the App component's useEffect completes.
 *
 * The listener is intentionally kept inside registerPushNotifications() too:
 * that function calls removeAllListeners() to avoid stale closures capturing
 * the wrong userId/familyId, which would clear this early listener.
 * registerPushNotifications() then immediately re-registers it, so the
 * listener is always active and there is never a double-registration.
 */
/**
 * Extract the deep-link path from a notification action, handling the two
 * common ways Capacitor surfaces FCM data on different platforms/versions:
 *
 *  1. Object  – action.notification.data = { path: '/tasks' }          (standard)
 *  2. String  – action.notification.data = '{"path":"/tasks"}'         (some Android cold-start taps)
 *  3. Flat    – path key at action.notification root (older plugins)
 */
function extractPath(action: ActionPerformed): string | undefined {
  let data: unknown = action.notification.data;

  // Some Capacitor/Android versions serialise the extras as a JSON string.
  if (typeof data === 'string') {
    try { data = JSON.parse(data); } catch { /* leave as-is */ }
  }

  if (data && typeof data === 'object') {
    const path = (data as Record<string, unknown>).path;
    if (typeof path === 'string' && path) return path;
  }

  // Older plugin versions may hoist data keys to the notification root.
  const rootPath = (action.notification as unknown as Record<string, unknown>).path;
  if (typeof rootPath === 'string' && rootPath) return rootPath;

  return undefined;
}

export function initializePushListeners(): void {
  if (!Capacitor.isNativePlatform() || _initializedPushActionListener) return;

  _initializedPushActionListener = true;
  PushNotifications.addListener('pushNotificationActionPerformed', (action: ActionPerformed) => {
    const path = extractPath(action);
    if (path) dispatchPushPath(path);
  });
}

/**
 * Registers the device for FCM/APNs push notifications and saves the token
 * to the Supabase `device_tokens` table so the Edge Function can look it up.
 *
 * Call this once after the user has authenticated and has an active family.
 */
export async function registerPushNotifications(userId: string, familyId: string): Promise<void> {
  // Push notifications only work in a native Capacitor context.
  if (!Capacitor.isNativePlatform()) return;
  if (!supabase || !isSupabaseConfigured()) return;

  // Request permission if not already granted.
  const permStatus = await PushNotifications.checkPermissions();
  if (permStatus.receive === 'prompt') {
    const result = await PushNotifications.requestPermissions();
    if (result.receive !== 'granted') {
      console.warn('[Push] Permission denied by user.');
      return;
    }
  }
  if (permStatus.receive === 'denied') {
    console.warn('[Push] Permission permanently denied.');
    return;
  }

  // Create the Android notification channel that FCM messages reference
  // (channel_id: "default" in notify-family edge function).  Must exist before
  // register() or Android 8+ silently drops notifications with an unknown channel.
  if (Capacitor.getPlatform() === 'android') {
    await PushNotifications.createChannel({
      id: 'default',
      name: 'Family Notifications',
      description: 'Huddle activity alerts',
      importance: 4,   // IMPORTANCE_HIGH — shows as heads-up notification
      visibility: 1,   // VISIBILITY_PUBLIC
      sound: 'default',
      vibration: true,
      lights: true,
    });
  }

  // Remove stale listeners from any previous call before adding fresh ones.
  // This function can be called more than once (init + handleAuthenticated),
  // and addListener accumulates — old closures would capture the wrong
  // userId/familyId and upsert tokens against the wrong context.
  await PushNotifications.removeAllListeners();

  // Attach listeners BEFORE register() and AWAIT each one so the native side
  // has fully registered the handler before we call register().  Without await,
  // the Capacitor bridge may process register() before the addListener message
  // is acknowledged by the native layer, causing "No listeners found for event
  // registration" and a missed FCM token on fast paths (e.g. permission already
  // granted — no dialog delay to mask the race).
  await PushNotifications.addListener('registration', async (token: Token) => {
    await upsertDeviceToken(userId, familyId, token.value);
  });

  await PushNotifications.addListener('registrationError', (err) => {
    console.error('[Push] Registration error:', err.error);
  });

  // Handle notification arriving while the app is in the foreground.
  await PushNotifications.addListener('pushNotificationReceived', (notification: PushNotificationSchema) => {
    pushReceivedListeners.forEach(fn => fn(notification));
  });

  // Handle notification tap when app is in background/closed.
  await PushNotifications.addListener('pushNotificationActionPerformed', (action: ActionPerformed) => {
    const path = extractPath(action);
    if (path) dispatchPushPath(path);
  });

  // Register with FCM/APNs — token arrives via the 'registration' listener above.
  await PushNotifications.register();
}

/**
 * Saves (or updates) this device's push token for the given user + family.
 * Called automatically by registerPushNotifications after registration.
 */
async function upsertDeviceToken(userId: string, familyId: string, token: string): Promise<void> {
  if (!supabase || !isSupabaseConfigured()) return;

  const platform = Capacitor.getPlatform(); // 'ios' | 'android'
  const { error } = await supabase
    .from('device_tokens')
    .upsert(
      { user_id: userId, family_id: familyId, token, platform, updated_at: new Date().toISOString() },
      // Conflict on the token itself so each physical device gets its own row.
      // userId+platform would overwrite e.g. an iPhone row when an iPad (also
      // 'ios') registers — that device would stop receiving notifications.
      // Requires a UNIQUE constraint on the token column in device_tokens.
      { onConflict: 'token' }
    );

  if (error) {
    console.error('[Push] Failed to upsert device token:', error.message);
  } else {
    console.info('[Push] Device token registered for', platform);
  }
}

// ---------------------------------------------------------------------------
// Web Push (VAPID) — browser / PWA push notifications
// ---------------------------------------------------------------------------

/**
 * Converts a base64url string to a Uint8Array, required for VAPID
 * applicationServerKey when subscribing via the Web Push API.
 */
function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  return Uint8Array.from([...rawData].map(c => c.charCodeAt(0)));
}

/**
 * Subscribes this browser to web push notifications and stores the subscription
 * in the Supabase `web_push_subscriptions` table so the Edge Function can
 * deliver server-sent push notifications when the app is fully closed.
 *
 * Requires VITE_VAPID_PUBLIC_KEY to be set in the environment.  If the key is
 * not configured the function exits silently — native FCM will still work.
 *
 * @returns true if the subscription was created or already existed, false on failure.
 */
export async function subscribeWebPush(userId: string, familyId: string): Promise<boolean> {
  if (Capacitor.isNativePlatform()) return false; // native uses FCM
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return false;
  if (!supabase || !isSupabaseConfigured()) return false;

  const vapidPublicKey =
    (window as any).__ENV__?.VITE_VAPID_PUBLIC_KEY ??
    (import.meta as any).env?.VITE_VAPID_PUBLIC_KEY;
  if (!vapidPublicKey) {
    console.info('[WebPush] VITE_VAPID_PUBLIC_KEY not set — skipping web push subscription.');
    return false;
  }

  try {
    const reg = await navigator.serviceWorker.ready;
    let sub = await reg.pushManager.getSubscription();
    if (!sub) {
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
      });
    }

    const subJson = sub.toJSON() as { endpoint: string; keys: { p256dh: string; auth: string } };
    const { error } = await supabase.from('web_push_subscriptions').upsert(
      {
        user_id: userId,
        family_id: familyId,
        endpoint: subJson.endpoint,
        p256dh: subJson.keys.p256dh,
        auth: subJson.keys.auth,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'endpoint' },
    );
    if (error) {
      console.warn('[WebPush] Failed to store subscription:', error.message);
      return false;
    }
    console.info('[WebPush] Subscription registered.');
    return true;
  } catch (err) {
    console.warn('[WebPush] Subscribe failed:', err);
    return false;
  }
}

/**
 * Unsubscribes this browser from web push and removes the record from
 * Supabase.  Call on logout.
 */
export async function unsubscribeWebPush(userId: string): Promise<void> {
  if (Capacitor.isNativePlatform()) return;
  if (!supabase || !isSupabaseConfigured()) return;

  try {
    if ('serviceWorker' in navigator) {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (sub) {
        const endpoint = sub.endpoint;
        await sub.unsubscribe();
        await supabase.from('web_push_subscriptions').delete().eq('endpoint', endpoint);
        console.info('[WebPush] Unsubscribed.');
      }
    }
  } catch (err) {
    console.warn('[WebPush] Unsubscribe failed:', err);
  }
}

/**
 * Removes this user's device token(s) from Supabase on logout so they stop
 * receiving push notifications after signing out.
 */
export async function unregisterPushNotifications(userId: string): Promise<void> {
  if (!Capacitor.isNativePlatform()) return;
  if (!supabase || !isSupabaseConfigured()) return;

  const { error } = await supabase
    .from('device_tokens')
    .delete()
    .eq('user_id', userId);

  if (error) {
    console.warn('[Push] Failed to remove device tokens:', error.message);
  } else {
    console.info('[Push] Device tokens removed on logout.');
  }

  // Also remove all local Capacitor listeners.
  await PushNotifications.removeAllListeners();
}

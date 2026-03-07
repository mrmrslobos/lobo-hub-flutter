import { createClient, type Session } from '@supabase/supabase-js';

type EnvLike = Record<string, string | undefined>;

const readEnv = (key: string, aliases: string[] = []): string => {
  const candidates = [key, ...aliases];

  // 1. Check for runtime injection (window.process.env)
  const windowEnv = (globalThis as any)?.process?.env as EnvLike | undefined;

  // 2. Check for build-time static variables
  const importMetaEnv = (() => {
    try {
      return import.meta.env as EnvLike;
    } catch {
      return undefined;
    }
  })();

  for (const envKey of candidates) {
    // Priority: Runtime Window > Static Vite Env
    const value = windowEnv?.[envKey] ?? importMetaEnv?.[envKey];
    if (value) return value;
  }

  return '';
};

const supabaseUrl = readEnv('VITE_SUPABASE_URL', ['SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_URL']);
const supabaseAnonKey = readEnv('VITE_SUPABASE_ANON_KEY', ['SUPABASE_ANON_KEY', 'NEXT_PUBLIC_SUPABASE_ANON_KEY']);

// ---------------------------------------------------------------------------
// Session cache — updated via onAuthStateChange so the custom fetch below
// always has the latest access token available synchronously.
//
// On Capacitor Android, the Supabase PostgREST client's `accessToken`
// callback can return null briefly after signUp/signIn because the GoTrue
// client's internal session state lags behind its async lock operations.
// When that happens every request falls back to the anon key (Authorization:
// Bearer <anonKey>), and auth.uid() is null in every RLS policy, causing
// INSERT/UPDATE failures with "new row violates row-level security policy".
//
// The fix: cache the session ourselves and forcibly inject the Bearer token
// in every outgoing fetch so auth.uid() is always the real user UUID.
// ---------------------------------------------------------------------------
let _cachedSession: Session | null = null;

/** Explicitly set the cached access token (called from App.tsx after signUp/signIn). */
export const setCachedSession = (session: Session | null) => {
  _cachedSession = session;
};

/** Read the currently cached session without acquiring the GoTrueClient lock. */
export const getCachedSession = () => _cachedSession;

export const supabase = (supabaseUrl && supabaseAnonKey)
  ? createClient(supabaseUrl, supabaseAnonKey, {
      auth: {
        // On Capacitor (native iOS/Android) the session is never encoded in
        // the URL — setting this to false prevents the Supabase client from
        // attempting to parse the hash/query string on every app launch,
        // which can transiently clear the stored session before the first
        // authenticated request is made (causing RLS violations during
        // the onboarding sync).
        detectSessionInUrl: false,
        persistSession: true,
        autoRefreshToken: true,
      },
      global: {
        // Custom fetch that explicitly injects the cached user JWT when
        // available.  This overrides the static anon-key Authorization header
        // that PostgREST falls back to when accessToken() returns null —
        // which is the root cause of RLS violations on Capacitor Android.
        //
        // IMPORTANT: Do NOT inject the user JWT for GoTrue /auth/v1/ requests.
        // The GoTrueClient manages its own credentials for token refresh,
        // sign-in, sign-up, etc.  Injecting the user JWT (especially an expired
        // one) into those requests can cause the auth server to reject or close
        // the connection without a proper HTTP response, which surfaces in
        // Capacitor Android as "TypeError: Failed to fetch".
        fetch: async (input: RequestInfo | URL, init: RequestInit = {}) => {
          const url = typeof input === 'string' ? input
            : input instanceof URL ? input.toString()
            : (input as Request).url;
          if (_cachedSession?.access_token && !url.includes('/auth/v1/')) {
            const headers = new Headers(init.headers);
            headers.set('Authorization', `Bearer ${_cachedSession.access_token}`);
            return fetch(input as any, { ...init, headers });
          }
          return fetch(input as any, init);
        },
      },
    })
  : null;

// Keep _cachedSession in sync with the GoTrue auth state.
// onAuthStateChange fires synchronously (via Promise.allSettled) inside
// signUp/signIn before those methods return — so the cache is populated
// before the first syncToCloud call that follows.
if (supabase) {
  supabase.auth.onAuthStateChange((_event, session) => {
    _cachedSession = session;
  });
}

export const isSupabaseConfigured = () => !!supabase;

/** Raw Supabase URL (for constructing Edge Function URLs in the AI proxy). */
export const getSupabaseUrl = () => supabaseUrl;
/** Raw Supabase anon key (for authenticating Edge Function calls). */
export const getSupabaseAnonKey = () => supabaseAnonKey;

export const getSupabaseConfigStatus = () => ({
  configured: !!supabase,
  hasUrl: !!supabaseUrl,
  hasAnonKey: !!supabaseAnonKey,
});

if (import.meta.env.PROD) {
  const status = getSupabaseConfigStatus();
  if (!status.configured) {
    console.warn('[FamilyHub] Supabase disabled: missing env vars.', status);
  } else {
    console.info('[FamilyHub] Supabase client configured.');
  }
}

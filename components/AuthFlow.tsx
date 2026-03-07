import React, { useState, useEffect } from 'react';
import {
  Mail, Lock, User as UserIcon, Sparkles, Home, ArrowRight,
  UserPlus, Key, Loader2, Globe, Check,
} from 'lucide-react';
import { User, Family } from '../types';
import { APP_CONFIG } from '../appConfig';
import { COUNTRIES, getCountryDefaults } from '../services/locale';
import { supabase, isSupabaseConfigured, setCachedSession, getCachedSession } from '../services/supabase';
import { getDB, saveDB, saveDBAndSync, persistLocalDB, reconcileCloud } from '../services/db';
import { createId } from '../services/id';
import { MODULE_GROUPS, ALL_MODULE_PATHS, ESSENTIAL_MODULES } from '../services/moduleConfig';
import { Capacitor } from '@capacitor/core';

// Custom URL scheme used as the OAuth redirect URI on native iOS/Android.
// Must match AndroidManifest.xml intent filter + Supabase Redirect URL config.
const NATIVE_OAUTH_REDIRECT = 'com.lobohub.app://login-callback';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function generateJoinCode(existingFamilies: Family[]): string {
  let code = '';
  do {
    code = Math.random().toString(36).substring(2, 8).toUpperCase();
  } while (existingFamilies.some((f) => f.joinCode === code));
  return code;
}

type AuthView = 'LOGIN' | 'SIGNUP' | 'ONBOARDING' | 'MODULE_SETUP' | 'FORGOT_PASSWORD';

// ---------------------------------------------------------------------------
// Social auth provider SVG icons (inline — no image imports needed)
// ---------------------------------------------------------------------------

const GoogleIcon = () => (
  <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
    <path fill="#4285F4" d="M23.745 12.27c0-.79-.07-1.54-.19-2.27h-11.36v4.51h6.5c-.29 1.48-1.14 2.73-2.4 3.58v3h3.86c2.26-2.09 3.57-5.17 3.57-8.82z"/>
    <path fill="#34A853" d="M12.195 24c3.24 0 5.95-1.08 7.93-2.91l-3.86-3c-1.08.72-2.45 1.16-4.07 1.16-3.13 0-5.78-2.11-6.73-4.96h-3.98v3.09C3.515 21.3 7.565 24 12.195 24z"/>
    <path fill="#FBBC05" d="M5.465 14.29c-.25-.72-.38-1.49-.38-2.29s.14-1.57.38-2.29V6.62h-3.98a11.86 11.86 0 000 10.76l3.98-3.09z"/>
    <path fill="#EA4335" d="M12.195 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C18.145 1.19 15.435 0 12.195 0 7.565 0 3.515 2.7 1.485 6.62l3.98 3.09c.95-2.85 3.6-4.96 6.73-4.96z"/>
  </svg>
);

const AppleIcon = () => (
  <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true">
    <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
  </svg>
);

const MicrosoftIcon = () => (
  <svg viewBox="0 0 21 21" width="18" height="18" aria-hidden="true">
    <rect x="1" y="1" width="9" height="9" fill="#f25022"/>
    <rect x="11" y="1" width="9" height="9" fill="#7fba00"/>
    <rect x="1" y="11" width="9" height="9" fill="#00a4ef"/>
    <rect x="11" y="11" width="9" height="9" fill="#ffb900"/>
  </svg>
);

// ---------------------------------------------------------------------------
// AuthFlow component
// ---------------------------------------------------------------------------

interface AuthFlowProps {
  onAuthenticated: (user: User, family: Family) => void;
}

const AuthFlow: React.FC<AuthFlowProps> = ({ onAuthenticated }) => {
  const [view, setView] = useState<AuthView>('LOGIN');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [familyName, setFamilyName] = useState('');
  const [joinCode, setJoinCode] = useState('');
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [currentUser, setCurrentUser] = useState<User | null>(null);
  const [onboardingOption, setOnboardingOption] = useState<'CREATE' | 'JOIN' | null>(null);
  const [createdFamily, setCreatedFamily] = useState<Family | null>(null);
  const [selectedModules, setSelectedModules] = useState<string[]>(ESSENTIAL_MODULES);
  const [selectedCountry, setSelectedCountry] = useState('US');
  const [resetSent, setResetSent] = useState(false);

  const toggleModule = (path: string) =>
    setSelectedModules(prev => prev.includes(path) ? prev.filter(p => p !== path) : [...prev, path]);

  // ── OAuth social sign-in ──────────────────────────────────────────────────
  // Requires providers to be enabled in your Supabase dashboard:
  //   Authentication → Providers → Google / Apple / Azure (Microsoft)
  // Set the redirect URL to your app's origin in each provider's settings.

  const signInWithProvider = async (
    provider: 'google' | 'apple' | 'azure',
    extraScopes?: string,
  ) => {
    if (!supabase || !isSupabaseConfigured()) {
      setError('Cloud auth is not configured. Please use email/password.');
      return;
    }
    setError('');
    setIsLoading(true);
    const { error } = await supabase.auth.signInWithOAuth({
      provider,
      options: {
        // On native (iOS/Android) redirect to our custom URL scheme so the OS
        // intercepts the callback and hands it to the Capacitor App plugin via
        // appUrlOpen instead of trying to load localhost in the browser.
        // On web, redirect back to the app's own origin so App.tsx init()
        // exchanges the code normally.
        redirectTo: Capacitor.isNativePlatform()
          ? NATIVE_OAUTH_REDIRECT
          : window.location.origin + window.location.pathname,
        scopes: extraScopes,
      },
    });
    if (error) {
      setError(error.message);
      setIsLoading(false);
    }
    // No else — the page redirects to the OAuth provider.
  };

  // Auto-continue if a Supabase session already exists when this screen mounts.
  useEffect(() => {
    if (!supabase || !isSupabaseConfigured()) return;
    let active = true;
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!active || !session?.user) return;
      setCachedSession(session);
      resolveUserProfile(session.user.id, session.user.email ?? '');
    });
    return () => { active = false; };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // On native, the OAuth code is exchanged in App.tsx's appUrlOpen handler.
  // That triggers a SIGNED_IN event here so we can resolve the user profile
  // without requiring a full page reload.
  useEffect(() => {
    if (!supabase || !isSupabaseConfigured() || !Capacitor.isNativePlatform()) return;
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'SIGNED_IN' && session?.user) {
        setCachedSession(session);
        resolveUserProfile(session.user.id, session.user.email ?? '');
      }
    });
    return () => subscription.unsubscribe();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const resolveUserProfile = async (authUserId: string, authEmail: string) => {
    if (supabase && isSupabaseConfigured()) {
      void supabase.rpc('claim_owned_families').then(({ error: err }) => {
        if (err) console.warn('[Auth] claim_owned_families failed (non-fatal):', err);
      });
    }

    let db = getDB();
    let user = db.users.find(u => u.id === authUserId);

    if (!user) {
      const reconciled = await reconcileCloud(db);
      if (reconciled !== db) {
        persistLocalDB(reconciled);
        db = reconciled;
      }
      user = db.users.find(u => u.id === authUserId);
    }

    if (!user) {
      const oldUser = db.users.find(u => u.email === authEmail);
      if (oldUser) {
        const oldId = oldUser.id;
        const newId = authUserId;
        const migratedDb: typeof db = {
          ...db,
          users: db.users.map(u => u.id === oldId ? { ...u, id: newId } : u),
          familyMembers: db.familyMembers.map(m => m.userId === oldId ? { ...m, userId: newId } : m),
          families: db.families.map(f => f.ownerId === oldId ? { ...f, ownerId: newId } : f),
          fitness: db.fitness.map(r => (r as any).userId === oldId ? { ...r, userId: newId } : r),
          fitnessPlans: db.fitnessPlans.map(r => (r as any).userId === oldId ? { ...r, userId: newId } : r),
          dailyHabits: db.dailyHabits.map(r => (r as any).userId === oldId ? { ...r, userId: newId } : r),
          dailyHabitCompletions: db.dailyHabitCompletions.map(r => (r as any).userId === oldId ? { ...r, userId: newId } : r),
          aiHistory: db.aiHistory.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
          tasks: db.tasks.map(t => ({
            ...t,
            creatorId: t.creatorId === oldId ? newId : t.creatorId,
            assignees: t.assignees.map(a => a === oldId ? newId : a),
          })),
          chores: db.chores.map(c => ({
            ...c,
            creatorId: c.creatorId === oldId ? newId : c.creatorId,
            assignees: c.assignees.map(a => a === oldId ? newId : a),
          })),
          choreCompletions: db.choreCompletions.map(r => (r as any).userId === oldId ? { ...r, userId: newId } : r),
          rewardRedemptions: db.rewardRedemptions.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
          savingsGoals: db.savingsGoals.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
          pollVotes: db.pollVotes.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
          prayerWall: db.prayerWall.map(r => r.creatorId === oldId ? { ...r, creatorId: newId } : r),
          readingPlans: db.readingPlans.map(r => r.creatorId === oldId ? { ...r, creatorId: newId } : r),
          readingPlanProgress: db.readingPlanProgress.map(r => r.userId === oldId ? { ...r, userId: newId } : r),
          periodCycles: (db.periodCycles || []).map(r => r.userId === oldId ? { ...r, userId: newId } : r),
          periodSymptoms: (db.periodSymptoms || []).map(r => r.userId === oldId ? { ...r, userId: newId } : r),
        };
        persistLocalDB(migratedDb);
        db = migratedDb;
        user = db.users.find(u => u.id === newId)!;
        console.info('[Auth] Migrated existing account from', oldId, '→', newId);
      }
    }

    if (!user) {
      const pendingRaw = localStorage.getItem('pending_signup');
      let pending: { name?: string; email?: string } | null = null;
      try { pending = pendingRaw ? JSON.parse(pendingRaw) : null; } catch { /* corrupted data */ }
      const pendingName = (pending?.email === authEmail ? pending.name : null)
        || authEmail.split('@')[0];
      localStorage.removeItem('pending_signup');

      const newUser: User = {
        id: authUserId,
        name: pendingName,
        email: authEmail,
        avatar: `https://api.dicebear.com/9.x/initials/svg?seed=${encodeURIComponent(pendingName)}`,
      };
      const freshDb = getDB();
      saveDB({ ...freshDb, users: [...freshDb.users, newUser] });
      setCurrentUser(newUser);
      setView('ONBOARDING');
      return;
    }

    const membership = db.familyMembers.find(m => m.userId === user!.id);
    const family = membership ? db.families.find(f => f.id === membership.familyId) : null;
    if (family) {
      onAuthenticated(user, family);
    } else {
      setCurrentUser(user);
      setView('ONBOARDING');
    }
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setIsLoading(true);
    try {
      if (supabase && isSupabaseConfigured()) {
        const { data, error: authError } = await supabase.auth.signInWithPassword({ email, password });
        if (authError) { setError(authError.message); return; }
        if (data.session) setCachedSession(data.session);
        if (data.user) await resolveUserProfile(data.user.id, data.user.email ?? email);
      } else {
        const db = getDB();
        const user = db.users.find(u => u.email === email);
        if (!user) { setError('No account found with that email'); return; }
        const membership = db.familyMembers.find(m => m.userId === user.id);
        const family = membership ? db.families.find(f => f.id === membership.familyId) : null;
        if (family) { onAuthenticated(user, family); } else { setCurrentUser(user); setView('ONBOARDING'); }
      }
    } catch (err: any) {
      setError(err?.message || 'An unexpected error occurred. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleForgotPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setIsLoading(true);
    try {
      if (supabase && isSupabaseConfigured()) {
        const { error: resetError } = await supabase.auth.resetPasswordForEmail(email, {
          redirectTo: window.location.href,
        });
        if (resetError) { setError(resetError.message); return; }
        setResetSent(true);
      } else {
        setError('Password reset requires Supabase to be configured.');
      }
    } catch (err: any) {
      setError(err?.message || 'An unexpected error occurred. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleSignup = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setIsLoading(true);
    try {
      if (supabase && isSupabaseConfigured()) {
        const { data, error: authError } = await supabase.auth.signUp({ email, password });
        if (authError) { setError(authError.message); return; }
        if (data.session && data.user) {
          setCachedSession(data.session);
          const db = getDB();
          const existingUser = db.users.find(u => u.email === email);
          if (existingUser) {
            await resolveUserProfile(data.user.id, email);
          } else {
            const newUser: User = {
              id: data.user.id,
              name,
              email,
              avatar: `https://api.dicebear.com/9.x/initials/svg?seed=${encodeURIComponent(name)}`,
            };
            saveDB({ ...db, users: [...db.users, newUser] });
            setCurrentUser(newUser);
            setView('ONBOARDING');
          }
        } else if (data.user) {
          localStorage.setItem('pending_signup', JSON.stringify({ name, email }));
          setError("Check your email and click the confirmation link. You'll be brought straight back here.");
          setView('LOGIN');
        }
      } else {
        const db = getDB();
        if (db.users.some(u => u.email === email)) {
          setError('An account with this email already exists. Please sign in.');
          setView('LOGIN');
          return;
        }
        const newUser: User = {
          id: createId(),
          name,
          email,
          avatar: `https://api.dicebear.com/9.x/initials/svg?seed=${encodeURIComponent(name)}`,
        };
        saveDB({ ...db, users: [...db.users, newUser] });
        setCurrentUser(newUser);
        setView('ONBOARDING');
      }
    } catch (err: any) {
      setError(err?.message || 'An unexpected error occurred. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleCreateFamily = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!currentUser || !familyName) return;
    setIsLoading(true);
    try {
      const db = getDB();
      const newJoinCode = generateJoinCode(db.families);
      const newFamily: Family = {
        id: createId(),
        name: familyName,
        ownerId: currentUser.id,
        joinCode: newJoinCode,
        createdAt: new Date().toISOString(),
      };
      const newDb = {
        ...db,
        families: [...db.families, newFamily],
        familyMembers: [...db.familyMembers, { userId: currentUser.id, familyId: newFamily.id, role: 'OWNER' as const }],
      };
      await saveDBAndSync(newDb);
      setCreatedFamily(newFamily);
      setSelectedModules(ESSENTIAL_MODULES);
      setView('MODULE_SETUP');
    } catch (err: any) {
      setError(err?.message || 'Failed to create family. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleModuleSetup = async () => {
    if (!currentUser || !createdFamily) return;
    setIsLoading(true);
    const db = getDB();
    const allSelected = ALL_MODULE_PATHS.every(p => selectedModules.includes(p));
    const updatedFamily: Family = {
      ...createdFamily,
      enabledModules: allSelected ? undefined : selectedModules,
      settings: getCountryDefaults(selectedCountry),
    };
    const updatedDb = {
      ...db,
      families: db.families.map(f => f.id === createdFamily.id ? updatedFamily : f),
    };
    await saveDBAndSync(updatedDb);
    setIsLoading(false);
    onAuthenticated(currentUser, updatedFamily);
  };

  const handleJoinFamily = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!currentUser || !joinCode) return;
    setIsLoading(true);
    setError('');
    try {
      const authUserId = getCachedSession()?.user?.id || currentUser.id;
      let family: Family | undefined;
      const code = joinCode.trim().toUpperCase();

      if (supabase && isSupabaseConfigured()) {
        const { data, error: sbError } = await supabase
          .rpc('find_family_by_join_code', { code });
        if (sbError) { setError(`Could not look up code: ${sbError.message}`); return; }
        if (data && data.length > 0) family = data[0] as Family;
      }

      if (!family) {
        const db = getDB();
        family = db.families.find(f => f.joinCode === code);
      }

      if (!family) { setError('Invalid join code. Please double check with your pack.'); return; }

      const db = getDB();
      if (db.familyMembers.some(m => m.userId === authUserId && m.familyId === family!.id)) {
        onAuthenticated(currentUser, family);
        return;
      }

      const newDb = {
        ...db,
        families: db.families.some(f => f.id === family!.id)
          ? db.families
          : [...db.families, family!],
        familyMembers: [...db.familyMembers, {
          userId: authUserId,
          familyId: family.id,
          role: (family.ownerId === authUserId ? 'OWNER' : 'MEMBER') as 'OWNER' | 'MEMBER',
        }],
      };
      await saveDBAndSync(newDb);
      onAuthenticated(currentUser, family);
    } catch (err: any) {
      setError(err?.message || 'Failed to join. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-[#fcfcf9] p-4">
      <div className="bg-white w-full max-w-md rounded-[2.5rem] p-10 shadow-2xl border border-stone-100 animate-in fade-in zoom-in-95 duration-300">
        <div className="text-center mb-8">
          <div className="w-16 h-16 bg-indigo-600 rounded-2xl flex items-center justify-center mx-auto mb-4 text-white shadow-lg shadow-indigo-100">
            <Sparkles size={32} />
          </div>
          <h1 className="text-3xl font-black text-stone-800 brand-font tracking-tight">{APP_CONFIG.appName}</h1>
          <p className="text-stone-500 text-sm">
            {view === 'LOGIN' ? APP_CONFIG.loginTagline
              : view === 'SIGNUP' ? APP_CONFIG.signupTagline
              : view === 'FORGOT_PASSWORD' ? 'Reset your password.'
              : APP_CONFIG.onboardingTagline}
          </p>
        </div>

        {error && (
          <div className="mb-6 p-3 bg-red-50 border border-red-100 text-red-600 text-xs font-bold rounded-xl text-center">
            {error}
          </div>
        )}

        {view === 'LOGIN' && (
          <form onSubmit={handleLogin} className="space-y-4">
            {!(supabase && isSupabaseConfigured()) && (
              <div className="p-3 bg-amber-50 border border-amber-200 text-amber-700 text-xs font-semibold rounded-xl">
                ⚠️ Supabase not detected — running in local mode. Passwords are not checked in local mode.
              </div>
            )}
            <div className="relative">
              <Mail className="absolute left-4 top-4 text-stone-400" size={18} />
              <input type="email" placeholder="Email Address" required value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full pl-12 pr-4 py-4 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
              />
            </div>
            <div className="relative">
              <Lock className="absolute left-4 top-4 text-stone-400" size={18} />
              <input type="password" placeholder="Password" required value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full pl-12 pr-4 py-4 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
              />
            </div>
            <div className="flex justify-end">
              <button type="button" onClick={() => { setError(''); setResetSent(false); setView('FORGOT_PASSWORD'); }}
                className="text-xs text-indigo-600 font-semibold hover:underline">
                Forgot password?
              </button>
            </div>
            <button type="submit" disabled={isLoading}
              className="w-full bg-indigo-600 text-white py-4 rounded-2xl font-bold hover:bg-indigo-700 shadow-xl shadow-indigo-100 transition-all flex items-center justify-center space-x-2 disabled:opacity-60 disabled:cursor-not-allowed">
              {isLoading ? <Loader2 size={18} className="animate-spin" /> : <><span>Sign In</span><ArrowRight size={18} /></>}
            </button>

            {supabase && isSupabaseConfigured() && (
              <>
                <div className="relative flex items-center my-2">
                  <div className="flex-1 border-t border-stone-200" />
                  <span className="mx-3 text-xs text-stone-400 font-medium">or continue with</span>
                  <div className="flex-1 border-t border-stone-200" />
                </div>
                <div className="space-y-2">
                  <button type="button" onClick={() => signInWithProvider('google', 'email profile openid')} disabled={isLoading}
                    className="w-full flex items-center justify-center gap-3 py-3 border border-stone-200 rounded-2xl font-semibold text-stone-700 hover:bg-stone-50 transition-colors text-sm disabled:opacity-60">
                    <GoogleIcon />Continue with Google
                  </button>
                  <button type="button" onClick={() => signInWithProvider('apple')} disabled={isLoading}
                    className="w-full flex items-center justify-center gap-3 py-3 border border-stone-200 rounded-2xl font-semibold text-stone-700 hover:bg-stone-50 transition-colors text-sm disabled:opacity-60">
                    <AppleIcon />Continue with Apple
                  </button>
                  <button type="button" onClick={() => signInWithProvider('azure', 'email profile openid offline_access')} disabled={isLoading}
                    className="w-full flex items-center justify-center gap-3 py-3 border border-stone-200 rounded-2xl font-semibold text-stone-700 hover:bg-stone-50 transition-colors text-sm disabled:opacity-60">
                    <MicrosoftIcon />Continue with Microsoft
                  </button>
                </div>
              </>
            )}

            <p className="text-center text-sm text-stone-400 mt-4">
              Don't have an account? <button type="button" onClick={() => setView('SIGNUP')} className="text-indigo-600 font-bold hover:underline">Sign Up</button>
            </p>
          </form>
        )}

        {view === 'FORGOT_PASSWORD' && (
          <div className="space-y-4">
            {resetSent ? (
              <div className="text-center space-y-4">
                <div className="w-14 h-14 bg-green-50 rounded-2xl flex items-center justify-center mx-auto">
                  <Check size={28} className="text-green-600" />
                </div>
                <p className="text-stone-700 font-semibold">Check your email</p>
                <p className="text-stone-500 text-sm">We sent a password reset link to <span className="font-bold text-stone-700">{email}</span>.</p>
                <button type="button" onClick={() => { setResetSent(false); setError(''); setView('LOGIN'); }}
                  className="text-indigo-600 font-bold text-sm hover:underline">Back to Sign In</button>
              </div>
            ) : (
              <form onSubmit={handleForgotPassword} className="space-y-4">
                <p className="text-stone-500 text-sm text-center">Enter your email and we'll send you a reset link.</p>
                <div className="relative">
                  <Mail className="absolute left-4 top-4 text-stone-400" size={18} />
                  <input type="email" placeholder="Email Address" required value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="w-full pl-12 pr-4 py-4 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
                  />
                </div>
                <button type="submit" disabled={isLoading}
                  className="w-full bg-indigo-600 text-white py-4 rounded-2xl font-bold hover:bg-indigo-700 shadow-xl shadow-indigo-100 transition-all flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-not-allowed">
                  {isLoading ? <Loader2 size={18} className="animate-spin" /> : 'Send Reset Link'}
                </button>
                <p className="text-center text-sm text-stone-400">
                  <button type="button" onClick={() => { setError(''); setView('LOGIN'); }} className="text-indigo-600 font-bold hover:underline">Back to Sign In</button>
                </p>
              </form>
            )}
          </div>
        )}

        {view === 'SIGNUP' && (
          <form onSubmit={handleSignup} className="space-y-4">
            {!(supabase && isSupabaseConfigured()) && (
              <div className="p-3 bg-amber-50 border border-amber-200 text-amber-700 text-xs font-semibold rounded-xl">
                ⚠️ Supabase not detected — running in local mode.
              </div>
            )}
            <div className="relative">
              <UserIcon className="absolute left-4 top-4 text-stone-400" size={18} />
              <input type="text" placeholder="Full Name" required value={name}
                onChange={(e) => setName(e.target.value)}
                className="w-full pl-12 pr-4 py-4 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
              />
            </div>
            <div className="relative">
              <Mail className="absolute left-4 top-4 text-stone-400" size={18} />
              <input type="email" placeholder="Email Address" required value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full pl-12 pr-4 py-4 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
              />
            </div>
            <div className="relative">
              <Lock className="absolute left-4 top-4 text-stone-400" size={18} />
              <input type="password" placeholder="Password" required value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full pl-12 pr-4 py-4 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
              />
            </div>
            <button type="submit" disabled={isLoading}
              className="w-full bg-indigo-600 text-white py-4 rounded-2xl font-bold hover:bg-indigo-700 shadow-xl shadow-indigo-100 transition-all flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-not-allowed">
              {isLoading ? <Loader2 size={18} className="animate-spin" /> : 'Create Account'}
            </button>

            {supabase && isSupabaseConfigured() && (
              <>
                <div className="relative flex items-center my-2">
                  <div className="flex-1 border-t border-stone-200" />
                  <span className="mx-3 text-xs text-stone-400 font-medium">or sign up with</span>
                  <div className="flex-1 border-t border-stone-200" />
                </div>
                <div className="space-y-2">
                  <button type="button" onClick={() => signInWithProvider('google', 'email profile openid')} disabled={isLoading}
                    className="w-full flex items-center justify-center gap-3 py-3 border border-stone-200 rounded-2xl font-semibold text-stone-700 hover:bg-stone-50 transition-colors text-sm disabled:opacity-60">
                    <GoogleIcon />Continue with Google
                  </button>
                  <button type="button" onClick={() => signInWithProvider('apple')} disabled={isLoading}
                    className="w-full flex items-center justify-center gap-3 py-3 border border-stone-200 rounded-2xl font-semibold text-stone-700 hover:bg-stone-50 transition-colors text-sm disabled:opacity-60">
                    <AppleIcon />Continue with Apple
                  </button>
                  <button type="button" onClick={() => signInWithProvider('azure', 'email profile openid offline_access')} disabled={isLoading}
                    className="w-full flex items-center justify-center gap-3 py-3 border border-stone-200 rounded-2xl font-semibold text-stone-700 hover:bg-stone-50 transition-colors text-sm disabled:opacity-60">
                    <MicrosoftIcon />Continue with Microsoft
                  </button>
                </div>
              </>
            )}

            <p className="text-center text-sm text-stone-400 mt-4">
              Already have an account? <button type="button" onClick={() => setView('LOGIN')} className="text-indigo-600 font-bold hover:underline">Login</button>
            </p>
          </form>
        )}

        {view === 'ONBOARDING' && (
          <div className="space-y-6">
            {!onboardingOption ? (
              <div className="grid grid-cols-1 gap-4">
                <button onClick={() => setOnboardingOption('CREATE')}
                  className="flex flex-col items-center justify-center p-8 bg-indigo-50 border-2 border-indigo-100 rounded-3xl hover:bg-indigo-100 transition-all group">
                  <Home size={32} className="text-indigo-600 mb-2 group-hover:scale-110 transition-transform" />
                  <span className="font-bold text-indigo-900">{APP_CONFIG.createHubLabel}</span>
                  <span className="text-xs text-indigo-600 mt-1">{APP_CONFIG.createHubSubLabel}</span>
                </button>
                <button onClick={() => setOnboardingOption('JOIN')}
                  className="flex flex-col items-center justify-center p-8 bg-stone-50 border-2 border-stone-100 rounded-3xl hover:bg-stone-100 transition-all group">
                  <UserPlus size={32} className="text-stone-500 mb-2 group-hover:scale-110 transition-transform" />
                  <span className="font-bold text-stone-800">{APP_CONFIG.joinHubLabel}</span>
                  <span className="text-xs text-stone-500 mt-1">{APP_CONFIG.joinHubSubLabel}</span>
                </button>
              </div>
            ) : onboardingOption === 'CREATE' ? (
              <form onSubmit={handleCreateFamily} className="space-y-4">
                <div className="bg-indigo-50 p-4 rounded-2xl mb-4 flex items-start space-x-3 text-indigo-700">
                  <Home className="shrink-0 mt-1" size={20} />
                  <p className="text-sm font-medium leading-relaxed">Name your home! This is what your shared space will be called.</p>
                </div>
                <div className="relative">
                  <Home className="absolute left-4 top-4 text-stone-400" size={18} />
                  <input type="text" placeholder={APP_CONFIG.familyNamePlaceholder} required autoFocus
                    value={familyName} onChange={(e) => setFamilyName(e.target.value)}
                    className="w-full pl-12 pr-4 py-4 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
                  />
                </div>
                <div className="flex gap-2">
                  <button type="button" onClick={() => setOnboardingOption(null)} className="flex-1 py-4 text-stone-500 font-bold">Back</button>
                  <button type="submit" disabled={isLoading}
                    className="flex-[2] bg-indigo-600 text-white py-4 rounded-2xl font-bold hover:bg-indigo-700 shadow-xl shadow-indigo-100 transition-all flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-not-allowed">
                    {isLoading ? <Loader2 size={18} className="animate-spin" /> : 'Create Home'}
                  </button>
                </div>
              </form>
            ) : (
              <form onSubmit={handleJoinFamily} className="space-y-4">
                <div className="bg-stone-50 p-4 rounded-2xl mb-4 flex items-start space-x-3 text-stone-600">
                  <Key className="shrink-0 mt-1" size={20} />
                  <p className="text-sm font-medium leading-relaxed">Enter the 6-character code provided by your family admin.</p>
                </div>
                <div className="relative">
                  <Key className="absolute left-4 top-4 text-stone-400" size={18} />
                  <input type="text" placeholder="Join Code (e.g., ABC123)" required autoFocus maxLength={6}
                    value={joinCode} onChange={(e) => setJoinCode(e.target.value.toUpperCase())}
                    className="w-full pl-12 pr-4 py-4 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-bold text-xl tracking-widest text-stone-900 placeholder:text-stone-400"
                  />
                </div>
                <div className="flex gap-2">
                  <button type="button" onClick={() => setOnboardingOption(null)} className="flex-1 py-4 text-stone-500 font-bold">Back</button>
                  <button type="submit" disabled={isLoading}
                    className="flex-[2] bg-indigo-600 text-white py-4 rounded-2xl font-bold hover:bg-indigo-700 shadow-xl shadow-indigo-100 transition-all flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-not-allowed">
                    {isLoading ? <><Loader2 size={18} className="animate-spin" />Joining…</> : 'Join Pack'}
                  </button>
                </div>
              </form>
            )}
          </div>
        )}

        {view === 'MODULE_SETUP' && (
          <div className="space-y-5">
            <div>
              <p className="text-xs font-black text-indigo-500 uppercase tracking-widest mb-1">Step 3 of 3</p>
              <h2 className="text-lg font-bold text-stone-800">Set up your home</h2>
              <p className="text-sm text-stone-400 mt-0.5">Pick your region and the modules your family needs.</p>
            </div>

            <div>
              <div className="flex items-center gap-2 mb-2">
                <Globe size={14} className="text-indigo-500 shrink-0" />
                <p className="text-[11px] font-black text-stone-400 uppercase tracking-widest">Your Region</p>
              </div>
              <div className="max-h-36 overflow-y-auto rounded-2xl border border-stone-100 divide-y divide-stone-50">
                {COUNTRIES.map(c => {
                  const active = selectedCountry === c.code;
                  return (
                    <button key={c.code} type="button" onClick={() => setSelectedCountry(c.code)}
                      className={`w-full flex items-center gap-3 px-3 py-2 text-left transition-colors ${active ? 'bg-indigo-600 text-white' : 'bg-white hover:bg-stone-50 text-stone-700'}`}>
                      <span className="text-lg shrink-0">{c.flag}</span>
                      <span className="font-semibold text-sm flex-1 truncate">{c.name}</span>
                      <span className={`text-xs shrink-0 ${active ? 'text-indigo-200' : 'text-stone-400'}`}>
                        {c.currencyCode} · {c.units === 'imperial' ? 'Imperial' : 'Metric'}
                      </span>
                      {active && <Check size={14} className="text-white shrink-0" />}
                    </button>
                  );
                })}
              </div>
            </div>

            <div className="flex gap-2">
              <button onClick={() => setSelectedModules(ESSENTIAL_MODULES)}
                className="flex-1 py-2 bg-stone-100 text-stone-600 rounded-xl text-xs font-bold hover:bg-stone-200 transition-colors">
                ⚡ Essentials
              </button>
              <button onClick={() => setSelectedModules([...ALL_MODULE_PATHS])}
                className="flex-1 py-2 bg-stone-100 text-stone-600 rounded-xl text-xs font-bold hover:bg-stone-200 transition-colors">
                ✨ Everything
              </button>
            </div>

            {MODULE_GROUPS.map(group => (
              <div key={group.label}>
                <p className="text-[10px] font-black text-stone-400 uppercase tracking-widest mb-2">{group.label}</p>
                <div className="grid grid-cols-2 gap-2">
                  {group.modules.map(m => {
                    const active = selectedModules.includes(m.path);
                    return (
                      <button key={m.path} onClick={() => toggleModule(m.path)}
                        className={`flex items-center gap-3 p-3 rounded-2xl text-left transition-all ${active ? 'bg-indigo-600 text-white shadow-sm shadow-indigo-200' : 'bg-stone-50 text-stone-600 hover:bg-stone-100 border border-stone-100'}`}>
                        <span className="text-2xl shrink-0">{m.emoji}</span>
                        <div className="min-w-0">
                          <p className="font-bold text-sm leading-tight truncate">{m.name}</p>
                          <p className={`text-[10px] leading-tight ${active ? 'text-indigo-200' : 'text-stone-400'}`}>{m.desc}</p>
                        </div>
                      </button>
                    );
                  })}
                </div>
              </div>
            ))}

            <button onClick={handleModuleSetup} disabled={selectedModules.length === 0 || isLoading}
              className="w-full bg-indigo-600 text-white py-4 rounded-2xl font-bold hover:bg-indigo-700 shadow-xl shadow-indigo-100 transition-all flex items-center justify-center gap-2 disabled:opacity-40 disabled:cursor-not-allowed">
              {isLoading ? <><Loader2 size={18} className="animate-spin" />Saving…</> : <>Let's go!<ArrowRight size={18} /></>}
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default AuthFlow;

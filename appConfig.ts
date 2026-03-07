/**
 * appConfig.ts — Central white-label brand configuration.
 *
 * Every user-facing string and brand value lives here.
 * Swap these out to completely rebrand the app for any family or publisher.
 */
export const APP_CONFIG = {
  // ── App identity (shown in stores, browser tabs, splash screens) ──────────
  appName: 'FamilyHub',
  appShortName: 'FamilyHub',
  appDescription: 'Family management hub for tasks, meals, budget, calendar, and more.',

  // ── Auth screen copy ──────────────────────────────────────────────────────
  loginTagline: 'Welcome back.',
  signupTagline: 'Create your account.',
  onboardingTagline: 'Set up your home.',

  // ── Onboarding ────────────────────────────────────────────────────────────
  createHubLabel: 'Create New Home',
  createHubSubLabel: 'Start fresh for your family',
  joinHubLabel: 'Join Existing Home',
  joinHubSubLabel: 'Join via invite code',
  familyNamePlaceholder: 'e.g., The Smith Family',

  // ── Sidebar / nav ─────────────────────────────────────────────────────────
  defaultUserName: 'Family Member',

  // ── AI features ───────────────────────────────────────────────────────────
  aiCoachName: 'AI Health Coach',

  // ── Internal storage keys (changing these breaks existing installs) ───────
  storageKey: 'lobohub_db',
  activeUserKey: 'lobohub_active_user_id',

  // ── Service worker ────────────────────────────────────────────────────────
  swCacheName: 'lobohub-cache-v1',
  swNotificationTag: 'lobohub',

  // ── Subscription pricing (shown in upgrade prompts and paywalls) ──────────
  trialDays: 14,
  pricing: {
    base: {
      monthly: '$9.99/month',
      annual: '$99/year',
      annualNote: '2 months free',
      label: 'FamilyHub Base',
      description: 'Everything your family needs — tasks, meals, budget, fitness, chores, devotionals, and more.',
    },
    ai: {
      monthly: '$17.99/month',
      annual: '$199/year',
      annualNote: '2 months free',
      label: 'FamilyHub AI',
      description: 'Everything in Base plus AI-powered recipe scraping, fitness plans, smart list categorisation, and more.',
    },
  },

  // ── Theme ─────────────────────────────────────────────────────────────────
  themeColor: '#6366f1',
  backgroundColor: '#fcfcf9',
} as const;

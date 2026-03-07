/**
 * hooks/useFeature.ts — Subscription tier feature gating
 *
 * Usage (in any component):
 *   const canUseAI    = useFeature(family, 'ai_recipes');
 *   const canUseBudget = useFeature(family, 'budget');
 *   if (!canUseBudget) return <UpgradePrompt requiredTier="base" ... />;
 *
 * Tier hierarchy:
 *   trial / base → all non-AI modules (budget, meals, fitness, rewards, etc.)
 *   ai           → everything in base + all AI-powered features
 *
 * RevenueCat is the source of truth on native platforms.
 * On web, always returns true (self-hosted deployments bypass payments).
 */

import { usePurchases } from '../contexts/PurchasesContext';
import { Family } from '../types';

export type Feature =
  // Base (non-AI) premium features — unlocked by Base or AI subscription
  | 'budget'
  | 'rewards'
  | 'meals_manual'
  | 'fitness_manual'
  // AI-powered features — unlocked by AI subscription only
  | 'ai_recipes'
  | 'ai_fitness'
  | 'ai_lists'
  | 'ai_devotional'
  | 'ai_budget'
  | 'ai_tasks'
  | 'ai_events'
  | 'ai_motivation'
  | 'ai_insights'
  | 'ai_prayer_wall'
  | 'ai_reading_plans';

const BASE_FEATURES: Feature[] = [
  'budget',
  'rewards',
  'meals_manual',
  'fitness_manual',
];

const AI_FEATURES: Feature[] = [
  'ai_recipes',
  'ai_fitness',
  'ai_lists',
  'ai_devotional',
  'ai_budget',
  'ai_tasks',
  'ai_events',
  'ai_motivation',
  'ai_insights',
  'ai_prayer_wall',
  'ai_reading_plans',
];

// Free features (always available, no subscription needed):
// Dashboard · Tasks · Lists · Calendar · Chores · Polls

/**
 * React hook — returns true when the feature is accessible.
 *
 * Priority order:
 *  1. RevenueCat AI entitlement  → all features unlocked
 *  2. RevenueCat Base entitlement → base features unlocked, AI locked
 *  3. family.subscriptionTier from DB → fallback for web/edge cases
 *  4. Default 'ai' during beta → everything open until you flip the switch
 *
 * To start enforcing payments:
 *  - In contexts/PurchasesContext.tsx set initial state to { hasBase: false, hasAI: false }
 */
export function useFeature(family: Family | null | undefined, feature: Feature): boolean {
  const { hasBase, hasAI } = usePurchases();

  // AI subscription unlocks everything
  if (hasAI) return true;

  // Base subscription unlocks non-AI features
  if (hasBase && BASE_FEATURES.includes(feature)) return true;
  if (hasBase && AI_FEATURES.includes(feature)) return false;

  // Fallback: use DB-stored tier (web / self-hosted)
  const tier = family?.subscriptionTier ?? 'ai'; // ← change 'ai' → 'base' or remove at launch
  if (tier === 'ai') return true;
  if (tier === 'base' || tier === 'trial') return BASE_FEATURES.includes(feature);
  return false;
}

/**
 * Non-hook version for use outside React components (e.g. server-side logic).
 */
export function hasFeature(
  family: Family | null | undefined,
  feature: Feature,
  hasBase = false,
  hasAI = false,
): boolean {
  if (hasAI) return true;
  if (hasBase) return BASE_FEATURES.includes(feature);
  const tier = family?.subscriptionTier ?? 'ai';
  if (tier === 'ai') return true;
  if (tier === 'base' || tier === 'trial') return BASE_FEATURES.includes(feature);
  return false;
}

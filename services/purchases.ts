/**
 * services/purchases.ts — RevenueCat integration
 *
 * Two subscription products, each with a 14-day free trial:
 *   Family Hub Base  → $9/month  — all non-AI features
 *   Family Hub AI    → $15/month — all features including AI
 *
 * All calls are no-ops on web (returns full access) so the Proxmox
 * deployment keeps working without any payment infrastructure.
 */

import { Capacitor } from '@capacitor/core';

// ── RevenueCat API keys ───────────────────────────────────────────────────
// Set via environment variables VITE_RC_IOS_API_KEY / VITE_RC_ANDROID_API_KEY.
const readRCEnv = (key: string): string => {
  try { return (import.meta.env as Record<string, string | undefined>)?.[key] ?? ''; } catch { return ''; }
};
export const RC_IOS_API_KEY = readRCEnv('VITE_RC_IOS_API_KEY');
export const RC_ANDROID_API_KEY = readRCEnv('VITE_RC_ANDROID_API_KEY');

/**
 * Entitlement IDs — must match exactly what you create in the RevenueCat dashboard.
 *
 * Set up two entitlements in RevenueCat:
 *   "Family Hub Base"  → granted by the $9/month product (+ 14-day trial)
 *   "Family Hub AI"    → granted by the $15/month product (+ 14-day trial)
 *                        (AI product should also grant Base in RevenueCat)
 */
export const ENTITLEMENT_BASE = 'Family Hub Base';
export const ENTITLEMENT_AI = 'Family Hub AI';

// ── Entitlement result ────────────────────────────────────────────────────

export interface EntitlementStatus {
  hasBase: boolean; // active Base or AI subscription (or trial)
  hasAI: boolean;   // active AI subscription (or trial)
  isInTrial: boolean; // currently in the 14-day trial period
}

// ── Init ─────────────────────────────────────────────────────────────────

/**
 * Call once at app startup before any entitlement checks.
 * Safe to call on web — returns immediately without doing anything.
 */
export const initPurchases = async (): Promise<void> => {
  if (!Capacitor.isNativePlatform()) return;

  try {
    const apiKey =
      Capacitor.getPlatform() === 'ios' ? RC_IOS_API_KEY : RC_ANDROID_API_KEY;
    if (!apiKey) {
      console.warn('[FamilyHub] RevenueCat API key not configured, skipping init.');
      return;
    }
    const { Purchases, LOG_LEVEL } = await import('@revenuecat/purchases-capacitor');
    await Purchases.setLogLevel({ level: LOG_LEVEL.DEBUG });
    await Purchases.configure({ apiKey });
    console.info('[FamilyHub] RevenueCat configured for', Capacitor.getPlatform());
  } catch (e) {
    console.warn('[FamilyHub] RevenueCat init failed:', e);
  }
};

// ── Entitlement check ─────────────────────────────────────────────────────

/**
 * Returns the current entitlement status from RevenueCat.
 *
 * On web (non-native) always returns full access so the self-hosted
 * Proxmox deployment is unaffected.
 */
export const checkEntitlements = async (): Promise<EntitlementStatus> => {
  // Web / Docker deployment — always fully unlocked
  if (!Capacitor.isNativePlatform()) {
    return { hasBase: true, hasAI: true, isInTrial: false };
  }

  try {
    const { Purchases } = await import('@revenuecat/purchases-capacitor');
    const { customerInfo } = await Purchases.getCustomerInfo();

    const active = customerInfo.entitlements.active;
    const hasAI = typeof active[ENTITLEMENT_AI] !== 'undefined';
    const hasBase = hasAI || typeof active[ENTITLEMENT_BASE] !== 'undefined';

    // Check if any active entitlement is in a trial period
    const isInTrial = Object.values(active).some(
      (e: any) => e?.periodType === 'TRIAL',
    );

    return { hasBase, hasAI, isInTrial };
  } catch (e) {
    console.warn('[FamilyHub] Could not check entitlements:', e);
    return { hasBase: false, hasAI: false, isInTrial: false };
  }
};

// ── Paywall ───────────────────────────────────────────────────────────────

/**
 * Presents the RevenueCat native paywall (shows both plans + trial offer).
 * Returns true when the user completes a purchase or restore.
 * Returns false on web — purchases are native-only.
 */
export const presentPaywall = async (): Promise<boolean> => {
  if (!Capacitor.isNativePlatform()) return false;

  try {
    const { RevenueCatUI, PAYWALL_RESULT } = await import(
      '@revenuecat/purchases-capacitor-ui'
    );
    const { result } = await RevenueCatUI.presentPaywall();
    return (
      result === PAYWALL_RESULT.PURCHASED || result === PAYWALL_RESULT.RESTORED
    );
  } catch (e) {
    console.warn('[FamilyHub] Paywall error:', e);
    return false;
  }
};

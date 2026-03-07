/**
 * components/UpgradePrompt.tsx
 *
 * Paywall modal shown when a user tries to access a feature outside
 * their current subscription.
 *
 * requiredTier="base"  → prompts for the $9/month Base plan (14-day trial)
 * requiredTier="ai"    → prompts for the $15/month AI plan (14-day trial)
 *
 * On native iOS/Android: tapping the CTA opens the RevenueCat native paywall.
 * On web: shows a message directing users to the mobile app.
 *
 * During beta, hasBase/hasAI default to true so this modal never appears
 * until you flip the defaults in contexts/PurchasesContext.tsx.
 */

import React, { useState } from 'react';
import { Sparkles, X, LayoutGrid, Loader2, Smartphone, Check } from 'lucide-react';
import { SubscriptionTier } from '../types';
import { usePurchases } from '../contexts/PurchasesContext';
import { APP_CONFIG } from '../appConfig';
import { Capacitor } from '@capacitor/core';

interface UpgradePromptProps {
  requiredTier: Exclude<SubscriptionTier, 'trial'>;
  featureName: string;
  onClose: () => void;
  onSuccess?: () => void;
}

const PLAN_DETAILS = {
  base: {
    label: APP_CONFIG.pricing.base.label,
    monthly: APP_CONFIG.pricing.base.monthly,
    annual: APP_CONFIG.pricing.base.annual,
    annualNote: APP_CONFIG.pricing.base.annualNote,
    perks: [
      'Budget & expense tracking',
      'Meal planning & recipes',
      'Fitness tracking',
      'Rewards & chore points',
      'Unlimited family members',
    ],
    icon: LayoutGrid,
    accentBg: 'bg-stone-800',
    accentLight: 'bg-stone-50 border-stone-200 text-stone-700',
    btnClass: 'bg-stone-800 hover:bg-stone-900 shadow-stone-100',
  },
  ai: {
    label: APP_CONFIG.pricing.ai.label,
    monthly: APP_CONFIG.pricing.ai.monthly,
    annual: APP_CONFIG.pricing.ai.annual,
    annualNote: APP_CONFIG.pricing.ai.annualNote,
    perks: [
      'Everything in Base',
      'AI recipe scraping from any URL',
      'AI weekly fitness plans',
      'Smart grocery categorisation',
      'AI devotional generation',
      'AI budget insights',
    ],
    icon: Sparkles,
    accentBg: 'bg-indigo-600',
    accentLight: 'bg-indigo-50 border-indigo-100 text-indigo-600',
    btnClass: 'bg-indigo-600 hover:bg-indigo-700 shadow-indigo-100',
  },
} as const;

const UpgradePrompt: React.FC<UpgradePromptProps> = ({
  requiredTier,
  featureName,
  onClose,
  onSuccess,
}) => {
  const { presentPaywall } = usePurchases();
  const [isLoading, setIsLoading] = useState(false);
  const isNative = Capacitor.isNativePlatform();
  const plan = PLAN_DETAILS[requiredTier];
  const Icon = plan.icon;

  const handleUpgrade = async () => {
    if (!isNative) return;
    setIsLoading(true);
    try {
      const purchased = await presentPaywall();
      if (purchased) {
        onSuccess?.();
        onClose();
      }
    } catch (err) {
      console.error('[UpgradePrompt] Paywall error:', err);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
      <div className="bg-white w-full max-w-sm rounded-3xl shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-200">

        {/* Header */}
        <div className={`${plan.accentBg} p-8 text-white text-center relative`}>
          <button
            onClick={onClose}
            className="absolute top-4 right-4 p-1.5 rounded-xl hover:bg-white/10 transition-colors"
          >
            <X size={18} />
          </button>

          <div className="w-14 h-14 bg-white/20 rounded-2xl flex items-center justify-center mx-auto mb-4">
            <Icon size={28} />
          </div>

          <p className="text-xs font-black uppercase tracking-widest opacity-70 mb-1">
            Unlock {featureName}
          </p>
          <h2 className="text-2xl font-black">{plan.label}</h2>

          <div className="mt-3 inline-flex items-center bg-white/20 rounded-full px-3 py-1">
            <span className="text-xs font-bold">
              {APP_CONFIG.trialDays}-day free trial — then {plan.monthly}
            </span>
          </div>
        </div>

        {/* Body */}
        <div className="p-6 space-y-4">

          {/* Perks list */}
          <ul className="space-y-2">
            {plan.perks.map((perk) => (
              <li key={perk} className="flex items-center gap-2.5 text-sm text-stone-700">
                <div className={`w-5 h-5 rounded-full flex items-center justify-center shrink-0 border ${plan.accentLight}`}>
                  <Check size={11} strokeWidth={3} />
                </div>
                {perk}
              </li>
            ))}
          </ul>

          {/* Annual nudge */}
          <div className="bg-amber-50 border border-amber-100 rounded-2xl px-4 py-3 flex items-center justify-between">
            <div>
              <p className="text-xs font-black text-amber-800 uppercase tracking-wide">Save with annual</p>
              <p className="text-sm font-bold text-amber-900">{plan.annual}</p>
            </div>
            <span className="text-xs font-bold bg-amber-200 text-amber-800 px-2 py-1 rounded-full">
              {plan.annualNote}
            </span>
          </div>

          {/* CTA */}
          {isNative ? (
            <button
              onClick={handleUpgrade}
              disabled={isLoading}
              className={`w-full py-4 rounded-2xl font-bold text-white transition-all shadow-lg flex items-center justify-center gap-2 ${plan.btnClass} disabled:opacity-60`}
            >
              {isLoading
                ? <Loader2 size={18} className="animate-spin" />
                : `Start ${APP_CONFIG.trialDays}-day free trial`}
            </button>
          ) : (
            <div className="flex items-center gap-3 bg-amber-50 border border-amber-100 rounded-2xl p-4">
              <Smartphone size={20} className="text-amber-500 shrink-0" />
              <p className="text-xs text-amber-700 font-medium leading-relaxed">
                Subscriptions are managed in the iOS and Android apps.
              </p>
            </div>
          )}

          <p className="text-center text-xs text-stone-400">
            No charge until trial ends · Cancel anytime
          </p>

          <button
            onClick={onClose}
            className="w-full pt-1 pb-2 text-stone-400 text-sm font-medium hover:text-stone-600 transition-colors"
          >
            Not now
          </button>
        </div>
      </div>
    </div>
  );
};

export default UpgradePrompt;

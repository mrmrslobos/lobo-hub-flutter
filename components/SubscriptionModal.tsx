import React, { useState } from 'react';
import { X, Sparkles, LayoutGrid, Check, Loader2, CreditCard, Smartphone, Star } from 'lucide-react';
import { usePurchases } from '../contexts/PurchasesContext';
import { APP_CONFIG } from '../appConfig';
import { Capacitor } from '@capacitor/core';

interface SubscriptionModalProps {
  onClose: () => void;
}

const SubscriptionModal: React.FC<SubscriptionModalProps> = ({ onClose }) => {
  const { hasBase, hasAI, isInTrial, presentPaywall } = usePurchases();
  const isNative = Capacitor.isNativePlatform();
  const [isLoading, setIsLoading] = useState(false);

  const handleUpgrade = async () => {
    if (!isNative) return;
    setIsLoading(true);
    try {
      await presentPaywall();
    } finally {
      setIsLoading(false);
    }
  };

  // Determine current plan label
  const currentPlanLabel = isInTrial
    ? `${APP_CONFIG.trialDays}-Day Free Trial`
    : hasAI
    ? APP_CONFIG.pricing.ai.label
    : hasBase
    ? APP_CONFIG.pricing.base.label
    : 'Free';

  const currentPlanColor = isInTrial
    ? 'bg-amber-100 text-amber-700'
    : hasAI
    ? 'bg-indigo-100 text-indigo-700'
    : hasBase
    ? 'bg-stone-100 text-stone-700'
    : 'bg-stone-100 text-stone-500';

  const plans = [
    {
      id: 'base',
      label: APP_CONFIG.pricing.base.label,
      monthly: APP_CONFIG.pricing.base.monthly,
      annual: APP_CONFIG.pricing.base.annual,
      annualNote: APP_CONFIG.pricing.base.annualNote,
      icon: LayoutGrid,
      accent: 'border-stone-300',
      headerBg: 'bg-stone-800',
      badgeBg: 'bg-stone-100 text-stone-700',
      checkBg: 'bg-stone-100 border-stone-200 text-stone-600',
      btnBg: 'bg-stone-800 hover:bg-stone-900',
      active: hasBase && !hasAI,
      perks: [
        'Budget & expense tracking',
        'Meal planning & recipes',
        'Fitness tracking',
        'Rewards & chore points',
        'Unlimited family members',
      ],
    },
    {
      id: 'ai',
      label: APP_CONFIG.pricing.ai.label,
      monthly: APP_CONFIG.pricing.ai.monthly,
      annual: APP_CONFIG.pricing.ai.annual,
      annualNote: APP_CONFIG.pricing.ai.annualNote,
      icon: Sparkles,
      accent: 'border-indigo-400 ring-2 ring-indigo-200',
      headerBg: 'bg-indigo-600',
      badgeBg: 'bg-indigo-100 text-indigo-700',
      checkBg: 'bg-indigo-50 border-indigo-200 text-indigo-600',
      btnBg: 'bg-indigo-600 hover:bg-indigo-700',
      active: hasAI,
      perks: [
        'Everything in Base',
        'AI weekly meal plans',
        'AI fitness plans',
        'AI devotionals & reading plans',
        'Smart grocery lists',
        'AI budget insights',
      ],
    },
  ] as const;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
      <div className="bg-white w-full max-w-lg rounded-3xl shadow-2xl overflow-hidden max-h-[90vh] flex flex-col">

        {/* Header */}
        <div className="bg-gradient-to-r from-indigo-600 to-purple-600 p-6 text-white relative shrink-0">
          <button
            onClick={onClose}
            className="absolute top-4 right-4 p-1.5 rounded-xl hover:bg-white/10 transition-colors"
          >
            <X size={20} />
          </button>
          <div className="flex items-center gap-3 mb-3">
            <div className="w-10 h-10 bg-white/20 rounded-2xl flex items-center justify-center">
              <CreditCard size={20} />
            </div>
            <div>
              <h2 className="text-xl font-black">Subscription</h2>
              <p className="text-indigo-200 text-xs">Manage your FamilyHub plan</p>
            </div>
          </div>

          {/* Current plan badge */}
          <div className="flex items-center gap-2">
            <Star size={12} className="text-amber-300" />
            <span className="text-xs font-bold text-white/80">Current plan:</span>
            <span className={`text-xs font-black px-2.5 py-1 rounded-full ${currentPlanColor}`}>
              {currentPlanLabel}
            </span>
          </div>
        </div>

        {/* Plan cards */}
        <div className="flex-1 overflow-y-auto p-5 space-y-4">

          {isInTrial && (
            <div className="bg-amber-50 border border-amber-200 rounded-2xl px-4 py-3 text-sm text-amber-800 font-medium text-center">
              Your {APP_CONFIG.trialDays}-day free trial gives you full access. Subscribe before it ends to keep everything.
            </div>
          )}

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {plans.map((plan) => {
              const Icon = plan.icon;
              return (
                <div
                  key={plan.id}
                  className={`rounded-2xl border-2 overflow-hidden transition-all ${plan.accent} ${plan.active ? 'opacity-100' : 'opacity-90'}`}
                >
                  {/* Plan header */}
                  <div className={`${plan.headerBg} text-white p-4 text-center`}>
                    <div className="w-9 h-9 bg-white/20 rounded-xl flex items-center justify-center mx-auto mb-2">
                      <Icon size={18} />
                    </div>
                    <p className="font-black text-base">{plan.label}</p>
                    <p className="text-white/80 text-lg font-black mt-1">{plan.monthly}</p>
                    <p className="text-white/60 text-[10px]">or {plan.annual} · {plan.annualNote}</p>
                    {plan.active && (
                      <span className={`mt-2 inline-block text-[10px] font-black uppercase tracking-widest px-2 py-0.5 rounded-full ${plan.badgeBg}`}>
                        Active
                      </span>
                    )}
                  </div>

                  {/* Perks */}
                  <div className="p-4 bg-white space-y-2">
                    {plan.perks.map((perk) => (
                      <div key={perk} className="flex items-center gap-2 text-xs text-stone-700">
                        <div className={`w-4 h-4 rounded-full border flex items-center justify-center shrink-0 ${plan.checkBg}`}>
                          <Check size={9} strokeWidth={3} />
                        </div>
                        {perk}
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>

          {/* Trial note */}
          <p className="text-center text-xs text-stone-400">
            {APP_CONFIG.trialDays}-day free trial · No charge until trial ends · Cancel anytime
          </p>

          {/* CTA */}
          {isNative ? (
            <button
              onClick={handleUpgrade}
              disabled={isLoading}
              className="w-full py-4 rounded-2xl font-bold text-white bg-indigo-600 hover:bg-indigo-700 transition-all shadow-lg shadow-indigo-100 flex items-center justify-center gap-2 disabled:opacity-60"
            >
              {isLoading ? (
                <Loader2 size={18} className="animate-spin" />
              ) : hasAI ? (
                'Manage Subscription'
              ) : (
                `Start ${APP_CONFIG.trialDays}-Day Free Trial`
              )}
            </button>
          ) : (
            <div className="flex items-center gap-3 bg-amber-50 border border-amber-100 rounded-2xl p-4">
              <Smartphone size={20} className="text-amber-500 shrink-0" />
              <p className="text-xs text-amber-700 font-medium leading-relaxed">
                Subscriptions are managed in the iOS and Android apps. Download FamilyHub to subscribe.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default SubscriptionModal;

/**
 * contexts/PurchasesContext.tsx
 *
 * Provides RevenueCat subscription state to the entire component tree.
 *
 *   hasBase      — active Base or AI subscription (or 14-day trial)
 *   hasAI        — active AI subscription (or trial)
 *   isInTrial    — currently in trial period
 *   presentPaywall  — opens the native RevenueCat paywall
 *   refreshEntitlements — re-checks RevenueCat (call after app resumes)
 */

import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
} from 'react';
import {
  initPurchases,
  checkEntitlements,
  presentPaywall as _presentPaywall,
  type EntitlementStatus,
} from '../services/purchases';

interface PurchasesContextType {
  hasBase: boolean;
  hasAI: boolean;
  isInTrial: boolean;
  isLoadingEntitlements: boolean;
  presentPaywall: () => Promise<boolean>;
  refreshEntitlements: () => Promise<void>;
}

const PurchasesContext = createContext<PurchasesContextType>({
  hasBase: true,
  hasAI: true,
  isInTrial: false,
  isLoadingEntitlements: false,
  presentPaywall: async () => false,
  refreshEntitlements: async () => {},
});

export const PurchasesProvider: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  // Default to true during beta — everyone gets full access.
  // Change to false when you're ready to enforce payments.
  const [status, setStatus] = useState<EntitlementStatus>({
    hasBase: true,
    hasAI: true,
    isInTrial: false,
  });
  const [isLoadingEntitlements, setIsLoadingEntitlements] = useState(false);

  const refreshEntitlements = useCallback(async () => {
    setIsLoadingEntitlements(true);
    try {
      const result = await checkEntitlements();
      setStatus(result);
    } catch (err) {
      console.warn('Failed to check entitlements:', err);
    } finally {
      setIsLoadingEntitlements(false);
    }
  }, []);

  // Init RevenueCat once on mount, then fetch entitlements
  useEffect(() => {
    initPurchases()
      .then(() => refreshEntitlements())
      .catch(err => console.warn('Purchase init failed:', err));
  }, [refreshEntitlements]);

  const presentPaywall = useCallback(async (): Promise<boolean> => {
    const purchased = await _presentPaywall();
    if (purchased) {
      await refreshEntitlements();
    }
    return purchased;
  }, [refreshEntitlements]);

  return (
    <PurchasesContext.Provider
      value={{
        hasBase: status.hasBase,
        hasAI: status.hasAI,
        isInTrial: status.isInTrial,
        isLoadingEntitlements,
        presentPaywall,
        refreshEntitlements,
      }}
    >
      {children}
    </PurchasesContext.Provider>
  );
};

/** Hook — access subscription state anywhere in the component tree */
export const usePurchases = (): PurchasesContextType =>
  useContext(PurchasesContext);

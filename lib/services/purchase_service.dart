import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/errors.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../models/models.dart';

/// RevenueCat integration. Configure API keys via `--dart-define=RC_IOS_KEY=...`
/// and `RC_ANDROID_KEY=...` (see [docs/REVENUECAT.md]).
///
/// In the RevenueCat dashboard, create a **default** offering whose packages use
/// these identifiers (attach App Store / Play products to each):
class PurchaseService {
  static bool _initialized = false;

  static bool get isConfigured => _initialized;

  static bool get _isMobileStore {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  /// Package identifiers on the current offering (must match RevenueCat).
  static String packageIdentifier(SubscriptionTier tier, bool yearly) {
    final period = yearly ? 'annual' : 'monthly';
    switch (tier) {
      case SubscriptionTier.trial:
      case SubscriptionTier.base:
        return 'base_$period';
      case SubscriptionTier.ai:
        return 'ai_$period';
      case SubscriptionTier.ai_family:
        return 'ai_family_$period';
    }
  }

  static Future<void> init({
    String? iosApiKey,
    String? androidApiKey,
  }) async {
    if (!_isMobileStore) {
      debugPrint('[PurchaseService] Skipping init (not iOS/Android).');
      return;
    }
    try {
      String? apiKey;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        apiKey = iosApiKey;
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        apiKey = androidApiKey;
      }

      if (apiKey == null || apiKey.isEmpty) {
        debugPrint(
            '[PurchaseService] No API key provided for this platform, skipping init.');
        return;
      }

      await Purchases.configure(PurchasesConfiguration(apiKey));
      _initialized = true;
      debugPrint('[PurchaseService] Initialized successfully.');
    } catch (e, st) {
      debugPrint('[PurchaseService] init() error: $e\n$st');
    }
  }

  /// Links RevenueCat [CustomerInfo] to your signed-in Supabase user id.
  static Future<void> syncIdentity(String? appUserId) async {
    if (!_initialized) return;
    try {
      if (appUserId == null || appUserId.isEmpty) {
        await Purchases.logOut();
        return;
      }
      await Purchases.logIn(appUserId);
    } catch (e, st) {
      debugPrint('[PurchaseService] syncIdentity error: $e\n$st');
    }
  }

  /// Call when the user signs out of the app (after Supabase sign-out is fine).
  static Future<void> revenueCatLogOut() async {
    if (!_initialized) return;
    try {
      await Purchases.logOut();
    } catch (e, st) {
      debugPrint('[PurchaseService] revenueCatLogOut error: $e\n$st');
    }
  }

  static Future<
      ({
        bool hasBase,
        bool hasAI,
        bool isInTrial,
      })> checkEntitlements() async {
    if (!_initialized) {
      return (hasBase: false, hasAI: false, isInTrial: false);
    }

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      final activeEntitlements = customerInfo.entitlements.active;

      final hasBase = activeEntitlements.containsKey('base');
      final hasAI = activeEntitlements.containsKey('ai');
      final isInTrial =
          activeEntitlements['base']?.periodType == PeriodType.trial;

      return (hasBase: hasBase, hasAI: hasAI, isInTrial: isInTrial);
    } catch (e, st) {
      debugPrint('[PurchaseService] checkEntitlements() error: $e\n$st');
      return (hasBase: false, hasAI: false, isInTrial: false);
    }
  }

  /// Resolves a [Package] from the current offering (`Offerings.current`).
  static Future<Package?> packageForPlan({
    required SubscriptionTier tier,
    required bool yearly,
  }) async {
    if (!_initialized) return null;
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) return null;
      final wanted = packageIdentifier(tier, yearly);
      for (final p in current.availablePackages) {
        if (p.identifier == wanted) return p;
      }
      return null;
    } catch (e, st) {
      debugPrint('[PurchaseService] packageForPlan error: $e\n$st');
      return null;
    }
  }

  /// Starts the native purchase flow for a store [Package].
  static Future<
      ({
        bool success,
        bool userCancelled,
        String? message,
      })> purchasePackage(Package package) async {
    if (!_initialized) {
      return (
        success: false,
        userCancelled: false,
        message: 'Store purchases are not configured on this device.',
      );
    }
    try {
      await Purchases.purchasePackage(package);
      return (success: true, userCancelled: false, message: null);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return (success: false, userCancelled: true, message: null);
      }
      return (
        success: false,
        userCancelled: false,
        message: e.message ?? e.code,
      );
    } catch (e, st) {
      debugPrint('[PurchaseService] purchasePackage error: $e\n$st');
      return (success: false, userCancelled: false, message: e.toString());
    }
  }

  static Future<
      ({
        bool success,
        String? message,
      })> restorePurchases() async {
    if (!_initialized) {
      return (success: false, message: 'Purchases are not configured.');
    }
    try {
      await Purchases.restorePurchases();
      return (success: true, message: null);
    } catch (e, st) {
      debugPrint('[PurchaseService] restorePurchases error: $e\n$st');
      return (success: false, message: e.toString());
    }
  }

  static Future<void> presentPaywall() async {
    if (!_initialized) {
      debugPrint('[PurchaseService] Not initialized, skipping paywall.');
      return;
    }

    try {
      // RevenueCat UI paywall not included — use [packageForPlan] + [purchasePackage]
      debugPrint(
          '[PurchaseService] presentPaywall() — use subscription screen purchase buttons.');
    } catch (e, st) {
      debugPrint('[PurchaseService] presentPaywall() error: $e\n$st');
    }
  }
}

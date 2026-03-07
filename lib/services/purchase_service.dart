import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class PurchaseService {
  static bool _initialized = false;

  static bool get isConfigured => _initialized;

  static Future<void> init({
    String? iosApiKey,
    String? androidApiKey,
  }) async {
    try {
      String? apiKey;
      if (Platform.isIOS) {
        apiKey = iosApiKey;
      } else if (Platform.isAndroid) {
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

  static Future<void> presentPaywall() async {
    if (!_initialized) {
      debugPrint('[PurchaseService] Not initialized, skipping paywall.');
      return;
    }

    try {
      await RevenueCatUI.presentPaywall();
    } catch (e, st) {
      debugPrint('[PurchaseService] presentPaywall() error: $e\n$st');
    }
  }
}

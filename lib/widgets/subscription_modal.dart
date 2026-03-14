// lib/widgets/subscription_modal.dart
// Subscription paywall modal for FamilyHub

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/theme.dart';
import '../services/ai_service.dart';
import '../services/purchase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SubscriptionModal — bottom sheet paywall
// ─────────────────────────────────────────────────────────────────────────────

class SubscriptionModal extends StatelessWidget {
  final String feature;
  final VoidCallback? onUpgrade;

  const SubscriptionModal({
    super.key,
    required this.feature,
    this.onUpgrade,
  });

  /// Returns true (and shows upgrade modal) if AI is blocked on the current plan.
  /// Screens should call this before attempting AI and abort if it returns true.
  static bool guardAI(BuildContext context) {
    if (!AiService.isAIBlocked) return false;
    show(context, feature: 'AI-powered features');
    return true;
  }

  /// Show as a modal bottom sheet
  static Future<void> show(
    BuildContext context, {
    required String feature,
    VoidCallback? onUpgrade,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SubscriptionModal(
        feature: feature,
        onUpgrade: onUpgrade,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.stone300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Crown icon
          const Text('👑', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),

          // Title
          const Text(
            'Upgrade to Premium',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.stone900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Subtitle
          Text(
            'Unlock $feature and more',
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.stone500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // Feature list
          _FeatureList(),
          const SizedBox(height: 28),

          // Primary CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.go('/subscription');
                onUpgrade?.call();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Start 14-Day Free Trial',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Secondary CTA
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Maybe Later',
                style: TextStyle(
                  color: AppTheme.stone500,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Fine print
          Text(
            'Cancel anytime. No commitment.',
            style: TextStyle(fontSize: 12, color: AppTheme.stone400),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  final List<String> _features = const [
    'AI-powered suggestions across all modules',
    'Unlimited recipes & meal planning',
    'Advanced budget analytics',
    'Priority support',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.stone100,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: _features
            .map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✅', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.stone900,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UpgradePrompt — small inline upgrade card
// ─────────────────────────────────────────────────────────────────────────────

class UpgradePrompt extends StatelessWidget {
  final String feature;

  const UpgradePrompt({super.key, required this.feature});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              color: AppTheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Premium Feature',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Upgrade to unlock $feature',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.stone700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () =>
                SubscriptionModal.show(context, feature: feature),
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Upgrade',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

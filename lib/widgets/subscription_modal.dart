// lib/widgets/subscription_modal.dart
// Subscription paywall modal for Huddle

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/ai_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AI paywall context — drives subtitle + benefit bullets per module
// ─────────────────────────────────────────────────────────────────────────────

enum AiPaywallKind {
  /// Default copy when the screen doesn’t specify a module.
  general,
  homeSuggestions,
  monthlyRecap,
  explore,
  tasks,
  meals,
  budget,
  calendar,
  fitness,
  devotional,
  lists,
}

class _PaywallCopy {
  final String subtitle;
  final List<String> bullets;

  const _PaywallCopy({required this.subtitle, required this.bullets});
}

const _paywallCopy = <AiPaywallKind, _PaywallCopy>{
  AiPaywallKind.general: _PaywallCopy(
    subtitle: 'AI that fits your real family rhythm — tasks, meals, faith, and more.',
    bullets: [
      'Smarter task breakdowns and weekly planning',
      'Meal ideas and shopping lists tuned to your tastes',
      'Faith content, devotionals, and reflections',
      'Budget and calendar help when you need a nudge',
    ],
  ),
  AiPaywallKind.homeSuggestions: _PaywallCopy(
    subtitle: 'Turn today’s chaos into a short, doable plan from your dashboard.',
    bullets: [
      'Personalized suggestions based on your family data',
      'Tap through to tasks, meals, or calendar in one flow',
      'Refresh anytime for a fresh take on priorities',
      'Everything stays private to your family',
    ],
  ),
  AiPaywallKind.monthlyRecap: _PaywallCopy(
    subtitle: 'See your month at a glance — wins, patterns, and gentle next steps.',
    bullets: [
      'Narrative summary you can share with your partner',
      'Highlights across tasks, meals, and routines',
      'Encouragement without the spreadsheet grind',
      'Unlocked on AI plans',
    ],
  ),
  AiPaywallKind.explore: _PaywallCopy(
    subtitle: 'Try AI in every module — one upgrade unlocks the full assistant.',
    bullets: [
      'Same account works across tasks, meals, budget, and more',
      'Cancel anytime from your store settings',
      'Kids’ data stays under your family’s control',
      'Optional AI Family plan for larger households',
    ],
  ),
  AiPaywallKind.tasks: _PaywallCopy(
    subtitle: 'Break big goals into steps your family can actually finish.',
    bullets: [
      'AI-suggested subtasks and wording tweaks',
      'Faster capture when you’re juggling errands',
      'Works with your existing lists and chores',
      'Part of AI & AI Family plans',
    ],
  ),
  AiPaywallKind.meals: _PaywallCopy(
    subtitle: 'Meal ideas and plans that respect how your week really goes.',
    bullets: [
      'Generate plans from what you already cook',
      'Adjust for picky eaters or busy nights',
      'Tie into shopping lists when you’re ready',
      'Wellness info is informational only — not medical advice',
    ],
  ),
  AiPaywallKind.budget: _PaywallCopy(
    subtitle: 'Surface patterns and prompts — you stay in control of every dollar.',
    bullets: [
      'Plain-language summaries of spending trends',
      'Ideas for categories and goals',
      'No bank passwords stored in the assistant',
      'Not financial advice; use your own judgment',
    ],
  ),
  AiPaywallKind.calendar: _PaywallCopy(
    subtitle: 'Let AI help you draft events, agendas, and reminders faster.',
    bullets: [
      'Turn rough notes into structured events',
      'Shorter setup for recurring family routines',
      'Respects your existing calendars and layers',
      'You review everything before it’s shared',
    ],
  ),
  AiPaywallKind.fitness: _PaywallCopy(
    subtitle: 'Coaching-style prompts and structure — not a replacement for a pro.',
    bullets: [
      'Workout ideas scaled to what you log',
      'Motivation when you’re rebuilding a habit',
      'General wellness only — not medical advice',
      'Unlocked on AI plans',
    ],
  ),
  AiPaywallKind.devotional: _PaywallCopy(
    subtitle: 'Scripture-centered devotionals and reading helps for busy adults.',
    bullets: [
      'Daily devotionals and reflection prompts',
      'Reading plans you can walk through as a family',
      'Honest tone — not generic kid-lesson fluff',
      'You choose what share or keep private',
    ],
  ),
  AiPaywallKind.lists: _PaywallCopy(
    subtitle: 'Smarter shopping and packing lists without retyping the same items.',
    bullets: [
      'Suggest items from context or past trips',
      'Reorder and group ideas in seconds',
      'Stays synced with your family’s shared lists',
      'Part of AI & AI Family plans',
    ],
  ),
};

// ─────────────────────────────────────────────────────────────────────────────
// SubscriptionModal — bottom sheet paywall
// ─────────────────────────────────────────────────────────────────────────────

class SubscriptionModal extends StatelessWidget {
  final AiPaywallKind kind;
  final VoidCallback? onUpgrade;

  const SubscriptionModal({
    super.key,
    this.kind = AiPaywallKind.general,
    this.onUpgrade,
  });

  /// Returns true (and shows upgrade modal) if AI is blocked on the current plan.
  static bool guardAI(BuildContext context, {AiPaywallKind kind = AiPaywallKind.general}) {
    if (!AiService.isAIBlocked) return false;
    show(context, kind: kind);
    return true;
  }

  /// Show as a modal bottom sheet
  static Future<void> show(
    BuildContext context, {
    AiPaywallKind kind = AiPaywallKind.general,
    VoidCallback? onUpgrade,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SubscriptionModal(
        kind: kind,
        onUpgrade: onUpgrade,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = _paywallCopy[kind] ?? _paywallCopy[AiPaywallKind.general]!;

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

          const Text('👑', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),

          const Text(
            'Upgrade for AI',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.stone900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          Text(
            copy.subtitle,
            style: const TextStyle(
              fontSize: 15,
              height: 1.35,
              color: AppTheme.stone600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          _FeatureList(bullets: copy.bullets),
          const SizedBox(height: 28),

          Consumer<AppProvider>(
            builder: (ctx, app, _) {
              final family = app.activeFamily;
              final onTrial =
                  family?.subscriptionTier == SubscriptionTier.trial &&
                      (family?.isTrialExpired != true);
              final cta = onTrial
                  ? 'Subscribe to unlock AI'
                  : 'View plans & subscribe';
              return SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    ctx.go('/subscription');
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
                  child: Text(
                    cta,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),

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
  final List<String> bullets;

  const _FeatureList({required this.bullets});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.stone100,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: bullets
            .map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 18, color: AppTheme.primary.withValues(alpha: 0.85)),
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
  final AiPaywallKind kind;

  const UpgradePrompt({
    super.key,
    required this.feature,
    this.kind = AiPaywallKind.general,
  });

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
              Icons.auto_awesome_rounded,
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
                  'AI feature',
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
            onPressed: () => SubscriptionModal.show(context, kind: kind),
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

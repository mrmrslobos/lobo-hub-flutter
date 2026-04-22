// lib/screens/subscription/subscription_screen.dart
// Subscription plans & pricing screen for Huddle

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/purchase_service.dart';
import '../../utils/ai_family_household.dart';
import '../../utils/user_facing_errors.dart';

// ─── Currency pricing data ──────────────────────────────────────────────────

class _PlanPricing {
  final String symbol;
  final double baseMonthly;
  final double baseYearly;
  final double aiMonthly;
  final double aiYearly;
  final double aiFamilyMonthly;
  final double aiFamilyYearly;

  const _PlanPricing({
    required this.symbol,
    required this.baseMonthly,
    required this.baseYearly,
    required this.aiMonthly,
    required this.aiYearly,
    required this.aiFamilyMonthly,
    required this.aiFamilyYearly,
  });
}

const _pricing = <String, _PlanPricing>{
  'AUD': _PlanPricing(symbol: r'$', baseMonthly: 9.99, baseYearly: 109, aiMonthly: 14.99, aiYearly: 159, aiFamilyMonthly: 17.99, aiFamilyYearly: 199),
  'USD': _PlanPricing(symbol: r'$', baseMonthly: 6.99, baseYearly: 74.99, aiMonthly: 9.99, aiYearly: 109, aiFamilyMonthly: 12.99, aiFamilyYearly: 139),
  'GBP': _PlanPricing(symbol: '£', baseMonthly: 5.49, baseYearly: 59.99, aiMonthly: 7.99, aiYearly: 84.99, aiFamilyMonthly: 9.99, aiFamilyYearly: 109),
  'CAD': _PlanPricing(symbol: r'$', baseMonthly: 8.99, baseYearly: 99, aiMonthly: 12.99, aiYearly: 139, aiFamilyMonthly: 15.99, aiFamilyYearly: 174),
  'INR': _PlanPricing(symbol: '₹', baseMonthly: 499, baseYearly: 4999, aiMonthly: 799, aiYearly: 7999, aiFamilyMonthly: 999, aiFamilyYearly: 9999),
};

const _currencyForLocale = <String, String>{
  'AU': 'AUD',
  'US': 'USD',
  'GB': 'GBP',
  'CA': 'CAD',
  'IN': 'INR',
};

// ─── Screen ─────────────────────────────────────────────────────────────────

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _yearly = true;
  String _currency = 'AUD';
  bool _restoreBusy = false;
  SubscriptionTier? _purchasingTier;
  final Map<String, String> _storePriceLabels = {};

  @override
  void initState() {
    super.initState();
    _loadCurrency();
    _loadStorePricing();
  }

  Future<void> _loadCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    final locale = prefs.getString('lobohub_locale') ?? 'AU';
    if (mounted) {
      setState(() {
        _currency = _currencyForLocale[locale] ?? 'AUD';
      });
    }
  }

  _PlanPricing get _prices => _pricing[_currency] ?? _pricing['AUD']!;

  String _priceKey(SubscriptionTier tier, bool yearly) =>
      '${tier.name}_${yearly ? 'y' : 'm'}';

  Future<void> _loadStorePricing() async {
    if (!PurchaseService.isConfigured) return;
    final next = <String, String>{};
    for (final tier in const [
      SubscriptionTier.base,
      SubscriptionTier.ai,
      SubscriptionTier.ai_family
    ]) {
      for (final yearly in const [false, true]) {
        final pkg = await PurchaseService.packageForPlan(
          tier: tier,
          yearly: yearly,
        );
        final label = pkg?.storeProduct.priceString;
        if (label != null && label.isNotEmpty) {
          next[_priceKey(tier, yearly)] = label;
        }
      }
    }
    if (!mounted || next.isEmpty) return;
    setState(() => _storePriceLabels.addAll(next));
  }

  String _formatPrice(double price) {
    final p = _prices;
    if (price == price.roundToDouble()) {
      return '${p.symbol}${price.toInt()}';
    }
    return '${p.symbol}${price.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final family = provider.activeFamily;
        if (family == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final currentTier = family.subscriptionTier;
        final trialDaysLeft = family.trialDaysRemaining;
        final isTrialExpired = family.isTrialExpired;
        final isOnTrial = currentTier == SubscriptionTier.trial;

        final fm = provider.db.familyMembers
            .where((m) => m.familyId == family.id);
        final declaredAdults = countDeclaredAdults(fm);
        final declaredUnder16 = countDeclaredUnder16(fm);
        final householdOverAiFamily =
            aiFamilyHouseholdOverDeclaredLimits(
          adultCount: declaredAdults,
          under16Count: declaredUnder16,
        );

        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: cs.surface,
            foregroundColor: cs.onSurface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              'Choose Your Plan',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: cs.onSurface,
              ),
            ),
            centerTitle: true,
            actions: [
              if (!kIsWeb && PurchaseService.isConfigured)
                TextButton(
                  onPressed: (_restoreBusy || _purchasingTier != null)
                      ? null
                      : _restorePurchases,
                  child: _restoreBusy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        )
                      : Text(
                          'Restore',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              // Trial banner
              if (isOnTrial)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isTrialExpired
                          ? [const Color(0xFFDC2626), const Color(0xFFEF4444)]
                          : [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isTrialExpired ? Icons.warning_rounded : Icons.timer_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isTrialExpired ? 'Trial expired' : 'Free trial',
                              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isTrialExpired
                                  ? AppConfig.planTrialExpiredBlurb
                                  : '$trialDaysLeft day${trialDaysLeft == 1 ? '' : 's'} left — full access!',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Billing toggle
              Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.stone100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _billingToggle('Monthly', !_yearly),
                      _billingToggle('Yearly', _yearly, badge: 'Save up to 20%'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Plan cards
              _buildPlanCard(
                tier: SubscriptionTier.base,
                currentTier: currentTier,
                name: AppConfig.planLabelEssentials,
                subtitle: AppConfig.planDescEssentials,
                monthlyPrice: _prices.baseMonthly,
                yearlyPrice: _prices.baseYearly,
                monthlyStorePrice: _storePriceLabels[_priceKey(SubscriptionTier.base, false)],
                yearlyStorePrice: _storePriceLabels[_priceKey(SubscriptionTier.base, true)],
                color: const Color(0xFF0EA5E9),
                icon: Icons.home_rounded,
                features: [
                  'Unlimited tasks & lists',
                  'Shared family calendar',
                  'Chore management & rewards',
                  'Family chat',
                  'Budget tracking',
                  'Meal planning (manual)',
                  'Prayer board & reading',
                  'Fitness logging',
                ],
              ),
              const SizedBox(height: 16),

              _buildPlanCard(
                tier: SubscriptionTier.ai,
                currentTier: currentTier,
                name: AppConfig.planLabelAi,
                subtitle: AppConfig.planDescAi,
                monthlyPrice: _prices.aiMonthly,
                yearlyPrice: _prices.aiYearly,
                monthlyStorePrice: _storePriceLabels[_priceKey(SubscriptionTier.ai, false)],
                yearlyStorePrice: _storePriceLabels[_priceKey(SubscriptionTier.ai, true)],
                color: const Color(0xFF8B5CF6),
                icon: Icons.auto_awesome_rounded,
                features: [
                  'Everything in ${AppConfig.planLabelEssentials}, plus:',
                  'AI meal plan generation',
                  'AI reading & reflection',
                  'AI task breakdown & suggestions',
                  'AI monthly family summaries',
                  'AI fitness coaching',
                  'Priority support',
                ],
              ),
              const SizedBox(height: 16),

              _buildPlanCard(
                tier: SubscriptionTier.ai_family,
                currentTier: currentTier,
                name: AppConfig.planLabelAiFamily,
                subtitle: AppConfig.planDescAiFamily,
                monthlyPrice: _prices.aiFamilyMonthly,
                yearlyPrice: _prices.aiFamilyYearly,
                monthlyStorePrice: _storePriceLabels[_priceKey(SubscriptionTier.ai_family, false)],
                yearlyStorePrice: _storePriceLabels[_priceKey(SubscriptionTier.ai_family, true)],
                color: const Color(0xFF16A34A),
                icon: Icons.family_restroom_rounded,
                popular: true,
                features: [
                  'Everything in ${AppConfig.planLabelAi}, plus:',
                  'Designed for up to 2 adult accounts + 4 under-16',
                  'Family member dashboards',
                  'Kids mode with parental controls',
                  'Shared AI suggestions per member',
                  'Family activity insights',
                  'Premium support',
                ],
              ),
              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: householdOverAiFamily
                      ? const Color(0xFFFFF7ED)
                      : AppTheme.stone50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: householdOverAiFamily
                        ? const Color(0xFFFDBA74)
                        : AppTheme.stone200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          householdOverAiFamily
                              ? Icons.info_outline_rounded
                              : Icons.groups_rounded,
                          size: 20,
                          color: householdOverAiFamily
                              ? const Color(0xFFEA580C)
                              : AppTheme.stone600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Larger-family AI plan',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: householdOverAiFamily
                                  ? const Color(0xFF9A3412)
                                  : AppTheme.stone800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'In Settings → Manage members, each profile can tick “This person is under 16” (or a parent can tick it for a child). That keeps pricing aligned with “2 adults + 4 children” without collecting IDs — misrepresenting ages can breach store rules and your terms.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        height: 1.35,
                        color: householdOverAiFamily
                            ? const Color(0xFF9A3412)
                            : AppTheme.stone600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This family: $declaredAdults adult${declaredAdults == 1 ? '' : 's'} declared, $declaredUnder16 under 16 declared (limit 2 + 4).',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppTheme.stone700,
                      ),
                    ),
                    if (householdOverAiFamily) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Your household is above the larger-family AI limit — add individual AI seats or adjust declarations so billing matches your real household.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          height: 1.35,
                          color: Color(0xFF9A3412),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Currency note
              Center(
                child: Text(
                  'Prices shown in $_currency',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Cancel anytime. No lock-in contracts.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _billingToggle(String label, bool selected, {String? badge}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _yearly = label == 'Yearly');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
                color: selected ? AppTheme.stone900 : AppTheme.stone500,
              ),
            ),
            if (badge != null && selected) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badge, style: const TextStyle(fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required SubscriptionTier tier,
    required SubscriptionTier currentTier,
    required String name,
    required String subtitle,
    required double monthlyPrice,
    required double yearlyPrice,
    String? monthlyStorePrice,
    String? yearlyStorePrice,
    required Color color,
    required IconData icon,
    required List<String> features,
    bool popular = false,
  }) {
    final isCurrentPlan = currentTier == tier;
    final selectedStorePrice = _yearly ? yearlyStorePrice : monthlyStorePrice;
    final price = _yearly ? yearlyPrice : monthlyPrice;
    final period = _yearly ? '/year' : '/month';
    final monthlySaving = (_yearly && selectedStorePrice == null)
        ? ' (${_formatPrice(yearlyPrice / 12)}/mo)'
        : '';

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: popular ? color : AppTheme.stone100,
          width: popular ? 2 : 1,
        ),
        boxShadow: popular
            ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 4))]
            : null,
      ),
      child: Column(
        children: [
          if (popular)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: const Text(
                'MOST POPULAR',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1, color: Colors.white),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 22, color: color),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: color)),
                        Text(subtitle, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Price
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      selectedStorePrice ?? _formatPrice(price),
                      style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 32, color: AppTheme.stone900),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(period, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone500)),
                    ),
                    if (_yearly)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 8),
                        child: Text(monthlySaving, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Features
                ...features.map((f) {
                  final isHeader = f.endsWith(':');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isHeader) ...[
                          Icon(Icons.check_rounded, size: 16, color: color),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            f,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
                              color: isHeader ? AppTheme.stone700 : AppTheme.stone600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (tier == SubscriptionTier.ai || tier == SubscriptionTier.ai_family)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'AI features provide general wellness information only and are not a substitute for professional medical, nutritional, or fitness advice.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.stone400,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // CTA button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isCurrentPlan ||
                            _restoreBusy ||
                            _purchasingTier != null
                        ? null
                        : () => _handleSubscribe(tier),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCurrentPlan ? AppTheme.stone200 : color,
                      foregroundColor: isCurrentPlan ? AppTheme.stone500 : Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    child: _purchasingTier == tier && !isCurrentPlan
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(isCurrentPlan ? 'Current Plan' : 'Subscribe'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restorePurchases() async {
    if (!PurchaseService.isConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add RevenueCat API keys at build time to enable purchases.')),
      );
      return;
    }
    setState(() => _restoreBusy = true);
    final result = await PurchaseService.restorePurchases();
    if (!mounted) return;
    setState(() => _restoreBusy = false);
    if (result.success) {
      final app = context.read<AppProvider>();
      await app.refreshStoreSubscription();
      await app.refreshFromCloud();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchases restored. Syncing your account…')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanizeForSnackBar(result.message ?? 'Restore failed.'),
          ),
        ),
      );
    }
  }

  Future<void> _handleSubscribe(SubscriptionTier tier) async {
    HapticFeedback.mediumImpact();
    if (!PurchaseService.isConfigured) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Store not configured', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800)),
          content: const Text(
            'Build the app with RevenueCat keys (RC_IOS_KEY / RC_ANDROID_KEY) and configure products in the RevenueCat dashboard. See docs/REVENUECAT.md.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _purchasingTier = tier);
    final pkg = await PurchaseService.packageForPlan(tier: tier, yearly: _yearly);
    if (pkg == null) {
      if (!mounted) return;
      setState(() => _purchasingTier = null);
      final wanted = PurchaseService.packageIdentifierCandidates(tier, _yearly);
      final have = await PurchaseService.currentOfferingPackageIdentifiers();
      final hint = have.isEmpty
          ? 'The app did not receive any packages from RevenueCat. In the dashboard: Product catalog → Offerings → set an offering as **Current**, add packages with the ids below, and attach your App Store / Play products to each package.'
          : 'Packages on the **current** offering right now: ${have.join(', ')}. The app looks for: ${wanted.join(' or ')}.';
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Products unavailable', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Text(
              '$hint\n\n'
              'Yearly plans use package id **annual** or **yearly** (both are accepted). See docs/REVENUECAT.md.',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600, height: 1.35),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }

    final outcome = await PurchaseService.purchasePackage(pkg);
    if (!mounted) return;
    setState(() => _purchasingTier = null);

    if (outcome.userCancelled) return;
    if (!outcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanizeForSnackBar(outcome.message ?? 'Purchase failed.'),
          ),
        ),
      );
      return;
    }

    final app = context.read<AppProvider>();
    await app.refreshStoreSubscription();
    await app.refreshFromCloud();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thank you! Your subscription is processing — sync complete.')),
    );
  }
}

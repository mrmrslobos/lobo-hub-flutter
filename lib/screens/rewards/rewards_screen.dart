// lib/screens/rewards/rewards_screen.dart
// Rewards & savings goals screen for FamilyHub
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

// ─── Main Screen ─────────────────────────────────────────────────────────────

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  void _showAddGoalSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SavingsGoalSheet(
        onSave: (goal) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(savingsGoals: [...db.savingsGoals, goal]));
        },
      ),
    );
  }

  Future<void> _addFunds(SavingsGoal goal, double amount) async {
    HapticFeedback.lightImpact();
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final newSaved = goal.savedAmount + amount;
    final updated = db.savingsGoals.map((g) {
      if (g.id == goal.id) {
        return g.copyWith(
          savedAmount: newSaved,
          completedAt: newSaved >= g.targetAmount ? DateTime.now() : g.completedAt,
        );
      }
      return g;
    }).toList();
    await provider.saveAndSync(db.copyWith(savingsGoals: updated));
  }

  Future<void> _deleteGoal(String goalId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Goal?'),
        content: const Text('Delete this savings goal? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    HapticFeedback.lightImpact();
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      savingsGoals: db.savingsGoals.where((g) => g.id != goalId).toList(),
    ));
    if (mounted) _showSnack(context, 'Goal removed');
  }

  Future<void> _redeemReward(Reward reward, String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redeem Reward?'),
        content: Text(
          'Redeem "${reward.title}" for ${reward.pointCost} points?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final updated = db.rewards.map((r) {
      if (r.id == reward.id) {
        return r.copyWith(
          redeemedBy: [...r.redeemedBy, userId],
        );
      }
      return r;
    }).toList();
    await provider.saveAndSync(db.copyWith(rewards: updated));
    if (mounted) _showSnack(context, '${reward.title} redeemed!');
  }

  Future<void> _deleteReward(String rewardId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Reward?'),
        content: const Text('Delete this reward? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    HapticFeedback.lightImpact();
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      rewards: db.rewards.where((r) => r.id != rewardId).toList(),
    ));
    if (mounted) _showSnack(context, 'Reward removed');
  }

  void _showAddRewardSheet({Reward? editReward}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RewardFormSheet(
        editReward: editReward,
        onSave: (reward) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          if (editReward != null) {
            await provider.saveAndSync(db.copyWith(
              rewards: db.rewards.map((r) => r.id == reward.id ? reward : r).toList(),
            ));
          } else {
            await provider.saveAndSync(db.copyWith(rewards: [...db.rewards, reward]));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final members = provider.familyMembers;
    final rewards = provider.db.rewards.where((r) => r.familyId == family.id).toList();
    final savingsGoals = provider.db.savingsGoals.where((g) => g.familyId == family.id).toList();
    final myEarnings = provider.choreEarningsForUser(user.id);
    final isOwner = user.id == family.ownerId;
    final completedGoals = savingsGoals.where((g) => g.savedAmount >= g.targetAmount).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: const AppDrawer(),
      appBar: const FamilyHubAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page Header ──
            PageHeader(
              title: 'Reward Store',
              subtitle: 'Manage rewards, savings goals, and approve requests.',
              actions: isOwner
                  ? [
                      ActionChipButton(
                        icon: Icons.savings_rounded,
                        label: 'Add Goal',
                        onTap: _showAddGoalSheet,
                        isPrimary: true,
                      ),
                      ActionChipButton(
                        icon: Icons.card_giftcard_rounded,
                        label: 'Add Reward',
                        onTap: _showAddRewardSheet,
                        backgroundColor: AppTheme.stone800,
                      ),
                    ]
                  : null,
            ),

            // ── Stat Cards ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(children: [
                _MiniStat(
                  icon: Icons.star_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  value: '\$${myEarnings.toStringAsFixed(2)}',
                  label: 'My Earnings',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.card_giftcard_rounded,
                  iconColor: AppTheme.primary,
                  value: '${rewards.length}',
                  label: 'Rewards',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.check_circle_rounded,
                  iconColor: AppTheme.success,
                  value: '$completedGoals',
                  label: 'Goals Met',
                ),
              ]),
            ),

            // ── Kids' Balances Section ──
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SectionHeader(title: "KIDS' BALANCES"),
            ),
            ...members.map((member) {
              final earned = provider.choreEarningsForUser(member.id);
              final displayName = provider.memberDisplayName(member);
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.stone100),
                  ),
                  child: Row(
                    children: [
                      AvatarInitials(name: displayName, size: 44),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.stone900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Earned: \$${earned.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: AppTheme.stone500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${earned.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.success,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Available balance',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              color: AppTheme.stone400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 12),

            // ── Reward Catalog Section ──
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SectionHeader(title: 'REWARD CATALOG'),
            ),

            if (rewards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OnboardingCard(
                  emoji: '🎁',
                  title: 'Set up your family reward store',
                  bullets: const [
                    'Kids earn points by completing chores',
                    'Create rewards with a point cost — screen time, treats, outings',
                    'Review and approve every redemption request',
                    'Kids can also set savings goals for bigger items',
                  ],
                  actionLabel: 'Add First Reward',
                  onAction: _showAddRewardSheet,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: rewards.length,
                  itemBuilder: (ctx, i) {
                    final reward = rewards[i];
                    final canRedeem = myEarnings >= reward.pointCost;
                    final alreadyRedeemed = reward.redeemedBy.contains(user.id);
                    return _RewardCard(
                      reward: reward,
                      canRedeem: canRedeem && !alreadyRedeemed,
                      alreadyRedeemed: alreadyRedeemed,
                      onRedeem: canRedeem && !alreadyRedeemed
                          ? () => _redeemReward(reward, user.id)
                          : null,
                      onDelete: () => _deleteReward(reward.id),
                      onEdit: () => _showAddRewardSheet(editReward: reward),
                    );
                  },
                ),
              ),

            // ── Savings Goals Section ──
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                const Expanded(child: SectionHeader(title: 'SAVINGS GOALS')),
                GestureDetector(
                  onTap: _showAddGoalSheet,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 2),
                    Text('New Goal', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                  ]),
                ),
              ]),
            ),

            if (savingsGoals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.stone100),
                  ),
                  child: const Column(children: [
                    Text('\u{1F3AF}', style: TextStyle(fontSize: 28)),
                    SizedBox(height: 8),
                    Text('No savings goals yet', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone400)),
                    SizedBox(height: 2),
                    Text('Set a target and save up for something special!', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                  ]),
                ),
              )
            else
              ...savingsGoals.map((goal) {
                final progress = goal.targetAmount > 0 ? (goal.savedAmount / goal.targetAmount).clamp(0.0, 1.0) : 0.0;
                final isComplete = goal.savedAmount >= goal.targetAmount;
                final goalMember = members.where((m) => m.id == goal.userId).firstOrNull ?? members.firstOrNull;
                final ownerName = goalMember != null ? provider.memberDisplayName(goalMember) : 'Unknown';
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isComplete ? AppTheme.success.withValues(alpha: 0.4) : AppTheme.stone100, width: isComplete ? 2 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(goal.icon ?? '\u{1F3AF}', style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(goal.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900)),
                          Text(ownerName, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                        ])),
                        if (isComplete)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                            child: const Text('Complete!', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.success)),
                          )
                        else
                          GestureDetector(
                            onTap: () => _deleteGoal(goal.id),
                            child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone300),
                          ),
                      ]),
                      const SizedBox(height: 12),
                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: AppTheme.stone100,
                          valueColor: AlwaysStoppedAnimation(isComplete ? AppTheme.success : AppTheme.primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('\$${goal.savedAmount.toStringAsFixed(0)} of \$${goal.targetAmount.toStringAsFixed(0)}',
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone600)),
                        Text('${(progress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: isComplete ? AppTheme.success : AppTheme.primary)),
                      ]),
                      if (!isComplete) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => _showAddFundsDialog(goal),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.savings_rounded, size: 16, color: AppTheme.primary),
                              const SizedBox(width: 6),
                              Text('Add Funds', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                            ]),
                          ),
                        ),
                      ],
                    ]),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _showAddFundsDialog(SavingsGoal goal) {
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Funds to ${goal.title}'),
        content: TextField(
          controller: amountCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: '\$ ',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount > 0) {
                _addFunds(goal, amount);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// ─── Reward Card ─────────────────────────────────────────────────────────────

class _RewardCard extends StatelessWidget {
  final Reward reward;
  final bool canRedeem;
  final bool alreadyRedeemed;
  final VoidCallback? onRedeem;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _RewardCard({
    required this.reward,
    required this.canRedeem,
    required this.alreadyRedeemed,
    required this.onRedeem,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: alreadyRedeemed ? AppTheme.success.withValues(alpha: 0.05) : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: alreadyRedeemed ? AppTheme.success.withValues(alpha: 0.3) : AppTheme.stone100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('🎁', style: TextStyle(fontSize: 28)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: onEdit,
              child: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.stone300),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone300),
            ),
          ]),
        ]),
        const SizedBox(height: 6),
        Text(reward.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.stone900), maxLines: 2, overflow: TextOverflow.ellipsis),
        const Spacer(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: AppTheme.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text('${reward.pointCost} pts', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.warning)),
          ),
          if (alreadyRedeemed)
            const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 18)
          else
            GestureDetector(
              onTap: onRedeem,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: canRedeem ? AppTheme.primary : AppTheme.stone200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Redeem', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: canRedeem ? Colors.white : AppTheme.stone400)),
              ),
            ),
        ]),
      ]),
    );
  }
}

// ─── Savings Goal Sheet ──────────────────────────────────────────────────────

class _SavingsGoalSheet extends StatefulWidget {
  final Function(SavingsGoal) onSave;
  const _SavingsGoalSheet({required this.onSave});

  @override
  State<_SavingsGoalSheet> createState() => _SavingsGoalSheetState();
}

class _SavingsGoalSheetState extends State<_SavingsGoalSheet> {
  static const _goalIcons = [
    '\u{1F3AE}', '\u{1F6F9}', '\u{1F3B8}', '\u{1F4F1}', '\u{1F3A7}',
    '\u{1F45F}', '\u{1F9F8}', '\u{1F3A8}', '\u{1F4DA}', '\u{1F6B2}',
    '\u26BD', '\u{1F3C0}', '\u{1F3A0}', '\u{1F48E}', '\u{1F436}', '\u2708\uFE0F',
  ];

  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _savedCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  String _selectedIcon = '\u{1F3AE}';
  String? _selectedMemberId;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _savedCtrl.dispose();
    _imageUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppProvider>();
    final family = provider.activeFamily!;
    final members = provider.familyMembers;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const SheetHandle(),
          const Text('New Savings Goal', style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900)),
          const SizedBox(height: 16),

          // Icon picker
          const Text('Pick an icon', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _goalIcons.map((icon) {
                final selected = _selectedIcon == icon;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIcon = icon),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.stone100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? AppTheme.primary : Colors.transparent, width: 2),
                    ),
                    child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Goal Title *',
              prefixIcon: Text(' $_selectedIcon ', style: const TextStyle(fontSize: 18)),
              prefixIconConstraints: const BoxConstraints(minWidth: 44),
            ),
          ),
          const SizedBox(height: 12),

          // Target amount
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Target Amount *',
              prefixText: '\$ ',
              prefixIcon: Icon(Icons.savings_rounded),
            ),
          ),
          const SizedBox(height: 12),

          // Already saved (optional)
          TextField(
            controller: _savedCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Already Saved (optional)',
              prefixText: '\$ ',
              prefixIcon: Icon(Icons.account_balance_wallet_rounded),
            ),
          ),
          const SizedBox(height: 12),

          // Image URL (optional)
          TextField(
            controller: _imageUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'Image URL (optional)',
              prefixIcon: Icon(Icons.image_rounded),
            ),
          ),
          const SizedBox(height: 16),

          // Member selector
          const Text('Saving for', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: members.map((m) {
              final selected = _selectedMemberId == m.id;
              final name = provider.memberDisplayName(m);
              return GestureDetector(
                onTap: () => setState(() => _selectedMemberId = m.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.stone100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? AppTheme.primary : Colors.transparent, width: 2),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AvatarInitials(name: name, size: 24),
                    const SizedBox(width: 6),
                    Text(name, style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppTheme.primary : AppTheme.stone600)),
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final title = _titleCtrl.text.trim();
                final amount = double.tryParse(_amountCtrl.text) ?? 0;
                if (title.isEmpty || amount <= 0) return;
                final initialSaved = double.tryParse(_savedCtrl.text) ?? 0;
                final goal = SavingsGoal(
                  id: const Uuid().v4(),
                  familyId: family.id,
                  userId: _selectedMemberId ?? provider.activeUser!.id,
                  title: title,
                  icon: _selectedIcon,
                  imageUrl: _imageUrlCtrl.text.trim().isEmpty ? null : _imageUrlCtrl.text.trim(),
                  targetAmount: amount,
                  savedAmount: initialSaved > 0 ? initialSaved : 0,
                  createdAt: DateTime.now(),
                );
                widget.onSave(goal);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Create Goal', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Reward Form Sheet ───────────────────────────────────────────────────────

class _RewardFormSheet extends StatefulWidget {
  final Future<void> Function(Reward) onSave;
  final Reward? editReward;
  const _RewardFormSheet({required this.onSave, this.editReward});

  @override
  State<_RewardFormSheet> createState() => _RewardFormSheetState();
}

class _RewardFormSheetState extends State<_RewardFormSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _costCtrl;
  String _selectedIcon = '🎁';
  bool _isSaving = false;
  final _uuid = const Uuid();

  static const _iconOptions = [
    '🎁', '🎮', '🍕', '🎬', '🏖️', '🛍️', '☕', '🍦', '🎯', '🏆',
    '💆', '🎤', '🎲', '📱', '🎵', '🌟', '🍫', '🚗', '✈️', '🏠',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.editReward;
    if (r != null) {
      final title = r.title;
      final iconMatch = RegExp(r'^(\p{Emoji_Presentation}|\p{Emoji}\uFE0F?)\s*', unicode: true).firstMatch(title);
      if (iconMatch != null) {
        _selectedIcon = iconMatch.group(0)!.trim();
        _titleCtrl = TextEditingController(text: title.substring(iconMatch.end));
      } else {
        _titleCtrl = TextEditingController(text: title);
      }
      _descCtrl = TextEditingController(text: r.description ?? '');
      _costCtrl = TextEditingController(text: '${r.pointCost}');
    } else {
      _titleCtrl = TextEditingController();
      _descCtrl = TextEditingController();
      _costCtrl = TextEditingController(text: '50');
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final titleWithIcon = '$_selectedIcon ${_titleCtrl.text.trim()}';
    final reward = Reward(
      id: widget.editReward?.id ?? _uuid.v4(),
      familyId: provider.activeFamily!.id,
      title: titleWithIcon,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      pointCost: int.tryParse(_costCtrl.text) ?? 50,
      redeemedBy: widget.editReward?.redeemedBy ?? [],
    );
    await widget.onSave(reward);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SheetHandle(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(widget.editReward != null ? 'Edit Reward' : 'New Reward', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 12),
          // Icon picker
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Choose Icon', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _iconOptions.map((icon) {
                final selected = _selectedIcon == icon;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIcon = icon),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.stone100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? AppTheme.primary : Colors.transparent, width: 2),
                    ),
                    child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Reward Title *',
              prefixIcon: Text(' $_selectedIcon ', style: const TextStyle(fontSize: 18)),
              prefixIconConstraints: const BoxConstraints(minWidth: 44),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description (optional)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _costCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Points Cost', prefixIcon: Icon(Icons.star_rounded)),
          ),
        ]),
      ),
    );
  }
}

// ─── Mini Stat Card ──────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _MiniStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(
                    fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w900, color: iconColor,
                  )),
                  Text(label, style: const TextStyle(
                    fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.stone400,
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

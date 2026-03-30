// lib/screens/rewards/rewards_screen.dart
// Rewards & savings goals screen for FamilyHub
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../utils/debounce.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

Future<void> _persistBudget(AppProvider provider, AppDB newDb) async {
  await provider.saveAndSync(newDb);
  await provider.syncBudgetNow();
}

Future<void> _persistRewards(AppProvider provider, AppDB newDb) async {
  await provider.saveAndSync(newDb);
  await provider.syncRewardsNow();
}

// ─── Main Screen ─────────────────────────────────────────────────────────────

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddGoalSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SavingsGoalSheet(
        onSave: (goal) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await _persistBudget(
              provider, db.copyWith(savingsGoals: [...db.savingsGoals, goal]));
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
          completedAt:
              newSaved >= g.targetAmount ? DateTime.now() : g.completedAt,
        );
      }
      return g;
    }).toList();
    await _persistBudget(provider, db.copyWith(savingsGoals: updated));
  }

  Future<void> _deleteGoal(String goalId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Goal?'),
        content: const Text('Delete this savings goal? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
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
    await _persistBudget(provider, db.copyWith(
      savingsGoals: db.savingsGoals.where((g) => g.id != goalId).toList(),
    ));
    if (mounted) _showSnack(context, 'Goal removed');
  }

  Future<void> _requestRedemption(Reward reward, String userId) async {
    final provider = context.read<AppProvider>();

    final hasPending = provider.db.rewardRedemptions.any((r) =>
        r.userId == userId &&
        r.rewardId == reward.id &&
        r.status == RedemptionStatus.PENDING);
    if (hasPending) {
      if (mounted) _showSnack(context, 'Already requested — waiting for approval');
      return;
    }

    final balance = provider.availableBalanceForUser(userId);
    final lowBalance = balance < reward.pointCost;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Reward?'),
        content: Text(
          'Request "${reward.title}" for ${reward.pointCost} points?\n\n'
          'A parent will review your request.'
          '${lowBalance ? '\n\nNote: Your current balance (\$${balance.toStringAsFixed(0)}) is below the cost.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    final db = provider.db;
    final redemption = RewardRedemption(
      id: const Uuid().v4(),
      familyId: provider.activeFamily!.id,
      userId: userId,
      rewardId: reward.id,
      rewardTitle: reward.title,
      amount: reward.pointCost,
      status: RedemptionStatus.PENDING,
      requestedAt: DateTime.now(),
    );
    await _persistRewards(provider, db.copyWith(
      rewardRedemptions: [...db.rewardRedemptions, redemption],
    ));
    if (mounted) _showSnack(context, 'Request sent! Waiting for approval.');
  }

  Future<void> _resolveRedemption(
    RewardRedemption redemption,
    RedemptionStatus newStatus,
    String resolverUserId,
    String? note,
  ) async {
    HapticFeedback.mediumImpact();
    final provider = context.read<AppProvider>();
    final db = provider.db;

    final updated = db.rewardRedemptions.map((r) {
      if (r.id == redemption.id) {
        return r.copyWith(
          status: newStatus,
          resolvedAt: DateTime.now(),
          resolvedBy: resolverUserId,
          resolvedNote: note,
        );
      }
      return r;
    }).toList();

    var newDb = db.copyWith(rewardRedemptions: updated);

    if (newStatus == RedemptionStatus.APPROVED) {
      final reward = db.rewards.firstWhereOrNull((r) => r.id == redemption.rewardId);
      if (reward != null && !reward.redeemedBy.contains(redemption.userId)) {
        newDb = newDb.copyWith(
          rewards: newDb.rewards.map((r) {
            if (r.id == reward.id) {
              return r.copyWith(
                redeemedBy: [...r.redeemedBy, redemption.userId],
              );
            }
            return r;
          }).toList(),
        );
      }
    }

    await _persistRewards(provider, newDb);
    if (mounted) {
      _showSnack(
        context,
        newStatus == RedemptionStatus.APPROVED
            ? '${redemption.rewardTitle} approved!'
            : '${redemption.rewardTitle} denied.',
      );
    }
  }

  void _showApprovalDialog(RewardRedemption redemption) {
    final noteCtrl = TextEditingController();
    final provider = context.read<AppProvider>();
    final requesterName = provider.userById(redemption.userId)?.name ?? 'Family member';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Review Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: 'From', value: requesterName),
            const SizedBox(height: 8),
            _InfoRow(label: 'Reward', value: redemption.rewardTitle),
            const SizedBox(height: 8),
            _InfoRow(label: 'Cost', value: '${redemption.amount} pts'),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Requested',
              value: DateFormat.yMMMd().format(redemption.requestedAt),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. "Great job this week!"',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resolveRedemption(
                redemption,
                RedemptionStatus.DENIED,
                provider.activeUser!.id,
                noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Deny'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resolveRedemption(
                redemption,
                RedemptionStatus.APPROVED,
                provider.activeUser!.id,
                noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteReward(String rewardId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Reward?'),
        content: const Text('Delete this reward? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
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
    await _persistRewards(provider, db.copyWith(
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
            await _persistRewards(provider, db.copyWith(
              rewards:
                  db.rewards.map((r) => r.id == reward.id ? reward : r).toList(),
            ));
          } else {
            await _persistRewards(
                provider, db.copyWith(rewards: [...db.rewards, reward]));
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
    final rewards =
        provider.db.rewards.where((r) => r.familyId == family.id).toList();
    final savingsGoals =
        provider.db.savingsGoals.where((g) => g.familyId == family.id).toList();
    final allRedemptions = provider.db.rewardRedemptions
        .where((r) => r.familyId == family.id)
        .toList();
    final pendingRequests =
        allRedemptions.where((r) => r.status == RedemptionStatus.PENDING).toList();
    final resolvedRequests = allRedemptions
        .where((r) => r.status != RedemptionStatus.PENDING)
        .toList()
      ..sort((a, b) => (b.resolvedAt ?? b.requestedAt)
          .compareTo(a.resolvedAt ?? a.requestedAt));

    final myBalance = provider.availableBalanceForUser(user.id);
    final isOwner = user.id == family.ownerId;
    final completedGoals =
        savingsGoals.where((g) => g.savedAmount >= g.targetAmount).length;

    return Scaffold(
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const FamilyHubAppBar(),
      body: Column(
        children: [
          // ── Page Header ──
          PageHeader(
            title: 'Reward Store',
            subtitle: 'Earn points from chores, request rewards, track savings.',
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              _MiniStat(
                icon: Icons.account_balance_wallet_rounded,
                iconColor: AppTheme.success,
                value: '\$${myBalance.toStringAsFixed(2)}',
                label: 'My Balance',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                icon: Icons.pending_actions_rounded,
                iconColor: const Color(0xFFF59E0B),
                value: '${pendingRequests.length}',
                label: 'Pending',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                icon: Icons.check_circle_rounded,
                iconColor: AppTheme.primary,
                value: '$completedGoals',
                label: 'Goals Met',
              ),
            ]),
          ),

          // ── Tabs ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: AppTheme.stone100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(3),
              dividerColor: Colors.transparent,
              labelColor: AppTheme.stone900,
              unselectedLabelColor: AppTheme.stone400,
              labelStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Store'),
                      if (rewards.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        _CountBadge(count: rewards.length, color: AppTheme.primary),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Requests'),
                      if (pendingRequests.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        _CountBadge(
                          count: pendingRequests.length,
                          color: const Color(0xFFF59E0B),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Goals'),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Tab content ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ── Tab 1: Store ──
                _StoreTab(
                  rewards: rewards,
                  members: members,
                  user: user,
                  provider: provider,
                  myBalance: myBalance,
                  isOwner: isOwner,
                  pendingRequests: pendingRequests,
                  onRedeem: (r) => _requestRedemption(r, user.id),
                  onDelete: _deleteReward,
                  onEdit: (r) => _showAddRewardSheet(editReward: r),
                  onAddReward: _showAddRewardSheet,
                ),

                // ── Tab 2: Requests ──
                _RequestsTab(
                  pendingRequests: pendingRequests,
                  resolvedRequests: resolvedRequests,
                  provider: provider,
                  isOwner: isOwner,
                  currentUserId: user.id,
                  onReview: _showApprovalDialog,
                ),

                // ── Tab 3: Goals ──
                _GoalsTab(
                  savingsGoals: savingsGoals,
                  members: members,
                  provider: provider,
                  onAddGoal: _showAddGoalSheet,
                  onDeleteGoal: _deleteGoal,
                  onShowAddFunds: _showAddFundsDialog,
                ),
              ],
            ),
          ),
        ],
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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

// ─── Store Tab ───────────────────────────────────────────────────────────────

class _StoreTab extends StatefulWidget {
  final List<Reward> rewards;
  final List<FamilyMember> members;
  final User user;
  final AppProvider provider;
  final double myBalance;
  final bool isOwner;
  final List<RewardRedemption> pendingRequests;
  final void Function(Reward) onRedeem;
  final void Function(String) onDelete;
  final void Function(Reward) onEdit;
  final VoidCallback onAddReward;

  const _StoreTab({
    required this.rewards,
    required this.members,
    required this.user,
    required this.provider,
    required this.myBalance,
    required this.isOwner,
    required this.pendingRequests,
    required this.onRedeem,
    required this.onDelete,
    required this.onEdit,
    required this.onAddReward,
  });

  @override
  State<_StoreTab> createState() => _StoreTabState();
}

class _StoreTabState extends State<_StoreTab> {
  final _searchCtrl = TextEditingController();
  final _debounce = Debouncer();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final t = _searchCtrl.text;
      _debounce.run(() {
        if (mounted) setState(() => _query = t);
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final rewards = q.isEmpty
        ? widget.rewards
        : widget.rewards
            .where((r) =>
                r.title.toLowerCase().contains(q) ||
                (r.description != null && r.description!.toLowerCase().contains(q)) ||
                r.pointCost.toString().contains(q))
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Kids' Balances Section ──
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: SectionHeader(title: "FAMILY BALANCES"),
          ),
          ...widget.members.map((member) {
            final earned = widget.provider.choreEarningsForUser(member.id);
            final spent = widget.provider.redemptionSpentForUser(member.id);
            final available = earned - spent;
            final displayName = widget.provider.memberDisplayName(member);
            final memberPending = widget.pendingRequests
                .where((r) => r.userId == member.id)
                .length;
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
                            'Earned: \$${earned.toStringAsFixed(2)}  ·  '
                            'Spent: \$${spent.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppTheme.stone400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${available.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: available > 0
                                ? AppTheme.success
                                : AppTheme.stone400,
                          ),
                        ),
                        if (memberPending > 0)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$memberPending pending',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD97706),
                              ),
                            ),
                          )
                        else
                          const Text(
                            'Available',
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

          const SizedBox(height: 8),

          // ── Reward Catalog Section ──
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SectionHeader(title: 'REWARD CATALOG'),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search rewards…',
                hintStyle: const TextStyle(fontFamily: 'Inter', color: AppTheme.stone400),
                prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.stone400),
                suffixIcon: _query.trim().isEmpty
                    ? null
                    : Semantics(
                        label: 'Clear search',
                        button: true,
                        child: IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.stone400),
                          onPressed: () {
                            _debounce.cancel();
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                      ),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.stone200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.stone200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          if (widget.rewards.isEmpty)
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
                onAction: widget.onAddReward,
              ),
            )
          else if (rewards.isEmpty && q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OnboardingCard(
                emoji: '🔎',
                title: 'No reward matches',
                bullets: const ['Try another title or point value', 'Clear search to see all rewards'],
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
                  final hasPending = widget.pendingRequests.any(
                      (r) => r.userId == widget.user.id && r.rewardId == reward.id);
                  return _RewardCard(
                    reward: reward,
                    canRedeem: !hasPending,
                    hasPendingRequest: hasPending,
                    onRedeem: !hasPending
                        ? () => widget.onRedeem(reward)
                        : null,
                    onDelete: () => widget.onDelete(reward.id),
                    onEdit: () => widget.onEdit(reward),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Requests Tab ────────────────────────────────────────────────────────────

class _RequestsTab extends StatelessWidget {
  final List<RewardRedemption> pendingRequests;
  final List<RewardRedemption> resolvedRequests;
  final AppProvider provider;
  final bool isOwner;
  final String currentUserId;
  final void Function(RewardRedemption) onReview;

  const _RequestsTab({
    required this.pendingRequests,
    required this.resolvedRequests,
    required this.provider,
    required this.isOwner,
    required this.currentUserId,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final approvable = isOwner ? pendingRequests : <RewardRedemption>[];
    final myPending = isOwner
        ? <RewardRedemption>[]
        : pendingRequests.where((r) => r.userId == currentUserId).toList();
    final myHistory =
        resolvedRequests.where((r) => r.userId == currentUserId).toList();
    final allHistory = resolvedRequests;

    if (pendingRequests.isEmpty && resolvedRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📋', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text(
              'No requests yet',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.stone400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isOwner
                  ? 'Requests from family members will appear here.'
                  : 'Request a reward from the Store tab!',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppTheme.stone400,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Pending: requests awaiting approval (visible to owner/parent) ──
          if (approvable.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(children: [
                const Expanded(
                    child: SectionHeader(title: 'AWAITING YOUR APPROVAL')),
                _CountBadge(
                    count: approvable.length,
                    color: const Color(0xFFF59E0B)),
              ]),
            ),
            ...approvable.map((r) => _PendingRequestCard(
                  redemption: r,
                  provider: provider,
                  showReviewButton: true,
                  onReview: () => onReview(r),
                )),
            const SizedBox(height: 12),
          ],

          // ── My pending requests ──
          if (myPending.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: SectionHeader(title: 'MY PENDING REQUESTS'),
            ),
            ...myPending.map((r) => _PendingRequestCard(
                  redemption: r,
                  provider: provider,
                  showReviewButton: false,
                  onReview: null,
                )),
            const SizedBox(height: 12),
          ],

          // ── History ──
          if ((isOwner ? allHistory : myHistory).isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: SectionHeader(title: 'HISTORY'),
            ),
            ...(isOwner ? allHistory : myHistory)
                .take(20)
                .map((r) => _HistoryCard(redemption: r, provider: provider)),
          ],
        ],
      ),
    );
  }
}

// ─── Pending Request Card ────────────────────────────────────────────────────

class _PendingRequestCard extends StatelessWidget {
  final RewardRedemption redemption;
  final AppProvider provider;
  final bool showReviewButton;
  final VoidCallback? onReview;

  const _PendingRequestCard({
    required this.redemption,
    required this.provider,
    required this.showReviewButton,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final userName =
        provider.userById(redemption.userId)?.name ?? 'Family member';
    final timeAgo = _formatTimeAgo(redemption.requestedAt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('⏳', style: TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    redemption.rewardTitle,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.stone900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$userName  ·  $timeAgo',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppTheme.stone400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${redemption.amount} pts',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFFD97706),
              ),
            ),
            if (showReviewButton) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onReview,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Review',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── History Card ────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final RewardRedemption redemption;
  final AppProvider provider;

  const _HistoryCard({required this.redemption, required this.provider});

  @override
  Widget build(BuildContext context) {
    final userName =
        provider.userById(redemption.userId)?.name ?? 'Family member';
    final isApproved = redemption.status == RedemptionStatus.APPROVED;
    final resolverName = redemption.resolvedBy != null
        ? provider.userById(redemption.resolvedBy!)?.name
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusBadge(status: redemption.status),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    redemption.rewardTitle,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.stone900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${redemption.amount} pts',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isApproved ? AppTheme.success : AppTheme.stone400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  userName,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppTheme.stone500,
                  ),
                ),
                if (resolverName != null) ...[
                  Text(
                    '  ·  ${isApproved ? 'approved' : 'denied'} by $resolverName',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: isApproved ? AppTheme.success : AppTheme.stone400,
                    ),
                  ),
                ],
                const Spacer(),
                if (redemption.resolvedAt != null)
                  Text(
                    DateFormat.yMMMd().format(redemption.resolvedAt!),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: AppTheme.stone400,
                    ),
                  ),
              ],
            ),
            if (redemption.resolvedNote != null &&
                redemption.resolvedNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isApproved
                      ? AppTheme.success.withValues(alpha: 0.05)
                      : AppTheme.error.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 14,
                      color: isApproved ? AppTheme.success : AppTheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '"${redemption.resolvedNote}"',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: isApproved
                              ? AppTheme.success
                              : AppTheme.stone600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Status Badge ────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final RedemptionStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final IconData icon;
    final String label;

    switch (status) {
      case RedemptionStatus.APPROVED:
        bg = AppTheme.success.withValues(alpha: 0.1);
        fg = AppTheme.success;
        icon = Icons.check_circle_rounded;
        label = 'Approved';
      case RedemptionStatus.DENIED:
        bg = AppTheme.error.withValues(alpha: 0.1);
        fg = AppTheme.error;
        icon = Icons.cancel_rounded;
        label = 'Denied';
      case RedemptionStatus.PENDING:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        icon = Icons.schedule_rounded;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ]),
    );
  }
}

// ─── Goals Tab ───────────────────────────────────────────────────────────────

class _GoalsTab extends StatelessWidget {
  final List<SavingsGoal> savingsGoals;
  final List<FamilyMember> members;
  final AppProvider provider;
  final VoidCallback onAddGoal;
  final void Function(String) onDeleteGoal;
  final void Function(SavingsGoal) onShowAddFunds;

  const _GoalsTab({
    required this.savingsGoals,
    required this.members,
    required this.provider,
    required this.onAddGoal,
    required this.onDeleteGoal,
    required this.onShowAddFunds,
  });

  @override
  Widget build(BuildContext context) {
    if (savingsGoals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎯', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text(
                'No savings goals yet',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.stone400,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Set a target and save up for something special!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppTheme.stone400,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onAddGoal,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Goal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(children: [
              const Expanded(child: SectionHeader(title: 'SAVINGS GOALS')),
              GestureDetector(
                onTap: onAddGoal,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 2),
                  Text('New Goal',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary)),
                ]),
              ),
            ]),
          ),
          ...savingsGoals.map((goal) {
            final progress = goal.targetAmount > 0
                ? (goal.savedAmount / goal.targetAmount).clamp(0.0, 1.0)
                : 0.0;
            final isComplete = goal.savedAmount >= goal.targetAmount;
            final goalMember = members
                    .where((m) => m.id == goal.userId)
                    .firstOrNull ??
                members.firstOrNull;
            final ownerName = goalMember != null
                ? provider.memberDisplayName(goalMember)
                : 'Unknown';
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: isComplete
                          ? AppTheme.success.withValues(alpha: 0.4)
                          : AppTheme.stone100,
                      width: isComplete ? 2 : 1),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(goal.icon ?? '🎯',
                            style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(goal.title,
                                  style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: AppTheme.stone900)),
                              Text(ownerName,
                                  style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      color: AppTheme.stone400)),
                            ])),
                        if (isComplete)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppTheme.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Text('Complete!',
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.success)),
                          )
                        else
                          GestureDetector(
                            onTap: () => onDeleteGoal(goal.id),
                            child: const Icon(Icons.close_rounded,
                                size: 16, color: AppTheme.stone300),
                          ),
                      ]),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: AppTheme.stone100,
                          valueColor: AlwaysStoppedAnimation(
                              isComplete ? AppTheme.success : AppTheme.primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                '\$${goal.savedAmount.toStringAsFixed(0)} of \$${goal.targetAmount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.stone600)),
                            Text('${(progress * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isComplete
                                        ? AppTheme.success
                                        : AppTheme.primary)),
                          ]),
                      if (!isComplete) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => onShowAddFunds(goal),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.savings_rounded,
                                      size: 16, color: AppTheme.primary),
                                  const SizedBox(width: 6),
                                  Text('Add Funds',
                                      style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.primary)),
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
    );
  }
}

// ─── Reward Card ─────────────────────────────────────────────────────────────

class _RewardCard extends StatelessWidget {
  final Reward reward;
  final bool canRedeem;
  final bool hasPendingRequest;
  final VoidCallback? onRedeem;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _RewardCard({
    required this.reward,
    required this.canRedeem,
    required this.hasPendingRequest,
    required this.onRedeem,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasPendingRequest
            ? const Color(0xFFFFFBEB)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: hasPendingRequest
                ? const Color(0xFFFDE68A)
                : AppTheme.stone100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('🎁', style: TextStyle(fontSize: 28)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: onEdit,
              child: const Icon(Icons.edit_outlined,
                  size: 16, color: AppTheme.stone300),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: const Icon(Icons.close_rounded,
                  size: 16, color: AppTheme.stone300),
            ),
          ]),
        ]),
        const SizedBox(height: 6),
        Text(reward.title,
            style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.stone900),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const Spacer(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Text('${reward.pointCost} pts',
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.warning)),
          ),
          if (hasPendingRequest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.schedule_rounded,
                    size: 12, color: Color(0xFFD97706)),
                SizedBox(width: 3),
                Text('Pending',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD97706))),
              ]),
            )
          else
            GestureDetector(
              onTap: onRedeem,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: canRedeem ? AppTheme.primary : AppTheme.stone200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Request',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color:
                            canRedeem ? Colors.white : AppTheme.stone400)),
              ),
            ),
        ]),
      ]),
    );
  }
}

// ─── Info Row (for dialogs) ──────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 80,
        child: Text(label,
            style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.stone400)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.stone900)),
      ),
    ]);
  }
}

// ─── Count Badge ─────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  const _CountBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
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
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              const Text('New Savings Goal',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.stone900)),
              const SizedBox(height: 16),
              const Text('Pick an icon',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.stone500)),
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
                          color: selected
                              ? AppTheme.primary.withValues(alpha: 0.1)
                              : AppTheme.stone100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: selected
                                  ? AppTheme.primary
                                  : Colors.transparent,
                              width: 2),
                        ),
                        child: Center(
                            child: Text(icon,
                                style: const TextStyle(fontSize: 20))),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Goal Title *',
                  prefixIcon:
                      Text(' $_selectedIcon ', style: const TextStyle(fontSize: 18)),
                  prefixIconConstraints: const BoxConstraints(minWidth: 44),
                ),
              ),
              const SizedBox(height: 12),
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
              TextField(
                controller: _savedCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Already Saved (optional)',
                  prefixText: '\$ ',
                  prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _imageUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Image URL (optional)',
                  prefixIcon: Icon(Icons.image_rounded),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Saving for',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.stone500)),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary.withValues(alpha: 0.1)
                            : AppTheme.stone100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: selected
                                ? AppTheme.primary
                                : Colors.transparent,
                            width: 2),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        AvatarInitials(name: name, size: 24),
                        const SizedBox(width: 6),
                        Text(name,
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight:
                                    selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected
                                    ? AppTheme.primary
                                    : AppTheme.stone600)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
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
                      imageUrl: _imageUrlCtrl.text.trim().isEmpty
                          ? null
                          : _imageUrlCtrl.text.trim(),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Create Goal',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
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
      final iconMatch = RegExp(
              r'^(\p{Emoji_Presentation}|\p{Emoji}\uFE0F?)\s*',
              unicode: true)
          .firstMatch(title);
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
      description:
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      pointCost: int.tryParse(_costCtrl.text) ?? 50,
      redeemedBy: widget.editReward?.redeemedBy ?? [],
    );
    await widget.onSave(reward);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SheetHandle(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
                widget.editReward != null ? 'Edit Reward' : 'New Reward',
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: AppTheme.stone900)),
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Choose Icon',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.stone500)),
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
                      color: selected
                          ? AppTheme.primary.withValues(alpha: 0.1)
                          : AppTheme.stone100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: selected
                              ? AppTheme.primary
                              : Colors.transparent,
                          width: 2),
                    ),
                    child: Center(
                        child:
                            Text(icon, style: const TextStyle(fontSize: 20))),
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
              prefixIcon:
                  Text(' $_selectedIcon ', style: const TextStyle(fontSize: 18)),
              prefixIconConstraints: const BoxConstraints(minWidth: 44),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Description (optional)',
                alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _costCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Points Cost',
                prefixIcon: Icon(Icons.star_rounded)),
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
              width: 32,
              height: 32,
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
                  Text(value,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: iconColor,
                      )),
                  Text(label,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.stone400,
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

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _formatTimeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.yMMMd().format(dt);
}

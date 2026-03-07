// lib/screens/rewards/rewards_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _redeemReward(Reward reward, String userId) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final updated = db.rewards.map((r) {
      if (r.id == reward.id) {
        return Reward(
          id: r.id,
          familyId: r.familyId,
          title: r.title,
          pointCost: r.pointCost,
          description: r.description,
          redeemedBy: [...r.redeemedBy, userId],
        );
      }
      return r;
    }).toList();
    await provider.saveAndSync(db.copyWith(rewards: updated));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${reward.title} redeemed!'),
        backgroundColor: AppTheme.success,
      ));
    }
  }

  Future<void> _deleteReward(String rewardId) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      rewards: db.rewards.where((r) => r.id != rewardId).toList(),
    ));
  }

  void _showAddRewardSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RewardFormSheet(
        onSave: (reward) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(rewards: [...db.rewards, reward]));
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
    final myPoints = provider.chorePointsForUser(user.id);

    final sortedMembers = [...members]
      ..sort((a, b) => provider.chorePointsForUser(b.id).compareTo(provider.chorePointsForUser(a.id)));

    final myRedemptions = rewards.where((r) => r.redeemedBy.contains(user.id)).toList();

    return Scaffold(
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddRewardSheet,
        child: const Icon(Icons.add_rounded),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            title: const Text('Rewards'),
            floating: true,
            bottom: TabBar(
              controller: _tabController,
              tabs: const [Tab(text: 'Rewards'), Tab(text: 'Redeemed')],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Rewards + Leaderboard
            CustomScrollView(
              slivers: [
                // My points banner
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(children: [
                      const Text('⭐', style: TextStyle(fontSize: 32)),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$myPoints', style: const TextStyle(fontFamily: 'Inter', fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
                        const Text('My Points', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70)),
                      ]),
                      const Spacer(),
                      const Text('🏆', style: TextStyle(fontSize: 24)),
                    ]),
                  ),
                ),
                // Leaderboard
                if (sortedMembers.length > 1) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text('LEADERBOARD', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 88,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: sortedMembers.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (ctx, i) {
                          final m = sortedMembers[i];
                          final pts = provider.chorePointsForUser(m.id);
                          final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i + 1}';
                          return Container(
                            width: 100,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: i == 0 ? AppTheme.primary.withOpacity(0.08) : AppTheme.stone50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: i == 0 ? AppTheme.primary.withOpacity(0.2) : AppTheme.stone100),
                            ),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(medal, style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 2),
                              Text(m.name.split(' ').first, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone800)),
                              Text('$pts pts', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: i == 0 ? AppTheme.primary : AppTheme.stone500)),
                            ]),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                // Rewards grid
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text('AVAILABLE REWARDS', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
                  ),
                ),
                rewards.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: EmptyState(
                            emoji: '🎁',
                            title: 'No rewards yet',
                            subtitle: 'Add rewards for the family to redeem.',
                            actionLabel: 'Add Reward',
                            onAction: _showAddRewardSheet,
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.1,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) {
                              final reward = rewards[i];
                              final canRedeem = myPoints >= reward.pointCost;
                              final alreadyRedeemed = reward.redeemedBy.contains(user.id);
                              return _RewardCard(
                                reward: reward,
                                canRedeem: canRedeem && !alreadyRedeemed,
                                alreadyRedeemed: alreadyRedeemed,
                                onRedeem: canRedeem && !alreadyRedeemed
                                    ? () => _redeemReward(reward, user.id)
                                    : null,
                                onDelete: () => _deleteReward(reward.id),
                              );
                            },
                            childCount: rewards.length,
                          ),
                        ),
                      ),
              ],
            ),
            // Tab 2: My redeemed
            myRedemptions.isEmpty
                ? const EmptyState(emoji: '🎫', title: 'No redemptions', subtitle: 'Redeem rewards to see them here.')
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: myRedemptions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final r = myRedemptions[i];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.success.withOpacity(0.2)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 32),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900)),
                            if (r.description != null)
                              Text(r.description!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text('${r.pointCost} pts', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.warning)),
                          ),
                        ]),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  final Reward reward;
  final bool canRedeem;
  final bool alreadyRedeemed;
  final VoidCallback? onRedeem;
  final VoidCallback onDelete;

  const _RewardCard({
    required this.reward,
    required this.canRedeem,
    required this.alreadyRedeemed,
    required this.onRedeem,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: alreadyRedeemed ? AppTheme.success.withOpacity(0.05) : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: alreadyRedeemed ? AppTheme.success.withOpacity(0.3) : AppTheme.stone100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('🎁', style: TextStyle(fontSize: 28)),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone300),
          ),
        ]),
        const SizedBox(height: 6),
        Text(reward.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.stone900), maxLines: 2, overflow: TextOverflow.ellipsis),
        const Spacer(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
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

class _RewardFormSheet extends StatefulWidget {
  final Future<void> Function(Reward) onSave;
  const _RewardFormSheet({required this.onSave});

  @override
  State<_RewardFormSheet> createState() => _RewardFormSheetState();
}

class _RewardFormSheetState extends State<_RewardFormSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _costCtrl = TextEditingController(text: '50');
  bool _isSaving = false;
  final _uuid = const Uuid();

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
    final reward = Reward(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      pointCost: int.tryParse(_costCtrl.text) ?? 50,
      redeemedBy: [],
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
            const Text('New Reward', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _titleCtrl, autofocus: true, textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Reward Title *', prefixIcon: Icon(Icons.card_giftcard_rounded))),
          const SizedBox(height: 12),
          TextField(controller: _descCtrl, maxLines: 2, textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description (optional)', alignLabelWithHint: true)),
          const SizedBox(height: 12),
          TextField(controller: _costCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Points Cost', prefixIcon: Icon(Icons.star_rounded))),
        ]),
      ),
    );
  }
}

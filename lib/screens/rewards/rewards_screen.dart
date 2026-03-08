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

class _RewardsScreenState extends State<RewardsScreen> {
  Future<void> _redeemReward(Reward reward, String userId) async {
    // Confirmation dialog
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
            child: const Text('Redeem 🎉'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

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
        content: Text('${reward.title} redeemed! 🎉'),
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
    final isOwner = user.id == family.ownerId;

    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppTheme.stone700),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 20, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('FamilyHub', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary)),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppTheme.stone500),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page Header ──
            PageHeader(
              title: 'Reward Store',
              subtitle: 'Manage rewards, savings goals, and approve requests',
              actions: isOwner
                  ? [
                      ActionChipButton(
                        icon: Icons.savings_rounded,
                        label: 'Add Goal',
                        onTap: () {},
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

            // ── Kids' Balances Section ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: const Text(
                "Kids' Balances",
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.stone900,
                ),
              ),
            ),
            ...members.map((member) {
              final pts = provider.chorePointsForUser(member.id);
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.stone100),
                  ),
                  child: Row(
                    children: [
                      AvatarInitials(name: member.name, size: 44),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member.name,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.stone900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Earned: \$$pts',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
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
                            '\$$pts',
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
                              fontWeight: FontWeight.w400,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: const Text(
                'Reward Catalog',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.stone900,
                ),
              ),
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
                ),
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
  String _selectedIcon = '🎁';
  bool _isSaving = false;
  final _uuid = const Uuid();

  static const _iconOptions = [
    '🎁', '🎮', '🍕', '🎬', '🏖️', '🛍️', '☕', '🍦', '🎯', '🏆',
    '💆', '🎤', '🎲', '📱', '🎵', '🌟', '🍫', '🚗', '✈️', '🏠',
  ];

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
    // Prepend icon to title since model has no icon field
    final titleWithIcon = '$_selectedIcon ${_titleCtrl.text.trim()}';
    final reward = Reward(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      title: titleWithIcon,
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
          // Icon picker
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Choose Icon', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
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
                      color: selected ? AppTheme.primary.withOpacity(0.1) : AppTheme.stone100,
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

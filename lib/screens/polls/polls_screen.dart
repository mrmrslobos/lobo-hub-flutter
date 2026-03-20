// lib/screens/polls/polls_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class PollsScreen extends StatefulWidget {
  const PollsScreen({super.key});

  @override
  State<PollsScreen> createState() => _PollsScreenState();
}

class _PollsScreenState extends State<PollsScreen> {
  String? _expandedPollId;
  int _selectedFilter = 0; // 0=Open, 1=Closed, 2=All

  // ── Data helpers ───────────────────────────────────────────────────────────

  Future<void> _vote(Poll poll, String optionId) async {
    final provider = context.read<AppProvider>();
    final userId = provider.activeUser?.id;
    if (userId == null) return;
    final db = provider.db;

    final updatedOptions = poll.options.map((o) {
      if (o.id == optionId) {
        if (o.voterIds.contains(userId)) {
          return o.copyWith(voterIds: o.voterIds.where((v) => v != userId).toList());
        } else {
          return o.copyWith(voterIds: [...o.voterIds, userId]);
        }
      } else {
        return o.copyWith(voterIds: o.voterIds.where((v) => v != userId).toList());
      }
    }).toList();

    final updatedPoll = poll.copyWith(options: updatedOptions);
    final updatedPolls = db.polls.map((p) => p.id == poll.id ? updatedPoll : p).toList();
    await provider.saveAndSync(db.copyWith(polls: updatedPolls));
  }

  Future<void> _closePoll(Poll poll) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Poll?'),
        content: const Text(
          'Once closed, no more votes can be cast. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.warning),
            child: const Text('Close Poll'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final updatedPoll = poll.copyWith(status: PollStatus.closed);
    await provider.saveAndSync(db.copyWith(
      polls: db.polls.map((p) => p.id == poll.id ? updatedPoll : p).toList(),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Poll closed'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _deletePoll(String pollId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Poll'),
        content: const Text('Delete this poll and all votes? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(polls: db.polls.where((p) => p.id != pollId).toList()));
  }

  void _showCreatePollSheet({Poll? editPoll}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePollSheet(
        editPoll: editPoll,
        onSave: (poll) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          if (editPoll != null) {
            await provider.saveAndSync(db.copyWith(
              polls: db.polls.map((p) => p.id == editPoll.id ? poll : p).toList(),
            ));
          } else {
            await provider.saveAndSync(db.copyWith(polls: [...db.polls, poll]));
            NotificationService.notifyFamilyActivity(
              title: 'New Poll',
              body: '${provider.activeUser?.name ?? "Someone"} asks: ${poll.question}',
              path: '/polls',
              familyId: provider.activeFamily?.id,
              excludeUserId: provider.activeUser?.id,
            );
          }
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final polls = provider.db.polls.where((p) => p.familyId == family.id).toList();

    // Auto-close expired polls
    final now = DateTime.now();
    final expiredPolls = polls.where((p) =>
      p.status == PollStatus.open && p.deadline != null && p.deadline!.isBefore(now),
    ).toList();
    if (expiredPolls.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final db = provider.db;
        var updatedPolls = db.polls.map((p) {
          if (expiredPolls.any((e) => e.id == p.id)) {
            return p.copyWith(status: PollStatus.closed);
          }
          return p;
        }).toList();
        await provider.saveAndSync(db.copyWith(polls: updatedPolls));
      });
    }

    polls.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final openPolls = polls.where((p) => p.status == PollStatus.open).toList();
    final closedPolls = polls.where((p) => p.status == PollStatus.closed).toList();
    final myVotes = polls.where((p) => p.options.any((o) => o.voterIds.contains(user.id))).length;

    final filteredPolls = _selectedFilter == 0
        ? openPolls
        : _selectedFilter == 1
            ? closedPolls
            : polls;

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppTheme.background,
      appBar: const FamilyHubAppBar(),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Page Header ──
          PageHeader(
            title: 'Family Polls',
            subtitle: 'Decide things together.',
            actions: [
              ActionChipButton(
                icon: Icons.add_rounded,
                label: 'New Poll',
                onTap: _showCreatePollSheet,
                isPrimary: true,
              ),
            ],
          ),

          // ── Stat Cards ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _StatCard(
                  icon: Icons.poll_outlined,
                  label: 'Total',
                  value: '${polls.length}',
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 10),
                _StatCard(
                  icon: Icons.how_to_vote_outlined,
                  label: 'Open',
                  value: '${openPolls.length}',
                  color: AppTheme.success,
                ),
                const SizedBox(width: 10),
                _StatCard(
                  icon: Icons.bar_chart_rounded,
                  label: 'My Votes',
                  value: '$myVotes',
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Filter Chips ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _FilterChip(
                  label: 'Open',
                  count: openPolls.length,
                  selected: _selectedFilter == 0,
                  onTap: () => setState(() => _selectedFilter = 0),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Closed',
                  count: closedPolls.length,
                  selected: _selectedFilter == 1,
                  onTap: () => setState(() => _selectedFilter = 1),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'All',
                  count: polls.length,
                  selected: _selectedFilter == 2,
                  onTap: () => setState(() => _selectedFilter = 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Poll cards or empty state ──
          if (filteredPolls.isEmpty)
            _buildEmptyState()
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: filteredPolls.map((poll) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Dismissible(
                    key: ValueKey(poll.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: AppTheme.error,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(Icons.delete, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    confirmDismiss: (direction) async {
                      return await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Poll'),
                          content: Text('Delete "${poll.question}"?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ) ?? false;
                    },
                    onDismissed: (direction) => _deletePoll(poll.id),
                    child: _PollCard(
                      poll: poll,
                      userId: user.id,
                      isExpanded: _expandedPollId == poll.id,
                      onTap: () => setState(() {
                        _expandedPollId = _expandedPollId == poll.id ? null : poll.id;
                      }),
                      onVote: poll.status == PollStatus.open ? (optId) => _vote(poll, optId) : null,
                      onClose: poll.status == PollStatus.open ? () => _closePoll(poll) : null,
                      onEdit: poll.status == PollStatus.open ? () => _showCreatePollSheet(editPoll: poll) : null,
                      onDelete: () => _deletePoll(poll.id),
                    ),
                  ),
                )).toList(),
              ),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final labels = ['open polls', 'closed polls', 'polls'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppTheme.stone50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.poll_outlined, size: 28, color: AppTheme.stone300),
            ),
            const SizedBox(height: 12),
            Text(
              'No ${labels[_selectedFilter]}',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.stone500),
            ),
            const SizedBox(height: 4),
            Text(
              _selectedFilter == 0
                  ? 'Tap "New Poll" to get the family voting!'
                  : _selectedFilter == 1
                      ? 'No polls have been closed yet'
                      : 'Create your first poll to decide together',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat Card ───────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                  Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.stone400)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Filter Chip ─────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.stone200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppTheme.stone600,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.2) : AppTheme.stone100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppTheme.stone500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Poll Card ───────────────────────────────────────────────────────────────

class _PollCard extends StatelessWidget {
  final Poll poll;
  final String userId;
  final bool isExpanded;
  final VoidCallback onTap;
  final Future<void> Function(String)? onVote;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  const _PollCard({
    required this.poll,
    required this.userId,
    required this.isExpanded,
    required this.onTap,
    required this.onVote,
    required this.onClose,
    this.onEdit,
    required this.onDelete,
  });

  bool get _isOpen => poll.status == PollStatus.open;

  @override
  Widget build(BuildContext context) {
    final totalVotes = poll.totalVotes;
    final hasVoted = poll.options.any((o) => o.voterIds.contains(userId));

    // Find the winning option
    PollOption? winningOption;
    if (totalVotes > 0) {
      winningOption = poll.options.reduce((a, b) => a.voterIds.length >= b.voterIds.length ? a : b);
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isOpen
                ? (isExpanded ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.primary.withValues(alpha: 0.15))
                : AppTheme.stone100,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              // Status indicator
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _isOpen
                      ? AppTheme.success.withValues(alpha: 0.1)
                      : AppTheme.stone50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _isOpen ? Icons.how_to_vote_outlined : Icons.lock_outline_rounded,
                  size: 18,
                  color: _isOpen ? AppTheme.success : AppTheme.stone400,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poll.question,
                      style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '$totalVotes vote${totalVotes == 1 ? '' : 's'}',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                        ),
                        if (poll.anonymous) ...[
                          const SizedBox(width: 6),
                          Container(width: 3, height: 3, decoration: const BoxDecoration(color: AppTheme.stone300, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Icon(Icons.visibility_off_rounded, size: 12, color: AppTheme.stone400),
                          const SizedBox(width: 3),
                          const Text('Anonymous', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                        ],
                        if (hasVoted) ...[
                          const SizedBox(width: 6),
                          Container(width: 3, height: 3, decoration: const BoxDecoration(color: AppTheme.stone300, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle_rounded, size: 12, color: AppTheme.primary),
                          const SizedBox(width: 3),
                          const Text('Voted', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isOpen
                      ? AppTheme.success.withValues(alpha: 0.1)
                      : AppTheme.stone50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isOpen ? 'Open' : 'Closed',
                  style: TextStyle(
                    fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700,
                    color: _isOpen ? AppTheme.success : AppTheme.stone400,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more_rounded, color: AppTheme.stone400, size: 22),
              ),
            ]),
          ),

          // ── Quick preview bar (collapsed) ──
          if (!isExpanded && totalVotes > 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 4,
                        child: Row(
                          children: poll.options.map((o) {
                            final pct = totalVotes > 0 ? o.voterIds.length / totalVotes : 0.0;
                            return Expanded(
                              flex: (pct * 100).round().clamp(1, 100),
                              child: Container(
                                color: o.id == winningOption?.id
                                    ? AppTheme.primary
                                    : AppTheme.primary.withValues(alpha: 0.15 + (pct * 0.3)),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (winningOption != null)
                    Text(
                      winningOption.text.length > 15
                          ? '${winningOption.text.substring(0, 15)}...'
                          : winningOption.text,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.stone400),
                    ),
                ],
              ),
            ),
          ],

          // ── Options (expanded) ──
          if (isExpanded) ...[
            const Divider(height: 1, color: AppTheme.stone100),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                ...poll.options.map((option) {
                  final isVotedOption = option.voterIds.contains(userId);
                  final pct = totalVotes > 0 ? option.voterIds.length / totalVotes : 0.0;
                  final isWinning = option.id == winningOption?.id && totalVotes > 0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: (_isOpen && onVote != null) ? () => onVote!(option.id) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isVotedOption
                              ? AppTheme.primary.withValues(alpha: 0.06)
                              : AppTheme.stone50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isVotedOption ? AppTheme.primary : AppTheme.stone200,
                            width: isVotedOption ? 1.5 : 1,
                          ),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 20, height: 20,
                              decoration: BoxDecoration(
                                color: isVotedOption ? AppTheme.primary : Colors.transparent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isVotedOption ? AppTheme.primary : AppTheme.stone300,
                                  width: 2,
                                ),
                              ),
                              child: isVotedOption
                                  ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(
                              option.text,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: isVotedOption || isWinning ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 14,
                                color: isVotedOption ? AppTheme.primary : AppTheme.stone800,
                              ),
                            )),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isVotedOption
                                    ? AppTheme.primary.withValues(alpha: 0.1)
                                    : AppTheme.stone100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${(pct * 100).round()}%',
                                style: TextStyle(
                                  fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700,
                                  color: isVotedOption ? AppTheme.primary : AppTheme.stone500,
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 5,
                              backgroundColor: AppTheme.stone100,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isVotedOption ? AppTheme.primary : (isWinning ? AppTheme.primary.withValues(alpha: 0.5) : AppTheme.stone300),
                              ),
                            ),
                          ),
                          if (option.voterIds.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${option.voterIds.length} vote${option.voterIds.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400),
                            ),
                          ],
                        ]),
                      ),
                    ),
                  );
                }),

                // Deadline info
                if (poll.deadline != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.stone50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 14, color: AppTheme.stone400),
                        const SizedBox(width: 6),
                        Text(
                          _isOpen
                              ? 'Ends ${DateFormat('MMM d, y').format(poll.deadline!)}'
                              : 'Ended ${DateFormat('MMM d, y').format(poll.deadline!)}',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                        ),
                      ],
                    ),
                  ),
                ],

                // Action buttons
                if ((_isOpen && onClose != null) || onDelete != null) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: AppTheme.stone100),
                  const SizedBox(height: 8),
                  Row(children: [
                    if (_isOpen && onEdit != null)
                      GestureDetector(
                        onTap: onEdit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_rounded, size: 14, color: AppTheme.primary),
                              const SizedBox(width: 6),
                              Text('Edit', style: TextStyle(
                                fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary,
                              )),
                            ],
                          ),
                        ),
                      ),
                    if (_isOpen && onClose != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onClose,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.stone50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.stone200),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline_rounded, size: 14, color: AppTheme.stone600),
                              SizedBox(width: 6),
                              Text('Close', style: TextStyle(
                                fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone600,
                              )),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 14, color: AppTheme.error),
                            SizedBox(width: 6),
                            Text('Delete', style: TextStyle(
                              fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.error,
                            )),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─── Create Poll Sheet ───────────────────────────────────────────────────────

class _CreatePollSheet extends StatefulWidget {
  final Future<void> Function(Poll) onSave;
  final Poll? editPoll;
  const _CreatePollSheet({required this.onSave, this.editPoll});

  @override
  State<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<_CreatePollSheet> {
  late final TextEditingController _questionCtrl;
  late final List<TextEditingController> _optionCtrls;
  DateTime? _expiresAt;
  bool _anonymous = false;
  bool _isSaving = false;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    final p = widget.editPoll;
    if (p != null) {
      _questionCtrl = TextEditingController(text: p.question);
      _optionCtrls = p.options
          .map((o) => TextEditingController(text: o.text))
          .toList();
      _expiresAt = p.deadline;
      _anonymous = p.anonymous;
    } else {
      _questionCtrl = TextEditingController();
      _optionCtrls = [TextEditingController(), TextEditingController()];
    }
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionCtrls) c.dispose();
    super.dispose();
  }

  void _addOption() {
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_optionCtrls.length <= 2) return;
    _optionCtrls[i].dispose();
    setState(() => _optionCtrls.removeAt(i));
  }

  Future<void> _pickDeadline() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _expiresAt = d);
  }

  Future<void> _save() async {
    if (_questionCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please enter a question'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    final validOptions = _optionCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (validOptions.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Add at least 2 options'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final ep = widget.editPoll;
    final poll = Poll(
      id: ep?.id ?? _uuid.v4(),
      familyId: provider.activeFamily!.id,
      question: _questionCtrl.text.trim(),
      options: ep != null
          ? validOptions.asMap().entries.map((e) {
              final idx = e.key;
              final text = e.value;
              final existing = idx < ep.options.length ? ep.options[idx] : null;
              return PollOption(
                id: existing?.id ?? _uuid.v4(),
                text: text,
                voterIds: existing?.voterIds ?? [],
              );
            }).toList()
          : validOptions.map((t) => PollOption(id: _uuid.v4(), text: t, voterIds: [])).toList(),
      status: ep?.status ?? PollStatus.open,
      creatorId: ep?.creatorId ?? provider.activeUser!.id,
      createdAt: ep?.createdAt ?? DateTime.now(),
      deadline: _expiresAt,
      anonymous: _anonymous,
    );
    await widget.onSave(poll);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SheetHandle(),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.poll_outlined, size: 18, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                const Text('New Poll', style: TextStyle(
                  fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.stone900,
                )),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.stone400),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                // Question
                _sectionLabel('Question'),
                const SizedBox(height: 8),
                TextField(
                  controller: _questionCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'What would you like to ask?',
                    hintStyle: const TextStyle(color: AppTheme.stone300),
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: AppTheme.stone50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                  ),
                ),
                const SizedBox(height: 20),

                // Options
                Row(
                  children: [
                    _sectionLabel('Options'),
                    const Spacer(),
                    GestureDetector(
                      onTap: _addOption,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 14, color: AppTheme.primary),
                            SizedBox(width: 4),
                            Text('Add', style: TextStyle(
                              fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary,
                            )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(_optionCtrls.length, (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: AppTheme.stone50,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.stone200),
                      ),
                      alignment: Alignment.center,
                      child: Text('${i + 1}', style: const TextStyle(
                        fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone400,
                      )),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _optionCtrls[i],
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Option ${i + 1}',
                          hintStyle: const TextStyle(color: AppTheme.stone300),
                          filled: true,
                          fillColor: AppTheme.stone50,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                        ),
                      ),
                    ),
                    if (_optionCtrls.length > 2)
                      IconButton(
                        onPressed: () => _removeOption(i),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: AppTheme.stone400,
                        visualDensity: VisualDensity.compact,
                      ),
                  ]),
                )),
                const SizedBox(height: 16),

                // Deadline
                _sectionLabel('Settings'),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickDeadline,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.stone50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.stone200),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.timer_outlined, size: 16, color: AppTheme.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Deadline', style: TextStyle(
                              fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800,
                            )),
                            Text(
                              _expiresAt != null
                                  ? 'Closes ${DateFormat('MMM d, y').format(_expiresAt!)}'
                                  : 'No deadline (optional)',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: _expiresAt != null ? AppTheme.stone600 : AppTheme.stone400),
                            ),
                          ],
                        ),
                      ),
                      if (_expiresAt != null)
                        GestureDetector(
                          onTap: () => setState(() => _expiresAt = null),
                          child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone400),
                        )
                      else
                        const Icon(Icons.edit_outlined, size: 14, color: AppTheme.stone400),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),

                // Anonymous toggle
                GestureDetector(
                  onTap: () => setState(() => _anonymous = !_anonymous),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _anonymous ? AppTheme.primary.withValues(alpha: 0.05) : AppTheme.stone50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _anonymous ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.stone200,
                      ),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: (_anonymous ? AppTheme.primary : AppTheme.stone400).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.visibility_off_rounded, size: 16, color: _anonymous ? AppTheme.primary : AppTheme.stone400),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Anonymous Voting', style: TextStyle(
                              fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600,
                              color: _anonymous ? AppTheme.primary : AppTheme.stone800,
                            )),
                            Text(
                              'Votes are hidden from other members',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: _anonymous ? AppTheme.primary.withValues(alpha: 0.7) : AppTheme.stone400),
                            ),
                          ],
                        ),
                      ),
                      if (_anonymous)
                        const Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.primary),
                    ]),
                  ),
                ),
                const SizedBox(height: 24),

                // Create button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Create Poll', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700),
  );
}

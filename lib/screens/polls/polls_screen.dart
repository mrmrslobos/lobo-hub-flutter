// lib/screens/polls/polls_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class PollsScreen extends StatefulWidget {
  const PollsScreen({super.key});

  @override
  State<PollsScreen> createState() => _PollsScreenState();
}

class _PollsScreenState extends State<PollsScreen> {
  String? _expandedPollId;

  Future<void> _vote(Poll poll, String optionId) async {
    final provider = context.read<AppProvider>();
    final userId = provider.activeUser?.id;
    if (userId == null) return;
    final db = provider.db;

    // Remove existing vote from all options first (no multi-vote in this impl)
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
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final updatedPoll = poll.copyWith(status: PollStatus.closed);
    await provider.saveAndSync(db.copyWith(
      polls: db.polls.map((p) => p.id == poll.id ? updatedPoll : p).toList(),
    ));
  }

  Future<void> _deletePoll(String pollId) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(polls: db.polls.where((p) => p.id != pollId).toList()));
  }

  void _showCreatePollSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePollSheet(
        onSave: (poll) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(polls: [...db.polls, poll]));
        },
      ),
    );
  }

  int _selectedFilter = 0; // 0=Open, 1=Closed, 2=All

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final polls = provider.db.polls.where((p) => p.familyId == family.id).toList();
    polls.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final openPolls = polls.where((p) => p.status == PollStatus.open).toList();
    final closedPolls = polls.where((p) => p.status == PollStatus.closed).toList();

    // My votes count
    final myVotes = polls.where((p) => p.options.any((o) => o.voterIds.contains(user.id))).length;

    // Filtered polls based on selected filter
    final filteredPolls = _selectedFilter == 0
        ? openPolls
        : _selectedFilter == 1
            ? closedPolls
            : polls;

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppTheme.background,
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
          IconButton(icon: const Icon(Icons.menu_rounded, color: AppTheme.stone500), onPressed: () {}),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Page Header
          PageHeader(
            title: 'Family Polls',
            subtitle: 'Decide things together',
            actions: [
              ActionChipButton(
                icon: Icons.add,
                label: 'New Poll',
                onTap: _showCreatePollSheet,
                isPrimary: true,
              ),
            ],
          ),

          // Stats Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.poll_outlined,
                    iconBgColor: const Color(0xFFDBEAFE),
                    iconColor: const Color(0xFF3B82F6),
                    value: '${polls.length}',
                    label: 'Total Polls',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.check_circle_outline,
                    iconBgColor: const Color(0xFFD1FAE5),
                    iconColor: const Color(0xFF10B981),
                    value: '${openPolls.length}',
                    label: 'Open Now',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.bar_chart_rounded,
                    iconBgColor: const Color(0xFFEDE9FE),
                    iconColor: const Color(0xFF8B5CF6),
                    value: '$myVotes',
                    label: 'My Votes',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IndigoChip(
                  label: 'Open (${openPolls.length})',
                  selected: _selectedFilter == 0,
                  onTap: () => setState(() => _selectedFilter = 0),
                ),
                const SizedBox(width: 8),
                IndigoChip(
                  label: 'Closed (${closedPolls.length})',
                  selected: _selectedFilter == 1,
                  onTap: () => setState(() => _selectedFilter = 1),
                ),
                const SizedBox(width: 8),
                IndigoChip(
                  label: 'All (${polls.length})',
                  selected: _selectedFilter == 2,
                  onTap: () => setState(() => _selectedFilter = 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Poll cards or empty state
          if (filteredPolls.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.stone100),
                ),
                child: Column(
                  children: [
                    Icon(Icons.poll_outlined, size: 40, color: AppTheme.stone300),
                    const SizedBox(height: 12),
                    const Text(
                      'No open polls',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.stone600),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Create one to get the family voting!',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: filteredPolls.map((poll) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PollCard(
                    poll: poll,
                    userId: user.id,
                    isExpanded: _expandedPollId == poll.id,
                    onTap: () => setState(() {
                      _expandedPollId = _expandedPollId == poll.id ? null : poll.id;
                    }),
                    onVote: poll.status == PollStatus.open ? (optId) => _vote(poll, optId) : null,
                    onClose: poll.status == PollStatus.open ? () => _closePoll(poll) : null,
                    onDelete: () => _deletePoll(poll.id),
                  ),
                )).toList(),
              ),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.stone100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.stone900),
          ),
          Text(
            label,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone500),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1),
  );
}

class _PollCard extends StatelessWidget {
  final Poll poll;
  final String userId;
  final bool isExpanded;
  final VoidCallback onTap;
  final Future<void> Function(String)? onVote;
  final VoidCallback? onClose;
  final VoidCallback onDelete;

  const _PollCard({
    required this.poll,
    required this.userId,
    required this.isExpanded,
    required this.onTap,
    required this.onVote,
    required this.onClose,
    required this.onDelete,
  });

  bool get _hasVoted => poll.options.any((o) => o.voterIds.contains(userId));
  bool get _isOpen => poll.status == PollStatus.open;

  @override
  Widget build(BuildContext context) {
    final totalVotes = poll.totalVotes;
    final userVotedOption = poll.options.cast<PollOption?>().firstWhere(
        (o) => o!.voterIds.contains(userId), orElse: () => null);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _isOpen ? AppTheme.primary.withOpacity(0.2) : AppTheme.stone100),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: _isOpen ? AppTheme.success : AppTheme.stone300,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(poll.question, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900)),
              ),
              Text('$totalVotes vote${totalVotes == 1 ? '' : 's'}',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
              const SizedBox(width: 8),
              Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: AppTheme.stone400, size: 20),
            ]),
          ),
          // Options (expanded)
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                ...poll.options.map((option) {
                  final isVotedOption = option.voterIds.contains(userId);
                  final pct = totalVotes > 0 ? option.voterIds.length / totalVotes : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: (_isOpen && onVote != null) ? () => onVote!(option.id) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isVotedOption ? AppTheme.primaryLight : AppTheme.stone50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isVotedOption ? AppTheme.primary : AppTheme.stone200, width: isVotedOption ? 2 : 1),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            if (isVotedOption) const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.primary),
                            if (!isVotedOption) const Icon(Icons.circle_outlined, size: 16, color: AppTheme.stone300),
                            const SizedBox(width: 8),
                            Expanded(child: Text(option.text, style: TextStyle(fontFamily: 'Inter', fontWeight: isVotedOption ? FontWeight.w700 : FontWeight.w500, fontSize: 14, color: isVotedOption ? AppTheme.primary : AppTheme.stone800))),
                            Text('${(pct * 100).round()}%', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: isVotedOption ? AppTheme.primary : AppTheme.stone400)),
                          ]),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 4,
                              backgroundColor: AppTheme.stone100,
                              valueColor: AlwaysStoppedAnimation<Color>(isVotedOption ? AppTheme.primary : AppTheme.stone300),
                            ),
                          ),
                          if (option.voterIds.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('${option.voterIds.length} vote${option.voterIds.length == 1 ? '' : 's'}',
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                          ],
                        ]),
                      ),
                    ),
                  );
                }),
                if (poll.expiresAt != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.timer_outlined, size: 14, color: AppTheme.stone400),
                    const SizedBox(width: 4),
                    Text('Ends ${DateFormat('MMM d').format(poll.expiresAt!)}',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                  ]),
                ],
                if (_isOpen && onClose != null || onDelete != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    if (_isOpen && onClose != null)
                      TextButton(
                        onPressed: onClose,
                        style: TextButton.styleFrom(foregroundColor: AppTheme.stone500, padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: const Text('Close Poll'),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: onDelete,
                      style: TextButton.styleFrom(foregroundColor: AppTheme.error, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: const Text('Delete'),
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

// ─────────────────────────────────────────────
// Create poll bottom sheet
// ─────────────────────────────────────────────

class _CreatePollSheet extends StatefulWidget {
  final Future<void> Function(Poll) onSave;
  const _CreatePollSheet({required this.onSave});

  @override
  State<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<_CreatePollSheet> {
  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];
  DateTime? _expiresAt;
  bool _isSaving = false;
  final _uuid = const Uuid();

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
    if (_questionCtrl.text.trim().isEmpty) return;
    final validOptions = _optionCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (validOptions.length < 2) return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final poll = Poll(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      question: _questionCtrl.text.trim(),
      options: validOptions.map((t) => PollOption(id: _uuid.v4(), text: t, voterIds: [])).toList(),
      status: PollStatus.open,
      creatorId: provider.activeUser!.id,
      createdAt: DateTime.now(),
      deadline: _expiresAt,
    );
    await widget.onSave(poll);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('New Poll', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
              TextButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
              TextField(
                controller: _questionCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Question *', alignLabelWithHint: true, prefixIcon: Icon(Icons.help_outline_rounded)),
              ),
              const SizedBox(height: 20),
              const Text('Options', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone600)),
              const SizedBox(height: 8),
              ...List.generate(_optionCtrls.length, (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _optionCtrls[i],
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: 'Option ${i + 1}',
                            prefixIcon: const Icon(Icons.circle_outlined, size: 16),
                          ),
                        ),
                      ),
                      if (_optionCtrls.length > 2)
                        IconButton(
                          onPressed: () => _removeOption(i),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: AppTheme.stone400,
                        ),
                    ]),
                  )),
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Option'),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDeadline,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.stone200)),
                  child: Row(children: [
                    const Icon(Icons.timer_outlined, size: 18, color: AppTheme.stone500),
                    const SizedBox(width: 10),
                    Text(
                      _expiresAt != null ? 'Expires ${DateFormat('MMM d, y').format(_expiresAt!)}' : 'No deadline (optional)',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: _expiresAt != null ? AppTheme.stone800 : AppTheme.stone400),
                    ),
                    const Spacer(),
                    if (_expiresAt != null)
                      GestureDetector(onTap: () => setState(() => _expiresAt = null), child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone400)),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

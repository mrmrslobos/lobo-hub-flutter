// lib/screens/prayer_wall/prayer_wall_screen.dart
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

const _warmCream = Color(0xFFFDF8F0);
const _warmAmber = Color(0xFFD97706);
const _warmGreen = Color(0xFF16A34A);
const _warmPink = Color(0xFFEC4899);
const _warmIndigo = Color(0xFF6366F1);

class PrayerWallScreen extends StatefulWidget {
  const PrayerWallScreen({super.key});

  @override
  State<PrayerWallScreen> createState() => _PrayerWallScreenState();
}

class _PrayerWallScreenState extends State<PrayerWallScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  Future<void> _togglePrayed(PrayerRequest request, String userId) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final newPrayed = request.prayedByIds.contains(userId)
        ? request.prayedByIds.where((id) => id != userId).toList()
        : [...request.prayedByIds, userId];
    await provider.saveAndSync(db.copyWith(
      prayerRequests: db.prayerRequests
          .map((r) => r.id == request.id ? r.copyWith(prayedByIds: newPrayed) : r)
          .toList(),
    ));
  }

  Future<void> _markAnswered(PrayerRequest request) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      prayerRequests: db.prayerRequests
          .map((r) => r.id == request.id ? r.copyWith(answeredAt: DateTime.now()) : r)
          .toList(),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Praise God! Marked as answered 🙌')),
      );
    }
  }

  Future<void> _deleteRequest(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      prayerRequests: db.prayerRequests.where((r) => r.id != id).toList(),
    ));
  }

  void _showAddSheet() {
    final initialType =
        _tabController.index == 0 ? 'gratitude' : 'request';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddPrayerSheet(
        initialType: initialType,
        onSave: (request) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(
              db.copyWith(prayerRequests: [...db.prayerRequests, request]));
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

    final all = provider.db.prayerRequests
        .where((r) => r.familyId == family.id)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final unanswered = all.where((r) => !r.answered).toList();
    final answered = all.where((r) => r.answered).toList();

    return Scaffold(
      backgroundColor: _warmCream,
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        backgroundColor: _warmAmber,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Entry',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            backgroundColor: _warmCream,
            title: const Text('🕊️ Prayer Wall'),
            floating: true,
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: _warmAmber,
              labelColor: _warmAmber,
              unselectedLabelColor: AppTheme.stone500,
              tabs: const [
                Tab(text: '🙏 Gratitude'),
                Tab(text: '🙏 Requests'),
                Tab(text: '✅ Answered'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            // Gratitude tab — re-uses unanswered pool (no type field in model)
            _PrayerList(
              requests: unanswered,
              userId: user.id,
              accentColor: _warmPink,
              onPrayed: (r) => _togglePrayed(r, user.id),
              onAnswered: null,
              onDelete: _deleteRequest,
              emptyTitle: 'No gratitude entries yet',
              emptySubtitle: 'Share what you\'re thankful for today',
            ),
            // Requests tab
            _PrayerList(
              requests: unanswered,
              userId: user.id,
              accentColor: _warmIndigo,
              onPrayed: (r) => _togglePrayed(r, user.id),
              onAnswered: _markAnswered,
              onDelete: _deleteRequest,
              emptyTitle: 'No prayer requests yet',
              emptySubtitle: 'Share what\'s on your heart',
            ),
            // Answered tab
            _PrayerList(
              requests: answered,
              userId: user.id,
              accentColor: _warmGreen,
              onPrayed: (r) => _togglePrayed(r, user.id),
              onAnswered: null,
              onDelete: _deleteRequest,
              emptyTitle: 'No answered prayers yet',
              emptySubtitle: 'Long-press a request to mark it answered',
            ),
          ],
        ),
      ),
    );
  }
}

// ─── List ─────────────────────────────────────────────────────────────────────

class _PrayerList extends StatelessWidget {
  final List<PrayerRequest> requests;
  final String userId;
  final Color accentColor;
  final Future<void> Function(PrayerRequest) onPrayed;
  final Future<void> Function(PrayerRequest)? onAnswered;
  final Future<void> Function(String) onDelete;
  final String emptyTitle;
  final String emptySubtitle;

  const _PrayerList({
    required this.requests,
    required this.userId,
    required this.accentColor,
    required this.onPrayed,
    required this.onAnswered,
    required this.onDelete,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return EmptyState(
        emoji: '🙏',
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) => _PrayerCard(
        request: requests[i],
        userId: userId,
        accentColor: accentColor,
        onPrayed: () => onPrayed(requests[i]),
        onAnswered: onAnswered != null && !requests[i].answered
            ? () => onAnswered!(requests[i])
            : null,
        onDelete: () => onDelete(requests[i].id),
      ),
    );
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class _PrayerCard extends StatelessWidget {
  final PrayerRequest request;
  final String userId;
  final Color accentColor;
  final VoidCallback onPrayed;
  final VoidCallback? onAnswered;
  final VoidCallback onDelete;

  static const _reactionEmojis = ['🙏', '❤️', '✨', '🕊️', '⭐'];

  const _PrayerCard({
    required this.request,
    required this.userId,
    required this.accentColor,
    required this.onPrayed,
    required this.onAnswered,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrayed = request.prayedByIds.contains(userId);
    final isAnswered = request.answered;
    final isOwner = request.userId == userId;

    return GestureDetector(
      onLongPress: onAnswered,
      child: Dismissible(
        key: Key(request.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppTheme.error,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
        ),
        confirmDismiss: (_) async => await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Prayer'),
            content: const Text('Remove this entry?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete',
                      style: TextStyle(color: AppTheme.error))),
            ],
          ),
        ),
        onDismissed: (_) => onDelete(),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isAnswered
                ? _warmGreen.withOpacity(0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: isAnswered
                    ? _warmGreen.withOpacity(0.25)
                    : accentColor.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.07),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(children: [
              Text(isAnswered ? '✅' : '🙏',
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.title,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppTheme.stone900,
                        ),
                      ),
                      Text(
                        DateFormat('MMM d').format(request.createdAt),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: AppTheme.stone400,
                        ),
                      ),
                    ]),
              ),
              if (isAnswered)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _warmGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Answered',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _warmGreen)),
                ),
              if (isOwner) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onDelete,
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: AppTheme.stone300),
                ),
              ],
            ]),
            if (request.body != null && request.body!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                request.body!,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppTheme.stone600,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 14),
            // Reactions row
            Row(children: [
              // Emoji reactions
              ..._reactionEmojis.map((emoji) => GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(
                          content: Text('Reacted with $emoji'),
                          duration: const Duration(seconds: 1),
                        ));
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.stone100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(emoji,
                          style: const TextStyle(fontSize: 13)),
                    ),
                  )),
              const Spacer(),
              // Prayed / 🙏 button
              GestureDetector(
                onTap: onPrayed,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: hasPrayed
                        ? accentColor.withOpacity(0.12)
                        : AppTheme.stone100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color:
                            hasPrayed ? accentColor : Colors.transparent),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('🙏', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 4),
                    Text(
                      '${request.prayedByIds.length}',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            hasPrayed ? accentColor : AppTheme.stone500,
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
            // Mark answered hint (long-press)
            if (!isAnswered && onAnswered != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onAnswered,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _warmGreen.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '✅ Mark as Answered',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _warmGreen,
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─── Add Sheet ────────────────────────────────────────────────────────────────

class _AddPrayerSheet extends StatefulWidget {
  final String initialType;
  final Future<void> Function(PrayerRequest) onSave;

  const _AddPrayerSheet({
    required this.initialType,
    required this.onSave,
  });

  @override
  State<_AddPrayerSheet> createState() => _AddPrayerSheetState();
}

class _AddPrayerSheetState extends State<_AddPrayerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _isSaving = false;
  late String _type;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final entry = PrayerRequest(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      userId: provider.activeUser!.id,
      title: _titleCtrl.text.trim(),
      body: _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
      answered: false,
      prayedByIds: [],
      createdAt: DateTime.now(),
    );
    await widget.onSave(entry);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _type == 'gratitude' ? _warmPink : _warmIndigo;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetHandle(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Share with Family',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: AppTheme.stone900,
                  )),
              TextButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Post',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 14),
            // Type chips
            Row(children: [
              Expanded(
                child: _TypeChip(
                  label: '❤️ Gratitude',
                  selected: _type == 'gratitude',
                  color: _warmPink,
                  onTap: () => setState(() => _type = 'gratitude'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TypeChip(
                  label: '🙏 Prayer Request',
                  selected: _type == 'request',
                  color: _warmIndigo,
                  onTap: () => setState(() => _type = 'request'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextFormField(
              controller: _titleCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _type == 'gratitude'
                    ? 'What are you grateful for? *'
                    : 'Prayer request topic *',
                hintText: _type == 'gratitude'
                    ? 'e.g. Family health, A blessing...'
                    : 'e.g. Healing, Guidance, Provision...',
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: typeColor, width: 2),
                ),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Please enter a title' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bodyCtrl,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                hintText: 'Share more of your heart...',
                alignLabelWithHint: true,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Type Chip ────────────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : AppTheme.stone50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : AppTheme.stone200,
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? color : AppTheme.stone500,
          ),
        ),
      ),
    );
  }
}

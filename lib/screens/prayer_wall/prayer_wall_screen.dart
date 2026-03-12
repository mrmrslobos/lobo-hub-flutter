// lib/screens/prayer_wall/prayer_wall_screen.dart
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
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

String _timeAgo(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays >= 365) {
    final years = (diff.inDays / 365).floor();
    return years == 1 ? '1 year ago' : '$years years ago';
  } else if (diff.inDays >= 30) {
    final months = (diff.inDays / 30).floor();
    return months == 1 ? '1 month ago' : '$months months ago';
  } else if (diff.inDays >= 7) {
    final weeks = (diff.inDays / 7).floor();
    return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
  } else if (diff.inDays >= 1) {
    return diff.inDays == 1 ? '1 day ago' : '${diff.inDays} days ago';
  } else if (diff.inHours >= 1) {
    return diff.inHours == 1 ? '1 hour ago' : '${diff.inHours} hours ago';
  } else if (diff.inMinutes >= 1) {
    return diff.inMinutes == 1 ? '1 minute ago' : '${diff.inMinutes} minutes ago';
  } else {
    return 'just now';
  }
}

class PrayerWallScreen extends StatefulWidget {
  const PrayerWallScreen({super.key});

  @override
  State<PrayerWallScreen> createState() => _PrayerWallScreenState();
}

class _PrayerWallScreenState extends State<PrayerWallScreen> {
  String _selectedFilter = 'all';
  String _searchQuery = '';

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
        _selectedFilter == 'gratitude' ? 'gratitude' : _selectedFilter == 'request' ? 'request' : 'gratitude';
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

    final gratitudes = all.where((r) => r.type == PrayerWallType.GRATITUDE).toList();
    final requests = all.where((r) => r.type == PrayerWallType.REQUEST && !r.answered).toList();
    final answered = all.where((r) => r.answered).toList();

    // Build user lookup map
    final userMap = <String, User>{};
    for (final u in provider.db.users) {
      userMap[u.id] = u;
    }

    // Filter posts based on selected filter
    List<PrayerRequest> filtered;
    switch (_selectedFilter) {
      case 'gratitude':
        filtered = gratitudes;
        break;
      case 'request':
        filtered = requests;
        break;
      case 'answered':
        filtered = answered;
        break;
      default:
        filtered = all;
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((r) => r.text.toLowerCase().contains(q)).toList();
    }

    return Scaffold(
      backgroundColor: _warmCream,
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
        actions: const [],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          // Page header
          const PageHeader(
            title: 'Prayer Wall',
            subtitle: 'Share gratitude, lift up prayers, and celebrate answered ones.',
          ),

          const SizedBox(height: 8),

          // + New Post button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showAddSheet,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('New Post',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _warmIndigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Stats row
          Row(
            children: [
              _StatBox(
                count: gratitudes.length,
                label: 'GRATITUDES',
                backgroundColor: const Color(0xFFFEF3C7),
                textColor: _warmAmber,
              ),
              const SizedBox(width: 10),
              _StatBox(
                count: requests.length,
                label: 'REQUESTS',
                backgroundColor: const Color(0xFFEEF2FF),
                textColor: _warmIndigo,
              ),
              const SizedBox(width: 10),
              _StatBox(
                count: answered.length,
                label: 'ANSWERED',
                backgroundColor: const Color(0xFFDCFCE7),
                textColor: _warmGreen,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  count: null,
                  selected: _selectedFilter == 'all',
                  onTap: () => setState(() => _selectedFilter = 'all'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Gratitude',
                  count: gratitudes.length,
                  selected: _selectedFilter == 'gratitude',
                  onTap: () => setState(() => _selectedFilter = 'gratitude'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Requests',
                  count: requests.length,
                  selected: _selectedFilter == 'request',
                  onTap: () => setState(() => _selectedFilter = 'request'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Answered',
                  count: answered.length,
                  selected: _selectedFilter == 'answered',
                  onTap: () => setState(() => _selectedFilter = 'answered'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Search
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search prayers...',
              hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.stone400),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _searchQuery = ''))
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
            ),
          ),
          const SizedBox(height: 16),

          // Posts
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: EmptyState(
                emoji: '🙏',
                title: _selectedFilter == 'gratitude'
                    ? 'No gratitude entries yet'
                    : _selectedFilter == 'request'
                        ? 'No prayer requests yet'
                        : _selectedFilter == 'answered'
                            ? 'No answered prayers yet'
                            : 'No posts yet',
                subtitle: 'Tap "+ New Post" to share with your family',
              ),
            )
          else
            ...filtered.map((request) {
              final author = userMap[request.creatorId];
              final isGratitude = request.type == PrayerWallType.GRATITUDE;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PrayerCard(
                  request: request,
                  userId: user.id,
                  accentColor: isGratitude ? _warmAmber : request.answered ? _warmGreen : _warmIndigo,
                  onPrayed: () => _togglePrayed(request, user.id),
                  onAnswered: !request.answered && request.type == PrayerWallType.REQUEST
                      ? () => _markAnswered(request)
                      : null,
                  onDelete: () => _deleteRequest(request.id),
                  authorName: author?.name ?? 'Family Member',
                  isGratitude: isGratitude,
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─── Stat Box ─────────────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  final int count;
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _StatBox({
    required this.count,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: textColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 0.8,
                color: textColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Filter Chip ──────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _warmIndigo : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _warmIndigo : AppTheme.stone200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: selected ? Colors.white : AppTheme.stone600,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withValues(alpha: 0.25) : AppTheme.stone100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: selected ? Colors.white : AppTheme.stone500,
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

// ─── Card ─────────────────────────────────────────────────────────────────────

class _PrayerCard extends StatelessWidget {
  final PrayerRequest request;
  final String userId;
  final Color accentColor;
  final VoidCallback onPrayed;
  final VoidCallback? onAnswered;
  final VoidCallback onDelete;
  final String authorName;
  final bool isGratitude;

  static const _reactionEmojis = ['🙏', '❤️', '✨', '🕊️', '⭐'];

  const _PrayerCard({
    required this.request,
    required this.userId,
    required this.accentColor,
    required this.onPrayed,
    required this.onAnswered,
    required this.onDelete,
    required this.authorName,
    required this.isGratitude,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrayed = request.prayedByIds.contains(userId);
    final isAnswered = request.answered;
    final isOwner = request.userId == userId;

    // Emoji avatar based on first letter of name
    final avatarEmoji = isGratitude ? '🌟' : '🙏';

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
            color: isGratitude
                ? const Color(0xFFFFFBEB)
                : isAnswered
                    ? _warmGreen.withValues(alpha: 0.05)
                    : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: isGratitude
                    ? const Color(0xFFFDE68A)
                    : isAnswered
                        ? _warmGreen.withValues(alpha: 0.25)
                        : accentColor.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.07),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header row: avatar + name + badge + timestamp + close button
            Row(children: [
              // Emoji avatar
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isGratitude
                      ? const Color(0xFFFEF3C7)
                      : isAnswered
                          ? _warmGreen.withValues(alpha: 0.1)
                          : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(avatarEmoji, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              authorName,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppTheme.stone900,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isGratitude
                                  ? const Color(0xFFFEF3C7)
                                  : isAnswered
                                      ? _warmGreen.withValues(alpha: 0.1)
                                      : const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isAnswered ? 'ANSWERED' : isGratitude ? 'GRATITUDE' : 'REQUEST',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 9,
                                letterSpacing: 0.5,
                                color: isGratitude
                                    ? _warmAmber
                                    : isAnswered
                                        ? _warmGreen
                                        : _warmIndigo,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _timeAgo(request.createdAt),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: AppTheme.stone400,
                        ),
                      ),
                    ]),
              ),
              if (isOwner)
                GestureDetector(
                  onTap: onDelete,
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: AppTheme.stone300),
                ),
            ]),
            // Title
            const SizedBox(height: 12),
            Text(
              request.title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppTheme.stone900,
              ),
            ),
            if (request.body != null && request.body!.isNotEmpty) ...[
              const SizedBox(height: 4),
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
                        ? accentColor.withValues(alpha: 0.12)
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
                    color: _warmGreen.withValues(alpha: 0.08),
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
          color: selected ? color.withValues(alpha: 0.1) : AppTheme.stone50,
          borderRadius: BorderRadius.circular(16),
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

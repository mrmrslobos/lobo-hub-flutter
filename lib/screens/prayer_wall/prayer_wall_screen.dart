// lib/screens/prayer_wall/prayer_wall_screen.dart
// Prayer wall screen for Huddle
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../config/cloud_sync_scope.dart';
import '../../config/module_config.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/family_activity_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/huddle_module_scaffold.dart';
import '../../widgets/module_ui_kit.dart';
import '../../utils/debounce.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

Future<void> _reportContent(
  BuildContext context,
  String contentType,
  String contentId,
) async {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Report Content'),
      content: Text('Report this $contentType? The family admin will be notified.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            final provider = context.read<AppProvider>();
            final familyId = provider.activeFamily?.id;
            final actorUserId = provider.activeUser?.id;
            if (familyId != null && actorUserId != null) {
              final nextDb = FamilyActivityService.append(
                provider.db,
                familyId: familyId,
                actorUserId: actorUserId,
                action: 'content_reported',
                detail: '$contentType:$contentId',
              );
              await provider.saveAndSync(
                nextDb,
                pushTableScope: {CloudSyncScope.familyActivityLogs},
              );
            }
            if (ctx.mounted) Navigator.pop(ctx);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Report saved for family admin review'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ));
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Report'),
        ),
      ],
    ),
  );
}

// ─── Constants ───────────────────────────────────────────────────────────────

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

// ─── Main Screen ─────────────────────────────────────────────────────────────

class PrayerWallScreen extends StatefulWidget {
  const PrayerWallScreen({super.key});

  @override
  State<PrayerWallScreen> createState() => _PrayerWallScreenState();
}

class _PrayerWallScreenState extends State<PrayerWallScreen> {
  String _selectedFilter = 'all';
  final _searchCtrl = TextEditingController();
  final _searchDebounce = Debouncer();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<AppProvider>()
          .scheduleModuleEnterCloudPull({CloudSyncScope.prayerWall});
    });
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _togglePrayed(PrayerRequest request, String userId) async {
    HapticFeedback.lightImpact();
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final newPrayed = request.prayedByIds.contains(userId)
        ? request.prayedByIds.where((id) => id != userId).toList()
        : [...request.prayedByIds, userId];
    await provider.saveAndSync(
      db.copyWith(
        prayerRequests: db.prayerRequests
            .map((r) => r.id == request.id ? r.copyWith(prayedByIds: newPrayed) : r)
            .toList(),
      ),
      pushTableScope: {CloudSyncScope.prayerWall},
    );
  }

  Future<void> _toggleReaction(PrayerRequest request, String emoji, String userId) async {
    HapticFeedback.selectionClick();
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final hasReacted = request.reactions.any((r) => r.userId == userId && r.emoji == emoji);
    final newReactions = hasReacted
        ? request.reactions.where((r) => !(r.userId == userId && r.emoji == emoji)).toList()
        : [...request.reactions, Reaction(userId: userId, emoji: emoji)];
    await provider.saveAndSync(
      db.copyWith(
        prayerRequests: db.prayerRequests
            .map((r) => r.id == request.id ? r.copyWith(reactions: newReactions) : r)
            .toList(),
      ),
      pushTableScope: {CloudSyncScope.prayerWall},
    );
  }

  Future<void> _markAnswered(PrayerRequest request) async {
    HapticFeedback.mediumImpact();
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(
      db.copyWith(
        prayerRequests: db.prayerRequests
            .map((r) => r.id == request.id ? r.copyWith(answeredAt: DateTime.now()) : r)
            .toList(),
      ),
      pushTableScope: {CloudSyncScope.prayerWall},
    );
    if (mounted) {
      _showSnack(context, 'Praise God! Marked as answered');
    }
  }

  Future<void> _deleteRequest(String id) async {
    final provider = context.read<AppProvider>();
    final request = provider.db.prayerRequests.where((r) => r.id == id).firstOrNull;
    if (request == null) return;
    if (request.userId != provider.activeUser?.id) {
      if (mounted) _showSnack(context, 'You can only delete your own post.');
      return;
    }
    final db = provider.db;
    try {
      await provider.saveAndSync(
        db.copyWith(prayerRequests: db.prayerRequests.where((r) => r.id != id).toList()),
        pushTableScope: {CloudSyncScope.prayerWall},
      );
    } catch (_) {
      if (mounted) _showSnack(context, 'Could not delete prayer.');
      return;
    }
    if (mounted) _showSnack(context, 'Prayer removed');
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
            db.copyWith(prayerRequests: [...db.prayerRequests, request]),
            pushTableScope: {CloudSyncScope.prayerWall},
          );
          try {
            final isGratitude = request.type == PrayerWallType.GRATITUDE;
            NotificationService.notifyFamilyActivityWithDb(
              provider.db,
              title: isGratitude ? 'New gratitude shared 🙏' : 'New prayer request 🙏',
              body: '${provider.activeUser?.name ?? 'Someone'} ${isGratitude ? 'shared a gratitude' : 'added a prayer request'} in ${AppConfig.appName}.',
              path: '/prayer-wall',
              familyId: provider.activeFamily?.id,
              excludeUserId: provider.activeUser?.id,
            );
          } catch (_) {}
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
      return const ModuleFamilyLoadingScaffold();
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

    return HuddleModuleScaffold(
      modulePath: '/prayer-wall',
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const MainAppBar(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── Page Header ──
          PageHeader(
            title: screenTitleForModulePath('/prayer-wall'),
            subtitle: 'Share gratitude, lift up prayers, and celebrate answered ones.',
            actions: [
              ActionChipButton(
                icon: Icons.add_rounded,
                label: 'New Post',
                onTap: _showAddSheet,
                isPrimary: true,
              ),
            ],
          ),

          // ── Stat cards ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(children: [
              _MiniStat(
                icon: Icons.favorite_rounded,
                iconColor: _warmAmber,
                value: '${gratitudes.length}',
                label: 'Gratitudes',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                icon: Icons.front_hand_rounded,
                iconColor: _warmIndigo,
                value: '${requests.length}',
                label: 'Requests',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                icon: Icons.check_circle_rounded,
                iconColor: _warmGreen,
                value: '${answered.length}',
                label: 'Answered',
              ),
            ]),
          ),

          // ── Filter chips ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SingleChildScrollView(
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
          ),

          const SizedBox(height: 12),

          // ── Search ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                _searchDebounce.run(() {
                  if (!mounted) return;
                  setState(() => _searchQuery = v);
                });
              },
              decoration: InputDecoration(
                hintText: 'Search prayers...',
                hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.stone400),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchDebounce.cancel();
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Posts ──
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: CatalogModuleEmptyState(
                modulePath: '/prayer-wall',
                title: _searchQuery.isNotEmpty
                    ? 'No matching posts'
                    : (_selectedFilter == 'gratitude'
                        ? 'No gratitude entries yet'
                        : _selectedFilter == 'request'
                            ? 'No prayer requests yet'
                            : _selectedFilter == 'answered'
                                ? 'No answered prayers yet'
                                : 'No posts yet'),
                subtitle: _searchQuery.isNotEmpty
                    ? 'Try a different search term'
                    : 'Tap "New Post" to share with your family',
                actionLabel: _searchQuery.isNotEmpty ? null : 'New post',
                onAction: _searchQuery.isNotEmpty ? null : _showAddSheet,
              ),
            )
          else
            ...filtered.map((request) {
              final author = userMap[request.creatorId];
              final isGratitude = request.type == PrayerWallType.GRATITUDE;
              final isOwner = request.userId == user.id;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Dismissible(
                  key: ValueKey(request.id),
                  direction: isOwner
                      ? DismissDirection.endToStart
                      : DismissDirection.none,
                  confirmDismiss: (_) async {
                    if (!isOwner) return false;
                    return await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Prayer'),
                        content: const Text('Remove this entry?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) => _deleteRequest(request.id),
                  background: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(Icons.delete, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  child: _PrayerCard(
                    request: request,
                    userId: user.id,
                    accentColor: isGratitude ? _warmAmber : request.answered ? _warmGreen : _warmIndigo,
                    onPrayed: () => _togglePrayed(request, user.id),
                    onAnswered: !request.answered && request.type == PrayerWallType.REQUEST
                        ? () => _markAnswered(request)
                        : null,
                    onReaction: (emoji) => _toggleReaction(request, emoji, user.id),
                    onDelete: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Prayer'),
                          content: const Text('Remove this entry?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
                          ],
                        ),
                      );
                      if (confirmed == true) _deleteRequest(request.id);
                    },
                    authorName: author?.name ?? 'Family Member',
                    isGratitude: isGratitude,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─── Prayer Card ─────────────────────────────────────────────────────────────

class _PrayerCard extends StatelessWidget {
  final PrayerRequest request;
  final String userId;
  final Color accentColor;
  final VoidCallback onPrayed;
  final VoidCallback? onAnswered;
  final void Function(String emoji) onReaction;
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
    required this.onReaction,
    required this.onDelete,
    required this.authorName,
    required this.isGratitude,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrayed = request.prayedByIds.contains(userId);
    final isAnswered = request.answered;
    final isOwner = request.userId == userId;

    // Emoji avatar based on type
    final avatarEmoji = isGratitude ? '🌟' : '🙏';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isGratitude
            ? const Color(0xFFFFFBEB)
            : isAnswered
                ? _warmGreen.withValues(alpha: 0.05)
                : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isGratitude
                ? const Color(0xFFFDE68A)
                : isAnswered
                    ? _warmGreen.withValues(alpha: 0.25)
                    : AppTheme.stone100),
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
          GestureDetector(
            onTap: () => _reportContent(context, 'prayer entry', request.id),
            child: const Icon(Icons.flag_outlined,
                size: 16, color: AppTheme.stone300),
          ),
          const SizedBox(width: 8),
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
          ..._reactionEmojis.map((emoji) {
            final count = request.reactions.where((r) => r.emoji == emoji).length;
            final hasReacted = request.reactions.any((r) => r.userId == userId && r.emoji == emoji);
            return GestureDetector(
                onTap: () => onReaction(emoji),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasReacted
                        ? accentColor.withValues(alpha: 0.12)
                        : AppTheme.stone100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: hasReacted ? accentColor : Colors.transparent),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(emoji, style: const TextStyle(fontSize: 13)),
                    if (count > 0) ...[
                      const SizedBox(width: 3),
                      Text('$count', style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: hasReacted ? accentColor : AppTheme.stone500,
                      )),
                    ],
                  ]),
                ),
              );
          }),
          const Spacer(),
          // Prayed button
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
        // Mark answered button
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
                'Mark as Answered',
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
    );
  }
}

// ─── Add Prayer Sheet ────────────────────────────────────────────────────────

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
      type: _type == 'gratitude' ? PrayerWallType.GRATITUDE : PrayerWallType.REQUEST,
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
          child: SingleChildScrollView(
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

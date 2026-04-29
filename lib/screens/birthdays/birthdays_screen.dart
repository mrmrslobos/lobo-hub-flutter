// lib/screens/birthdays/birthdays_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../config/cloud_sync_scope.dart';
import '../../config/module_config.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/huddle_module_scaffold.dart';
import '../../widgets/module_ui_kit.dart';
import '../../utils/debounce.dart';

// ─── Type config ─────────────────────────────────────────────────────────────

const _typeConfig = <String, ({String label, String emoji, SpecialDateType enumVal})>{
  'birthday':    (label: 'Birthday',    emoji: '🎂', enumVal: SpecialDateType.BIRTHDAY),
  'anniversary': (label: 'Anniversary', emoji: '💍', enumVal: SpecialDateType.ANNIVERSARY),
  'memorial':    (label: 'Memorial',    emoji: '🕊️', enumVal: SpecialDateType.MEMORIAL),
  'other':       (label: 'Other',       emoji: '🎉', enumVal: SpecialDateType.OTHER),
};

String _typeKey(SpecialDateType t) {
  switch (t) {
    case SpecialDateType.BIRTHDAY: return 'birthday';
    case SpecialDateType.ANNIVERSARY: return 'anniversary';
    case SpecialDateType.MEMORIAL: return 'memorial';
    case SpecialDateType.OTHER: return 'other';
  }
}

String _typeEmoji(SpecialDateType t) => _typeConfig[_typeKey(t)]?.emoji ?? '⭐';
String _typeLabel(SpecialDateType t) => _typeConfig[_typeKey(t)]?.label ?? 'Other';

// ─── Main Screen ─────────────────────────────────────────────────────────────

class BirthdaysScreen extends StatefulWidget {
  const BirthdaysScreen({super.key});

  @override
  State<BirthdaysScreen> createState() => _BirthdaysScreenState();
}

class _BirthdaysScreenState extends State<BirthdaysScreen> {
  final _searchCtrl = TextEditingController();
  final _searchDebounce = Debouncer();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final t = _searchCtrl.text;
      _searchDebounce.run(() {
        if (mounted) setState(() => _searchQuery = t);
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce.dispose();
    super.dispose();
  }

  bool _occasionMatches(Occasion o, String q) {
    if (q.isEmpty) return true;
    if (o.title.toLowerCase().contains(q)) return true;
    if (_typeLabel(o.type).toLowerCase().contains(q)) return true;
    if (DateFormat('MMM d').format(o.date).toLowerCase().contains(q)) return true;
    if (DateFormat('MMMM').format(o.date).toLowerCase().contains(q)) return true;
    return false;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  int _daysUntil(Occasion occasion) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime next = DateTime(now.year, occasion.date.month, occasion.date.day);
    if (next.isBefore(today)) {
      next = DateTime(now.year + 1, occasion.date.month, occasion.date.day);
    }
    return next.difference(today).inDays;
  }

  int? _age(Occasion occasion) {
    // Age only makes sense for occasions with a known origin year (non-recurring)
    // In the model: recurring means year == null
    if (occasion.recurring) return null;
    final now = DateTime.now();
    final originYear = occasion.date.year;
    if (originYear < 1900 || originYear > now.year) return null;
    int age = now.year - originYear;
    final thisYear = DateTime(now.year, occasion.date.month, occasion.date.day);
    if (thisYear.isAfter(now)) age--;
    return age > 0 ? age : null;
  }

  void _scheduleReminders(Occasion occasion) {
    final now = DateTime.now();
    final thisYear = DateTime(now.year, occasion.date.month, occasion.date.day);
    final nextOccurrence = thisYear.isBefore(now)
        ? DateTime(now.year + 1, occasion.date.month, occasion.date.day)
        : thisYear;

    final idBase = occasion.id.hashCode.abs() % 100000;

    // Day-of reminder at 9 AM
    final dayOf = DateTime(nextOccurrence.year, nextOccurrence.month, nextOccurrence.day, 9);
    if (dayOf.isAfter(now)) {
      NotificationService.scheduleOnce(
        id: idBase,
        title: '🎉 Today: ${occasion.title}',
        body: 'Don\'t forget — it\'s ${occasion.title} today!',
        when: dayOf,
        payload: '/birthdays',
      );
    }

    // 7 days before at 9 AM
    final weekBefore = dayOf.subtract(const Duration(days: 7));
    if (weekBefore.isAfter(now)) {
      NotificationService.scheduleOnce(
        id: idBase + 1,
        title: '📅 Coming up: ${occasion.title}',
        body: '${occasion.title} is in 1 week!',
        when: weekBefore,
        payload: '/birthdays',
      );
    }
  }

  Color _badgeColor(int days) {
    if (days == 0) return const Color(0xFFEC4899); // pink for today
    if (days <= 7) return AppTheme.success;
    if (days <= 30) return AppTheme.warning;
    return AppTheme.stone400;
  }

  bool _isOwner(AppProvider provider) {
    final userId = provider.activeUser?.id;
    return userId != null && provider.activeFamily?.ownerId == userId;
  }

  bool _canManageOccasion(AppProvider provider, Occasion occasion) {
    final userId = provider.activeUser?.id;
    return userId != null && (occasion.creatorId == userId || _isOwner(provider));
  }

  // ── Data actions ───────────────────────────────────────────────────────────

  Future<void> _deleteOccasion(String id) async {
    final provider = context.read<AppProvider>();
    final occasion = provider.db.occasions.cast<Occasion?>().firstWhere(
      (o) => o?.id == id,
      orElse: () => null,
    );
    if (occasion == null || !_canManageOccasion(provider, occasion)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the creator or family owner can delete this occasion.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Occasion'),
        content: const Text('Remove this occasion?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = provider.db;
    await provider.saveAndSync(
      db.copyWith(occasions: db.occasions.where((o) => o.id != id).toList()),
      pushTableScope: CloudSyncScope.occasionBundle,
    );
  }

  void _showAddSheet({Occasion? editOccasion}) {
    final provider = context.read<AppProvider>();
    if (editOccasion != null && !_canManageOccasion(provider, editOccasion)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the creator or family owner can edit this occasion.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OccasionFormSheet(
        editOccasion: editOccasion,
        onSave: (occasion) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          if (editOccasion != null) {
            await provider.saveAndSync(
              db.copyWith(
                occasions: db.occasions.map((o) => o.id == editOccasion.id ? occasion : o).toList(),
              ),
              pushTableScope: CloudSyncScope.occasionBundle,
            );
          } else {
            await provider.saveAndSync(
              db.copyWith(occasions: [...db.occasions, occasion]),
              pushTableScope: CloudSyncScope.occasionBundle,
            );
            NotificationService.notifyFamilyActivityWithDb(
              provider.db,
              title: 'New occasion',
              body: '${provider.activeUser?.name ?? "Someone"} added ${occasion.title} in ${AppConfig.appName}.',
              path: '/birthdays',
              familyId: provider.activeFamily?.id,
              excludeUserId: provider.activeUser?.id,
            );
          }
          _scheduleReminders(occasion);
        },
      ),
    );
  }

  void _showOccasionActions(Occasion occasion) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _badgeColor(_daysUntil(occasion)).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(_typeEmoji(occasion.type), style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(occasion.title, style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.stone900,
                        )),
                        Text(_typeLabel(occasion.type), style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400,
                        )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _actionTile(Icons.edit_outlined, 'Edit Occasion', AppTheme.stone700, () {
              Navigator.pop(ctx);
              _showAddSheet(editOccasion: occasion);
            }),
            _actionTile(Icons.delete_outline_rounded, 'Delete Occasion', AppTheme.error, () {
              Navigator.pop(ctx);
              _deleteOccasion(occasion.id);
            }),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 12),
          ],
        ),
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(
              fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: color,
            )),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final family = provider.activeFamily;
    if (family == null) return const ModuleFamilyLoadingScaffold();

    final occasions = provider.db.occasions
        .where((o) => o.familyId == family.id)
        .toList();
    occasions.sort((a, b) => _daysUntil(a).compareTo(_daysUntil(b)));

    final q = _searchQuery.trim().toLowerCase();
    final upcoming = occasions
        .where((o) => _daysUntil(o) <= 30 && _occasionMatches(o, q))
        .toList();
    final later = occasions
        .where((o) => _daysUntil(o) > 30 && _occasionMatches(o, q))
        .toList();

    // Next occasion
    final nextOccasion = occasions.isNotEmpty ? occasions.first : null;
    final nextDays = nextOccasion != null ? _daysUntil(nextOccasion) : null;

    return HuddleModuleScaffold(
      modulePath: '/birthdays',
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const MainAppBar(),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Page Header ──
          PageHeader(
            title: screenTitleForModulePath('/birthdays'),
            subtitle: 'Birthdays, anniversaries & special dates.',
            actions: [
              ActionChipButton(
                icon: Icons.add_rounded,
                label: 'Add Occasion',
                onTap: () => _showAddSheet(),
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
                  icon: Icons.celebration_rounded,
                  label: 'Total',
                  value: '${occasions.length}',
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 10),
                _StatCard(
                  icon: Icons.upcoming_rounded,
                  label: 'This Month',
                  value: '${upcoming.length}',
                  color: AppTheme.success,
                ),
                const SizedBox(width: 10),
                _StatCard(
                  icon: Icons.timer_outlined,
                  label: 'Next In',
                  value: nextDays != null ? (nextDays == 0 ? 'Today' : '${nextDays}d') : '—',
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search occasions…',
                hintStyle: const TextStyle(fontFamily: 'Inter', color: AppTheme.stone400),
                prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.stone400),
                suffixIcon: _searchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.stone400),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                filled: true,
                fillColor: AppTheme.stone50,
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
          const SizedBox(height: 12),

          // ── Next Up Banner ──
          if (nextOccasion != null && nextDays != null && nextDays <= 7)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: nextDays == 0
                        ? [const Color(0xFFEC4899), const Color(0xFFF472B6)]
                        : [const Color(0xFF8B7BF7), const Color(0xFFB4A0FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(_typeEmoji(nextOccasion.type), style: const TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nextDays == 0
                                ? "It's today!"
                                : nextDays == 1
                                    ? 'Tomorrow!'
                                    : 'In $nextDays days',
                            style: TextStyle(
                              fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            nextOccasion.title,
                            style: const TextStyle(
                              fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white,
                            ),
                          ),
                          if (_age(nextOccasion) != null)
                            Text(
                              'Turning ${_age(nextOccasion)! + 1}',
                              style: TextStyle(
                                fontFamily: 'Inter', fontSize: 13, color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      DateFormat('MMM d').format(nextOccasion.date),
                      style: TextStyle(
                        fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (nextOccasion != null && nextDays != null && nextDays <= 7)
            const SizedBox(height: 16),

          // ── Content ──
          if (occasions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.stone100),
                ),
                child: CatalogModuleEmptyState(
                  modulePath: '/birthdays',
                  title: 'No occasions yet',
                  subtitle:
                      'Birthdays, anniversaries, and milestones show up on the calendar and stay visible for the whole family.',
                  compact: true,
                  emojiSize: 44,
                  actionLabel: 'Add occasion',
                  onAction: () => _showAddSheet(),
                ),
              ),
            )
          else if (upcoming.isEmpty && later.isEmpty && q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OnboardingCard(
                emoji: '🔎',
                title: 'No matches',
                bullets: const ['Try another name or month', 'Clear search to see all occasions'],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (upcoming.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Row(
                        children: [
                          Text('COMING UP', style: TextStyle(
                            fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
                            color: AppTheme.stone400, letterSpacing: 1.1,
                          )),
                          SizedBox(width: 8),
                        ],
                      ),
                    ),
                    ...upcoming.map((o) => _buildOccasionCard(o)),
                  ],
                  if (later.isNotEmpty) ...[
                    if (upcoming.isNotEmpty) const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text('LATER', style: TextStyle(
                        fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
                        color: AppTheme.stone400, letterSpacing: 1.1,
                      )),
                    ),
                    ...later.map((o) => _buildOccasionCard(o)),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildOccasionCard(Occasion occasion) {
    final days = _daysUntil(occasion);
    final age = _age(occasion);
    final emoji = _typeEmoji(occasion.type);
    final color = _badgeColor(days);
    final isToday = days == 0;

    final provider = context.read<AppProvider>();
    final canManage = _canManageOccasion(provider, occasion);
    return Dismissible(
      key: ValueKey(occasion.id),
      direction: canManage ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppTheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete, color: Colors.white),
            SizedBox(width: 8),
            Text('Delete', style: TextStyle(
              fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (!canManage) return false;
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete this occasion?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete', style: TextStyle(color: AppTheme.error)),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => _deleteOccasion(occasion.id),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          onLongPress: canManage ? () => _showOccasionActions(occasion) : null,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isToday
                  ? const Color(0xFFEC4899).withValues(alpha: 0.3)
                  : days <= 7
                      ? AppTheme.success.withValues(alpha: 0.3)
                      : AppTheme.stone100,
            ),
          ),
          child: Row(children: [
            // Emoji badge
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(occasion.title, style: const TextStyle(
                  fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900,
                )),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.stone50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_typeLabel(occasion.type), style: const TextStyle(
                      fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.stone500,
                    )),
                  ),
                  if (age != null) ...[
                    const SizedBox(width: 8),
                    Text('Turns ${age + 1}', style: const TextStyle(
                      fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500,
                    )),
                  ],
                  if (!occasion.recurring) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.repeat_rounded, size: 12, color: AppTheme.stone300),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMMM d').format(occasion.date),
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                ),
              ],
            )),
            // Days badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  if (isToday)
                    const Text('TODAY', style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w800,
                      color: Color(0xFFEC4899),
                    ))
                  else ...[
                    Text('$days', style: TextStyle(
                      fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: color,
                    )),
                    Text('days', style: TextStyle(
                      fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: color,
                    )),
                  ],
                ],
              ),
            ),
          ]),
        ),
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

// ─── Occasion Form Sheet ─────────────────────────────────────────────────────

class _OccasionFormSheet extends StatefulWidget {
  final Future<void> Function(Occasion) onSave;
  final Occasion? editOccasion;
  const _OccasionFormSheet({required this.onSave, this.editOccasion});

  @override
  State<_OccasionFormSheet> createState() => _OccasionFormSheetState();
}

class _OccasionFormSheetState extends State<_OccasionFormSheet> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _type = 'birthday';
  DateTime _date = DateTime.now();
  bool _recurring = true;
  bool _isSaving = false;
  final _uuid = const Uuid();

  bool get _isEditing => widget.editOccasion != null;

  @override
  void initState() {
    super.initState();
    if (widget.editOccasion != null) {
      final o = widget.editOccasion!;
      _titleCtrl.text = o.title;
      _notesCtrl.text = o.notes ?? '';
      _type = _typeKey(o.type);
      _date = o.date;
      _recurring = o.recurring;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please enter a name or title'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final config = _typeConfig[_type]!;
    final occasion = Occasion(
      id: widget.editOccasion?.id ?? _uuid.v4(),
      familyId: provider.activeFamily!.id,
      creatorId: widget.editOccasion?.creatorId ?? (provider.activeUser!.id),
      title: _titleCtrl.text.trim(),
      type: config.enumVal,
      date: _date,
      recurring: _recurring,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await widget.onSave(occasion);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
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
                  child: Icon(
                    _isEditing ? Icons.edit_outlined : Icons.celebration_outlined,
                    size: 18,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _isEditing ? 'Edit Occasion' : 'New Occasion',
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.stone900),
                ),
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
                // Name
                _sectionLabel('Name'),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleCtrl,
                  autofocus: !_isEditing,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'e.g., Mom\'s Birthday',
                    hintStyle: const TextStyle(color: AppTheme.stone300),
                    filled: true,
                    fillColor: AppTheme.stone50,
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                  ),
                ),
                const SizedBox(height: 20),

                // Type selector
                _sectionLabel('Type'),
                const SizedBox(height: 8),
                Row(
                  children: _typeConfig.entries.map((entry) {
                    final key = entry.key;
                    final config = entry.value;
                    final isSelected = key == _type;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: key != 'other' ? 8 : 0),
                        child: GestureDetector(
                          onTap: () => setState(() => _type = key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.primaryLight : AppTheme.stone50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? AppTheme.primary : AppTheme.stone200,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(config.emoji, style: const TextStyle(fontSize: 20)),
                                const SizedBox(height: 4),
                                Text(config.label, style: TextStyle(
                                  fontFamily: 'Inter', fontSize: 11, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? AppTheme.primary : AppTheme.stone600,
                                )),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Date picker
                _sectionLabel('Date'),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickDate,
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
                        child: const Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          DateFormat('MMMM d, y').format(_date),
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800),
                        ),
                      ),
                      const Icon(Icons.edit_outlined, size: 14, color: AppTheme.stone400),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // Recurring toggle
                GestureDetector(
                  onTap: () => setState(() => _recurring = !_recurring),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _recurring ? AppTheme.primary.withValues(alpha: 0.05) : AppTheme.stone50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _recurring ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.stone200,
                      ),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: (_recurring ? AppTheme.primary : AppTheme.stone400).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.repeat_rounded, size: 16, color: _recurring ? AppTheme.primary : AppTheme.stone400),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Recurring Yearly', style: TextStyle(
                              fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600,
                              color: _recurring ? AppTheme.primary : AppTheme.stone800,
                            )),
                            Text(
                              'Repeat this event each year',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: _recurring ? AppTheme.primary.withValues(alpha: 0.7) : AppTheme.stone400),
                            ),
                          ],
                        ),
                      ),
                      if (_recurring)
                        const Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.primary),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),

                // Notes
                _sectionLabel('Notes (optional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Gift ideas, reminders, etc.',
                    hintStyle: const TextStyle(color: AppTheme.stone300),
                    filled: true,
                    fillColor: AppTheme.stone50,
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                  ),
                ),
                const SizedBox(height: 24),

                // Save button
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
                        : Text(_isEditing ? 'Save Changes' : 'Add Occasion', style: const TextStyle(
                            fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16,
                          )),
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

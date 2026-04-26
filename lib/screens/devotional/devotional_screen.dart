// lib/screens/devotional/devotional_screen.dart
// Devotional & reading-plan screen for Huddle
import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;

import '../../app.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../config/cloud_sync_scope.dart';
import '../../config/module_config.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../services/database_service.dart';
import '../../services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/huddle_module_scaffold.dart';
import '../../widgets/huddle_subpage_scaffold.dart';
import '../../widgets/subscription_modal.dart';
import '../../utils/debounce.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

// Per-user daily devotional (schedule + default privacy). Stored in User.settings.
const _kUserDailyEnabled = 'daily_devotional_enabled';
const _kUserDailyHour = 'daily_devotional_hour';
const _kUserDailyMinute = 'daily_devotional_minute';
const _kUserDailyPrivate = 'daily_devotional_private_default';

bool _userDailyEnabled(User? u, Family? f) {
  if (u?.settings.containsKey(_kUserDailyEnabled) == true) {
    return u!.settings[_kUserDailyEnabled] == true;
  }
  return f?.dailyDevotionalEnabled ?? false;
}

int _userDailyHour(User? u, Family? f) {
  if (u?.settings[_kUserDailyHour] != null) {
    return (u!.settings[_kUserDailyHour] as num).toInt();
  }
  return f?.dailyDevotionalHour ?? 7;
}

int _userDailyMinute(User? u, Family? f) {
  if (u?.settings[_kUserDailyMinute] != null) {
    return (u!.settings[_kUserDailyMinute] as num).toInt();
  }
  return f?.dailyDevotionalMinute ?? 0;
}

bool _userDailyPrivateDefault(User? u) => u?.settings[_kUserDailyPrivate] == true;

int _userDailyNotificationId(String userId) =>
    9910000 + (userId.hashCode.abs() % 900000);

String _devotionalShareText(DevotionalEntry e) {
  final buf = StringBuffer();
  buf.writeln(e.title);
  if (e.scripture != null && e.scripture!.trim().isNotEmpty) {
    buf.writeln();
    buf.writeln(e.scripture);
  }
  if (e.content != null && e.content!.trim().isNotEmpty) {
    buf.writeln();
    buf.writeln(e.content);
  }
  if (e.prayer != null && e.prayer!.trim().isNotEmpty) {
    buf.writeln();
    buf.writeln('Prayer: ${e.prayer}');
  }
  buf.writeln();
  buf.writeln('Shared from ${AppConfig.appName}');
  return buf.toString();
}

bool _canSeeDevotional(DevotionalEntry e, String familyId, String? viewerId) {
  if (e.familyId != familyId) return false;
  if (e.visibility != Visibility.PRIVATE) return true;
  if (viewerId == null || viewerId.isEmpty) return false;
  return e.creatorId == viewerId;
}

/// Pull a reference from stored scripture (em/en/hyphen dash lines, or a ref-only line).
String? _scriptureRefForAvoidList(String? scripture) {
  if (scripture == null || scripture.trim().isEmpty) return null;
  final lines = scripture
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  for (var i = lines.length - 1; i >= 0; i--) {
    final line = lines[i];
    final dash = RegExp(r'^[\u2014\u2013\-]\s*(.+)$');
    final m = dash.firstMatch(line);
    if (m != null) return m.group(1)!.trim();
    if (line.length <= 120 &&
        RegExp(r'\d+\s*:\s*\d+').hasMatch(line) &&
        RegExp(r'[A-Za-z\u00C0-\u024F]').hasMatch(line)) {
      return line;
    }
  }
  final em = scripture.lastIndexOf('\u2014');
  if (em >= 0) return scripture.substring(em + 1).trim();
  final en = scripture.lastIndexOf('\u2013');
  if (en >= 0) return scripture.substring(en + 1).trim();
  return null;
}

/// Extract the reference portion for UI badges (short label when possible).
String _extractRef(String scripture) =>
    _scriptureRefForAvoidList(scripture) ?? scripture.trim();

const _kScriptureBucketsDevotional = <String>[
  'Old Testament narrative or Torah (not used in your avoid-list)',
  'Wisdom literature — Job, Psalms, Proverbs, or Ecclesiastes',
  'Major or minor prophets',
  'The Gospels — life or teaching of Jesus',
  'Acts and the early church',
  'Pauline epistles (Romans through Philemon)',
  'Hebrews, general epistles, or Revelation',
];

String _dailyScriptureBucket(String familyId, DateTime now) {
  final dayKey =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  var h = 0;
  for (final cu in '$familyId$dayKey'.codeUnits) {
    h = (h * 31 + cu) & 0x7fffffff;
  }
  return _kScriptureBucketsDevotional[h % _kScriptureBucketsDevotional.length];
}

/// Recent passages, titles, daily bucket, and a unique nonce so AI output varies run-to-run.
String _devotionalVarietyBlock(AppDB db, String familyId) {
  final sorted = db.devotionals
      .where((e) => e.familyId == familyId)
      .toList()
    ..sort((a, b) {
      final c = b.date.compareTo(a.date);
      if (c != 0) return c;
      return b.updatedAt.compareTo(a.updatedAt);
    });

  final refs = <String>[];
  final titles = <String>[];
  final seenR = <String>{};
  final seenT = <String>{};

  for (final e in sorted) {
    if (refs.length < 16) {
      final r = _scriptureRefForAvoidList(e.scripture);
      if (r != null && r.isNotEmpty && seenR.add(r)) refs.add(r);
    }
    if (titles.length < 10) {
      final t = e.title.trim();
      if (t.isNotEmpty && t != 'Daily Devotional' && seenT.add(t)) titles.add(t);
    }
    if (refs.length >= 16 && titles.length >= 10) break;
  }

  final bucket = _dailyScriptureBucket(familyId, DateTime.now());
  final nonce = const Uuid().v4();
  final ts = DateTime.now().toUtc().toIso8601String();

  final buf = StringBuffer()
    ..write("\n\nToday's Scripture focus (choose ONE tight passage within this region): $bucket.")
    ..write(
      '\nAvoid overused default choices (e.g. John 3:16, Psalm 23, Philippians 4:6-7, Jeremiah 29:11) unless they truly fit and are not excluded below.',
    );
  if (refs.isNotEmpty) {
    buf
      ..write('\nIMPORTANT: Do NOT use these recently used passages (different book/chapter): ')
      ..write(refs.join('; '))
      ..write('.');
  }
  if (titles.isNotEmpty) {
    buf
      ..write('\nDo NOT reuse or lightly rephrase these recent titles: ')
      ..write(titles.join('; '))
      ..write('.');
  }
  buf
    ..write('\nVary tone, metaphors, and structure; avoid boilerplate openings.')
    ..write('\nUnique generation id (do not echo): $nonce at $ts.');
  return buf.toString();
}

/// Per-user prayer lives in [DevotionalThought] with kind [DevotionalNoteKind.prayer]; legacy [DevotionalEntry.userPrayer] is still honored until cleared.
bool _entryHasPersonalPrayer(
  DevotionalEntry e,
  String? uid,
  List<DevotionalThought> thoughts,
) {
  if (uid != null) {
    final row = thoughts.firstWhereOrNull(
      (t) =>
          t.devotionalId == e.id &&
          t.userId == uid &&
          t.kind == DevotionalNoteKind.prayer,
    );
    if (row != null && row.body.trim().isNotEmpty) return true;
  }
  return e.userPrayer != null && e.userPrayer!.trim().isNotEmpty;
}

String? _myPrayerBody(
  DevotionalEntry e,
  String? uid,
  List<DevotionalThought> thoughts,
) {
  if (uid != null) {
    final row = thoughts.firstWhereOrNull(
      (t) =>
          t.devotionalId == e.id &&
          t.userId == uid &&
          t.kind == DevotionalNoteKind.prayer,
    );
    if (row != null && row.body.trim().isNotEmpty) return row.body;
  }
  return e.userPrayer;
}

// ─── Main Screen ─────────────────────────────────────────────────────────────

class DevotionalScreen extends StatefulWidget {
  /// Opens this entry after sync (e.g. daily devotional notification).
  final String? initialDevotionalId;

  const DevotionalScreen({super.key, this.initialDevotionalId});

  @override
  State<DevotionalScreen> createState() => _DevotionalScreenState();
}

class _DevotionalScreenState extends State<DevotionalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DevotionalEntry? _selectedEntry;
  ReadingPlan? _selectedPlan;
  bool _dismissedAutoOpen = false;
  bool _deepLinkHandled = false;
  Set<String> _localDismissedDates = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadDismissedDates();
  }

  Future<void> _loadDismissedDates() async {
    final dates = await _getDismissedDates();
    if (mounted) setState(() => _localDismissedDates = dates);
  }

  @override
  void didUpdateWidget(DevotionalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDevotionalId != oldWidget.initialDevotionalId) {
      _deepLinkHandled = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = widget.initialDevotionalId;
    if (id != null && id.isNotEmpty && !_deepLinkHandled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDevotionalFromNotification(id));
    }
  }

  Future<void> _openDevotionalFromNotification(String id) async {
    if (!mounted || _deepLinkHandled) return;
    final provider = context.read<AppProvider>();
    DevotionalEntry? match(Iterable<DevotionalEntry> list) {
      for (final e in list) {
        if (e.id == id) return e;
      }
      return null;
    }

    var e = match(provider.db.devotionalEntries);
    if (e == null) {
      await provider.refreshFromCloud();
      if (!mounted) return;
      e = match(context.read<AppProvider>().db.devotionalEntries);
    }
    if (!mounted) return;
    if (e != null) {
      setState(() {
        _selectedEntry = e;
        _tabController.index = 0;
        _deepLinkHandled = true;
      });
    } else {
      _deepLinkHandled = true;
      _showSnack(context, 'Still loading today\'s devotional — open Devotional again in a few seconds.');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _deleteEntry(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final entry = db.devotionalEntries.where((e) => e.id == id).firstOrNull;
    final userId = provider.activeUser?.id;
    final isOwner = userId != null && provider.activeFamily?.ownerId == userId;
    if (entry == null || userId == null || !(entry.creatorId == userId || isOwner)) {
      if (mounted) _showSnack(context, 'Only the entry creator or family owner can delete this devotional.');
      return;
    }
    final isDailyAuto = entry.tags.contains('daily-auto'); // FIXED: entry non-null after guard

    if (isDailyAuto) {
      // 1) Locally remember that we dismissed today's auto devotional.
      //    This survives _deletedKeys clearing and blocks any new auto
      //    devotional for the same date from appearing during merge.
      final dateKey = DateFormat('yyyy-MM-dd').format(entry.date);
      await _dismissAutoDate(dateKey);

      // 2) Mark as dismissed in the DB so the edge function sees it
      //    and won't regenerate.
      await provider.saveAndSync(
        db.copyWith(
          devotionalEntries: db.devotionalEntries.map((e) {
            if (e.id == id) {
              final newTags = e.tags
                  .where((t) => t != 'daily-auto')
                  .toList()
                ..add('daily-auto-dismissed');
              return e.copyWith(tags: newTags);
            }
            return e;
          }).toList(),
        ),
        pushTableScope: CloudSyncScope.devotionalBundle,
      );
    } else {
      await provider.saveAndSync(
        db.copyWith(
          devotionalEntries: db.devotionalEntries.where((e) => e.id != id).toList(),
          devotionalThoughts:
              db.devotionalThoughts.where((t) => t.devotionalId != id).toList(),
        ),
        pushTableScope: CloudSyncScope.devotionalBundle,
      );
    }
    if (_selectedEntry?.id == id) setState(() => _selectedEntry = null);
  }

  /// Track dismissed auto-devotional dates in SharedPreferences.
  static const _dismissedKey = 'dismissed_auto_devotional_dates';

  Future<Set<String>> _getDismissedDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_dismissedKey)?.toSet() ?? {};
  }

  Future<void> _dismissAutoDate(String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    final dates = prefs.getStringList(_dismissedKey)?.toSet() ?? {};
    dates.add(dateKey);
    // Only keep last 7 days to prevent unbounded growth
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    dates.removeWhere((d) {
      try { return DateTime.parse(d).isBefore(cutoff); } catch (_) { return true; }
    });
    await prefs.setStringList(_dismissedKey, dates.toList());
    setState(() => _localDismissedDates = dates);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final family = provider.activeFamily;
    if (family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final uid = provider.activeUser?.id;
    final entries = provider.db.devotionalEntries
        .where((e) {
          if (!_canSeeDevotional(e, family.id, uid)) return false;
          if (e.tags.contains('daily-auto-dismissed')) return false;
          // Also hide auto-generated devotionals for locally dismissed dates.
          // This catches new devotionals created by the cron with different IDs.
          if (e.tags.contains('daily-auto') && _localDismissedDates.isNotEmpty) {
            final dateKey = DateFormat('yyyy-MM-dd').format(e.date);
            if (_localDismissedDates.contains(dateKey)) return false;
          }
          return true;
        })
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final plans = provider.db.readingPlans
        .where((p) => p.familyId == family.id)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // If viewing a devotional entry detail
    if (_selectedEntry != null) {
      return BackNavigationScope(
        onBack: () {
          setState(() { _selectedEntry = null; _dismissedAutoOpen = true; });
          return true;
        },
        child: _EntryDetailView(
          entry: _selectedEntry!,
          onBack: () => setState(() { _selectedEntry = null; _dismissedAutoOpen = true; }),
          onDelete: () => _deleteEntry(_selectedEntry!.id),
          onUpsertThought: (thought) async {
            final provider = context.read<AppProvider>();
            final db = provider.db;
            final rest =
                db.devotionalThoughts.where((t) => t.id != thought.id).toList();
            await provider.saveAndSync(
              db.copyWith(devotionalThoughts: [...rest, thought]),
              pushTableScope: CloudSyncScope.devotionalBundle,
            );
          },
          onUpdatePrayer: (prayer) async {
            final provider = context.read<AppProvider>();
            final db = provider.db;
            final uid = provider.activeUser?.id;
            if (uid == null) return;
            final entry = _selectedEntry!;
            final sid = DevotionalThought.stableId(
              entry.id,
              uid,
              DevotionalNoteKind.prayer,
            );
            final trimmed = prayer.trim();
            List<DevotionalThought> nextThoughts;
            if (trimmed.isEmpty) {
              nextThoughts =
                  db.devotionalThoughts.where((t) => t.id != sid).toList();
            } else {
              final rest =
                  db.devotionalThoughts.where((t) => t.id != sid).toList();
              nextThoughts = [
                ...rest,
                DevotionalThought(
                  id: sid,
                  devotionalId: entry.id,
                  familyId: entry.familyId,
                  userId: uid,
                  kind: DevotionalNoteKind.prayer,
                  body: trimmed,
                ),
              ];
            }
            final cleared = entry.copyWith(userPrayer: null);
            await provider.saveAndSync(
              db.copyWith(
                devotionalThoughts: nextThoughts,
                devotionalEntries: db.devotionalEntries
                    .map((e) => e.id == cleared.id ? cleared : e)
                    .toList(),
              ),
              pushTableScope: CloudSyncScope.devotionalBundle,
            );
            setState(() => _selectedEntry = cleared);
          },
          onToggleFavorite: () async {
            final provider = context.read<AppProvider>();
            final db = provider.db;
            final updated = _selectedEntry!.copyWith(isFavorited: !_selectedEntry!.isFavorited);
            await provider.saveAndSync(
              db.copyWith(
                devotionalEntries: db.devotionalEntries
                    .map((e) => e.id == updated.id ? updated : e)
                    .toList(),
              ),
              pushTableScope: {CloudSyncScope.devotionals},
            );
            setState(() => _selectedEntry = updated);
          },
          onShare: () => Share.share(_devotionalShareText(_selectedEntry!)),
          onShareWithFamily: () async {
            final provider = context.read<AppProvider>();
            final db = provider.db;
            final updated = _selectedEntry!.copyWith(visibility: Visibility.FAMILY);
            await provider.saveAndSync(
              db.copyWith(
                devotionalEntries: db.devotionalEntries
                    .map((e) => e.id == updated.id ? updated : e)
                    .toList(),
              ),
              pushTableScope: {CloudSyncScope.devotionals},
            );
            setState(() => _selectedEntry = updated);
            if (context.mounted) {
              _showSnack(context, 'Shared with family');
            }
          },
        ),
      );
    }

    // If viewing a reading plan detail
    if (_selectedPlan != null) {
      return BackNavigationScope(
        onBack: () {
          setState(() => _selectedPlan = null);
          return true;
        },
        child: _ReadingPlanDetailView(
          plan: _selectedPlan!,
          entries: entries,
          thoughts: provider.db.devotionalThoughts,
          activeUserId: provider.activeUser?.id,
          onBack: () => setState(() => _selectedPlan = null),
        ),
      );
    }

    // ── Computed stats ──
    final favCount = entries.where((e) => e.isFavorited).length;

    return HuddleModuleScaffold(
      modulePath: '/devotional',
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const MainAppBar(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page Header ──
            PageHeader(
              title: screenTitleForModulePath('/devotional'),
              subtitle: 'Reflect, pray, and grow as a family.',
            ),

            // ── Stat cards ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(children: [
                _MiniStat(
                  icon: Icons.menu_book_rounded,
                  iconColor: AppTheme.primary,
                  value: '${entries.length}',
                  label: 'Devotionals',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.bookmark_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  value: '$favCount',
                  label: 'Favorites',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.calendar_month_rounded,
                  iconColor: const Color(0xFF8B7BF7),
                  value: '${plans.length}',
                  label: 'Plans',
                ),
              ]),
            ),

            // ── Tab chips ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppTabBar(
                tabs: const ['Devotionals', 'Reading Plans'],
                selectedIndex: _tabController.index,
                onSelected: (i) => _tabController.animateTo(i),
              ),
            ),
            const SizedBox(height: 16),

            // ── AI TOOLS section header ──
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 20, 10),
              child: Text('AI TOOLS', style: TextStyle(
                fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
                color: AppTheme.stone400, letterSpacing: 1.2,
              )),
            ),

            // Tab content
            if (_tabController.index == 0)
              _DevotionalsTab(
                entries: entries,
                familyId: family.id,
                onSelectEntry: (e) => setState(() => _selectedEntry = e),
                onDeleteEntry: (id) => _deleteEntry(id),
                skipAutoOpen: _dismissedAutoOpen,
              )
            else
              _ReadingPlansTab(
                plans: plans,
                entries: entries,
                familyId: family.id,
                onSelectPlan: (p) => setState(() => _selectedPlan = p),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Devotionals Tab ─────────────────────────────────────────────────────────

class _DevotionalsTab extends StatefulWidget {
  final List<DevotionalEntry> entries;
  final String familyId;
  final ValueChanged<DevotionalEntry> onSelectEntry;
  final ValueChanged<String> onDeleteEntry;
  final bool skipAutoOpen;

  const _DevotionalsTab({
    required this.entries,
    required this.familyId,
    required this.onSelectEntry,
    required this.onDeleteEntry,
    this.skipAutoOpen = false,
  });

  @override
  State<_DevotionalsTab> createState() => _DevotionalsTabState();
}

class _DevotionalsTabState extends State<_DevotionalsTab> {
  final _topicCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _searchDebounce = Debouncer();
  late bool _isShared;
  bool _isGenerating = false;
  String _searchQuery = '';
  bool _showFavoritesOnly = false;
  bool _pastReadingsExpanded = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AppProvider>().activeUser;
    _isShared = !_userDailyPrivateDefault(u);
    // Check if we need to auto-generate today's daily devotional
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeGenerateDaily());
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  /// Sync with the cloud to pick up server-generated devotionals
  /// (produced by the daily-devotional edge function even when the app is
  /// closed). If the server hasn't generated one yet (e.g. cron not
  /// configured or timing mismatch), falls back to client-side generation
  /// so the user never sees a perpetual "Awaiting..." state.
  Future<void> _maybeGenerateDaily() async {
    if (!mounted) return;
    final provider = context.read<AppProvider>();
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) return;
    if (!_userDailyEnabled(user, family)) return;

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    DevotionalEntry? findTodaysDevotional() {
      try {
        return provider.db.devotionalEntries.firstWhere((e) =>
          e.familyId == family.id &&
          e.creatorId == user.id &&
          e.tags.contains('daily-auto') &&
          DateTime(e.date.year, e.date.month, e.date.day) == todayDate,
        );
      } catch (_) {
        return null;
      }
    }

    // Already have today's devotional locally — auto-open it
    // (unless user already dismissed it by pressing back)
    final existing = findTodaysDevotional();
    if (existing != null) {
      if (mounted && !widget.skipAutoOpen) widget.onSelectEntry(existing);
      return;
    }

    // Sync with cloud — the server may still generate a family-wide daily;
    // prefer a row created by this user for today.
    try {
      final merged = await DatabaseService.reconcileCloud(
        provider.db,
        family.id,
        getLocalAfterFetch: () => provider.db,
      );
      if (mounted) {
        provider.updateDb(merged);
        final synced = findTodaysDevotional();
        if (synced != null) {
          if (!widget.skipAutoOpen) widget.onSelectEntry(synced);
          return;
        }
      }
    } catch (e) {
      debugPrint('Cloud sync for daily devotional failed: $e');
    }

    // Fallback: if scheduled time has passed and no devotional arrived from
    // the server, generate one client-side so the user isn't stuck on
    // "Awaiting..." forever.
    if (!mounted) return;
    final utcDt = DateTime.utc(2024, 1, 1, _userDailyHour(user, family), _userDailyMinute(user, family));
    final localDt = utcDt.toLocal();
    final scheduledToday = DateTime(today.year, today.month, today.day, localDt.hour, localDt.minute);
    if (today.isBefore(scheduledToday)) return; // not yet time

    await _generateDailyFallback(family.id);
  }

  /// Client-side fallback: generate today's daily devotional via AI when
  /// the server-side cron hasn't produced one.
  Future<void> _generateDailyFallback(String familyId) async {
    if (AiService.isAIBlocked) return;
    setState(() => _isGenerating = true);
    try {
      final provider = context.read<AppProvider>();
      final variety = _devotionalVarietyBlock(provider.db, familyId);
      final prompt = '''Write an adult-oriented daily devotional for today.
Audience: mature adults navigating real life—work stress, relationships, parenting fatigue, grief, temptation, doubt, health, money worries, and ordinary discouragement. Speak with honesty and compassion; do not talk down, use childish language, or rely on simplistic moral tales.

Pick one Bible verse or short passage (within the assigned Scripture region below) and build a focused devotional around it.

Requirements:
- Be direct where it helps: name common adult struggles without being graphic or sensational.
- Anchor hope in God's character and in specific promises from Scripture (quote or paraphrase faithfully).
- Close the main message on an uplifting, faith-filled note—realistic, not trite.
- Aim for roughly 250–400 words in "content" when possible.

Return JSON with these exact fields: title, scripture, scriptureRef, content, reflectionPrompts (array of 3 personal reflection or journaling prompts for an adult), prayer.
For "scripture", write out the FULL verse text (e.g. "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.").
For "scriptureRef", provide only the reference (e.g. "John 3:16").
For "prayer", write a sincere, adult-voiced prayer that names real tension and rests on God's promises.$variety''';

      final raw = await AiService.ask(
        prompt: prompt,
        feature: 'ai_devotional',
        familyId: familyId,
        responseMimeType: 'application/json',
      );

      if (raw != null && mounted) {
        provider.saveAiHistory(module: 'devotional', prompt: 'Auto-generate daily devotional', response: raw);
        final vis = _userDailyPrivateDefault(provider.activeUser)
            ? Visibility.PRIVATE
            : Visibility.FAMILY;
        final data = AiService.tryParseJsonObject(raw);
        if (data != null) {
          final scriptureRef = data['scriptureRef'] as String?;
          final scriptureText = data['scripture'] as String?;
          final scripture = scriptureText != null && scriptureRef != null
              ? '$scriptureText\n\u2014 $scriptureRef'
              : scriptureText ?? scriptureRef;
          final entry = DevotionalEntry(
            id: const Uuid().v4(),
            familyId: familyId,
            creatorId: provider.activeUser?.id ?? '',
            title: data['title'] as String? ?? 'Daily Devotional',
            scripture: scripture,
            content: data['content'] as String?,
            reflectionPrompts: (data['reflectionPrompts'] as List?)?.cast<String>() ?? [],
            prayer: data['prayer'] as String?,
            date: DateTime.now(),
            visibility: vis,
            tags: ['daily-auto'],
          );
          final db = provider.db;
          await provider.saveAndSync(
            db.copyWith(
              devotionalEntries: [...db.devotionalEntries, entry],
            ),
            pushTableScope: {CloudSyncScope.devotionals},
          );
          if (mounted) widget.onSelectEntry(entry);
        } else {
          final entry = DevotionalEntry(
            id: const Uuid().v4(),
            familyId: familyId,
            creatorId: provider.activeUser?.id ?? '',
            title: 'Daily Devotional',
            content: raw,
            date: DateTime.now(),
            visibility: vis,
            tags: ['daily-auto'],
          );
          final db = provider.db;
          await provider.saveAndSync(
            db.copyWith(
              devotionalEntries: [...db.devotionalEntries, entry],
            ),
            pushTableScope: {CloudSyncScope.devotionals},
          );
          if (mounted) widget.onSelectEntry(entry);
        }
      }
    } catch (e) {
      debugPrint('Client-side daily devotional generation failed: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generate() async {
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.devotional)) return;
    setState(() => _isGenerating = true);
    try {
      final topic = _topicCtrl.text.trim().isEmpty ? 'a random Bible verse' : _topicCtrl.text.trim();
      final provider = context.read<AppProvider>();
      final variety = _devotionalVarietyBlock(provider.db, widget.familyId);
      final prompt = '''Write an adult-oriented daily devotional based on: $topic.
Audience: mature adults navigating real life—work stress, relationships, parenting fatigue, grief, temptation, doubt, health, money worries, and ordinary discouragement. Speak with honesty and compassion; do not talk down, use childish language, or rely on simplistic moral tales.

Center the passage in the Scripture region below unless the topic requires a specific text.

Requirements:
- Be direct where it helps: name common adult struggles without being graphic or sensational.
- Anchor hope in God's character and in specific promises from Scripture (quote or paraphrase faithfully).
- Close the main message on an uplifting, faith-filled note—realistic, not trite.
- Aim for roughly 250–400 words in "content" when possible.

Return JSON with these exact fields: title, scripture, scriptureRef, content, reflectionPrompts (array of 3 personal reflection or journaling prompts for an adult), prayer.
For "scripture", write out the FULL verse text (e.g. "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.").
For "scriptureRef", provide only the reference (e.g. "John 3:16").
For "prayer", write a sincere, adult-voiced prayer that names real tension and rests on God's promises.$variety''';

      final raw = await AiService.ask(
        prompt: prompt,
        feature: 'ai_devotional',
        familyId: widget.familyId,
        responseMimeType: 'application/json',
      );

      if (raw != null && mounted) {
        provider.saveAiHistory(module: 'devotional', prompt: 'Generate devotional on: $topic', response: raw);
        final data = AiService.tryParseJsonObject(raw);
        if (data != null) {
          final scriptureRef = data['scriptureRef'] as String?;
          final scriptureText = data['scripture'] as String?;
          final scripture = scriptureText != null && scriptureRef != null
              ? '$scriptureText\n\u2014 $scriptureRef'
              : scriptureText ?? scriptureRef;
          final entry = DevotionalEntry(
            id: const Uuid().v4(),
            familyId: widget.familyId,
            creatorId: provider.activeUser?.id ?? '',
            title: data['title'] as String? ?? 'Daily Devotional',
            scripture: scripture,
            content: data['content'] as String?,
            reflectionPrompts: (data['reflectionPrompts'] as List?)?.cast<String>() ?? [],
            prayer: data['prayer'] as String?,
            date: DateTime.now(),
            visibility: _isShared ? Visibility.FAMILY : Visibility.PRIVATE,
          );
          final db = provider.db;
          await provider.saveAndSync(
            db.copyWith(
              devotionalEntries: [...db.devotionalEntries, entry],
            ),
            pushTableScope: {CloudSyncScope.devotionals},
          );
          if (!mounted) return;
          _topicCtrl.clear();
          widget.onSelectEntry(entry);
        } else {
          // Fallback: treat raw as plain text
          final entry = DevotionalEntry(
            id: const Uuid().v4(),
            familyId: widget.familyId,
            creatorId: provider.activeUser?.id ?? '',
            title: 'Daily Devotional',
            content: raw,
            date: DateTime.now(),
            visibility: _isShared ? Visibility.FAMILY : Visibility.PRIVATE,
          );
          final db = provider.db;
          await provider.saveAndSync(
            db.copyWith(
              devotionalEntries: [...db.devotionalEntries, entry],
            ),
            pushTableScope: {CloudSyncScope.devotionals},
          );
          if (mounted) widget.onSelectEntry(entry);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnack(context, 'Failed to generate: $e');
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── AI Faith Assistant Card ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _AiFeatureCard(
            icon: Icons.auto_awesome,
            gradientColors: const [Color(0xFFF59E0B), Color(0xFFF97316)],
            title: 'AI Faith Assistant',
            hintText: 'e.g. Anxiety, burnout, forgiveness, grief...',
            controller: _topicCtrl,
            loading: _isGenerating,
            buttonLabel: 'Generate Now',
            onAction: _isGenerating ? null : _generate,
            extraContent: Row(
              children: [
                _toggleChip('Shared', _isShared, () => setState(() => _isShared = true)),
                const SizedBox(width: 8),
                _toggleChip('Private', !_isShared, () => setState(() => _isShared = false)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Daily AI Devotional Schedule ──
        _DailyDevotionalCard(
          familyId: widget.familyId,
          onTapToday: (entry) => widget.onSelectEntry(entry),
          onGenerateNow: () => _generateDailyFallback(widget.familyId),
          isGenerating: _isGenerating,
          onUserSettingsChanged: () {
            final u = context.read<AppProvider>().activeUser;
            if (mounted) {
              setState(() => _isShared = !_userDailyPrivateDefault(u));
            }
          },
        ),
        const SizedBox(height: 24),

        // ── Past Readings (collapsible) ──
        // Exclude today's daily-auto devotional — it's the active reading
        // shown via the Daily Devotional card, not a "past" reading.
        () {
          final now = DateTime.now();
          final todayDate = DateTime(now.year, now.month, now.day);
          final pastEntries = widget.entries.where((e) =>
            !(e.tags.contains('daily-auto') &&
              DateTime(e.date.year, e.date.month, e.date.day) == todayDate)
          ).toList();
          if (pastEntries.isEmpty) return const SizedBox.shrink();
          final filtered = pastEntries.where((entry) {
              if (_showFavoritesOnly && !entry.isFavorited) return false;
              if (_searchQuery.isNotEmpty) {
                final q = _searchQuery.toLowerCase();
                if (!entry.title.toLowerCase().contains(q) &&
                    !(entry.scripture?.toLowerCase().contains(q) ?? false) &&
                    !(entry.content?.toLowerCase().contains(q) ?? false) &&
                    !entry.tags.any((t) => t.toLowerCase().contains(q))) {
                  return false;
                }
              }
              return true;
            }).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tappable header to expand/collapse
                GestureDetector(
                  onTap: () => setState(() => _pastReadingsExpanded = !_pastReadingsExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.stone100),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.menu_book_outlined, size: 18, color: AppTheme.stone500),
                          const SizedBox(width: 8),
                          Text(_showFavoritesOnly ? 'Favorites' : 'Past Readings', style: TextStyle(
                            fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.stone900,
                          )),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.stone100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${pastEntries.length}', style: TextStyle(
                              fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.stone500,
                            )),
                          ),
                          const Spacer(),
                          AnimatedRotation(
                            turns: _pastReadingsExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.stone400),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Collapsible content
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      // Search box
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
                            hintText: 'Search devotionals...',
                            hintStyle: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
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
                      const SizedBox(height: 10),
                      // Favorites filter
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => setState(() => _showFavoritesOnly = !_showFavoritesOnly),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _showFavoritesOnly ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.stone100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: _showFavoritesOnly ? AppTheme.primary : AppTheme.stone200),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _showFavoritesOnly ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                                      size: 16, color: _showFavoritesOnly ? AppTheme.primary : AppTheme.stone500,
                                    ),
                                    const SizedBox(width: 4),
                                    Text('Favorites', style: TextStyle(
                                      fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
                                      color: _showFavoritesOnly ? AppTheme.primary : AppTheme.stone600,
                                    )),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text('${filtered.length} result${filtered.length == 1 ? '' : 's'}', style: TextStyle(
                              fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400,
                            )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Filtered entries list
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(child: Text(
                            _showFavoritesOnly ? 'No favorited devotionals yet' : 'No matching devotionals',
                            style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
                          )),
                        )
                      else
                        ...filtered.map((entry) {
                          final provider = context.read<AppProvider>();
                          final userId = provider.activeUser?.id;
                          final isOwner = userId != null && provider.activeFamily?.ownerId == userId;
                          final canManage = userId != null && (entry.creatorId == userId || isOwner);
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                            child: Dismissible(
                              key: Key(entry.id),
                              direction: canManage ? DismissDirection.endToStart : DismissDirection.none,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: AppTheme.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text('Delete', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.error)),
                                    SizedBox(width: 8),
                                    Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                                  ],
                                ),
                              ),
                              confirmDismiss: (_) async {
                                if (!canManage) return false;
                                return await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Devotional'),
                                    content: Text('Delete "${entry.title}"?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
                                    ],
                                  ),
                                );
                              },
                              onDismissed: (_) => widget.onDeleteEntry(entry.id),
                              child: GestureDetector(
                                onTap: () => widget.onSelectEntry(entry),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppTheme.stone100),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (entry.scripture != null)
                                        Text(
                                          'BASED ON ${_extractRef(entry.scripture!).toUpperCase()}',
                                          style: TextStyle(
                                            fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700,
                                            color: AppTheme.stone400, letterSpacing: 0.5,
                                          ),
                                        ),
                                      if (entry.scripture != null) const SizedBox(height: 6),
                                      Text(entry.title, style: TextStyle(
                                        fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.stone900,
                                      ), maxLines: 2, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('MMM d, yyyy').format(entry.date),
                                        style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          if (entry.visibility == Visibility.FAMILY)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              margin: const EdgeInsets.only(right: 6),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primary.withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text('Shared', style: TextStyle(
                                                fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primary,
                                              )),
                                            ),
                                          if (entry.isFavorited)
                                            Icon(Icons.bookmark_rounded, size: 16, color: AppTheme.primary),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                  crossFadeState: _pastReadingsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                ),
              ],
            );
          }(),
      ],
    );
  }

  Widget _toggleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: selected ? 0.5 : 0.2)),
        ),
        child: Text(label, style: TextStyle(
          fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
          color: Colors.white.withValues(alpha: selected ? 1.0 : 0.7),
        )),
      ),
    );
  }
}

// ─── Reading Plans Tab ───────────────────────────────────────────────────────

class _ReadingPlansTab extends StatefulWidget {
  final List<ReadingPlan> plans;
  final List<DevotionalEntry> entries;
  final String familyId;
  final ValueChanged<ReadingPlan> onSelectPlan;

  const _ReadingPlansTab({
    required this.plans,
    required this.entries,
    required this.familyId,
    required this.onSelectPlan,
  });

  @override
  State<_ReadingPlansTab> createState() => _ReadingPlansTabState();
}

class _ReadingPlansTabState extends State<_ReadingPlansTab> {
  final _customTopicCtrl = TextEditingController();
  String? _selectedTopic;
  int _duration = 7;
  bool _isGenerating = false;

  static const _topics = [
    'Gratitude', 'Faith in Hard Times', 'Love & Kindness',
    'Patience', 'Courage', 'Forgiveness', 'Family Unity', 'Hope',
  ];

  @override
  void dispose() {
    _customTopicCtrl.dispose();
    super.dispose();
  }

  Future<void> _generatePlan() async {
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.devotional)) return;
    final topic = _customTopicCtrl.text.trim().isNotEmpty
        ? _customTopicCtrl.text.trim()
        : _selectedTopic;
    if (topic == null || topic.isEmpty) {
      _showSnack(context, 'Please select or enter a topic');
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final provider = context.read<AppProvider>();
      final prompt = '''Generate a $_duration-day adult Bible reading plan on "$topic".
Each day should speak to grown believers facing daily life: stress, relationships, weariness, sin and repentance, hope, and God's promises—honest and direct, Scripture-centered, uplifting without being shallow.

Return JSON: { "title": string, "description": string, "entries": [{ "day": number, "title": string, "scripture": string, "scriptureRef": string, "content": string, "discussion": string }] }
For each entry's "scripture", write out the FULL verse text (e.g. "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.").
For "scriptureRef", provide only the book/chapter/verse reference (e.g. "John 3:16").
For each entry's "discussion" field, provide one substantive personal reflection prompt for an adult (not a children's discussion question).''';

      final raw = await AiService.ask(
        prompt: prompt,
        feature: 'ai_devotional',
        familyId: widget.familyId,
        responseMimeType: 'application/json',
      );

      if (raw != null && mounted) {
        provider.saveAiHistory(module: 'devotional', prompt: 'Generate $_duration-day Bible reading plan on "$topic"', response: raw);
        final data = AiService.tryParseJsonObject(raw);
        if (data == null) {
          if (mounted) {
            _showSnack(context, 'Could not parse the reading plan. Try generating again.');
          }
          return;
        }
        final entriesData = (data['entries'] as List?) ?? [];
        final planId = const Uuid().v4();

        // Create devotional entries for each day
        final newEntries = <DevotionalEntry>[];
        for (final dayData in entriesData) {
          final d = dayData as Map<String, dynamic>;
          final sRef = d['scriptureRef'] as String?;
          final sText = d['scripture'] as String?;
          final combinedScripture = sText != null && sRef != null
              ? '$sText\n\u2014 $sRef'
              : sText ?? sRef;
          final entry = DevotionalEntry(
            id: const Uuid().v4(),
            familyId: widget.familyId,
            creatorId: provider.activeUser?.id ?? '',
            title: d['title'] as String? ?? 'Day ${d['day']}',
            scripture: combinedScripture,
            content: d['content'] as String?,
            reflectionPrompts: [if (d['discussion'] != null) d['discussion'] as String],
            date: DateTime.now(),
          );
          newEntries.add(entry);
        }

        final planDays = newEntries
            .asMap()
            .entries
            .map((e) => <String, dynamic>{
                  'devotional_id': e.value.id,
                  'day': e.key + 1,
                  'title': e.value.title,
                })
            .toList();
        final plan = ReadingPlan(
          id: planId,
          familyId: widget.familyId,
          creatorId: provider.activeUser?.id ?? '',
          title: data['title'] as String? ?? '$topic Reading Plan',
          description: (data['description'] as String?) ?? '',
          totalDays: newEntries.length,
          days: planDays,
          entryIds: newEntries.map((e) => e.id).toList(),
          createdAt: DateTime.now(),
        );

        final db = provider.db;
        await provider.saveAndSync(
          db.copyWith(
            devotionalEntries: [...db.devotionalEntries, ...newEntries],
            readingPlans: [...db.readingPlans, plan],
          ),
          pushTableScope: {
            CloudSyncScope.devotionals,
            CloudSyncScope.readingPlans,
          },
        );

        if (!mounted) return;
        _customTopicCtrl.clear();
        widget.onSelectPlan(plan);
      }
    } catch (e) {
      if (mounted) {
        _showSnack(context, 'Failed to generate plan: $e');
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final thoughts = app.db.devotionalThoughts;
    final uid = app.activeUser?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Create a Reading Plan Card ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _AiFeatureCard(
            icon: Icons.auto_awesome,
            gradientColors: const [Color(0xFF8B7BF7), Color(0xFFB4A0FF)],
            title: 'Create a Reading Plan',
            hintText: 'Or type your own theme...',
            controller: _customTopicCtrl,
            loading: _isGenerating,
            buttonLabel: 'Generate Plan',
            onAction: _isGenerating ? null : _generatePlan,
            onTextChanged: (_) => setState(() => _selectedTopic = null),
            extraContent: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Topic chips
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _topics.map((t) {
                    final selected = _selectedTopic == t;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedTopic = selected ? null : t;
                        if (!selected) _customTopicCtrl.clear();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: selected ? Border.all(color: Colors.white.withValues(alpha: 0.6)) : null,
                        ),
                        child: Text(t, style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
                          color: Colors.white.withValues(alpha: selected ? 1.0 : 0.8),
                        )),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
              ],
            ),
            extraContentAfterInput: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                // Duration selector
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [7, 14, 21, 30].map((d) {
                    final selected = _duration == d;
                    return GestureDetector(
                      onTap: () => setState(() => _duration = d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: selected ? Border.all(color: Colors.white.withValues(alpha: 0.6)) : null,
                        ),
                        child: Text('$d days', style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12,
                          color: Colors.white.withValues(alpha: selected ? 1.0 : 0.7),
                        )),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Your Reading Plans ──
        if (widget.plans.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 20, 10),
            child: Text('YOUR READING PLANS', style: TextStyle(
              fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11,
              color: AppTheme.stone400, letterSpacing: 1.2,
            )),
          ),
          const SizedBox(height: 4),
          ...widget.plans.map((plan) {
            final totalDays = plan.entryIds.length;
            final completedDays = plan.entryIds.where((id) {
              final entry = widget.entries.cast<DevotionalEntry?>().firstWhere(
                (e) => e?.id == id, orElse: () => null,
              );
              if (entry == null) return false;
              return _entryHasPersonalPrayer(entry, uid, thoughts);
            }).length;
            final progress = totalDays > 0 ? completedDays / totalDays : 0.0;

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: GestureDetector(
                onTap: () => widget.onSelectPlan(plan),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.stone100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.title, style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.stone900,
                      ), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        '$totalDays days  \u00B7  ${DateFormat('MMM d').format(plan.createdAt)}',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: AppTheme.stone100,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$completedDays/$totalDays days  \u00B7  ${(progress * 100).round()}%',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ─── Entry Detail View ───────────────────────────────────────────────────────

class _EntryDetailView extends StatelessWidget {
  final DevotionalEntry entry;
  final VoidCallback onBack;
  final VoidCallback onDelete;
  final Future<void> Function(DevotionalThought thought) onUpsertThought;
  final Future<void> Function(String) onUpdatePrayer;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShare;
  final VoidCallback onShareWithFamily;

  const _EntryDetailView({
    required this.entry,
    required this.onBack,
    required this.onDelete,
    required this.onUpsertThought,
    required this.onUpdatePrayer,
    required this.onToggleFavorite,
    required this.onShare,
    required this.onShareWithFamily,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final thoughtsForEntry =
        app.db.devotionalThoughts.where((t) => t.devotionalId == entry.id).toList();
    final myPrayer =
        _myPrayerBody(entry, app.activeUser?.id, app.db.devotionalThoughts);
    final cs = Theme.of(context).colorScheme;
    final onSurf = cs.onSurface;
    return Scaffold(
      appBar: SubpageAppBar(
        onBack: onBack,
        actions: [
          IconButton(
            icon: Icon(Icons.share_rounded, color: onSurf.withValues(alpha: 0.55)),
            tooltip: 'Share',
            onPressed: onShare,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.stone400),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Devotional'),
                  content: const Text('This will permanently remove this devotional.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
                  ],
                ),
              );
              if (confirmed == true) onDelete();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scripture badge
            if (entry.scripture != null) ...[
              Text(
                'SCRIPTURE ROOT — ${_extractRef(entry.scripture!).toUpperCase()}',
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700,
                  color: onSurf.withValues(alpha: 0.45), letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Title
            Text(entry.title, style: TextStyle(
              fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 26, color: onSurf,
              height: 1.2,
            )),
            const SizedBox(height: 12),

            // Scripture reference
            if (entry.scripture != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDBA74)),
                ),
                child: SelectableText(
                  '"${entry.scripture}"',
                  style: TextStyle(
                    fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600,
                    color: Color(0xFFEA580C), fontStyle: FontStyle.italic,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Content
            if (entry.content != null) ...[
              Text(
                'READING',
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700,
                  color: onSurf.withValues(alpha: 0.45), letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                entry.content!,
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 16, color: onSurf.withValues(alpha: 0.88), height: 1.65,
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Reflection prompts
            if (entry.reflectionPrompts.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF2F8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF9A8D4).withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.favorite_outline_rounded, size: 16, color: const Color(0xFFEC4899)),
                        const SizedBox(width: 6),
                        const Text('PERSONAL REFLECTION', style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11,
                          color: Color(0xFFEC4899), letterSpacing: 0.5,
                        )),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...entry.reflectionPrompts.asMap().entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Q${e.key + 1}. ',
                              style: TextStyle(
                                fontFamily: 'Inter', fontWeight: FontWeight.w700,
                                fontSize: 14, color: Color(0xFFEC4899),
                              ),
                            ),
                            Expanded(
                              child: Text(e.value, style: TextStyle(
                                fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone700, height: 1.4,
                              )),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            _DevotionalThoughtsSection(
              key: ValueKey(entry.id),
              entry: entry,
              activeUserId: app.activeUser?.id,
              users: app.db.users,
              thoughts: thoughtsForEntry,
              onUpsertThought: onUpsertThought,
            ),
            const SizedBox(height: 20),

            // Prayer
            if (entry.prayer != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDE68A).withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PRAYER', style: TextStyle(
                      fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11,
                      color: Color(0xFFD97706), letterSpacing: 0.5,
                    )),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '"${entry.prayer}"',
                        style: TextStyle(
                          fontFamily: 'Inter', fontSize: 14, fontStyle: FontStyle.italic,
                          color: AppTheme.stone600, height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('YOUR PRAYER', style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 10,
                          color: AppTheme.stone400, letterSpacing: 0.5,
                        )),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _showAddPrayerDialog(context, myPrayer),
                          child: const Text('Add Prayer', style: TextStyle(
                            fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12,
                            color: Color(0xFFF59E0B),
                          )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      myPrayer?.isNotEmpty == true
                          ? myPrayer!
                          : 'No personal prayer yet. Tap "Add Prayer" to write one.',
                      style: TextStyle(
                        fontFamily: 'Inter', fontSize: 12,
                        color: myPrayer?.isNotEmpty == true ? AppTheme.stone600 : AppTheme.stone400,
                        fontStyle: myPrayer?.isNotEmpty == true ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onToggleFavorite();
                      _showSnack(context, entry.isFavorited ? 'Removed from favorites' : 'Saved to favorites');
                    },
                    icon: Icon(entry.isFavorited ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded, size: 18),
                    label: Text(entry.isFavorited ? 'Favorited' : 'Save to Favorites'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.stone600,
                      side: const BorderSide(color: AppTheme.stone200),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: entry.visibility == Visibility.FAMILY
                        ? AppTheme.primary.withValues(alpha: 0.08)
                        : AppTheme.stone50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.stone200),
                  ),
                  child: Text(
                    entry.visibility == Visibility.FAMILY ? 'Shared' : 'Private',
                    style: TextStyle(
                      fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13,
                      color: entry.visibility == Visibility.FAMILY ? AppTheme.primary : AppTheme.stone500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share text'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: Color(0xFFC7D2FE)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (entry.visibility == Visibility.PRIVATE) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        onShareWithFamily();
                      },
                      icon: const Icon(Icons.groups_rounded, size: 18),
                      label: const Text('Share with family'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPrayerDialog(BuildContext context, String? initialPrayer) {
    final controller = TextEditingController(text: initialPrayer ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your Prayer'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Write your prayer...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              onUpdatePrayer(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _DevotionalThoughtsSection extends StatefulWidget {
  final DevotionalEntry entry;
  final String? activeUserId;
  final List<User> users;
  final List<DevotionalThought> thoughts;
  final Future<void> Function(DevotionalThought thought) onUpsertThought;

  const _DevotionalThoughtsSection({
    super.key,
    required this.entry,
    required this.activeUserId,
    required this.users,
    required this.thoughts,
    required this.onUpsertThought,
  });

  @override
  State<_DevotionalThoughtsSection> createState() =>
      _DevotionalThoughtsSectionState();
}

class _DevotionalThoughtsSectionState extends State<_DevotionalThoughtsSection> {
  late TextEditingController _controller;
  final _debounce = Debouncer(duration: const Duration(milliseconds: 650));

  DevotionalThought? _myThought() {
    final uid = widget.activeUserId;
    if (uid == null) return null;
    return widget.thoughts.firstWhereOrNull(
      (t) => t.userId == uid && t.kind == DevotionalNoteKind.thought,
    );
  }

  @override
  void initState() {
    super.initState();
    final mine = _myThought();
    _controller = TextEditingController(text: mine?.body ?? '');
  }

  @override
  void dispose() {
    _debounce.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveFromController() async {
    final uid = widget.activeUserId;
    if (uid == null || !mounted) return;
    final body = _controller.text;
    var thought = _myThought();
    thought ??= DevotionalThought(
      id: DevotionalThought.stableId(
        widget.entry.id,
        uid,
        DevotionalNoteKind.thought,
      ),
      devotionalId: widget.entry.id,
      familyId: widget.entry.familyId,
      userId: uid,
      kind: DevotionalNoteKind.thought,
      body: '',
    );
    final next = thought.copyWith(body: body);
    await widget.onUpsertThought(next);
  }

  String _displayName(String userId) {
    final u = widget.users.firstWhereOrNull((x) => x.id == userId);
    if (u == null || u.name.trim().isEmpty) return 'Family member';
    return u.name.trim();
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.activeUserId;
    if (uid == null) return const SizedBox.shrink();

    final shared = widget.entry.visibility == Visibility.FAMILY;
    final others = widget.thoughts
        .where((t) =>
            t.userId != uid &&
            t.kind == DevotionalNoteKind.thought &&
            t.body.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFC7D2FE).withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 18, color: AppTheme.primary),
              const SizedBox(width: 6),
              const Text(
                'MY THOUGHTS',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: AppTheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            shared
                ? 'Saved with this devotional. When it is shared with your home, everyone can read the reflections below.'
                : 'Only you can see this devotional and your notes.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppTheme.stone500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText:
                  'What stood out? Questions? How will you live this out?',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            onChanged: (_) {
              _debounce.run(() => unawaited(_saveFromController()));
            },
          ),
          if (shared && others.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.groups_rounded, size: 16, color: AppTheme.stone500),
                const SizedBox(width: 6),
                const Text(
                  'FROM THE FAMILY',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: AppTheme.stone500,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...others.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.stone200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName(t.userId),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppTheme.stone700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.body,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: AppTheme.stone600,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Reading Plan Detail View ────────────────────────────────────────────────

class _ReadingPlanDetailView extends StatefulWidget {
  final ReadingPlan plan;
  final List<DevotionalEntry> entries;
  final List<DevotionalThought> thoughts;
  final String? activeUserId;
  final VoidCallback onBack;

  const _ReadingPlanDetailView({
    required this.plan,
    required this.entries,
    required this.thoughts,
    required this.activeUserId,
    required this.onBack,
  });

  @override
  State<_ReadingPlanDetailView> createState() => _ReadingPlanDetailViewState();
}

class _ReadingPlanDetailViewState extends State<_ReadingPlanDetailView> {
  int _currentDay = 0;

  List<DevotionalEntry> get _planEntries {
    return widget.plan.entryIds.map((id) {
      return widget.entries.cast<DevotionalEntry?>().firstWhere(
        (e) => e?.id == id, orElse: () => null,
      );
    }).whereType<DevotionalEntry>().toList();
  }

  @override
  void initState() {
    super.initState();
    final entries = _planEntries;
    final uid = widget.activeUserId;
    final thoughts = widget.thoughts;
    for (int i = 0; i < entries.length; i++) {
      if (!_entryHasPersonalPrayer(entries[i], uid, thoughts)) {
        _currentDay = i;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _planEntries;
    final totalDays = entries.length;
    final currentEntry = _currentDay < entries.length ? entries[_currentDay] : null;
    final uid = widget.activeUserId;
    final thoughts = widget.thoughts;
    final completedCount = entries
        .where((e) => _entryHasPersonalPrayer(e, uid, thoughts))
        .length;

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SubpageAppBar(
        onBack: widget.onBack,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back link
            GestureDetector(
              onTap: widget.onBack,
              child: const Text('< Back to all plans', style: TextStyle(
                fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary,
              )),
            ),
            const SizedBox(height: 16),

            // Plan header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(widget.plan.title, style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 24, color: AppTheme.stone900,
                    height: 1.2,
                  )),
                ),
                const SizedBox(width: 12),
                // Progress circle
                SizedBox(
                  width: 48, height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: totalDays > 0 ? completedCount / totalDays : 0,
                        strokeWidth: 4,
                        backgroundColor: AppTheme.stone100,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                      ),
                      Text(
                        '$completedCount/$totalDays',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.stone600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (widget.plan.description.isNotEmpty)
              Text(widget.plan.description, style: TextStyle(
                fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone500, height: 1.4,
              )),
            const SizedBox(height: 20),

            // Day selector circles
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(totalDays, (i) {
                  final isComplete = i < entries.length &&
                      _entryHasPersonalPrayer(entries[i], uid, thoughts);
                  final isCurrent = i == _currentDay;
                  return GestureDetector(
                    onTap: () => setState(() => _currentDay = i),
                    child: Container(
                      width: 36, height: 36,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isCurrent ? AppTheme.primary : isComplete ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.stone50,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCurrent ? AppTheme.primary : isComplete ? AppTheme.success : AppTheme.stone200,
                          width: isCurrent ? 2 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: isComplete && !isCurrent
                          ? const Icon(Icons.check_rounded, size: 16, color: AppTheme.success)
                          : Text('${i + 1}', style: TextStyle(
                              fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700,
                              color: isCurrent ? Colors.white : AppTheme.stone600,
                            )),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),

            // Current day content
            if (currentEntry != null) ...[
              Text('DAY ${_currentDay + 1} OF $totalDays', style: TextStyle(
                fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700,
                color: AppTheme.primary, letterSpacing: 0.5,
              )),
              const SizedBox(height: 8),
              Text(currentEntry.title, style: TextStyle(
                fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 22, color: AppTheme.stone900,
              )),
              const SizedBox(height: 12),

              // Scripture
              if (currentEntry.scripture != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDBA74)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SCRIPTURE', style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 10,
                        color: Color(0xFFEA580C), letterSpacing: 0.5,
                      )),
                      const SizedBox(height: 6),
                      Text(
                        '"${currentEntry.scripture}"',
                        style: TextStyle(
                          fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600,
                          color: Color(0xFFEA580C), fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // Reflection
              if (currentEntry.content != null) ...[
                const Text('REFLECTION', style: TextStyle(
                  fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 10,
                  color: AppTheme.stone400, letterSpacing: 0.5,
                )),
                const SizedBox(height: 8),
                Text(currentEntry.content!, style: TextStyle(
                  fontFamily: 'Inter', fontSize: 15, color: AppTheme.stone700, height: 1.6,
                )),
                const SizedBox(height: 20),
              ],

              // Reflection prompts
              if (currentEntry.reflectionPrompts.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDBA74).withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('REFLECT & APPLY', style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11,
                        color: Color(0xFFEA580C), letterSpacing: 0.5,
                      )),
                      const SizedBox(height: 10),
                      ...currentEntry.reflectionPrompts.map((q) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(q, style: TextStyle(
                          fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone700, height: 1.4,
                        )),
                      )),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Bottom nav buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        final provider = context.read<AppProvider>();
                        final db = provider.db;
                        final userId = widget.activeUserId;
                        if (userId == null) return;
                        final sid = DevotionalThought.stableId(
                          currentEntry.id,
                          userId,
                          DevotionalNoteKind.prayer,
                        );
                        final existing = db.devotionalThoughts.firstWhereOrNull(
                          (t) =>
                              t.devotionalId == currentEntry.id &&
                              t.userId == userId &&
                              t.kind == DevotionalNoteKind.prayer,
                        );
                        final body = existing?.body.trim().isNotEmpty == true
                            ? existing!.body
                            : (currentEntry.userPrayer?.trim().isNotEmpty == true
                                ? currentEntry.userPrayer!
                                : 'completed');
                        final prayerThought = DevotionalThought(
                          id: sid,
                          devotionalId: currentEntry.id,
                          familyId: currentEntry.familyId,
                          userId: userId,
                          kind: DevotionalNoteKind.prayer,
                          body: body,
                        );
                        final without =
                            db.devotionalThoughts.where((t) => t.id != sid).toList();
                        final cleared = currentEntry.copyWith(userPrayer: null);
                        provider.saveAndSync(
                          db.copyWith(
                            devotionalThoughts: [...without, prayerThought],
                            devotionalEntries: db.devotionalEntries
                                .map((e) => e.id == cleared.id ? cleared : e)
                                .toList(),
                          ),
                          pushTableScope: CloudSyncScope.devotionalBundle,
                        );
                        setState(() {});
                        _showSnack(context, 'Day ${_currentDay + 1} complete!');
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text('Mark Day ${_currentDay + 1}\nComplete', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.3)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                    ),
                  ),
                  if (_currentDay < totalDays - 1) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => setState(() => _currentDay++),
                      child: Row(
                        children: const [
                          Text('Next\nday', textAlign: TextAlign.center, style: TextStyle(
                            fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500,
                          )),
                          SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, color: AppTheme.stone400),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Daily AI Devotional Schedule Card ──────────────────────────────────────

class _DailyDevotionalCard extends StatefulWidget {
  final String familyId;
  final ValueChanged<DevotionalEntry>? onTapToday;
  final VoidCallback? onGenerateNow;
  final bool isGenerating;
  final VoidCallback? onUserSettingsChanged;

  const _DailyDevotionalCard({
    required this.familyId,
    this.onTapToday,
    this.onGenerateNow,
    this.isGenerating = false,
    this.onUserSettingsChanged,
  });

  @override
  State<_DailyDevotionalCard> createState() => _DailyDevotionalCardState();
}

class _DailyDevotionalCardState extends State<_DailyDevotionalCard> {
  Future<void> _rescheduleUserNotif(AppProvider provider) async {
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) return;
    final nid = _userDailyNotificationId(user.id);
    if (!_userDailyEnabled(user, family)) {
      await NotificationService.cancel(nid);
      return;
    }
    final utcRef = DateTime.utc(
      2024,
      1,
      1,
      _userDailyHour(user, family),
      _userDailyMinute(user, family),
    );
    final local = utcRef.toLocal();
    await NotificationService.scheduleDaily(
      id: nid,
      title: 'Daily devotional',
      body: 'Open ${AppConfig.appName} for today\'s reading.',
      time: Time(local.hour, local.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final family = provider.activeFamily;
    final user = provider.activeUser;
    final familyId = widget.familyId;
    if (family == null || user == null) return const SizedBox.shrink();

    final enabled = _userDailyEnabled(user, family);
    final utcDt = DateTime.utc(
      2024,
      1,
      1,
      _userDailyHour(user, family),
      _userDailyMinute(user, family),
    );
    final localDt = utcDt.toLocal();
    final hour = localDt.hour;
    final minute = localDt.minute;
    final timeOfDay = TimeOfDay(hour: hour, minute: minute);
    final formattedTime = timeOfDay.format(context);
    final dailyPrivate = _userDailyPrivateDefault(user);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayEntry = enabled
        ? provider.db.devotionalEntries.cast<DevotionalEntry?>().firstWhere(
            (e) =>
                e!.familyId == familyId &&
                e.creatorId == user.id &&
                e.tags.contains('daily-auto') &&
                DateTime(e.date.year, e.date.month, e.date.day) == today,
            orElse: () => null,
          )
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.schedule_rounded, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Your daily AI devotional',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch.adaptive(
                    value: enabled,
                    onChanged: (val) => _toggleUser(context, val),
                    activeThumbColor: Colors.white, // FIXED: activeColor deprecated
                    activeTrackColor: Colors.white.withValues(alpha: 0.35),
                    inactiveThumbColor: Colors.white70,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              enabled
                  ? 'Yours only: time and privacy are saved on your profile. New dailies start private if you choose — share any entry from its screen.'
                  : 'Turn on for a personal daily reading at the time you pick.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            if (enabled) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _togglePrivateDefault(context, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        decoration: BoxDecoration(
                          color: dailyPrivate
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          'New dailies: Private',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            color: dailyPrivate ? const Color(0xFF6366F1) : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _togglePrivateDefault(context, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        decoration: BoxDecoration(
                          color: !dailyPrivate
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          'New dailies: Family',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            color: !dailyPrivate ? const Color(0xFF6366F1) : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _pickTime(context, timeOfDay),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            formattedTime,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.edit_rounded, size: 14, color: Colors.white.withValues(alpha: 0.7)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _testEdgeFunction(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.send_rounded, size: 16, color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ),
                  const Spacer(),
                  if (todayEntry != null)
                    GestureDetector(
                      onTap: () => widget.onTapToday?.call(todayEntry),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Read today\'s',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                    )
                  else if (widget.isGenerating)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Generating...',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (now.isBefore(DateTime(now.year, now.month, now.day, hour, minute)))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Scheduled',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: widget.onGenerateNow,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Generate now',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleUser(BuildContext context, bool val) async {
    final provider = context.read<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) return;

    final patch = <String, dynamic>{_kUserDailyEnabled: val};
    if (val &&
        !user.settings.containsKey(_kUserDailyHour) &&
        !user.settings.containsKey(_kUserDailyMinute)) {
      patch[_kUserDailyHour] = family.dailyDevotionalHour;
      patch[_kUserDailyMinute] = family.dailyDevotionalMinute;
    }
    await provider.updateActiveUserSettings(patch);
    await _rescheduleUserNotif(provider);
    widget.onUserSettingsChanged?.call();
  }

  Future<void> _togglePrivateDefault(BuildContext context, bool private) async {
    final provider = context.read<AppProvider>();
    await provider.updateActiveUserSettings({_kUserDailyPrivate: private});
    widget.onUserSettingsChanged?.call();
  }

  /// Manually invoke the daily-devotional edge function in test mode
  /// to verify server-side generation + notifications work.
  Future<void> _testEdgeFunction(BuildContext context) async {
    final provider = context.read<AppProvider>();
    final family = provider.activeFamily;
    if (family == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Testing server-side devotional...')),
    );

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'daily-devotional',
        body: {'test': true, 'family_id': family.id},
      );
      if (!context.mounted) return;
      final data = res.data;
      final generated = data?['generated'] ?? 0;
      final sent = data?['sent'] ?? 0;
      final error = data?['error'];

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server error: $error'), backgroundColor: Colors.red),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generated: $generated, Notifications sent: $sent')),
        );
        // Sync to pick up the new devotional
        if (generated > 0) {
          await provider.refreshFromCloud();
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Edge function failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickTime(BuildContext context, TimeOfDay current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: 'Choose devotional delivery time',
    );
    if (picked == null || !context.mounted) return;

    final now = DateTime.now();
    final localDt = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    final utcDt = localDt.toUtc();

    final provider = context.read<AppProvider>();
    await provider.updateActiveUserSettings({
      _kUserDailyHour: utcDt.hour,
      _kUserDailyMinute: utcDt.minute,
    });
    await _rescheduleUserNotif(provider);
  }

}

// ─── AI Feature Card (consistent with meals pattern) ─────────────────────────

class _AiFeatureCard extends StatelessWidget {
  final IconData icon;
  final List<Color> gradientColors;
  final String title;
  final String hintText;
  final TextEditingController controller;
  final bool loading;
  final String buttonLabel;
  final VoidCallback? onAction;
  final Widget? extraContent;
  final Widget? extraContentAfterInput;
  final ValueChanged<String>? onTextChanged;

  const _AiFeatureCard({
    required this.icon,
    required this.gradientColors,
    required this.title,
    required this.hintText,
    required this.controller,
    required this.loading,
    required this.buttonLabel,
    this.onAction,
    this.extraContent,
    this.extraContentAfterInput,
    this.onTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text(title, style: TextStyle(
              fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white,
            )),
          ]),
          const SizedBox(height: 10),
          if (extraContent != null) extraContent!,
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: controller,
              onChanged: onTextChanged,
              style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 14),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Inter'),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: false,
              ),
            ),
          ),
          if (extraContentAfterInput != null) extraContentAfterInput!,
          const SizedBox(height: 10),
          Row(
            children: [
              if (extraContent != null && extraContentAfterInput == null) const Spacer(),
              if (extraContentAfterInput != null)
                Expanded(
                  child: GestureDetector(
                    onTap: onAction,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: loading
                            ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: gradientColors.first))
                            : Text(buttonLabel, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: gradientColors.first)),
                      ),
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: onAction,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: loading
                        ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: gradientColors.first))
                        : Text(buttonLabel, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: gradientColors.first)),
                  ),
                ),
            ],
          ),
        ],
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
                  Text(label, style: TextStyle(
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

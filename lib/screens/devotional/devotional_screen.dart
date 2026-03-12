// lib/screens/devotional/devotional_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart' hide Visibility;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../services/database_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

/// Extract the reference portion from a combined scripture string.
/// e.g. "For God so loved...\n— John 3:16" → "John 3:16"
/// Falls back to the full string if no em-dash separator is found.
String _extractRef(String scripture) {
  final idx = scripture.lastIndexOf('\u2014');
  if (idx >= 0) return scripture.substring(idx + 1).trim();
  return scripture;
}

class DevotionalScreen extends StatefulWidget {
  const DevotionalScreen({super.key});

  @override
  State<DevotionalScreen> createState() => _DevotionalScreenState();
}

class _DevotionalScreenState extends State<DevotionalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DevotionalEntry? _selectedEntry;
  ReadingPlan? _selectedPlan;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _deleteEntry(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      devotionalEntries: db.devotionalEntries.where((e) => e.id != id).toList(),
    ));
    if (_selectedEntry?.id == id) setState(() => _selectedEntry = null);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final family = provider.activeFamily;
    if (family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final entries = provider.db.devotionalEntries
        .where((e) => e.familyId == family.id)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final plans = provider.db.readingPlans
        .where((p) => p.familyId == family.id)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // If viewing a devotional entry detail
    if (_selectedEntry != null) {
      return _EntryDetailView(
        entry: _selectedEntry!,
        onBack: () => setState(() => _selectedEntry = null),
        onDelete: () => _deleteEntry(_selectedEntry!.id),
        onUpdatePrayer: (prayer) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          final updated = _selectedEntry!.copyWith(userPrayer: prayer);
          await provider.saveAndSync(db.copyWith(
            devotionalEntries: db.devotionalEntries.map((e) => e.id == updated.id ? updated : e).toList(),
          ));
          setState(() => _selectedEntry = updated);
        },
      );
    }

    // If viewing a reading plan detail
    if (_selectedPlan != null) {
      return _ReadingPlanDetailView(
        plan: _selectedPlan!,
        entries: entries,
        onBack: () => setState(() => _selectedPlan = null),
      );
    }

    return Scaffold(
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
            const Text('FamilyHub', style: TextStyle(
              fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary,
            )),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            PageHeader(
              title: 'Spiritual Growth',
              subtitle: 'Reflect, pray, and grow as a family.',
            ),

            // Tab chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.stone100,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    _tabChip(0, Icons.menu_book_outlined, 'Devotionals'),
                    const SizedBox(width: 4),
                    _tabChip(1, Icons.calendar_month_rounded, 'Reading Plans'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Tab content
            if (_tabController.index == 0)
              _DevotionalsTab(
                entries: entries,
                familyId: family.id,
                onSelectEntry: (e) => setState(() => _selectedEntry = e),
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

  Widget _tabChip(int index, IconData icon, String label) {
    final selected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.stone800 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : AppTheme.stone500),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13,
                color: selected ? Colors.white : AppTheme.stone600,
              )),
            ],
          ),
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

  const _DevotionalsTab({
    required this.entries,
    required this.familyId,
    required this.onSelectEntry,
  });

  @override
  State<_DevotionalsTab> createState() => _DevotionalsTabState();
}

class _DevotionalsTabState extends State<_DevotionalsTab> {
  final _topicCtrl = TextEditingController();
  bool _isShared = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    // Check if we need to auto-generate today's daily devotional
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeGenerateDaily());
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  /// Auto-generate a daily devotional if enabled and not yet created today.
  /// First syncs with the cloud to pick up server-generated devotionals
  /// (produced by the daily-devotional edge function even when the app is
  /// closed). Falls back to client-side generation if nothing was found.
  Future<void> _maybeGenerateDaily() async {
    if (!mounted) return;
    final provider = context.read<AppProvider>();
    final family = provider.activeFamily;
    if (family == null || !family.dailyDevotionalEnabled) return;

    final now = DateTime.now();
    final scheduledTime = DateTime(now.year, now.month, now.day, family.dailyDevotionalHour, family.dailyDevotionalMinute);

    // Only generate if we're past the scheduled time
    if (now.isBefore(scheduledTime)) return;

    final today = DateTime(now.year, now.month, now.day);

    bool _hasTodaysDevotional() => provider.db.devotionalEntries.any((e) =>
      e.familyId == family.id &&
      e.tags.contains('daily-auto') &&
      DateTime(e.date.year, e.date.month, e.date.day) == today,
    );

    // Check local first
    if (_hasTodaysDevotional()) return;

    // Sync with cloud — the server may have already generated today's devotional
    try {
      final merged = await DatabaseService.reconcileCloud(provider.db, family.id);
      if (mounted) provider.updateDb(merged);
    } catch (_) {
      // Cloud sync failed — continue with local check
    }
    if (!mounted) return;

    // Re-check after cloud sync
    if (_hasTodaysDevotional()) return;

    // Fallback: generate client-side (server may not have run yet)
    setState(() => _isGenerating = true);
    try {
      final raw = await AiService.ask(
        prompt: '''Write a kids-friendly family devotional for today.
Pick a random Bible verse and build a short, warm devotional around it.
Return JSON with these exact fields: title, scripture, scriptureRef, content, reflectionPrompts (array of 3 discussion questions), prayer.
For "scripture", write out the FULL verse text (e.g. "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.").
For "scriptureRef", provide only the reference (e.g. "John 3:16").
Make the content warm, relatable, and suitable for children.''',
        feature: 'ai_devotional',
        familyId: family.id,
        responseMimeType: 'application/json',
      );

      if (raw != null && mounted) {
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final scriptureRef = data['scriptureRef'] as String?;
          final scriptureText = data['scripture'] as String?;
          final scripture = scriptureText != null && scriptureRef != null
              ? '$scriptureText\n\u2014 $scriptureRef'
              : scriptureText ?? scriptureRef;
          final entry = DevotionalEntry(
            id: const Uuid().v4(),
            familyId: family.id,
            creatorId: provider.activeUser?.id ?? '',
            title: data['title'] as String? ?? 'Daily Devotional',
            scripture: scripture,
            content: data['content'] as String?,
            reflectionPrompts: (data['reflectionPrompts'] as List?)?.cast<String>() ?? [],
            prayer: data['prayer'] as String?,
            tags: ['daily-auto'],
            date: DateTime.now(),
            visibility: Visibility.FAMILY,
          );
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(
            devotionalEntries: [...db.devotionalEntries, entry],
          ));
          if (mounted) widget.onSelectEntry(entry);
        } catch (_) {
          final entry = DevotionalEntry(
            id: const Uuid().v4(),
            familyId: family.id,
            creatorId: provider.activeUser?.id ?? '',
            title: 'Daily Devotional',
            content: raw,
            tags: ['daily-auto'],
            date: DateTime.now(),
            visibility: Visibility.FAMILY,
          );
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(
            devotionalEntries: [...db.devotionalEntries, entry],
          ));
          if (mounted) widget.onSelectEntry(entry);
        }
      }
    } catch (e) {
      debugPrint('Daily devotional auto-generation failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate devotional. Pull down to retry.'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generate() async {
    setState(() => _isGenerating = true);
    try {
      final topic = _topicCtrl.text.trim().isEmpty ? 'a random Bible verse' : _topicCtrl.text.trim();
      final provider = context.read<AppProvider>();
      final prompt = '''Write a kids-friendly family devotional based on: $topic.
Return JSON with these exact fields: title, scripture, scriptureRef, content, reflectionPrompts (array of 3 discussion questions), prayer.
For "scripture", write out the FULL verse text (e.g. "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.").
For "scriptureRef", provide only the reference (e.g. "John 3:16").
Make the content warm, relatable, and suitable for children.''';

      final raw = await AiService.ask(
        prompt: prompt,
        feature: 'ai_devotional',
        familyId: widget.familyId,
        responseMimeType: 'application/json',
      );

      if (raw != null && mounted) {
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
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
          await provider.saveAndSync(db.copyWith(
            devotionalEntries: [...db.devotionalEntries, entry],
          ));
          _topicCtrl.clear();
          if (mounted) widget.onSelectEntry(entry);
        } catch (_) {
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
          await provider.saveAndSync(db.copyWith(
            devotionalEntries: [...db.devotionalEntries, entry],
          ));
          if (mounted) widget.onSelectEntry(entry);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to generate: $e'),
          backgroundColor: AppTheme.error,
        ));
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
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFF97316)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text('AI Faith Assistant', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                ]),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _topicCtrl,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Patience, Hope, Forgiveness...',
                      hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Inter'),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      filled: false,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _toggleChip('Shared', _isShared, () => setState(() => _isShared = true)),
                    const SizedBox(width: 8),
                    _toggleChip('Private', !_isShared, () => setState(() => _isShared = false)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _isGenerating ? null : _generate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _isGenerating
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)))
                            : const Text('Generate Now', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFF59E0B))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Daily AI Devotional Schedule ──
        _DailyDevotionalCard(
          familyId: widget.familyId,
          onTapToday: (entry) => widget.onSelectEntry(entry),
        ),
        const SizedBox(height: 24),

        // ── Past Readings ──
        if (widget.entries.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, size: 18, color: AppTheme.stone500),
                const SizedBox(width: 8),
                const Text('Past Readings', style: TextStyle(
                  fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.stone900,
                )),
                const Spacer(),
                Text('${widget.entries.length}', style: const TextStyle(
                  fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone400,
                )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...widget.entries.map((entry) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
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
                        style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700,
                          color: AppTheme.stone400, letterSpacing: 0.5,
                        ),
                      ),
                    if (entry.scripture != null) const SizedBox(height: 6),
                    Text(entry.title, style: const TextStyle(
                      fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.stone900,
                    ), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('MMM d, yyyy').format(entry.date),
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                    ),
                    if (entry.visibility == Visibility.FAMILY) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Shared', style: TextStyle(
                          fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primary,
                        )),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )),
        ],
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
    final topic = _customTopicCtrl.text.trim().isNotEmpty
        ? _customTopicCtrl.text.trim()
        : _selectedTopic;
    if (topic == null || topic.isEmpty) return;

    setState(() => _isGenerating = true);
    try {
      final provider = context.read<AppProvider>();
      final prompt = '''Generate a $_duration-day family Bible reading plan on "$topic".
Return JSON: { "title": string, "description": string, "entries": [{ "day": number, "title": string, "scripture": string, "scriptureRef": string, "content": string, "discussion": string }] }
For each entry's "scripture", write out the FULL verse text (e.g. "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.").
For "scriptureRef", provide only the book/chapter/verse reference (e.g. "John 3:16").
Make it warm, kid-friendly, and relatable.''';

      final raw = await AiService.ask(
        prompt: prompt,
        feature: 'ai_devotional',
        familyId: widget.familyId,
        responseMimeType: 'application/json',
      );

      if (raw != null && mounted) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
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

        final plan = ReadingPlan(
          id: planId,
          familyId: widget.familyId,
          creatorId: provider.activeUser?.id ?? '',
          title: data['title'] as String? ?? '$topic Reading Plan',
          description: (data['description'] as String?) ?? '',
          entryIds: newEntries.map((e) => e.id).toList(),
          createdAt: DateTime.now(),
        );

        final db = provider.db;
        await provider.saveAndSync(db.copyWith(
          devotionalEntries: [...db.devotionalEntries, ...newEntries],
          readingPlans: [...db.readingPlans, plan],
        ));

        _customTopicCtrl.clear();
        if (mounted) {
          widget.onSelectPlan(plan);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to generate plan: $e'),
          backgroundColor: AppTheme.error,
        ));
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
        // ── Create a Reading Plan Card ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B7BF7), Color(0xFFB4A0FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Create a Reading Plan', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                ]),
                const SizedBox(height: 8),
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
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _customTopicCtrl,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 14),
                    onChanged: (_) => setState(() => _selectedTopic = null),
                    decoration: const InputDecoration(
                      hintText: 'Or type your own theme...',
                      hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Inter'),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      filled: false,
                    ),
                  ),
                ),
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
                const SizedBox(height: 12),
                // Generate button
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _isGenerating ? null : _generatePlan,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: _isGenerating
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B7BF7)))
                            : const Text('Generate Plan', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF8B7BF7))),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Your Reading Plans ──
        if (widget.plans.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Text('Your Reading Plans', style: TextStyle(
              fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.stone900,
            )),
          ),
          const SizedBox(height: 12),
          ...widget.plans.map((plan) {
            final totalDays = plan.entryIds.length;
            // Count completed days (entries that have userPrayer or are marked in some way)
            final completedDays = plan.entryIds.where((id) {
              final entry = widget.entries.cast<DevotionalEntry?>().firstWhere(
                (e) => e?.id == id, orElse: () => null,
              );
              return entry?.userPrayer != null && entry!.userPrayer!.isNotEmpty;
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
                      Text(plan.title, style: const TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.stone900,
                      ), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        '$totalDays days  \u00B7  ${DateFormat('MMM d').format(plan.createdAt)}',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
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
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400),
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
  final Future<void> Function(String) onUpdatePrayer;

  const _EntryDetailView({
    required this.entry,
    required this.onBack,
    required this.onDelete,
    required this.onUpdatePrayer,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.stone700),
          onPressed: onBack,
        ),
        actions: [
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
                'KIDS FRIENDLY BASED ON ${_extractRef(entry.scripture!).toUpperCase()}',
                style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppTheme.stone400, letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Title
            Text(entry.title, style: const TextStyle(
              fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 26, color: AppTheme.stone900,
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
                child: Text(
                  '"${entry.scripture}"',
                  style: const TextStyle(
                    fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600,
                    color: Color(0xFFEA580C), fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Content
            if (entry.content != null) ...[
              Text(entry.content!, style: const TextStyle(
                fontFamily: 'Inter', fontSize: 15, color: AppTheme.stone700, height: 1.6,
              )),
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
                        const Text('FAMILY REFLECTION', style: TextStyle(
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
                              style: const TextStyle(
                                fontFamily: 'Inter', fontWeight: FontWeight.w700,
                                fontSize: 14, color: Color(0xFFEC4899),
                              ),
                            ),
                            Expanded(
                              child: Text(e.value, style: const TextStyle(
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
                        style: const TextStyle(
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
                          onTap: () => _showAddPrayerDialog(context),
                          child: const Text('Add Prayer', style: TextStyle(
                            fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12,
                            color: Color(0xFFF59E0B),
                          )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.userPrayer?.isNotEmpty == true
                          ? entry.userPrayer!
                          : 'No personal prayer yet. Tap "Add Prayer" to write one.',
                      style: TextStyle(
                        fontFamily: 'Inter', fontSize: 12,
                        color: entry.userPrayer?.isNotEmpty == true ? AppTheme.stone600 : AppTheme.stone400,
                        fontStyle: entry.userPrayer?.isNotEmpty == true ? FontStyle.normal : FontStyle.italic,
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Saved to favorites'), backgroundColor: AppTheme.success),
                      );
                    },
                    icon: const Icon(Icons.bookmark_outline_rounded, size: 18),
                    label: const Text('Save to Favorites'),
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
          ],
        ),
      ),
    );
  }

  void _showAddPrayerDialog(BuildContext context) {
    final controller = TextEditingController(text: entry.userPrayer ?? '');
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

// ─── Reading Plan Detail View ────────────────────────────────────────────────

class _ReadingPlanDetailView extends StatefulWidget {
  final ReadingPlan plan;
  final List<DevotionalEntry> entries;
  final VoidCallback onBack;

  const _ReadingPlanDetailView({
    required this.plan,
    required this.entries,
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
    // Start at first incomplete day
    final entries = _planEntries;
    for (int i = 0; i < entries.length; i++) {
      if (entries[i].userPrayer == null || entries[i].userPrayer!.isEmpty) {
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
    final completedCount = entries.where((e) => e.userPrayer != null && e.userPrayer!.isNotEmpty).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.stone700),
          onPressed: widget.onBack,
        ),
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
                  child: Text(widget.plan.title, style: const TextStyle(
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
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.stone600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (widget.plan.description != null)
              Text(widget.plan.description!, style: const TextStyle(
                fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone500, height: 1.4,
              )),
            const SizedBox(height: 20),

            // Day selector circles
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(totalDays, (i) {
                  final isComplete = i < entries.length &&
                      entries[i].userPrayer != null && entries[i].userPrayer!.isNotEmpty;
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
              Text('DAY ${_currentDay + 1} OF $totalDays', style: const TextStyle(
                fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700,
                color: AppTheme.primary, letterSpacing: 0.5,
              )),
              const SizedBox(height: 8),
              Text(currentEntry.title, style: const TextStyle(
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
                        style: const TextStyle(
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
                Text(currentEntry.content!, style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 15, color: AppTheme.stone700, height: 1.6,
                )),
                const SizedBox(height: 20),
              ],

              // Discussion
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
                      const Text('FAMILY DISCUSSION', style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11,
                        color: Color(0xFFEA580C), letterSpacing: 0.5,
                      )),
                      const SizedBox(height: 10),
                      ...currentEntry.reflectionPrompts.map((q) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(q, style: const TextStyle(
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
                        // Mark as complete (save a userPrayer marker)
                        final provider = context.read<AppProvider>();
                        final db = provider.db;
                        final updated = currentEntry.copyWith(
                          userPrayer: currentEntry.userPrayer?.isNotEmpty == true
                              ? currentEntry.userPrayer
                              : 'completed',
                        );
                        provider.saveAndSync(db.copyWith(
                          devotionalEntries: db.devotionalEntries.map(
                            (e) => e.id == updated.id ? updated : e,
                          ).toList(),
                        ));
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Day ${_currentDay + 1} complete!'),
                          backgroundColor: AppTheme.success,
                        ));
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text('Mark Day ${_currentDay + 1}\nComplete', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, height: 1.3)),
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

class _DailyDevotionalCard extends StatelessWidget {
  final String familyId;
  final ValueChanged<DevotionalEntry>? onTapToday;

  const _DailyDevotionalCard({required this.familyId, this.onTapToday});

  static const _notifId = 9901; // stable ID for daily devotional notification

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final family = provider.activeFamily;
    if (family == null) return const SizedBox.shrink();

    final enabled = family.dailyDevotionalEnabled;
    final hour = family.dailyDevotionalHour;
    final minute = family.dailyDevotionalMinute;
    final timeOfDay = TimeOfDay(hour: hour, minute: minute);
    final formattedTime = timeOfDay.format(context);

    // Check if today's devotional exists
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayEntry = enabled
        ? provider.db.devotionalEntries.cast<DevotionalEntry?>().firstWhere(
            (e) => e!.familyId == familyId &&
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
                const Icon(Icons.schedule_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Daily AI Devotional', style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white,
                  )),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch.adaptive(
                    value: enabled,
                    onChanged: (val) => _toggle(context, val, hour, minute),
                    activeColor: Colors.white,
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
                  ? 'A fresh devotional is generated and delivered to your family every day \u2014 even if the app is closed.'
                  : 'Enable to receive a fresh AI devotional at your chosen time each day.',
              style: TextStyle(
                fontFamily: 'Inter', fontSize: 12, height: 1.4,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            if (enabled) ...[
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
                          Text(formattedTime, style: const TextStyle(
                            fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white,
                          )),
                          const SizedBox(width: 6),
                          Icon(Icons.edit_rounded, size: 14, color: Colors.white.withValues(alpha: 0.7)),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (todayEntry != null)
                    GestureDetector(
                      onTap: () => onTapToday?.call(todayEntry),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Read Today\'s', style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF6366F1),
                        )),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        now.isBefore(DateTime(now.year, now.month, now.day, hour, minute))
                            ? 'Scheduled'
                            : 'Generating...',
                        style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.7),
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

  Future<void> _toggle(BuildContext context, bool val, int hour, int minute) async {
    final provider = context.read<AppProvider>();
    final family = provider.activeFamily!;
    final updated = family.copyWith(dailyDevotionalEnabled: val);
    final db = provider.db;
    provider.updateFamily(updated);
    await provider.saveAndSync(db.copyWith(
      families: db.families.map((f) => f.id == updated.id ? updated : f).toList(),
    ));

    if (val) {
      await _scheduleNotification(hour, minute);
    } else {
      await NotificationService.cancel(_notifId);
    }
  }

  Future<void> _pickTime(BuildContext context, TimeOfDay current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: 'Choose devotional delivery time',
    );
    if (picked == null || !context.mounted) return;

    final provider = context.read<AppProvider>();
    final family = provider.activeFamily!;
    final updated = family.copyWith(
      dailyDevotionalHour: picked.hour,
      dailyDevotionalMinute: picked.minute,
    );
    final db = provider.db;
    provider.updateFamily(updated);
    await provider.saveAndSync(db.copyWith(
      families: db.families.map((f) => f.id == updated.id ? updated : f).toList(),
    ));

    await _scheduleNotification(picked.hour, picked.minute);
  }

  static Future<void> _scheduleNotification(int hour, int minute) async {
    await NotificationService.cancel(_notifId);
    await NotificationService.scheduleDaily(
      id: _notifId,
      title: 'Daily Devotional Ready',
      body: 'Your family\u2019s AI devotional for today is here. Open to read and reflect together.',
      time: Time(hour, minute),
    );
  }
}

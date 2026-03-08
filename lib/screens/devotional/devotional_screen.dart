// lib/screens/devotional/devotional_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class DevotionalScreen extends StatefulWidget {
  const DevotionalScreen({super.key});

  @override
  State<DevotionalScreen> createState() => _DevotionalScreenState();
}

class _DevotionalScreenState extends State<DevotionalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DevotionalEntry? _selectedEntry;

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
      devotionalEntries:
          db.devotionalEntries.where((e) => e.id != id).toList(),
    ));
    if (_selectedEntry?.id == id) setState(() => _selectedEntry = null);
  }

  void _showAddDevotionalSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DevotionalFormSheet(
        onSave: (entry) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(
              devotionalEntries: [...db.devotionalEntries, entry]));
        },
      ),
    );
  }

  void _showAddReadingPlanSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddReadingPlanSheet(
        onSave: (plan) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(
              db.copyWith(readingPlans: [...db.readingPlans, plan]));
        },
      ),
    );
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
        .toList();
    entries.sort((a, b) => b.date.compareTo(a.date));

    if (_selectedEntry != null) {
      final fresh = entries
          .cast<DevotionalEntry?>()
          .firstWhere((e) => e?.id == _selectedEntry!.id, orElse: () => null);
      if (fresh == null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => setState(() => _selectedEntry = null));
      }
    }

    if (_selectedEntry != null) {
      return _EntryDetailView(
        entry: _selectedEntry!,
        onBack: () => setState(() => _selectedEntry = null),
        onDelete: () => _deleteEntry(_selectedEntry!.id),
      );
    }

    final plans = provider.db.readingPlans
        .where((p) => p.familyId == family.id)
        .toList();
    plans.sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
            const Text('FamilyHub', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary)),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(icon: const Icon(Icons.menu_rounded, color: AppTheme.stone500), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page Header ──
            PageHeader(
              title: 'Spiritual Growth',
              subtitle: 'Reflect, pray, and grow as a family.',
              actions: [
                ActionChipButton(
                  icon: Icons.add_rounded,
                  label: 'New Devotional',
                  onTap: _showAddDevotionalSheet,
                  isPrimary: true,
                ),
                ActionChipButton(
                  icon: Icons.menu_book_rounded,
                  label: 'New Reading Plan',
                  onTap: _showAddReadingPlanSheet,
                ),
              ],
            ),

            // ── Tab chips ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _tabController.index == 0 ? AppTheme.stone800 : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: _tabController.index == 0 ? null : Border.all(color: AppTheme.stone200),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Devotionals',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _tabController.index == 0 ? Colors.white : AppTheme.stone600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _tabController.index == 1 ? AppTheme.stone800 : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: _tabController.index == 1 ? null : Border.all(color: AppTheme.stone200),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Reading Plans',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _tabController.index == 1 ? Colors.white : AppTheme.stone600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── AI Faith Assistant card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD97706), Color(0xFFEA580C)],
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
                        const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        const Text(
                          'AI Faith Assistant',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Need inspiration? Tell me a topic (e.g., Patience, Hope, Forgiveness) and I\'ll draft a devotional.',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const TextField(
                        style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Enter a topic...',
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Shared', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white54),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Private', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Generate Now',
                            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFD97706)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Tab content ──
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // ── Tab 1: Devotionals ──────────────────────────────────
                  _DevotionalsTab(
                    entries: entries,
                    provider: provider,
                    onTap: (e) => setState(() => _selectedEntry = e),
                    onAdd: _showAddDevotionalSheet,
                  ),
                  // ── Tab 2: Reading Plans ────────────────────────────────
                  _ReadingPlansTab(
                    plans: plans,
                    provider: provider,
                    onAdd: _showAddReadingPlanSheet,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tab 1: Devotionals list
// ─────────────────────────────────────────────

class _DevotionalsTab extends StatelessWidget {
  final List<DevotionalEntry> entries;
  final AppProvider provider;
  final ValueChanged<DevotionalEntry> onTap;
  final VoidCallback onAdd;

  const _DevotionalsTab({
    required this.entries,
    required this.provider,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return EmptyState(
        emoji: '📖',
        title: 'No devotionals yet',
        subtitle: 'Share scripture and reflections with your family.',
        actionLabel: 'Add Devotional',
        onAction: onAdd,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final entry = entries[i];
        final author =
            provider.userById(entry.userId)?.name ?? 'Member';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => onTap(entry),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.stone100),
              ),
              child: Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                      child: Text('📖', style: TextStyle(fontSize: 22))),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(entry.title,
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppTheme.stone900)),
                      if (entry.scripture != null &&
                          entry.scripture!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(entry.scripture!,
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: AppTheme.primary,
                                fontStyle: FontStyle.italic)),
                      ],
                      const SizedBox(height: 4),
                      Text(
                          '${author.split(' ').first} · ${DateFormat('MMM d, y').format(entry.date)}',
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              color: AppTheme.stone400)),
                    ])),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.stone400),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Tab 2: Reading Plans list
// ─────────────────────────────────────────────

class _ReadingPlansTab extends StatefulWidget {
  final List<ReadingPlan> plans;
  final AppProvider provider;
  final VoidCallback onAdd;

  const _ReadingPlansTab({
    required this.plans,
    required this.provider,
    required this.onAdd,
  });

  @override
  State<_ReadingPlansTab> createState() => _ReadingPlansTabState();
}

class _ReadingPlansTabState extends State<_ReadingPlansTab> {
  final Set<String> _expanded = {};

  Future<void> _toggleEntry(ReadingPlan plan, int entryIndex) async {
    final updatedEntries = List<ReadingPlanEntry>.from(plan.entries);
    updatedEntries[entryIndex] = updatedEntries[entryIndex]
        .copyWith(completed: !updatedEntries[entryIndex].completed);
    final updatedPlan = plan.copyWith(entries: updatedEntries);

    final provider = widget.provider;
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      readingPlans: db.readingPlans
          .map((p) => p.id == plan.id ? updatedPlan : p)
          .toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.plans.isEmpty) {
      return EmptyState(
        emoji: '📚',
        title: 'No reading plans yet',
        subtitle: 'Create a reading plan or generate one with AI.',
        actionLabel: 'Add Reading Plan',
        onAction: widget.onAdd,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: widget.plans.length,
      itemBuilder: (ctx, i) {
        final plan = widget.plans[i];
        final isExpanded = _expanded.contains(plan.id);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.stone100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan header
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() {
                    if (isExpanded) {
                      _expanded.remove(plan.id);
                    } else {
                      _expanded.add(plan.id);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(plan.title,
                                style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: AppTheme.stone900)),
                          ),
                          Icon(
                            isExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            color: AppTheme.stone400,
                          ),
                        ]),
                        if (plan.description != null &&
                            plan.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(plan.description!,
                              style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  color: AppTheme.stone500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: plan.progress,
                              backgroundColor: AppTheme.stone100,
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(4),
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Day ${plan.completedCount} of ${plan.entries.length}',
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.stone500),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
                // Expanded entries
                if (isExpanded) ...[
                  const Divider(height: 1, color: AppTheme.stone100),
                  ...plan.entries.asMap().entries.map((e) {
                    final idx = e.key;
                    final entry = e.value;
                    return _ReadingPlanEntryTile(
                      entry: entry,
                      onToggle: () => _toggleEntry(plan, idx),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReadingPlanEntryTile extends StatelessWidget {
  final ReadingPlanEntry entry;
  final VoidCallback onToggle;

  const _ReadingPlanEntryTile({required this.entry, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: entry.completed
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : AppTheme.stone50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: entry.completed ? AppTheme.primary : AppTheme.stone200,
              ),
            ),
            child: Center(
              child: Text(
                '${entry.day}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color:
                      entry.completed ? AppTheme.primary : AppTheme.stone500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: entry.completed
                        ? AppTheme.stone400
                        : AppTheme.stone900,
                    decoration:
                        entry.completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (entry.scripture != null && entry.scripture!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.scripture!,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppTheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Checkbox(
            value: entry.completed,
            onChanged: (_) => onToggle(),
            activeColor: AppTheme.primary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Detail view
// ─────────────────────────────────────────────

class _EntryDetailView extends StatelessWidget {
  final DevotionalEntry entry;
  final VoidCallback onBack;
  final VoidCallback onDelete;

  const _EntryDetailView(
      {required this.entry, required this.onBack, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
        title: const Text('Devotional'),
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: onDelete,
              color: AppTheme.error),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.title,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  color: AppTheme.stone900)),
          const SizedBox(height: 6),
          Text(DateFormat('EEEE, MMMM d, y').format(entry.date),
              style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
          if (entry.scripture != null && entry.scripture!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border(
                    left: BorderSide(color: AppTheme.primary, width: 4)),
              ),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SCRIPTURE',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                        letterSpacing: 1.1)),
                const SizedBox(height: 6),
                Text(entry.scripture!,
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.stone700,
                        height: 1.5)),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.stone50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.stone100),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('REFLECTION',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.stone400,
                      letterSpacing: 1.1)),
              const SizedBox(height: 8),
              Text(entry.content ?? '',
                  style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      color: AppTheme.stone800,
                      height: 1.6)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Add devotional form
// ─────────────────────────────────────────────

class _DevotionalFormSheet extends StatefulWidget {
  final Future<void> Function(DevotionalEntry) onSave;
  const _DevotionalFormSheet({required this.onSave});

  @override
  State<_DevotionalFormSheet> createState() => _DevotionalFormSheetState();
}

class _DevotionalFormSheetState extends State<_DevotionalFormSheet> {
  final _titleCtrl = TextEditingController();
  final _scriptureCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  bool _isAiGenerating = false;
  List<String> _reflectionPrompts = [];
  String? _prayer;
  final _uuid = const Uuid();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _scriptureCtrl.dispose();
    _contentCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _aiGenerate() async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) return;
    setState(() => _isAiGenerating = true);

    final familyId = context.read<AppProvider>().activeFamily?.id ?? '';
    final prompt = '''
You are a family devotional writer for a Christian family app. Always respond with valid JSON only, no markdown fences.

Create a family devotional about "$topic". Return a JSON object with:
- "title" (string)
- "scripture" (string, e.g. "John 3:16")
- "content" (string, encouraging message 2-3 paragraphs)
- "reflectionPrompts" (array of 3 strings, questions for family discussion)
- "prayer" (string, a closing prayer)
''';

    try {
      final raw = await AiService.ask(prompt: prompt, feature: 'ai_devotional', familyId: familyId);
      if (raw == null || !mounted) {
        if (mounted) setState(() => _isAiGenerating = false);
        return;
      }
      var cleaned = raw.trim();
      if (cleaned.startsWith('```')) cleaned = cleaned.substring(cleaned.indexOf('\n') + 1);
      if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.lastIndexOf('```'));
      cleaned = cleaned.trim();

      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        setState(() {
          _titleCtrl.text = decoded['title']?.toString() ?? topic;
          _scriptureCtrl.text = decoded['scripture']?.toString() ?? '';
          _contentCtrl.text = decoded['content']?.toString() ?? '';
          if (decoded['reflectionPrompts'] is List) {
            _reflectionPrompts = (decoded['reflectionPrompts'] as List).map((e) => e.toString()).toList();
          }
          _prayer = decoded['prayer']?.toString();
          _isAiGenerating = false;
        });
      } else {
        setState(() => _isAiGenerating = false);
      }
    } catch (e) {
      debugPrint('[Devotional] AI generate error: $e');
      if (mounted) setState(() => _isAiGenerating = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty || _contentCtrl.text.trim().isEmpty)
      return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final entry = DevotionalEntry(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      userId: provider.activeUser!.id,
      title: _titleCtrl.text.trim(),
      content: _contentCtrl.text.trim(),
      scripture: _scriptureCtrl.text.trim().isEmpty
          ? null
          : _scriptureCtrl.text.trim(),
      reflectionPrompts: _reflectionPrompts,
      prayer: _prayer,
      tags: _topicCtrl.text.trim().isNotEmpty ? [_topicCtrl.text.trim()] : [],
      date: _date,
    );
    await widget.onSave(entry);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('New Devotional',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: AppTheme.stone900)),
                  TextButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
          ),
          Expanded(
            child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  // AI Generation section
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.auto_awesome, size: 16, color: Colors.white),
                          SizedBox(width: 8),
                          Text('AI Devotional Generator', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                        ]),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: TextField(
                            controller: _topicCtrl,
                            style: const TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: 'e.g. Gratitude, Faith in Hard Times...',
                              hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Inter'),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: _isAiGenerating ? null : _aiGenerate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                              child: _isAiGenerating
                                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)))
                                  : const Text('Generate', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF8B5CF6))),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                      controller: _titleCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                          labelText: 'Title *',
                          prefixIcon: Icon(Icons.title_rounded))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _scriptureCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                          labelText: 'Scripture Reference (optional)',
                          prefixIcon: Icon(Icons.menu_book_rounded))),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contentCtrl,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Content / Reflection *',
                        alignLabelWithHint: true),
                  ),
                  if (_reflectionPrompts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Reflection Questions', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone900)),
                    const SizedBox(height: 6),
                    ...List.generate(_reflectionPrompts.length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${i + 1}. ', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.primary)),
                        Expanded(child: Text(_reflectionPrompts[i], style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone700))),
                      ]),
                    )),
                  ],
                  if (_prayer != null && _prayer!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Prayer', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone900)),
                    const SizedBox(height: 6),
                    Text(_prayer!, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontStyle: FontStyle.italic, color: AppTheme.stone600)),
                  ],
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                          color: AppTheme.stone50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.stone200)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 18, color: AppTheme.stone500),
                        const SizedBox(width: 10),
                        Text(DateFormat('EEE, MMM d, y').format(_date),
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: AppTheme.stone800)),
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

// ─────────────────────────────────────────────
// Add Reading Plan sheet
// ─────────────────────────────────────────────

class _AddReadingPlanSheet extends StatefulWidget {
  final Future<void> Function(ReadingPlan) onSave;
  const _AddReadingPlanSheet({required this.onSave});

  @override
  State<_AddReadingPlanSheet> createState() => _AddReadingPlanSheetState();
}

class _AddReadingPlanSheetState extends State<_AddReadingPlanSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();

  final List<ReadingPlanEntry> _entries = [];
  bool _isGenerating = false;
  bool _isSaving = false;
  String? _generateError;
  final _uuid = const Uuid();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateWithAI() async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) {
      setState(() => _generateError = 'Enter a topic to generate a plan.');
      return;
    }
    setState(() {
      _isGenerating = true;
      _generateError = null;
    });

    try {
      final familyId = context.read<AppProvider>().activeFamily?.id ?? '';
      final response = await AiService.ask(
        prompt:
            'Generate a 7-day devotional reading plan on $topic. Return JSON with fields: title, description, entries (array of {day, title, scripture, content})',
        feature: 'ai_devotional',
        familyId: familyId,
      );

      if (response == null) {
        setState(() => _generateError = 'No response from AI. Try again.');
        return;
      }

      // Extract JSON from response
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1) {
        setState(() => _generateError = 'Could not parse AI response.');
        return;
      }

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final generatedEntries = (data['entries'] as List? ?? [])
          .map((e) => ReadingPlanEntry(
                day: (e['day'] as num).toInt(),
                title: e['title'] as String? ?? 'Day ${e['day']}',
                scripture: e['scripture'] as String?,
                content: e['content'] as String?,
                completed: false,
              ))
          .toList();

      setState(() {
        if (_titleCtrl.text.trim().isEmpty) {
          _titleCtrl.text = data['title'] as String? ?? topic;
        }
        if (_descCtrl.text.trim().isEmpty) {
          _descCtrl.text = data['description'] as String? ?? '';
        }
        _entries
          ..clear()
          ..addAll(generatedEntries);
      });
    } catch (e) {
      setState(() => _generateError = 'Failed to generate plan: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _addManualEntry() {
    final dayNum = _entries.length + 1;
    setState(() {
      _entries.add(ReadingPlanEntry(
        day: dayNum,
        title: 'Day $dayNum',
        completed: false,
      ));
    });
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final plan = ReadingPlan(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      creatorId: provider.activeUser!.id,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      createdAt: DateTime.now(),
    );
    await widget.onSave(plan);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('New Reading Plan',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: AppTheme.stone900)),
                  TextButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
          ),
          Expanded(
            child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  TextField(
                    controller: _titleCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Plan Title *',
                        prefixIcon: Icon(Icons.bookmark_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 16),
                  // AI Generation section
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        const Icon(Icons.auto_awesome_rounded,
                            size: 18, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        const Text('Generate with AI',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppTheme.primary)),
                      ]),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _topicCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                            labelText: 'Topic (e.g. "Faith and Trust")',
                            prefixIcon: Icon(Icons.lightbulb_outline_rounded)),
                      ),
                      const SizedBox(height: 10),
                      if (_generateError != null) ...[
                        Text(_generateError!,
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: AppTheme.error)),
                        const SizedBox(height: 8),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isGenerating ? null : _generateWithAI,
                          icon: _isGenerating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.auto_awesome_rounded,
                                  size: 18),
                          label: Text(_isGenerating
                              ? 'Generating...'
                              : 'Generate 7-Day Plan'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  // Entries list
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            'Entries (${_entries.length})',
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppTheme.stone800)),
                        TextButton.icon(
                          onPressed: _addManualEntry,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add Entry'),
                        ),
                      ]),
                  ..._entries.asMap().entries.map((e) {
                    final idx = e.key;
                    final entry = e.value;
                    return _ManualEntryRow(
                      entry: entry,
                      onUpdate: (updated) {
                        setState(() => _entries[idx] = updated);
                      },
                      onRemove: () {
                        setState(() {
                          _entries.removeAt(idx);
                          // Renumber
                          for (int j = 0; j < _entries.length; j++) {
                            _entries[j] = _entries[j].copyWith(day: j + 1);
                          }
                        });
                      },
                    );
                  }),
                  if (_entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Generate with AI or add entries manually.',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: AppTheme.stone400),
                        ),
                      ),
                    ),
                ]),
          ),
        ]),
      ),
    );
  }
}

class _ManualEntryRow extends StatefulWidget {
  final ReadingPlanEntry entry;
  final ValueChanged<ReadingPlanEntry> onUpdate;
  final VoidCallback onRemove;

  const _ManualEntryRow({
    required this.entry,
    required this.onUpdate,
    required this.onRemove,
  });

  @override
  State<_ManualEntryRow> createState() => _ManualEntryRowState();
}

class _ManualEntryRowState extends State<_ManualEntryRow> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _scriptureCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.entry.title);
    _scriptureCtrl =
        TextEditingController(text: widget.entry.scripture ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _scriptureCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onUpdate(widget.entry.copyWith(
      title: _titleCtrl.text,
      scripture:
          _scriptureCtrl.text.trim().isEmpty ? null : _scriptureCtrl.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.stone50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.stone200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text('${widget.entry.day}',
                  style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary)),
            ),
          ),
          const SizedBox(width: 8),
          const Text('Day entry',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.stone600)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppTheme.stone400),
            onPressed: widget.onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _titleCtrl,
          onChanged: (_) => _notify(),
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Title', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _scriptureCtrl,
          onChanged: (_) => _notify(),
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Scripture (optional)', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),
      ]),
    );
  }
}

// lib/screens/ai_history/ai_history_screen.dart
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/cloud_sync_scope.dart';
import '../../config/module_config.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/huddle_module_scaffold.dart';
import '../../widgets/module_ui_kit.dart';
import '../../utils/debounce.dart';

class AIHistoryScreen extends StatefulWidget {
  const AIHistoryScreen({super.key});

  @override
  State<AIHistoryScreen> createState() => _AIHistoryScreenState();
}

class _AIHistoryScreenState extends State<AIHistoryScreen> {
  String? _selectedModule; // null = show all
  final _searchCtrl = TextEditingController();
  final _searchDebounce = Debouncer();
  String _searchQuery = '';

  bool _canManageEntry(AppProvider provider, AIHistoryEntry entry) {
    final userId = provider.activeUser?.id;
    return userId != null && entry.userId == userId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppProvider>().scheduleModuleEnterCloudPull({
        CloudSyncScope.aiHistory,
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _deleteEntry(String id) async {
    HapticFeedback.mediumImpact();
    final provider = context.read<AppProvider>();
    final entry = provider.db.aiHistory.cast<AIHistoryEntry?>().firstWhere(
      (e) => e?.id == id,
      orElse: () => null,
    );
    if (entry == null || !_canManageEntry(provider, entry)) {
      if (mounted) _showSnack('Only your own AI history entries can be deleted.');
      return;
    }
    final db = provider.db;
    await provider.saveAndSync(
      db.copyWith(aiHistory: db.aiHistory.where((e) => e.id != id).toList()),
      pushTableScope: {CloudSyncScope.aiHistory},
    );
    if (mounted) _showSnack('Entry deleted');
  }

  void _openDetail(BuildContext context, AIHistoryEntry entry, Color color) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EntryDetailSheet(
        entry: entry,
        moduleColor: color,
        onDelete: () => _deleteEntry(entry.id),
      ),
    );
  }

  Color _moduleColor(String module) {
    final m = module.toLowerCase();
    final colors = {
      'chat': AppTheme.primary,
      'tasks': AppTheme.success,
      'ai_tasks': AppTheme.success,
      'meals': AppTheme.warning,
      'ai_recipes': AppTheme.warning,
      'fitness': AppTheme.error,
      'ai_fitness': AppTheme.error,
      'devotional': const Color(0xFF059669),
      'ai_devotional': const Color(0xFF059669),
      'budget': const Color(0xFF0EA5E9),
      'ai_budget': const Color(0xFF0EA5E9),
      'dashboard': const Color(0xFF6366F1),
      'ai_motivation': const Color(0xFF6366F1),
      'calendar': const Color(0xFF8B5CF6),
      'ai_events': const Color(0xFF8B5CF6),
      'lists': const Color(0xFF06B6D4),
      'ai_lists': const Color(0xFF06B6D4),
    };
    return colors[m] ?? AppTheme.stone500;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const ModuleFamilyLoadingScaffold();
    }

    final allEntries = provider.db.aiHistory
        .where((e) => e.familyId == family.id && e.userId == user.id)
        .toList();
    allEntries.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Collect unique modules
    final modules = allEntries.map((e) => e.module).toSet().toList()..sort();

    var shown = _selectedModule == null
        ? allEntries
        : allEntries.where((e) => e.module == _selectedModule).toList();
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      shown = shown
          .where((e) =>
              e.prompt.toLowerCase().contains(q) ||
              e.response.toLowerCase().contains(q) ||
              e.module.toLowerCase().contains(q))
          .toList();
    }

    return HuddleModuleScaffold(
      modulePath: '/ai-history',
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const MainAppBar(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: screenTitleForModulePath('/ai-history'),
              subtitle: 'Your AI interactions & responses',
              actions: [
                if (allEntries.isNotEmpty)
                  ActionChipButton(
                    icon: Icons.delete_sweep_rounded,
                    label: 'Clear All',
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Clear All History'),
                          content: const Text('This will remove all AI history for you. Continue?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear', style: TextStyle(color: AppTheme.error))),
                          ],
                        ),
                      );
                      if (confirm == true && mounted) {
                        final prov = context.read<AppProvider>();
                        final db = prov.db;
                        await prov.saveAndSync(
                          db.copyWith(
                            aiHistory: db.aiHistory.where((e) => e.userId != user.id).toList(),
                          ),
                          pushTableScope: {CloudSyncScope.aiHistory},
                        );
                        if (mounted) _showSnack('History cleared');
                      }
                    },
                    backgroundColor: AppTheme.error.withValues(alpha: 0.1),
                    foregroundColor: AppTheme.error,
                  ),
              ],
            ),
            if (allEntries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) {
                    _searchDebounce.run(() {
                      if (!mounted) return;
                      setState(() => _searchQuery = v);
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search prompts and responses…',
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.stone200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.stone200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primary),
                    ),
                  ),
                ),
              ),
            // Stats row
            if (allEntries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(children: [
                  _MiniStat(icon: Icons.auto_awesome_rounded, color: AppTheme.primary, value: '${allEntries.length}', label: 'Prompts'),
                  const SizedBox(width: 10),
                  _MiniStat(icon: Icons.category_rounded, color: const Color(0xFF8B5CF6), value: '${modules.length}', label: 'Modules'),
                  const SizedBox(width: 10),
                  _MiniStat(
                    icon: Icons.calendar_today_rounded,
                    color: const Color(0xFF0EA5E9),
                    value: '${allEntries.where((e) => e.createdAt.month == DateTime.now().month && e.createdAt.year == DateTime.now().year).length}',
                    label: 'This Month',
                  ),
                ]),
              ),
            // Module filter chips
            if (modules.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  itemCount: 1 + modules.length,
                  cacheExtent: 120, // FIXED: horizontal chip list uses builder
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: const Text('All'),
                          selected: _selectedModule == null,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedModule = null);
                          },
                          showCheckmark: false,
                        ),
                      );
                    }
                    final m = modules[i - 1];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(m),
                        selected: _selectedModule == m,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedModule = m);
                        },
                        showCheckmark: false,
                      ),
                    );
                  },
                ),
              ),
            const SectionHeader(title: 'History'),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OnboardingCard(
                  emoji: '\u{1F916}',
                  title: 'No AI history',
                  bullets: [
                    'Your AI interactions will appear here',
                    'Use AI features across the app to generate history',
                    'Review past prompts and responses',
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: shown.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _HistoryCard(
                      entry: entry,
                      moduleColor: _moduleColor(entry.module),
                      onTap: () => _openDetail(context, entry, _moduleColor(entry.module)),
                      onDelete: _canManageEntry(provider, entry)
                          ? () => _deleteEntry(entry.id)
                          : null,
                    ),
                  )).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final AIHistoryEntry entry;
  final Color moduleColor;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _HistoryCard({
    required this.entry,
    required this.moduleColor,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(entry.id),
      direction: onDelete != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        if (onDelete == null) return false;
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Entry'),
            content: const Text('Delete this AI history entry?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete?.call(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.stone100),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: moduleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('🤖', style: TextStyle(fontSize: 18))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: moduleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(entry.module, style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: moduleColor)),
                ),
                const Spacer(),
                Text(DateFormat('MMM d, h:mm a').format(entry.createdAt), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
              ]),
              const SizedBox(height: 6),
              Text(
                entry.prompt,
                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone900),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                entry.response,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
            ])),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Detail bottom sheet
// ─────────────────────────────────────────────

class _EntryDetailSheet extends StatelessWidget {
  final AIHistoryEntry entry;
  final Color moduleColor;
  final VoidCallback? onDelete;

  const _EntryDetailSheet({
    required this.entry,
    required this.moduleColor,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: moduleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  entry.module,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: moduleColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  DateFormat('MMM d, y · h:mm a').format(entry.createdAt),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: AppTheme.stone400,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.error),
                onPressed: onDelete == null ? null : () async {
                  HapticFeedback.mediumImpact();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Entry'),
                      content: const Text('Delete this AI history entry?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    if (context.mounted) Navigator.pop(context);
                    onDelete?.call();
                  }
                },
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Prompt section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(16),
                        border: const Border(
                            left: BorderSide(
                                color: AppTheme.primary, width: 4)),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Text('👤',
                                  style: TextStyle(fontSize: 13)),
                              SizedBox(width: 6),
                              Text('YOUR PROMPT',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primary,
                                    letterSpacing: 1.1,
                                  )),
                            ]),
                            const SizedBox(height: 8),
                            SelectableText(
                              entry.prompt,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: AppTheme.stone900,
                                height: 1.55,
                              ),
                            ),
                          ]),
                    ),
                    const SizedBox(height: 16),
                    // Response section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.stone50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.stone100),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Text('🤖',
                                  style: TextStyle(fontSize: 13)),
                              const SizedBox(width: 6),
                              const Text('AI RESPONSE',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.stone400,
                                    letterSpacing: 1.1,
                                  )),
                              const Spacer(),
                              // Copy button
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Clipboard.setData(ClipboardData(
                                      text: entry.response));
                                  ScaffoldMessenger.of(context)
                                    ..clearSnackBars()
                                    ..showSnackBar(SnackBar(
                                      content: const Text('Response copied!', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      duration: const Duration(seconds: 2),
                                    ));
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: moduleColor.withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                            Icons.copy_rounded,
                                            size: 12,
                                            color: moduleColor),
                                        const SizedBox(width: 4),
                                        Text('Copy',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: moduleColor,
                                            )),
                                      ]),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            SelectableText(
                              entry.response,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: AppTheme.stone800,
                                height: 1.65,
                              ),
                            ),
                          ]),
                    ),
                  ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _MiniStat({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.stone900)),
            Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone500)),
          ]),
        ]),
      ),
    );
  }
}

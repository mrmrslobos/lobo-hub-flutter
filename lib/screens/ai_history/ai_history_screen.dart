// lib/screens/ai_history/ai_history_screen.dart
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class AIHistoryScreen extends StatefulWidget {
  const AIHistoryScreen({super.key});

  @override
  State<AIHistoryScreen> createState() => _AIHistoryScreenState();
}

class _AIHistoryScreenState extends State<AIHistoryScreen> {
  String? _selectedModule; // null = show all

  Future<void> _deleteEntry(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      aiHistory: db.aiHistory.where((e) => e.id != id).toList(),
    ));
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
    final colors = {
      'chat': AppTheme.primary,
      'tasks': AppTheme.success,
      'meals': AppTheme.warning,
      'fitness': AppTheme.error,
      'devotional': const Color(0xFF059669),
      'budget': const Color(0xFF0EA5E9),
    };
    return colors[module.toLowerCase()] ?? AppTheme.stone500;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final allEntries = provider.db.aiHistory
        .where((e) => e.familyId == family.id && e.userId == user.id)
        .toList();
    allEntries.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Collect unique modules
    final modules = allEntries.map((e) => e.module).toSet().toList()..sort();

    final shown = _selectedModule == null
        ? allEntries
        : allEntries.where((e) => e.module == _selectedModule).toList();

    return Scaffold(
      drawer: const AppDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('AI History'),
            floating: true,
            actions: [
              if (allEntries.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  onPressed: () async {
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
                      await prov.saveAndSync(db.copyWith(
                        aiHistory: db.aiHistory.where((e) => e.userId != user.id).toList(),
                      ));
                    }
                  },
                  tooltip: 'Clear all',
                  color: AppTheme.error,
                ),
            ],
          ),
          // Module filter chips
          if (modules.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: _selectedModule == null,
                        onSelected: (_) => setState(() => _selectedModule = null),
                        showCheckmark: false,
                      ),
                    ),
                    ...modules.map((m) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(m),
                            selected: _selectedModule == m,
                            onSelected: (_) => setState(() => _selectedModule = m),
                            showCheckmark: false,
                          ),
                        )),
                  ],
                ),
              ),
            ),
          shown.isEmpty
              ? SliverFillRemaining(
                  child: EmptyState(
                    emoji: '🤖',
                    title: 'No AI history',
                    subtitle: 'Your AI interactions will appear here.',
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final entry = shown[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _HistoryCard(
                            entry: entry,
                            moduleColor: _moduleColor(entry.module),
                            onTap: () => _openDetail(context, entry, _moduleColor(entry.module)),
                            onDelete: () => _deleteEntry(entry.id),
                          ),
                        );
                      },
                      childCount: shown.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final AIHistoryEntry entry;
  final Color moduleColor;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryCard({
    required this.entry,
    required this.moduleColor,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
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
              decoration: BoxDecoration(color: moduleColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('🤖', style: TextStyle(fontSize: 18))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: moduleColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
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
  final VoidCallback onDelete;

  const _EntryDetailSheet({
    required this.entry,
    required this.moduleColor,
    required this.onDelete,
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
                  color: moduleColor.withOpacity(0.1),
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
                onPressed: () {
                  Navigator.pop(context);
                  onDelete();
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
                                  Clipboard.setData(ClipboardData(
                                      text: entry.response));
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                    content: Text('Response copied!'),
                                    duration: Duration(seconds: 2),
                                  ));
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: moduleColor.withOpacity(0.1),
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

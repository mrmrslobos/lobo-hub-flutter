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
// Detail view
// ─────────────────────────────────────────────

class _EntryDetailView extends StatelessWidget {
  final AIHistoryEntry entry;
  final Color moduleColor;
  final VoidCallback onBack;
  final VoidCallback onDelete;

  const _EntryDetailView({
    required this.entry,
    required this.moduleColor,
    required this.onBack,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
        title: const Text('AI Response'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: onDelete, color: AppTheme.error),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: moduleColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(entry.module, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: moduleColor)),
            ),
            const SizedBox(width: 10),
            Text(DateFormat('MMM d, y · h:mm a').format(entry.createdAt), style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
          ]),
          const SizedBox(height: 16),
          // Prompt
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: AppTheme.primary, width: 4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Text('👤', style: TextStyle(fontSize: 14)),
                SizedBox(width: 6),
                Text('PROMPT', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.primary, letterSpacing: 1.1)),
              ]),
              const SizedBox(height: 8),
              Text(entry.prompt, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, color: AppTheme.stone900, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 16),
          // Response
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.stone50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.stone100),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Text('🤖', style: TextStyle(fontSize: 14)),
                SizedBox(width: 6),
                Text('RESPONSE', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
              ]),
              const SizedBox(height: 8),
              Text(entry.response, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, color: AppTheme.stone800, height: 1.6)),
            ]),
          ),
        ]),
      ),
    );
  }
}

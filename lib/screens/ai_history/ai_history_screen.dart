import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../config/theme.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class AiHistoryScreen extends StatefulWidget {
  const AiHistoryScreen({super.key});
  @override
  State<AiHistoryScreen> createState() => _AiHistoryScreenState();
}

class _AiHistoryScreenState extends State<AiHistoryScreen> {
  String? _filterModule;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final userId = provider.activeUser?.id ?? '';
    final all = provider.db.aiHistory
        .where((e) => e.userId == userId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final modules = all.map((e) => e.module).toSet().toList()..sort();
    final filtered = _filterModule != null ? all.where((e) => e.module == _filterModule).toList() : all;

    return Scaffold(
      appBar: AppBar(
        leading: Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.menu_rounded), onPressed: () => Scaffold.of(ctx).openDrawer())),
        title: const Text('AI History'),
        actions: [
          if (all.isNotEmpty) IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear all',
            onPressed: () => _confirmClearAll(context, provider),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: filtered.isEmpty
          ? const EmptyState(emoji: '🤖', title: 'No AI history', subtitle: 'Use AI features across the app to see your history here')
          : Column(children: [
              if (modules.length > 1) SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  IndigoChip(label: 'All', selected: _filterModule == null, onTap: () => setState(() => _filterModule = null)),
                  const SizedBox(width: 6),
                  ...modules.map((m) => Padding(padding: const EdgeInsets.only(right: 6), child: IndigoChip(label: m, selected: _filterModule == m, onTap: () => setState(() => _filterModule = _filterModule == m ? null : m)))),
                ]),
              ),
              Expanded(child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _HistoryCard(
                  entry: filtered[i],
                  onTap: () => _showDetail(ctx, filtered[i], provider),
                  onDelete: () async {
                    final newDb = provider.db.copyWith(aiHistory: provider.db.aiHistory.where((e) => e.id != filtered[i].id).toList());
                    await provider.saveAndSync(newDb);
                  },
                ),
              )),
            ]),
    );
  }

  void _showDetail(BuildContext context, AIHistoryEntry entry, AppProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7, maxChildSize: 0.95, expand: false,
        builder: (_, ctrl) => SingleChildScrollView(controller: ctrl, padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SheetHandle(),
          Row(children: [
            _ModuleBadge(module: entry.module),
            const Spacer(),
            Text(_fmtDate(entry.createdAt), style: const TextStyle(fontSize: 12, color: AppTheme.stone400)),
          ]),
          const SizedBox(height: 12),
          Text('Prompt', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppTheme.stone400)),
          const SizedBox(height: 4),
          SelectableText(entry.prompt, style: Theme.of(context).textTheme.bodyMedium),
          const Divider(height: 24),
          Row(children: [
            Text('Response', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppTheme.stone400)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 14),
              label: const Text('Copy'),
              onPressed: () { Clipboard.setData(ClipboardData(text: entry.response)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!'))); },
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
            ),
          ]),
          const SizedBox(height: 4),
          SelectableText(entry.response, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
        ])),
      ),
    );
  }

  void _confirmClearAll(BuildContext context, AppProvider provider) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Clear AI History?'),
      content: const Text('This will delete all your AI history. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
          onPressed: () async {
            final userId = provider.activeUser?.id ?? '';
            final newDb = provider.db.copyWith(aiHistory: provider.db.aiHistory.where((e) => e.userId != userId).toList());
            await provider.saveAndSync(newDb);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Clear All'),
        ),
      ],
    ));
  }

  static String _fmtDate(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dt.month-1]} ${dt.day}, ${dt.year}';
  }
}

class _HistoryCard extends StatelessWidget {
  final AIHistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _HistoryCard({required this.entry, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final date = '${m[entry.createdAt.month-1]} ${entry.createdAt.day}';
    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _ModuleBadge(module: entry.module),
            const Spacer(),
            Text(date, style: const TextStyle(fontSize: 11, color: AppTheme.stone400)),
          ]),
          const SizedBox(height: 8),
          Text(entry.prompt, style: Theme.of(context).textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(entry.response, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      ),
    );
  }
}

class _ModuleBadge extends StatelessWidget {
  final String module;
  const _ModuleBadge({required this.module});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(8)),
      child: Text(module, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
    );
  }
}

// lib/screens/devotional/devotional_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class DevotionalScreen extends StatefulWidget {
  const DevotionalScreen({super.key});

  @override
  State<DevotionalScreen> createState() => _DevotionalScreenState();
}

class _DevotionalScreenState extends State<DevotionalScreen> {
  DevotionalEntry? _selectedEntry;

  Future<void> _deleteEntry(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      devotionalEntries: db.devotionalEntries.where((e) => e.id != id).toList(),
    ));
    if (_selectedEntry?.id == id) setState(() => _selectedEntry = null);
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DevotionalFormSheet(
        onSave: (entry) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(devotionalEntries: [...db.devotionalEntries, entry]));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final family = provider.activeFamily;
    if (family == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final entries = provider.db.devotionalEntries
        .where((e) => e.familyId == family.id)
        .toList();
    entries.sort((a, b) => b.date.compareTo(a.date));

    if (_selectedEntry != null) {
      final fresh = entries.cast<DevotionalEntry?>().firstWhere((e) => e?.id == _selectedEntry!.id, orElse: () => null);
      if (fresh == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _selectedEntry = null));
      }
    }

    if (_selectedEntry != null) {
      return _EntryDetailView(
        entry: _selectedEntry!,
        onBack: () => setState(() => _selectedEntry = null),
        onDelete: () => _deleteEntry(_selectedEntry!.id),
      );
    }

    return Scaffold(
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.add_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(title: Text('Devotional'), floating: true),
          entries.isEmpty
              ? SliverFillRemaining(
                  child: EmptyState(
                    emoji: '📖',
                    title: 'No devotionals yet',
                    subtitle: 'Share scripture and reflections with your family.',
                    actionLabel: 'Add Devotional',
                    onAction: _showAddSheet,
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final entry = entries[i];
                        final author = provider.userById(entry.userId)?.name ?? 'Member';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedEntry = entry),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.stone100),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 46, height: 46,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)]),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Center(child: Text('📖', style: TextStyle(fontSize: 22))),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(entry.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900)),
                                  if (entry.scripture != null && entry.scripture!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(entry.scripture!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.primary, fontStyle: FontStyle.italic)),
                                  ],
                                  const SizedBox(height: 4),
                                  Text('${author.split(' ').first} · ${DateFormat('MMM d, y').format(entry.date)}',
                                      style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                                ])),
                                const Icon(Icons.chevron_right_rounded, color: AppTheme.stone400),
                              ]),
                            ),
                          ),
                        );
                      },
                      childCount: entries.length,
                    ),
                  ),
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

  const _EntryDetailView({required this.entry, required this.onBack, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
        title: const Text('Devotional'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: onDelete, color: AppTheme.error),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 24, color: AppTheme.stone900)),
          const SizedBox(height: 6),
          Text(DateFormat('EEEE, MMMM d, y').format(entry.date),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
          if (entry.scripture != null && entry.scripture!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border(left: BorderSide(color: AppTheme.primary, width: 4)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SCRIPTURE', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.primary, letterSpacing: 1.1)),
                const SizedBox(height: 6),
                Text(entry.scripture!, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontStyle: FontStyle.italic, color: AppTheme.stone700, height: 1.5)),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('REFLECTION', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              Text(entry.content, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, color: AppTheme.stone800, height: 1.6)),
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
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  final _uuid = const Uuid();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _scriptureCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
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
    if (_titleCtrl.text.trim().isEmpty || _contentCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final entry = DevotionalEntry(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      userId: provider.activeUser!.id,
      title: _titleCtrl.text.trim(),
      content: _contentCtrl.text.trim(),
      scripture: _scriptureCtrl.text.trim().isEmpty ? null : _scriptureCtrl.text.trim(),
      date: _date,
    );
    await widget.onSave(entry);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('New Devotional', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
              TextButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
              TextField(controller: _titleCtrl, autofocus: true, textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Title *', prefixIcon: Icon(Icons.title_rounded))),
              const SizedBox(height: 12),
              TextField(controller: _scriptureCtrl, textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Scripture Reference (optional)', prefixIcon: Icon(Icons.menu_book_rounded))),
              const SizedBox(height: 12),
              TextField(
                controller: _contentCtrl,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Content / Reflection *', alignLabelWithHint: true),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.stone200)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.stone500),
                    const SizedBox(width: 10),
                    Text(DateFormat('EEE, MMM d, y').format(_date), style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone800)),
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

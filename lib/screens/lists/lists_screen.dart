// lib/screens/lists/lists_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart' hide Visibility;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  ShoppingList? _selectedList;

  Future<void> _createList(String name, {Visibility visibility = Visibility.FAMILY, List<String> sharedWith = const []}) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final list = ShoppingList(
      id: const Uuid().v4(),
      familyId: provider.activeFamily!.id,
      creatorId: provider.activeUser!.id,
      title: name,
      items: [],
      visibility: visibility,
      sharedWith: sharedWith,
    );
    final updated = [...db.shoppingLists, list];
    await provider.saveAndSync(db.copyWith(shoppingLists: updated));
    if (visibility != Visibility.PRIVATE) {
      NotificationService.notifyFamilyActivity(
        title: 'New List Created',
        body: '${provider.activeUser?.name ?? "Someone"} created: ${list.title}',
      );
    }
    setState(() => _selectedList = list);
  }

  Future<void> _deleteList(ShoppingList list) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      shoppingLists: db.shoppingLists.where((l) => l.id != list.id).toList(),
    ));
    if (_selectedList?.id == list.id) setState(() => _selectedList = null);
  }

  Future<void> _addItem(ShoppingList list, String name) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final newItem = ListItem(id: const Uuid().v4(), text: name, checked: false);
    final updatedList = list.copyWith(items: [...list.items, newItem]);
    final updatedLists = db.shoppingLists.map((l) => l.id == list.id ? updatedList : l).toList();
    await provider.saveAndSync(db.copyWith(shoppingLists: updatedLists));
    setState(() => _selectedList = updatedList);
    // Notify family about new item on shared list
    if (list.visibility != Visibility.PRIVATE) {
      NotificationService.notifyFamilyActivity(
        title: 'Item Added to ${list.title}',
        body: '${provider.activeUser?.name ?? "Someone"} added: $name',
      );
    }
  }

  Future<void> _toggleItem(ShoppingList list, ListItem item) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final updatedItems = list.items.map((i) => i.id == item.id ? i.copyWith(checked: !i.checked) : i).toList();
    final updatedList = list.copyWith(items: updatedItems);
    final updatedLists = db.shoppingLists.map((l) => l.id == list.id ? updatedList : l).toList();
    await provider.saveAndSync(db.copyWith(shoppingLists: updatedLists));
    setState(() => _selectedList = updatedList);
    // Notify family when item is checked off on shared list
    if (!item.checked && list.visibility != Visibility.PRIVATE) {
      NotificationService.notifyFamilyActivity(
        title: '${list.title} Updated',
        body: '${provider.activeUser?.name ?? "Someone"} checked off: ${item.text}',
      );
    }
  }

  Future<void> _deleteItem(ShoppingList list, String itemId) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final updatedList = list.copyWith(items: list.items.where((i) => i.id != itemId).toList());
    final updatedLists = db.shoppingLists.map((l) => l.id == list.id ? updatedList : l).toList();
    await provider.saveAndSync(db.copyWith(shoppingLists: updatedLists));
    setState(() => _selectedList = updatedList);
  }

  void _showNewListSheet() {
    final ctrl = TextEditingController();
    final provider = context.read<AppProvider>();
    final members = provider.familyMembers;
    var shareResult = const SharePickerResult(visibility: Visibility.FAMILY, sharedWith: []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetHandle(),
            const Text('New List', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'List Name *', prefixIcon: Icon(Icons.list_rounded)),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  Navigator.pop(ctx);
                  _createList(v.trim(), visibility: shareResult.visibility, sharedWith: shareResult.sharedWith);
                }
              },
            ),
            const SizedBox(height: 16),
            SharePicker(
              members: members.map((m) => SharePickerMember(id: m.id, name: m.name)).toList(),
              onChanged: (result) => shareResult = result,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (ctrl.text.trim().isNotEmpty) {
                    Navigator.pop(ctx);
                    _createList(ctrl.text.trim(), visibility: shareResult.visibility, sharedWith: shareResult.sharedWith);
                  }
                },
                child: const Text('Create List'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showAiCategorization() async {
    if (_selectedList == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a list first')),
      );
      return;
    }

    final list = _selectedList!;
    final itemNames = list.items.map((i) => i.name).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AiCategorizationSheet(list: list, itemNames: itemNames),
    );
  }

  void _showAiTextToChecklist() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AiTextToChecklistSheet(
        onListCreated: (list) {
          setState(() => _selectedList = list);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final family = provider.activeFamily;
    if (family == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final lists = provider.db.shoppingLists.where((l) => l.familyId == family.id).toList();

    // Sync selectedList with latest db state
    if (_selectedList != null) {
      final fresh = lists.cast<ShoppingList?>().firstWhere((l) => l?.id == _selectedList!.id, orElse: () => null);
      if (fresh == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _selectedList = null));
      } else if (fresh != _selectedList) {
        _selectedList = fresh;
      }
    }

    if (_selectedList != null) {
      return _ListDetailView(
        list: _selectedList!,
        onBack: () => setState(() => _selectedList = null),
        onAddItem: (name) => _addItem(_selectedList!, name),
        onToggleItem: (item) => _toggleItem(_selectedList!, item),
        onDeleteItem: (id) => _deleteItem(_selectedList!, id),
        onDeleteList: () => _deleteList(_selectedList!),
        onAiCategorize: _showAiCategorization,
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
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
              title: '\u{1F4CB} Family Lists',
              subtitle: 'Shared shopping & to-do lists',
              actions: [
                ActionChipButton(
                  icon: Icons.add_rounded,
                  label: 'New List',
                  onTap: _showNewListSheet,
                  isPrimary: true,
                ),
              ],
            ),

            // ── AI Checklist Wizard card ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('\u{1F9D9}', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('AI Checklist Wizard', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                        const Text('Smart categorization & text-to-list', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
                      ])),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _showAiCategorization,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                            alignment: Alignment.center,
                            child: const Text('Categorize', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: _showAiTextToChecklist,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                            alignment: Alignment.center,
                            child: const Text('Text to List', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),

            // ── YOUR LISTS heading ──
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'YOUR LISTS',
                style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1),
              ),
            ),

            const SizedBox(height: 10),

            // ── List items ──
            if (lists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OnboardingCard(
                  emoji: '\u{1F4CB}',
                  title: 'Create Your First List',
                  bullets: ['Shopping lists with smart categorization', 'Share with family members', 'AI-powered item suggestions'],
                  actionLabel: '+ New List',
                  onAction: _showNewListSheet,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: lists.map((list) {
                    final checked = list.items.where((it) => it.checked).length;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Dismissible(
                        key: Key(list.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                        ),
                        confirmDismiss: (_) async => await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete List'),
                            content: Text('Delete "${list.name}"?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
                            ],
                          ),
                        ),
                        onDismissed: (_) => _deleteList(list),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedList = list),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.stone100),
                            ),
                            child: Row(children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.list_rounded, color: AppTheme.primary, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(list.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900)),
                                Text(
                                  '${list.items.length} item${list.items.length == 1 ? '' : 's'}${list.items.isNotEmpty ? ' \u00B7 $checked done' : ''}',
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                                ),
                              ])),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.stone100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${list.items.length}',
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.stone600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded, color: AppTheme.stone400),
                            ]),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// AI Categorization Bottom Sheet
// ─────────────────────────────────────────────

class _AiCategorizationSheet extends StatefulWidget {
  final ShoppingList list;
  final List<String> itemNames;

  const _AiCategorizationSheet({required this.list, required this.itemNames});

  @override
  State<_AiCategorizationSheet> createState() => _AiCategorizationSheetState();
}

class _AiCategorizationSheetState extends State<_AiCategorizationSheet> {
  Map<String, List<String>>? _categories;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _categorize();
  }

  Future<void> _categorize() async {
    try {
      // categorizeItems returns Map<item, category>; invert to Map<category, [items]>
      final familyId = context.read<AppProvider>().activeFamily?.id ?? '';
      final raw = await AiService.categorizeItems(widget.itemNames, familyId: familyId);
      final grouped = <String, List<String>>{};
      for (final entry in raw.entries) {
        grouped.putIfAbsent(entry.value, () => []).add(entry.key);
      }
      if (mounted) setState(() { _categories = grouped; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.stone200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'AI Categories — ${widget.list.name}',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppTheme.stone900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Error: $_error',
                style: const TextStyle(color: AppTheme.error, fontFamily: 'Inter'),
              ),
            )
          else if (_categories == null || _categories!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No categories returned.',
                style: TextStyle(fontFamily: 'Inter', color: AppTheme.stone500),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _categories!.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              letterSpacing: 0.5,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...entry.value.map((itemName) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                const Icon(Icons.circle, size: 6, color: AppTheme.stone400),
                                const SizedBox(width: 8),
                                Text(
                                  itemName,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 14,
                                    color: AppTheme.stone800,
                                  ),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// List detail view
// ─────────────────────────────────────────────

class _ListDetailView extends StatefulWidget {
  final ShoppingList list;
  final VoidCallback onBack;
  final Future<void> Function(String) onAddItem;
  final Future<void> Function(ListItem) onToggleItem;
  final Future<void> Function(String) onDeleteItem;
  final VoidCallback onDeleteList;
  final VoidCallback onAiCategorize;

  const _ListDetailView({
    required this.list,
    required this.onBack,
    required this.onAddItem,
    required this.onToggleItem,
    required this.onDeleteItem,
    required this.onDeleteList,
    required this.onAiCategorize,
  });

  @override
  State<_ListDetailView> createState() => _ListDetailViewState();
}

class _ListDetailViewState extends State<_ListDetailView> {
  final _addCtrl = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _addCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _addCtrl.text.trim();
    if (name.isNotEmpty) {
      widget.onAddItem(name);
      _addCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final unchecked = widget.list.items.where((i) => !i.checked).toList();
    final checked = widget.list.items.where((i) => i.checked).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.stone700),
          onPressed: widget.onBack,
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
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: AppTheme.stone500),
            tooltip: 'AI Categorize',
            onPressed: widget.onAiCategorize,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete List'),
                  content: Text('Delete "${widget.list.name}"?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
                  ],
                ),
              );
              if (confirm == true) widget.onDeleteList();
            },
            color: AppTheme.error,
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: widget.list.items.isEmpty
              ? const EmptyState(emoji: '🛒', title: 'Empty list', subtitle: 'Add items below.')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    ...unchecked.map((item) => _ItemTile(
                          item: item,
                          onToggle: () => widget.onToggleItem(item),
                          onDelete: () => widget.onDeleteItem(item.id),
                        )),
                    if (checked.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('Checked (${checked.length})', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.stone400)),
                      ),
                      ...checked.map((item) => _ItemTile(
                            item: item,
                            onToggle: () => widget.onToggleItem(item),
                            onDelete: () => widget.onDeleteItem(item.id),
                          )),
                    ],
                  ],
                ),
        ),
        Container(
          padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.stone100)),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _addCtrl,
                focusNode: _focusNode,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Add item...', prefixIcon: Icon(Icons.add_rounded)),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _submit,
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// AI Text-to-Checklist Bottom Sheet
// ─────────────────────────────────────────────

class _AiTextToChecklistSheet extends StatefulWidget {
  final void Function(ShoppingList) onListCreated;
  const _AiTextToChecklistSheet({required this.onListCreated});

  @override
  State<_AiTextToChecklistSheet> createState() => _AiTextToChecklistSheetState();
}

class _AiTextToChecklistSheetState extends State<_AiTextToChecklistSheet> {
  final _textController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _convert() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);

    const systemPrompt =
        'You are a checklist assistant. Always respond with valid JSON only, no markdown fences.';
    final prompt =
        'Turn this text into a structured checklist: "$text". Return a JSON array of objects with "text" and "quantity".';

    try {
      final familyId = context.read<AppProvider>().activeFamily?.id ?? '';
      final raw = await AiService.ask(prompt: '$systemPrompt\n\n$prompt', feature: 'ai_lists', familyId: familyId);
      if (raw == null || !mounted) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      var cleaned = raw.trim();
      if (cleaned.startsWith('```')) cleaned = cleaned.substring(cleaned.indexOf('\n') + 1);
      if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.lastIndexOf('```'));
      cleaned = cleaned.trim();

      final decoded = jsonDecode(cleaned);
      if (decoded is! List) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final provider = context.read<AppProvider>();
      final db = provider.db;
      final userId = provider.activeUser?.id ?? '';
      final familyId = provider.activeFamily?.id ?? '';

      final items = decoded.map((item) {
        final itemText = item is Map ? (item['text']?.toString() ?? '') : item.toString();
        final qty = item is Map ? item['quantity']?.toString() : null;
        return ListItem(
          id: const Uuid().v4(),
          text: itemText,
          quantity: qty,
          checked: false,
        );
      }).where((i) => i.text.isNotEmpty).toList();

      final listTitle = 'AI: ${text.length > 20 ? '${text.substring(0, 20)}...' : text}';
      final newList = ShoppingList(
        id: const Uuid().v4(),
        familyId: familyId,
        creatorId: userId,
        title: listTitle,
        items: items,
      );

      await provider.saveAndSync(db.copyWith(shoppingLists: [...db.shoppingLists, newList]));

      if (mounted) {
        Navigator.pop(context);
        widget.onListCreated(newList);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created "$listTitle" with ${items.length} items'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      debugPrint('[Lists] text-to-checklist error: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not convert text. Try again.'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewInsets.bottom + 32;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.stone200, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Row(children: [
            Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 20),
            SizedBox(width: 8),
            Text('AI Text to Checklist', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.stone900)),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Paste any text and AI will convert it into a structured checklist.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'e.g. "2 lbs chicken breast, 1 bag rice, salad mix, olive oil, garlic..."',
              filled: true,
              fillColor: AppTheme.stone50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _convert,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Convert to Checklist', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final ListItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ItemTile({required this.item, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline_rounded, color: AppTheme.error, size: 20),
      ),
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: item.checked ? AppTheme.success : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: item.checked ? AppTheme.success : AppTheme.stone300, width: 2),
                ),
                child: item.checked ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: item.checked ? AppTheme.stone400 : AppTheme.stone900,
                    decoration: item.checked ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (item.quantity != null && item.quantity!.isNotEmpty && item.quantity != '1')
                Text('×${item.quantity}', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
            ]),
          ),
        ),
      ),
    );
  }
}

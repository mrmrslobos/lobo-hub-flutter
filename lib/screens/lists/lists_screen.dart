// lib/screens/lists/lists_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  ShoppingList? _selectedList;

  Future<void> _createList(String name) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final list = ShoppingList(
      id: const Uuid().v4(),
      familyId: provider.activeFamily!.id,
      name: name,
      items: [],
      createdBy: provider.activeUser!.id,
      createdAt: DateTime.now(),
    );
    final updated = [...db.shoppingLists, list];
    await provider.saveAndSync(db.copyWith(shoppingLists: updated));
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
    final newItem = ListItem(id: const Uuid().v4(), name: name, checked: false, quantity: 1);
    final updatedList = list.copyWith(items: [...list.items, newItem]);
    final updatedLists = db.shoppingLists.map((l) => l.id == list.id ? updatedList : l).toList();
    await provider.saveAndSync(db.copyWith(shoppingLists: updatedLists));
    setState(() => _selectedList = updatedList);
  }

  Future<void> _toggleItem(ShoppingList list, ListItem item) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final updatedItems = list.items.map((i) => i.id == item.id ? i.copyWith(checked: !i.checked) : i).toList();
    final updatedList = list.copyWith(items: updatedItems);
    final updatedLists = db.shoppingLists.map((l) => l.id == list.id ? updatedList : l).toList();
    await provider.saveAndSync(db.copyWith(shoppingLists: updatedLists));
    setState(() => _selectedList = updatedList);
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                  Navigator.pop(context);
                  _createList(v.trim());
                }
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (ctrl.text.trim().isNotEmpty) {
                    Navigator.pop(context);
                    _createList(ctrl.text.trim());
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
      );
    }

    return Scaffold(
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewListSheet,
        child: const Icon(Icons.add_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(title: Text('Lists'), floating: true),
          lists.isEmpty
              ? SliverFillRemaining(
                  child: EmptyState(
                    emoji: '📋',
                    title: 'No lists yet',
                    subtitle: 'Create a shopping list for your family.',
                    actionLabel: 'Create List',
                    onAction: _showNewListSheet,
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final list = lists[i];
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
                                      '${list.items.length} item${list.items.length == 1 ? '' : 's'}${list.items.isNotEmpty ? ' · $checked done' : ''}',
                                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                                    ),
                                  ])),
                                  if (list.items.isNotEmpty) ...[
                                    SizedBox(
                                      width: 36, height: 36,
                                      child: CircularProgressIndicator(
                                        value: checked / list.items.length,
                                        strokeWidth: 3,
                                        backgroundColor: AppTheme.stone100,
                                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.success),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  const Icon(Icons.chevron_right_rounded, color: AppTheme.stone400),
                                ]),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: lists.length,
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

  const _ListDetailView({
    required this.list,
    required this.onBack,
    required this.onAddItem,
    required this.onToggleItem,
    required this.onDeleteItem,
    required this.onDeleteList,
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
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: widget.onBack),
        title: Text(widget.list.name),
        actions: [
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
              if (item.quantity > 1)
                Text('×${item.quantity}', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
            ]),
          ),
        ),
      ),
    );
  }
}

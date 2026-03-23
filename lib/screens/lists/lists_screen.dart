// lib/screens/lists/lists_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart' hide Visibility;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/subscription_modal.dart';

class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  ShoppingList? _selectedList;

  // ── Data helpers ───────────────────────────────────────────────────────────

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
      NotificationService.notifyFamilyActivityWithDb(
        provider.db,
        title: 'New List Created',
        body: '${provider.activeUser?.name ?? "Someone"} created: ${list.title}',
        path: '/lists',
        familyId: provider.activeFamily?.id,
        excludeUserId: provider.activeUser?.id,
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

  void _showListActions(ShoppingList list) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(list.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: AppTheme.primary),
            title: const Text('Rename', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(ctx);
              _showRenameDialog(list);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_rounded, color: AppTheme.error),
            title: Text('Delete', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppTheme.error)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(ctx);
              _deleteList(list);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showRenameDialog(ShoppingList list) {
    final ctrl = TextEditingController(text: list.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename List'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'List name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(ctx);
              final provider = context.read<AppProvider>();
              final db = provider.db;
              final updated = list.copyWith(title: newName);
              await provider.saveAndSync(db.copyWith(
                shoppingLists: db.shoppingLists
                    .map((l) => l.id == list.id ? updated : l)
                    .toList(),
              ));
              if (_selectedList?.id == list.id) {
                setState(() => _selectedList = updated);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _addItem(ShoppingList list, String name) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final newItem = ListItem(id: const Uuid().v4(), text: name, checked: false);
    final updatedList = list.copyWith(items: [...list.items, newItem]);
    final updatedLists = db.shoppingLists.map((l) => l.id == list.id ? updatedList : l).toList();
    await provider.saveAndSync(db.copyWith(shoppingLists: updatedLists));
    setState(() => _selectedList = updatedList);
    if (list.visibility != Visibility.PRIVATE) {
      NotificationService.notifyFamilyActivityWithDb(
        provider.db,
        title: 'Item Added to ${list.title}',
        body: '${provider.activeUser?.name ?? "Someone"} added: $name',
        path: '/lists',
        familyId: provider.activeFamily?.id,
        excludeUserId: provider.activeUser?.id,
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
    if (!item.checked && list.visibility != Visibility.PRIVATE) {
      NotificationService.notifyFamilyActivityWithDb(
        provider.db,
        title: '${list.title} Updated',
        body: '${provider.activeUser?.name ?? "Someone"} checked off: ${item.text}',
        path: '/lists',
        familyId: provider.activeFamily?.id,
        excludeUserId: provider.activeUser?.id,
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

  // ── Sheet launchers ────────────────────────────────────────────────────────

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
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetHandle(),
            // Header with icon badge
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.playlist_add_rounded, size: 18, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 12),
                  const Text('New List', style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.stone900,
                  )),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.stone400),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'List Name *',
                prefixIcon: Icon(Icons.list_rounded),
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  Navigator.pop(ctx);
                  _createList(v.trim(), visibility: shareResult.visibility, sharedWith: shareResult.sharedWith);
                }
              },
            ),
            const SizedBox(height: 16),
            SharePicker(
              members: members.map((m) {
                final user = provider.userById(m.userId);
                return SharePickerMember(id: m.id, name: user?.name ?? m.name);
              }).toList(),
              onChanged: (result) => shareResult = result,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  if (ctrl.text.trim().isNotEmpty) {
                    Navigator.pop(ctx);
                    _createList(ctrl.text.trim(), visibility: shareResult.visibility, sharedWith: shareResult.sharedWith);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Create List', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showAiCategorization() async {
    ShoppingList? list = _selectedList;

    if (list == null) {
      final provider = context.read<AppProvider>();
      final familyId = provider.activeFamily?.id;
      final allLists = provider.db.shoppingLists.where((l) => l.familyId == familyId && l.items.isNotEmpty).toList();
      if (allLists.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Create a list with items first'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
        return;
      }
      list = await showModalBottomSheet<ShoppingList>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.category_rounded, size: 18, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 12),
                  const Text('Select a list to categorize', style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.stone900,
                  )),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.stone100),
            ...allLists.map((l) => InkWell(
              onTap: () => Navigator.pop(ctx, l),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.list_rounded, size: 18, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15, color: AppTheme.stone800)),
                        Text('${l.items.length} items', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                      ],
                    )),
                    const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.stone300),
                  ],
                ),
              ),
            )),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ]),
        ),
      );
      if (list == null) return;
      setState(() => _selectedList = list);
    }

    final itemNames = list.items.map((i) => i.text).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AiCategorizationSheet(list: list!, itemNames: itemNames),
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

  // ── Build ──────────────────────────────────────────────────────────────────

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
      return BackNavigationScope(
        onBack: () {
          setState(() => _selectedList = null);
          return true;
        },
        child: _ListDetailView(
          list: _selectedList!,
          onBack: () => setState(() => _selectedList = null),
          onAddItem: (name) => _addItem(_selectedList!, name),
          onToggleItem: (item) => _toggleItem(_selectedList!, item),
          onDeleteItem: (id) => _deleteItem(_selectedList!, id),
          onDeleteList: () => _deleteList(_selectedList!),
          onAiCategorize: _showAiCategorization,
        ),
      );
    }

    // Stats
    final totalItems = lists.fold<int>(0, (s, l) => s + l.items.length);
    final checkedItems = lists.fold<int>(0, (s, l) => s + l.items.where((i) => i.checked).length);

    return Scaffold(
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const FamilyHubAppBar(),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Page Header ──
          PageHeader(
            title: 'Family Lists',
            subtitle: 'Shared shopping & to-do lists.',
            actions: [
              ActionChipButton(
                icon: Icons.add_rounded,
                label: 'New List',
                onTap: _showNewListSheet,
                isPrimary: true,
              ),
            ],
          ),

          // ── Stat Cards ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _MiniStat(icon: Icons.format_list_bulleted_rounded, label: 'Lists', value: '${lists.length}', color: AppTheme.primary),
                const SizedBox(width: 10),
                _MiniStat(icon: Icons.inventory_2_outlined, label: 'Items', value: '$totalItems', color: const Color(0xFFF59E0B)),
                const SizedBox(width: 10),
                _MiniStat(icon: Icons.check_circle_outline, label: 'Done', value: '$checkedItems', color: AppTheme.success),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── AI Checklist Wizard ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.auto_awesome, size: 18, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('AI Checklist Wizard', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                      Text('Smart categorization & text-to-list', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                    ])),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _showAiCategorization,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.category_rounded, size: 14, color: Colors.white),
                              SizedBox(width: 6),
                              Text('Categorize', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: _showAiTextToChecklist,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.text_snippet_outlined, size: 14, color: Colors.white),
                              SizedBox(width: 6),
                              Text('Text to List', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── YOUR LISTS heading ──
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'YOUR LISTS',
              style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1),
            ),
          ),

          // ── List cards or empty state ──
          if (lists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.stone100),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: AppTheme.stone50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.checklist_rounded, size: 28, color: AppTheme.stone300),
                    ),
                    const SizedBox(height: 12),
                    const Text('No lists yet', style: TextStyle(
                      fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.stone500,
                    )),
                    const SizedBox(height: 4),
                    const Text('Tap "New List" to create your first list', style: TextStyle(
                      fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400,
                    )),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _showNewListSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('+ New List', style: TextStyle(
                          fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white,
                        )),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: lists.map((list) {
                  final total = list.items.length;
                  final checked = list.items.where((it) => it.checked).length;
                  final progress = total > 0 ? checked / total : 0.0;
                  final isShared = list.visibility == Visibility.FAMILY;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Dismissible(
                      key: Key(list.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        decoration: BoxDecoration(
                          color: AppTheme.error,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                      ),
                      confirmDismiss: (_) async => await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete List'),
                          content: Text('Delete "${list.title}"?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
                          ],
                        ),
                      ),
                      onDismissed: (_) => _deleteList(list),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedList = list),
                        onLongPress: () => _showListActions(list),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.stone100),
                          ),
                          child: Column(
                            children: [
                              Row(children: [
                                Container(
                                  width: 44, height: 44,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryLight,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.checklist_rounded, color: AppTheme.primary, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(list.title, style: const TextStyle(
                                      fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900,
                                    )),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          '$total item${total == 1 ? '' : 's'}',
                                          style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                                        ),
                                        if (total > 0) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            width: 3, height: 3,
                                            decoration: const BoxDecoration(color: AppTheme.stone300, shape: BoxShape.circle),
                                          ),
                                          const SizedBox(width: 6),
                                          Text('$checked done', style: const TextStyle(
                                            fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400,
                                          )),
                                        ],
                                      ],
                                    ),
                                  ],
                                )),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isShared
                                            ? AppTheme.primary.withValues(alpha: 0.08)
                                            : AppTheme.stone50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isShared ? 'Family' : 'Personal',
                                        style: TextStyle(
                                          fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700,
                                          color: isShared ? AppTheme.primary : AppTheme.stone400,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.stone300),
                                  ],
                                ),
                              ]),
                              if (total > 0) ...[
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 4,
                                    backgroundColor: AppTheme.stone100,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      progress >= 1.0 ? AppTheme.success : AppTheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Mini Stat Card ──────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniStat({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                  Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.stone400)),
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
    if (SubscriptionModal.guardAI(context)) return;
    try {
      final familyId = context.read<AppProvider>().activeFamily?.id;
      if (familyId == null) {
        if (mounted) setState(() { _error = 'No active family'; _loading = false; });
        return;
      }
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
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          // Header
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 18, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AI Categories', style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.stone900,
                      )),
                      Text(widget.list.title, style: const TextStyle(
                        fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400,
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_loading)
            const SizedBox(
              height: 120,
              child: Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Analyzing items...', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
                ],
              )),
            )
          else if (_error != null)
            _errorCard(_error!)
          else if (_categories == null || _categories!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text(
                'No categories returned.',
                style: TextStyle(fontFamily: 'Inter', color: AppTheme.stone500),
              )),
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
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.stone50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.stone100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key.toUpperCase(),
                              style: const TextStyle(
                                fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11,
                                letterSpacing: 0.8, color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...entry.value.map((itemName) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6, height: 6,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(alpha: 0.4),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    itemName,
                                    style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone800),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          if (_categories != null && _categories!.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  final itemToCategory = <String, String>{};
                  for (final entry in _categories!.entries) {
                    for (final itemName in entry.value) {
                      itemToCategory[itemName] = entry.key;
                    }
                  }

                  final updatedItems = widget.list.items.map((item) {
                    final cat = itemToCategory[item.text];
                    if (cat != null) {
                      return item.copyWith(aiCategory: cat);
                    }
                    return item;
                  }).toList();

                  updatedItems.sort((a, b) {
                    if (a.checked != b.checked) return a.checked ? 1 : -1;
                    final catA = a.aiCategory ?? 'zzz';
                    final catB = b.aiCategory ?? 'zzz';
                    return catA.compareTo(catB);
                  });

                  final provider = context.read<AppProvider>();
                  final db = provider.db;
                  final updatedList = widget.list.copyWith(items: updatedItems);
                  final updatedLists = db.shoppingLists
                      .map((l) => l.id == widget.list.id ? updatedList : l)
                      .toList();
                  provider.saveAndSync(db.copyWith(shoppingLists: updatedLists));

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Categories applied! Use the group icon to view by category.'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ));
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Apply Categories', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 20, color: AppTheme.error),
            const SizedBox(width: 10),
            Expanded(child: Text(
              message,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.error),
            )),
          ],
        ),
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
  TextEditingController _addCtrl = TextEditingController();
  bool _groupedView = false;

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _addCtrl.text.trim();
    if (name.isNotEmpty) {
      widget.onAddItem(name);
      _addCtrl.clear();
    }
  }

  Future<void> _editItem(ListItem item) async {
    final textCtrl = TextEditingController(text: item.text);
    final qtyCtrl = TextEditingController(text: item.quantity ?? '');

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetHandle(),
            // Header with icon badge
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 12),
                  const Text('Edit Item', style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.stone900,
                  )),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.stone400),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            TextField(
              controller: textCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Item name',
                prefixIcon: Icon(Icons.edit_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(
                labelText: 'Quantity (optional)',
                hintText: 'e.g. 2 lbs',
                prefixIcon: Icon(Icons.scale_rounded),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {'text': textCtrl.text.trim(), 'quantity': qtyCtrl.text.trim()}),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Save Changes', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ]),
        ),
      ),
    );

    if (result == null || result['text']!.isEmpty) return;

    final provider = context.read<AppProvider>();
    final db = provider.db;
    final updatedItems = widget.list.items.map((i) {
      if (i.id != item.id) return i;
      return i.copyWith(
        text: result['text'],
        quantity: result['quantity']!.isEmpty ? null : result['quantity'],
      );
    }).toList();
    final updatedList = widget.list.copyWith(items: updatedItems);
    final updatedLists = db.shoppingLists.map((l) => l.id == widget.list.id ? updatedList : l).toList();
    await provider.saveAndSync(db.copyWith(shoppingLists: updatedLists));
  }

  @override
  Widget build(BuildContext context) {
    final unchecked = widget.list.items.where((i) => !i.checked).toList();
    final checked = widget.list.items.where((i) => i.checked).toList();
    final total = widget.list.items.length;
    final progress = total > 0 ? checked.length / total : 0.0;

    // Grouped view: group unchecked items by aiCategory
    final hasCategories = unchecked.any((i) => i.aiCategory != null && i.aiCategory!.isNotEmpty);
    Map<String, List<ListItem>>? grouped;
    if (_groupedView && hasCategories) {
      grouped = {};
      for (final item in unchecked) {
        final cat = item.aiCategory ?? 'Other';
        grouped.putIfAbsent(cat, () => []).add(item);
      }
    }

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface.withValues(alpha: 0.85)),
          onPressed: widget.onBack,
        ),
        title: Text(widget.list.title, style: TextStyle(
          fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: cs.onSurface,
        )),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          if (hasCategories)
            IconButton(
              icon: Icon(
                _groupedView ? Icons.view_list_rounded : Icons.category_rounded,
                color: _groupedView ? AppTheme.primary : AppTheme.stone500,
              ),
              tooltip: _groupedView ? 'List view' : 'Grouped view',
              onPressed: () => setState(() => _groupedView = !_groupedView),
            ),
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: AppTheme.stone500, size: 20),
            tooltip: 'AI Categorize',
            onPressed: widget.onAiCategorize,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error, size: 20),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete List'),
                  content: Text('Delete "${widget.list.title}"?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
                  ],
                ),
              );
              if (confirm == true) widget.onDeleteList();
            },
          ),
        ],
      ),
      body: Column(children: [
        // ── Progress card ──
        if (total > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.stone100),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: (progress >= 1.0 ? AppTheme.success : AppTheme.primary).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      progress >= 1.0 ? Icons.celebration_rounded : Icons.checklist_rounded,
                      size: 18,
                      color: progress >= 1.0 ? AppTheme.success : AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              progress >= 1.0 ? 'All done!' : '${unchecked.length} remaining',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone700),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (progress >= 1.0 ? AppTheme.success : AppTheme.primary).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${checked.length}/$total',
                                style: TextStyle(
                                  fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700,
                                  color: progress >= 1.0 ? AppTheme.success : AppTheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: AppTheme.stone100,
                            valueColor: AlwaysStoppedAnimation(
                              progress >= 1.0 ? AppTheme.success : AppTheme.primary,
                            ),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Items list ──
        Expanded(
          child: total == 0
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: AppTheme.stone50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shopping_cart_outlined, size: 28, color: AppTheme.stone300),
                      ),
                      const SizedBox(height: 12),
                      const Text('Empty list', style: TextStyle(
                        fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.stone500,
                      )),
                      const SizedBox(height: 4),
                      const Text('Add items below to get started', style: TextStyle(
                        fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400,
                      )),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    if (grouped != null)
                      ...grouped.entries.expand((entry) => [
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Row(
                            children: [
                              Text(
                                entry.key.toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
                                  color: AppTheme.primary, letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${entry.value.length}',
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone300),
                              ),
                            ],
                          ),
                        ),
                        ...entry.value.map((item) => _ItemTile(
                          item: item,
                          onToggle: () => widget.onToggleItem(item),
                          onDelete: () => widget.onDeleteItem(item.id),
                          onEdit: () => _editItem(item),
                        )),
                      ])
                    else
                      ...unchecked.map((item) => _ItemTile(
                        item: item,
                        onToggle: () => widget.onToggleItem(item),
                        onDelete: () => widget.onDeleteItem(item.id),
                        onEdit: () => _editItem(item),
                      )),
                    if (checked.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 6),
                        child: Row(
                          children: [
                            const Text('CHECKED', style: TextStyle(
                              fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
                              color: AppTheme.stone400, letterSpacing: 1.1,
                            )),
                            const SizedBox(width: 8),
                            Text('${checked.length}', style: const TextStyle(
                              fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone300,
                            )),
                          ],
                        ),
                      ),
                      ...checked.map((item) => _ItemTile(
                        item: item,
                        onToggle: () => widget.onToggleItem(item),
                        onDelete: () => widget.onDeleteItem(item.id),
                        onEdit: () => _editItem(item),
                      )),
                    ],
                  ],
                ),
        ),

        // ── Add item bar ──
        Container(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 10,
            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(top: BorderSide(color: AppTheme.stone100)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, -2)),
            ],
          ),
          child: Row(children: [
            Expanded(
              child: Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  final query = textEditingValue.text.trim().toLowerCase();
                  if (query.isEmpty) return const Iterable<String>.empty();
                  final provider = context.read<AppProvider>();
                  final allNames = provider.db.shoppingLists
                      .expand((l) => l.items)
                      .map((i) => i.text)
                      .toSet()
                      .where((name) => name.toLowerCase().contains(query) && name.toLowerCase() != query)
                      .toList()
                    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                  return allNames.take(5);
                },
                onSelected: (value) {
                  _addCtrl.text = value;
                  _submit();
                },
                fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                  _addCtrl = textEditingController;
                  return TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Add item...',
                      hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
                      prefixIcon: const Icon(Icons.add_rounded, size: 20, color: AppTheme.stone400),
                      filled: true,
                      fillColor: AppTheme.stone50,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
                    ),
                    onSubmitted: (_) { onFieldSubmitted(); _submit(); },
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _submit,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
              ),
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
    if (SubscriptionModal.guardAI(context)) return;
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please enter some text to convert'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    setState(() => _loading = true);

    const systemPrompt =
        'You are a checklist assistant. Always respond with valid JSON only, no markdown fences.';
    final prompt =
        'Turn this text into a structured checklist: "$text". Return a JSON array of objects with "text" and "quantity".';

    try {
      final familyId = context.read<AppProvider>().activeFamily?.id;
      if (familyId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final raw = await AiService.ask(prompt: '$systemPrompt\n\n$prompt', feature: 'ai_lists', familyId: familyId);
      if (raw == null || !mounted) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      context.read<AppProvider>().saveAiHistory(module: 'lists', prompt: 'Generate checklist from: "$text"', response: raw);

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Created "$listTitle" with ${items.length} items'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      debugPrint('[Lists] text-to-checklist error: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Could not convert text. Try again.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewInsets.bottom + 32;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          // Header
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.auto_awesome, size: 18, color: Colors.white.withValues(alpha: 0.9)),
                ),
                const SizedBox(width: 12),
                const Text('AI Text to Checklist', style: TextStyle(
                  fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.stone900,
                )),
              ],
            ),
          ),
          const Text(
            'Paste any text and AI will convert it into a structured checklist.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _textController,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'e.g. "2 lbs chicken breast, 1 bag rice, salad mix, olive oil, garlic..."',
              hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone300),
              filled: true,
              fillColor: AppTheme.stone50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _convert,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              icon: _loading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                _loading ? 'Converting...' : 'Convert to Checklist',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Item Tile
// ─────────────────────────────────────────────

class _ItemTile extends StatelessWidget {
  final ListItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  const _ItemTile({required this.item, required this.onToggle, required this.onDelete, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: AppTheme.error, size: 20),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Item?'),
            content: Text('Remove "${item.text}" from the list?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          onTap: onToggle,
          onLongPress: onEdit,
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
                  item.text,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: item.checked ? AppTheme.stone400 : AppTheme.stone900,
                    decoration: item.checked ? TextDecoration.lineThrough : null,
                    decorationColor: AppTheme.stone300,
                  ),
                ),
              ),
              if (item.quantity != null && item.quantity!.isNotEmpty && item.quantity != '1')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.stone100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('\u00D7${item.quantity}', style: const TextStyle(
                    fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.stone500,
                  )),
                ),
              if (onEdit != null && !item.checked) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onEdit,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.edit_outlined, size: 14, color: AppTheme.stone300),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

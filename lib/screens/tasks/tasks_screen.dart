// lib/screens/tasks/tasks_screen.dart
// Task management screen for FamilyHub

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/subscription_modal.dart';

// ─── Filter enum ──────────────────────────────────────────────────────────────

enum _TaskFilter { all, mine, others, today, highPriority, done }

// ─── Tasks screen ─────────────────────────────────────────────────────────────

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  _TaskFilter _filter = _TaskFilter.all;
  String? _selectedFolder;
  String? _selectedMemberId;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  List<String> _customFolderNames = [];
  bool _customFoldersLoaded = false;
  static const _taskFoldersKeyPrefix = 'task_folders_';

  static const _folderNames = ['Home', 'Work', 'Personal', 'Shopping', 'AI Generated', 'Event'];

  static const _folderIcons = {
    'Home': Icons.home_outlined,
    'Work': Icons.work_outline_rounded,
    'Personal': Icons.person_outline_rounded,
    'Shopping': Icons.shopping_cart_outlined,
    'AI Generated': Icons.auto_awesome_outlined,
    'Event': Icons.event_outlined,
  };

  /// All folder names: defaults + custom (custom first so they appear at top after defaults).
  List<String> get _allFolderNames => [
    ..._folderNames,
    ..._customFolderNames.where((n) => !_folderNames.any((d) => d.toLowerCase() == n.toLowerCase())),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_customFoldersLoaded && context.read<AppProvider>().activeFamily != null) {
      _customFoldersLoaded = true;
      _loadCustomFolders();
    }
  }

  Future<void> _loadCustomFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final familyId = context.read<AppProvider>().activeFamily?.id;
    if (familyId == null) return;
    final key = '$_taskFoldersKeyPrefix$familyId';
    final json = prefs.getString(key);
    if (json == null) return;
    try {
      final list = jsonDecode(json) as List<dynamic>?;
      if (list != null && mounted) setState(() => _customFolderNames = list.map((e) => e.toString()).toList());
    } catch (_) {}
  }

  Future<void> _saveCustomFolders() async {
    final familyId = context.read<AppProvider>().activeFamily?.id;
    if (familyId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_taskFoldersKeyPrefix$familyId';
    await prefs.setString(key, jsonEncode(_customFolderNames));
  }

  Future<void> _showCreateFolderDialog() async {
    final nameCtrl = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('New folder', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Folder name',
              hintText: 'e.g. Errands, Projects',
            ),
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (created != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final exists = _allFolderNames.any((f) => f.toLowerCase() == name.toLowerCase());
    if (exists) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A folder named "$name" already exists'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _customFolderNames = [..._customFolderNames, name]..sort());
    await _saveCustomFolders();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Task> _filteredTasks(AppProvider provider) {
    final familyId = provider.activeFamily?.id;
    final userId = provider.activeUser?.id;
    if (familyId == null) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return provider.db.tasks.where((t) {
      if (t.familyId != familyId) return false;

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!t.title.toLowerCase().contains(q) &&
            !(t.notes?.toLowerCase().contains(q) ?? false) &&
            !t.tags.any((tag) => tag.toLowerCase().contains(q))) {
          return false;
        }
      }

      // Folder filter
      if (_selectedFolder != null) {
        final folderLower = _selectedFolder!.toLowerCase();
        if (!t.tags.any((tag) => tag.toLowerCase() == folderLower)) return false;
      }

      // Member filter
      if (_selectedMemberId != null) {
        if (!t.assigneeIds.contains(_selectedMemberId) && t.createdBy != _selectedMemberId) return false;
      }

      switch (_filter) {
        case _TaskFilter.all:
          return !t.completed;
        case _TaskFilter.mine:
          return !t.completed && (t.assigneeIds.contains(userId) || t.createdBy == userId);
        case _TaskFilter.others:
          return !t.completed && !t.assigneeIds.contains(userId) && t.createdBy != userId && t.assigneeIds.isNotEmpty;
        case _TaskFilter.today:
          return !t.completed && t.dueDate != null && _isSameDay(t.dueDate!, today);
        case _TaskFilter.highPriority:
          return !t.completed && t.priority == Priority.HIGH;
        case _TaskFilter.done:
          return t.completed;
      }
    }).toList()
      ..sort((a, b) {
        if (_filter == _TaskFilter.done) {
          return 0; // keep insertion order for completed
        }
        if (a.isOverdue && !b.isOverdue) return -1;
        if (!a.isOverdue && b.isOverdue) return 1;
        if (a.dueDate != null && b.dueDate != null) {
          return a.dueDate!.compareTo(b.dueDate!);
        }
        if (a.dueDate != null) return -1;
        if (b.dueDate != null) return 1;
        return b.priority.index.compareTo(a.priority.index);
      });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _toggleComplete(AppProvider provider, Task task) async {
    HapticFeedback.lightImpact();
    final db = provider.db;
    final updated = task.copyWith(
      completed: !task.completed,
      completedBy: !task.completed ? provider.activeUser?.id : null,
      updatedAt: DateTime.now(),
    );
    var tasks = db.tasks.map((t) => t.id == task.id ? updated : t).toList();

    // Generate next recurring instance when completing a recurring task
    if (updated.completed && task.recurrence != Recurrence.NONE && task.dueDate != null) {
      final nextDue = _nextRecurrenceDate(task.dueDate!, task.recurrence);
      final nextTask = task.copyWith(
        id: const Uuid().v4(),
        completed: false,
        completedBy: null,
        dueDate: nextDue,
        updatedAt: DateTime.now(),
      );
      tasks = [...tasks, nextTask];
      if (nextTask.dueDate != null && nextTask.reminderMinutes != null && nextTask.dueTime != null) {
        NotificationService.scheduleTaskReminder(
          taskId: nextTask.id,
          taskTitle: nextTask.title,
          dueDate: nextTask.dueDate!,
          dueTime: nextTask.dueTime!,
          reminderMinutes: nextTask.reminderMinutes!,
        );
      }
    }

    await provider.saveAndSync(db.copyWith(tasks: tasks));
    if (provider.activeFamily != null) await provider.syncTasksNow();
    if (updated.completed) {
      NotificationService.cancelTaskReminder(task.id);
    }
  }

  DateTime _nextRecurrenceDate(DateTime current, Recurrence recurrence) {
    switch (recurrence) {
      case Recurrence.DAILY:
        return current.add(const Duration(days: 1));
      case Recurrence.WEEKLY:
        return current.add(const Duration(days: 7));
      case Recurrence.MONTHLY:
        return DateTime(current.year, current.month + 1, current.day);
      case Recurrence.NONE:
        return current;
    }
  }

  Future<void> _deleteTask(AppProvider provider, Task task) async {
    final db = provider.db;
    final tasks = db.tasks.where((t) => t.id != task.id).toList();
    await provider.saveAndSync(db.copyWith(tasks: tasks));
    if (provider.activeFamily != null) await provider.syncTasksNow();
    NotificationService.cancelTaskReminder(task.id);
  }

  void _showAddTaskSheet(BuildContext context, {Task? editTask}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TaskFormSheet(editTask: editTask),
    );
  }

  void _showAiBreakdownSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AiBreakdownSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final tasks = _filteredTasks(provider);
        final familyId = provider.activeFamily?.id;
        final userId = provider.activeUser?.id;
        final members = provider.familyMembers;

        // Counts for filters
        final allTasks = provider.db.tasks.where((t) => t.familyId == familyId && !t.completed).toList();
        final myTasks = allTasks.where((t) => t.assigneeIds.contains(userId) || t.createdBy == userId).toList();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final otherTasks = allTasks.where((t) => !t.assigneeIds.contains(userId) && t.createdBy != userId && t.assigneeIds.isNotEmpty).toList();
        final dueTodayTasks = allTasks.where((t) => t.dueDate != null && _isSameDay(t.dueDate!, today)).toList();
        final highPriorityTasks = allTasks.where((t) => t.priority == Priority.HIGH).toList();
        final doneTasks = provider.db.tasks.where((t) => t.familyId == familyId && t.completed).toList();
        final overdueTasks = allTasks.where((t) => t.isOverdue).toList();

        // Folder counts
        final allCount = allTasks.length;
        int folderCount(String folder) {
          final fl = folder.toLowerCase();
          return allTasks.where((t) => t.tags.any((tag) => tag.toLowerCase() == fl)).length;
        }

        // Progress
        final totalTasks = provider.db.tasks.where((t) => t.familyId == familyId).length;
        final completedCount = doneTasks.length;

        return Scaffold(
          drawer: const AppDrawer(),
          appBar: const FamilyHubAppBar(),
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Page Header
              PageHeader(
                title: 'Tasks',
                subtitle: 'Stay on top of what matters.',
              ),

              // Quick stats row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _StatCard(
                      icon: Icons.assignment_outlined,
                      label: 'Active',
                      value: '${allTasks.length}',
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    _StatCard(
                      icon: Icons.check_circle_outline,
                      label: 'Done',
                      value: '$completedCount',
                      color: AppTheme.success,
                    ),
                    const SizedBox(width: 10),
                    _StatCard(
                      icon: Icons.warning_amber_rounded,
                      label: 'Overdue',
                      value: '${overdueTasks.length}',
                      color: overdueTasks.isNotEmpty ? AppTheme.error : AppTheme.stone400,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          '$completedCount of $totalTasks completed',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone500),
                        ),
                        const Spacer(),
                        if (totalTasks > 0)
                          Text(
                            '${(completedCount / totalTasks * 100).round()}%',
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: totalTasks > 0 ? completedCount / totalTasks : 0,
                        minHeight: 6,
                        backgroundColor: AppTheme.stone100,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Add task + AI planner row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showAddTaskSheet(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.stone800,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, size: 18, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'New Task',
                                style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _showAiBreakdownSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'AI Plan',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search tasks...',
                    hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.stone400),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Filter chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(label: 'All', count: allTasks.length, selected: _filter == _TaskFilter.all, onTap: () => setState(() => _filter = _TaskFilter.all)),
                      const SizedBox(width: 8),
                      _FilterChip(label: 'Mine', count: myTasks.length, selected: _filter == _TaskFilter.mine, onTap: () => setState(() => _filter = _TaskFilter.mine)),
                      const SizedBox(width: 8),
                      _FilterChip(label: 'Others', count: otherTasks.length, selected: _filter == _TaskFilter.others, onTap: () => setState(() => _filter = _TaskFilter.others)),
                      const SizedBox(width: 8),
                      _FilterChip(label: 'Today', count: dueTodayTasks.length, selected: _filter == _TaskFilter.today, onTap: () => setState(() => _filter = _TaskFilter.today)),
                      const SizedBox(width: 8),
                      _FilterChip(label: 'Urgent', count: highPriorityTasks.length, selected: _filter == _TaskFilter.highPriority, onTap: () => setState(() => _filter = _TaskFilter.highPriority), color: highPriorityTasks.isNotEmpty ? AppTheme.error : null),
                      const SizedBox(width: 8),
                      _FilterChip(label: 'Done', count: doneTasks.length, selected: _filter == _TaskFilter.done, onTap: () => setState(() => _filter = _TaskFilter.done), color: AppTheme.success),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // FOLDERS section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Text(
                  'FOLDERS',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.stone100),
                  ),
                  child: Column(
                    children: [
                      _buildFolderItem('All Tasks', Icons.inbox_rounded, allCount,
                        isSelected: _selectedFolder == null,
                        onTap: () => setState(() { _selectedFolder = null; _selectedMemberId = null; }),
                      ),
                      for (final folder in _allFolderNames) ...[
                        const Divider(height: 1),
                        _buildFolderItem(
                          folder,
                          _folderIcons[folder] ?? Icons.folder_outlined,
                          folderCount(folder),
                          isSelected: _selectedFolder == folder,
                          onTap: () => setState(() { _selectedFolder = folder; _selectedMemberId = null; }),
                        ),
                      ],
                      const Divider(height: 1),
                      InkWell(
                        onTap: _showCreateFolderDialog,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.create_new_folder_outlined, size: 20, color: AppTheme.primary),
                              const SizedBox(width: 10),
                              Text(
                                'Create folder',
                                style: TextStyle(
                                  fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // TEAM section
              if (members.length > 1) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Text(
                    'TEAM',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.stone100),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < members.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          InkWell(
                            borderRadius: i == 0
                                ? const BorderRadius.vertical(top: Radius.circular(12))
                                : i == members.length - 1
                                    ? const BorderRadius.vertical(bottom: Radius.circular(12))
                                    : BorderRadius.zero,
                            onTap: () => setState(() {
                              if (_selectedMemberId == members[i].id) {
                                _selectedMemberId = null;
                              } else {
                                _selectedMemberId = members[i].id;
                                _selectedFolder = null;
                              }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  AvatarInitials(name: provider.memberDisplayName(members[i]), size: 30),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      provider.memberDisplayName(members[i]),
                                      style: TextStyle(
                                        fontFamily: 'Inter', fontSize: 14,
                                        fontWeight: _selectedMemberId == members[i].id ? FontWeight.w700 : FontWeight.w500,
                                        color: _selectedMemberId == members[i].id ? AppTheme.primary : AppTheme.stone800,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _selectedMemberId == members[i].id
                                          ? AppTheme.primary.withValues(alpha: 0.1)
                                          : AppTheme.stone50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${allTasks.where((t) => t.assigneeIds.contains(members[i].id)).length}',
                                      style: TextStyle(
                                        fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600,
                                        color: _selectedMemberId == members[i].id ? AppTheme.primary : AppTheme.stone400,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Section header for task list
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      _filter == _TaskFilter.done ? 'COMPLETED' : 'TASKS',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${tasks.length}',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone300),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Task cards list
              if (tasks.isEmpty)
                _buildEmptyState()
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: tasks.map((task) => _TaskCard(
                      task: task,
                      provider: provider,
                      onToggle: () => _toggleComplete(provider, task),
                      onEdit: () => _showAddTaskSheet(context, editTask: task),
                      onDelete: () => _deleteTask(provider, task),
                    )).toList(),
                  ),
                ),

              const SizedBox(height: 100),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    IconData icon;
    String title;
    String subtitle;

    switch (_filter) {
      case _TaskFilter.done:
        icon = Icons.check_circle_outline_rounded;
        title = 'No completed tasks yet';
        subtitle = 'Tasks you complete will appear here';
      case _TaskFilter.today:
        icon = Icons.today_rounded;
        title = 'Nothing due today';
        subtitle = 'Enjoy your free time!';
      case _TaskFilter.highPriority:
        icon = Icons.flag_outlined;
        title = 'No urgent tasks';
        subtitle = 'All high-priority items are handled';
      case _TaskFilter.mine:
        icon = Icons.person_outline_rounded;
        title = 'No tasks assigned to you';
        subtitle = 'Create a task or ask someone to assign one';
      case _TaskFilter.others:
        icon = Icons.people_outline_rounded;
        title = 'No tasks from others';
        subtitle = 'Tasks assigned to family members show here';
      case _TaskFilter.all:
        icon = Icons.task_alt_rounded;
        title = 'All clear!';
        subtitle = 'Tap "New Task" to add something';
    }

    if (_searchQuery.isNotEmpty) {
      icon = Icons.search_off_rounded;
      title = 'No matching tasks';
      subtitle = 'Try a different search term';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.stone50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppTheme.stone300),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.stone600),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderItem(String name, IconData icon, int count, {bool isSelected = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? AppTheme.primary : AppTheme.stone400),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppTheme.primary : AppTheme.stone700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.stone50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700,
                  color: isSelected ? AppTheme.primary : AppTheme.stone500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

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

// ─── Filter chip with count ───────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppTheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? activeColor.withValues(alpha: 0.1) : AppTheme.stone50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor.withValues(alpha: 0.4) : AppTheme.stone200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600,
                color: selected ? activeColor : AppTheme.stone600,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? activeColor.withValues(alpha: 0.15) : AppTheme.stone200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700,
                    color: selected ? activeColor : AppTheme.stone500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── AI Breakdown Sheet ───────────────────────────────────────────────────────

class _AiBreakdownSheet extends StatefulWidget {
  @override
  State<_AiBreakdownSheet> createState() => _AiBreakdownSheetState();
}

class _AiBreakdownSheetState extends State<_AiBreakdownSheet> {
  final _goalCtrl = TextEditingController();
  bool _loading = false;
  List<String>? _subTasks;
  late List<bool> _selected;
  bool _saving = false;

  @override
  void dispose() {
    _goalCtrl.dispose();
    super.dispose();
  }

  Future<void> _breakdown() async {
    if (SubscriptionModal.guardAI(context)) return;
    final goal = _goalCtrl.text.trim();
    if (goal.isEmpty) return;
    setState(() {
      _loading = true;
      _subTasks = null;
    });
    try {
      final familyId = context.read<AppProvider>().activeFamily?.id;
      if (familyId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final result = await AiService.breakdownTask(goal, familyId: familyId);
      if (mounted) {
        if (result.isNotEmpty) {
          context.read<AppProvider>().saveAiHistory(module: 'tasks', prompt: 'Break down task: "$goal"', response: result.join('\n'));
        }
        setState(() {
          _loading = false;
          _subTasks = result;
          _selected = List.filled(result.length, true);
        });
      }
    } catch (e) {
      debugPrint('[Tasks] AI breakdown error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addAllTasks() async {
    if (_subTasks == null) return;
    setState(() => _saving = true);
    try {
      final provider = context.read<AppProvider>();
      final db = provider.db;
      final familyId = provider.activeFamily!.id;
      final userId = provider.activeUser!.id;
      const uuid = Uuid();

      final selectedTitles = <String>[];
      for (int i = 0; i < _subTasks!.length; i++) {
        if (_selected[i]) selectedTitles.add(_subTasks![i]);
      }

      if (selectedTitles.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final newTasks = selectedTitles.map((title) => Task(
            id: uuid.v4(),
            familyId: familyId,
            title: title,
            completed: false,
            priority: Priority.MEDIUM,
            recurrence: Recurrence.NONE,
            dueDate: null,
            assignees: [userId],
            tags: ['AI Generated'],
            creatorId: userId,
          )).toList();

      final updatedTasks = [...db.tasks, ...newTasks];
      await provider.saveAndSync(db.copyWith(tasks: updatedTasks));
      if (provider.activeFamily != null) await provider.syncTasksNow();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${newTasks.length} task${newTasks.length == 1 ? '' : 's'}'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF6366F1)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Task Breakdown',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.stone900),
                        ),
                        Text(
                          'Break a goal into actionable steps',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Text('Describe your goal', style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _goalCtrl,
                    autofocus: _subTasks == null,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: "e.g. Plan Sarah's birthday party",
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _breakdown,
                      icon: _loading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                          : const Icon(Icons.auto_awesome, size: 16),
                      label: Text(_loading ? 'Generating...' : 'Generate Sub-Tasks'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),

                  // Results
                  if (_subTasks != null) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Generated sub-tasks', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700)),
                        ),
                        GestureDetector(
                          onTap: () {
                            final allSelected = _selected.every((s) => s);
                            setState(() {
                              for (int i = 0; i < _selected.length; i++) {
                                _selected[i] = !allSelected;
                              }
                            });
                          },
                          child: Text(
                            _selected.every((s) => s) ? 'Deselect all' : 'Select all',
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_subTasks!.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(12)),
                        child: const Column(
                          children: [
                            Icon(Icons.lightbulb_outline, size: 32, color: AppTheme.stone300),
                            SizedBox(height: 8),
                            Text('No sub-tasks generated. Try rephrasing your goal with more detail.',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      ...List.generate(_subTasks!.length, (i) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: _selected[i] ? const Color(0xFF7C3AED).withValues(alpha: 0.06) : AppTheme.stone50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selected[i] ? const Color(0xFF7C3AED).withValues(alpha: 0.25) : AppTheme.stone200,
                            ),
                          ),
                          child: CheckboxListTile(
                            value: _selected[i],
                            onChanged: (v) => setState(() => _selected[i] = v ?? false),
                            title: Text(
                              _subTasks![i],
                              style: TextStyle(
                                fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500,
                                color: _selected[i] ? AppTheme.stone900 : AppTheme.stone400,
                                decoration: _selected[i] ? null : TextDecoration.lineThrough,
                              ),
                            ),
                            activeColor: const Color(0xFF7C3AED),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      }),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_saving || _selected.every((s) => !s)) ? null : _addAllTasks,
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                            : Text('Add ${_selected.where((s) => s).length} Task${_selected.where((s) => s).length == 1 ? '' : 's'}'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Task card ────────────────────────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  final Task task;
  final AppProvider provider;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.provider,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(task.id),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: (task.completed ? AppTheme.warning : AppTheme.success).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              task.completed ? Icons.undo_rounded : Icons.check_circle_outline_rounded,
              color: task.completed ? AppTheme.warning : AppTheme.success,
            ),
            const SizedBox(width: 8),
            Text(
              task.completed ? 'Undo' : 'Complete',
              style: TextStyle(
                fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600,
                color: task.completed ? AppTheme.warning : AppTheme.success,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Delete', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.error)),
            SizedBox(width: 8),
            Icon(Icons.delete_outline_rounded, color: AppTheme.error),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Swipe right to toggle complete
          onToggle();
          return false; // don't remove from list, toggle handles state
        } else {
          // Swipe left to delete
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete Task'),
              content: Text('Delete "${task.title}"?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
              ],
            ),
          );
        }
      },
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onEdit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: task.completed ? AppTheme.stone50 : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: task.isOverdue
                  ? AppTheme.error.withValues(alpha: 0.3)
                  : task.completed
                      ? AppTheme.stone100
                      : AppTheme.stone200,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Animated checkbox
                GestureDetector(
                  onTap: onToggle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: task.completed
                            ? AppTheme.success
                            : task.isOverdue
                                ? AppTheme.error
                                : task.priority == Priority.HIGH
                                    ? AppTheme.error.withValues(alpha: 0.5)
                                    : AppTheme.stone300,
                        width: 2,
                      ),
                      color: task.completed ? AppTheme.success : Colors.transparent,
                    ),
                    child: task.completed
                        ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: task.completed ? AppTheme.stone400 : AppTheme.stone900,
                          decoration: task.completed ? TextDecoration.lineThrough : null,
                          decorationColor: AppTheme.stone300,
                        ),
                      ),
                      if (task.notes != null && task.notes!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          task.notes!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter', fontSize: 13,
                            color: task.completed ? AppTheme.stone300 : AppTheme.stone500,
                          ),
                        ),
                      ],
                      if (!task.completed) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            PriorityBadge(priority: task.priority.name.toUpperCase()),
                            if (task.dueDate != null)
                              _DueDateChip(dueDate: task.dueDate!, isOverdue: task.isOverdue),
                            if (task.recurrence != Recurrence.NONE)
                              _RecurrenceChip(recurrence: task.recurrence),
                            for (final tag in task.tags)
                              _TagChip(tag: tag),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Assignee avatars
                if (task.assigneeIds.isNotEmpty && !task.completed) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: task.assigneeIds.length == 1
                        ? 28
                        : 28 + (task.assigneeIds.length - 1) * 16.0,
                    height: 28,
                    child: Stack(
                      children: [
                        for (int i = 0; i < task.assigneeIds.length; i++)
                          Positioned(
                            left: i * 16.0,
                            child: AvatarInitials(
                              name: provider.displayNameForUserId(
                                task.assigneeIds[i],
                              ),
                              size: 28,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Chip widgets ─────────────────────────────────────────────────────────────

class _DueDateChip extends StatelessWidget {
  final DateTime dueDate;
  final bool isOverdue;

  const _DueDateChip({required this.dueDate, required this.isOverdue});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);

    String label;
    if (dueDay == today) {
      label = 'Today';
    } else if (dueDay == tomorrow) {
      label = 'Tomorrow';
    } else {
      label = DateFormat('MMM d').format(dueDate);
    }

    final color = isOverdue ? AppTheme.error : AppTheme.stone500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isOverdue ? Icons.warning_amber_rounded : Icons.calendar_today_outlined, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
          ),
        ],
      ),
    );
  }
}

class _RecurrenceChip extends StatelessWidget {
  final Recurrence recurrence;

  const _RecurrenceChip({required this.recurrence});

  @override
  Widget build(BuildContext context) {
    final labels = {
      Recurrence.DAILY: 'Daily',
      Recurrence.WEEKLY: 'Weekly',
      Recurrence.MONTHLY: 'Monthly',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.repeat_rounded, size: 10, color: AppTheme.primary),
          const SizedBox(width: 4),
          Text(
            labels[recurrence] ?? '',
            style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;
  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.stone100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tag,
        style: const TextStyle(fontSize: 11, color: AppTheme.stone500, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
      ),
    );
  }
}

// ─── Add / Edit task bottom sheet ─────────────────────────────────────────────

class _TaskFormSheet extends StatefulWidget {
  final Task? editTask;

  const _TaskFormSheet({this.editTask});

  @override
  State<_TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends State<_TaskFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _tagsCtrl;

  Priority _priority = Priority.MEDIUM;
  Recurrence _recurrence = Recurrence.NONE;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  int? _reminderMinutes;
  List<String> _assigneeIds = [];
  bool _loading = false;

  static const _reminderOptions = [
    (0, 'At time'),
    (5, '5 min'),
    (15, '15 min'),
    (30, '30 min'),
    (60, '1 hour'),
    (1440, '1 day'),
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.editTask;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _notesCtrl = TextEditingController(text: t?.notes ?? '');
    _tagsCtrl = TextEditingController(text: t?.tags.join(', ') ?? '');
    if (t != null) {
      _priority = t.priority;
      _recurrence = t.recurrence;
      _dueDate = t.dueDate;
      _assigneeIds = List.from(t.assignees);
      _reminderMinutes = t.reminderMinutes;
      if (t.dueTime != null && t.dueTime!.contains(':')) {
        final parts = t.dueTime!.split(':');
        _dueTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Warn if due date is in the past (only for new tasks)
    if (widget.editTask == null && _dueDate != null) {
      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      if (_dueDate!.isBefore(today)) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Past Due Date'),
            content: const Text('The due date is in the past. Create this task anyway?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create Anyway')),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    setState(() => _loading = true);
    try {
      final provider = context.read<AppProvider>();
      final db = provider.db;
      final familyId = provider.activeFamily!.id;
      final userId = provider.activeUser!.id;
      const uuid = Uuid();

      final tags = _tagsCtrl.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final dueTimeStr = _dueTime != null
          ? '${_dueTime!.hour.toString().padLeft(2, '0')}:${_dueTime!.minute.toString().padLeft(2, '0')}'
          : null;

      Task savedTask;
      if (widget.editTask != null) {
        savedTask = widget.editTask!.copyWith(
          title: _titleCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          priority: _priority,
          recurrence: _recurrence,
          dueDate: _dueDate,
          dueTime: dueTimeStr,
          reminderMinutes: _reminderMinutes,
          assignees: _assigneeIds,
          tags: tags,
          updatedAt: DateTime.now(),
        );
        final tasks = db.tasks.map((t) => t.id == savedTask.id ? savedTask : t).toList();
        await provider.saveAndSync(db.copyWith(tasks: tasks));
        if (provider.activeFamily != null) await provider.syncTasksNow();
      } else {
        savedTask = Task(
          id: uuid.v4(),
          familyId: familyId,
          title: _titleCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          completed: false,
          priority: _priority,
          recurrence: _recurrence,
          dueDate: _dueDate,
          dueTime: dueTimeStr,
          reminderMinutes: _reminderMinutes,
          assignees: _assigneeIds,
          tags: tags,
          creatorId: userId,
        );
        final tasks = [...db.tasks, savedTask];
        await provider.saveAndSync(db.copyWith(tasks: tasks));
        if (provider.activeFamily != null) await provider.syncTasksNow();

        // Notify family about new shared task
        try {
          if (_assigneeIds.length > 1 || (_assigneeIds.isNotEmpty && _assigneeIds.first != userId)) {
            NotificationService.notifyFamilyActivityWithDb(
              provider.db,
              title: 'New Task Assigned',
              body: '${provider.activeUser?.name ?? 'Someone'} created: ${savedTask.title}',
              path: '/tasks',
              familyId: provider.activeFamily?.id,
              excludeUserId: provider.activeUser?.id,
            );
          }
        } catch (_) {}
      }

      // Schedule reminder notification if configured
      try {
        if (savedTask.dueDate != null && dueTimeStr != null && _reminderMinutes != null) {
          await NotificationService.scheduleTaskReminder(
            taskId: savedTask.id,
            taskTitle: savedTask.title,
            dueDate: savedTask.dueDate!,
            dueTime: dueTimeStr,
            reminderMinutes: _reminderMinutes!,
          );
        } else {
          await NotificationService.cancelTaskReminder(savedTask.id);
        }
      } catch (_) {}

      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppProvider>();
    final members = provider.familyMembers;
    final isEditing = widget.editTask != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isEditing ? Icons.edit_outlined : Icons.add_task_rounded,
                            size: 18,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isEditing ? 'Edit Task' : 'New Task',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Title
                    TextFormField(
                      controller: _titleCtrl,
                      autofocus: !isEditing,
                      textCapitalization: TextCapitalization.sentences,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'What needs to be done?',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Notes
                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        hintText: 'Any extra details...',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Due date & time row
                    _sectionLabel('Schedule'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickDate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.stone50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.stone200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.stone500),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _dueDate != null ? DateFormat('EEE, MMM d').format(_dueDate!) : 'No date',
                                      style: TextStyle(
                                        fontFamily: 'Inter', fontSize: 13,
                                        color: _dueDate != null ? AppTheme.stone800 : AppTheme.stone400,
                                      ),
                                    ),
                                  ),
                                  if (_dueDate != null)
                                    GestureDetector(
                                      onTap: () => setState(() { _dueDate = null; _dueTime = null; _reminderMinutes = null; }),
                                      child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone400),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_dueDate != null) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: _dueTime ?? TimeOfDay.now(),
                              );
                              if (picked != null) setState(() => _dueTime = picked);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.stone50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.stone200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.stone500),
                                  const SizedBox(width: 8),
                                  Text(
                                    _dueTime != null ? _dueTime!.format(context) : 'Time',
                                    style: TextStyle(
                                      fontFamily: 'Inter', fontSize: 13,
                                      color: _dueTime != null ? AppTheme.stone800 : AppTheme.stone400,
                                    ),
                                  ),
                                  if (_dueTime != null) ...[
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () => setState(() { _dueTime = null; _reminderMinutes = null; }),
                                      child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone400),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Reminder
                    if (_dueDate != null && _dueTime != null) ...[
                      const SizedBox(height: 12),
                      _sectionLabel('Reminder'),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _MiniChip(label: 'None', selected: _reminderMinutes == null, onTap: () => setState(() => _reminderMinutes = null)),
                            ..._reminderOptions.map((opt) => _MiniChip(
                              label: opt.$2,
                              selected: _reminderMinutes == opt.$1,
                              onTap: () => setState(() => _reminderMinutes = opt.$1),
                            )),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Priority
                    _sectionLabel('Priority'),
                    const SizedBox(height: 8),
                    Row(
                      children: Priority.values.map((p) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: p != Priority.HIGH ? 8 : 0),
                          child: GestureDetector(
                            onTap: () => setState(() => _priority = p),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _priority == p ? _priorityColor(p).withValues(alpha: 0.1) : AppTheme.stone50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _priority == p ? _priorityColor(p) : AppTheme.stone200,
                                  width: _priority == p ? 1.5 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(_priorityIcon(p), size: 14, color: _priority == p ? _priorityColor(p) : AppTheme.stone400),
                                  const SizedBox(width: 4),
                                  Text(
                                    p.name[0].toUpperCase() + p.name.substring(1).toLowerCase(),
                                    style: TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Inter',
                                      color: _priority == p ? _priorityColor(p) : AppTheme.stone500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Recurrence
                    _sectionLabel('Repeat'),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: Recurrence.values.map((r) => _MiniChip(
                          label: _recurrenceLabel(r),
                          selected: _recurrence == r,
                          onTap: () => setState(() => _recurrence = r),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Assignees
                    if (members.isNotEmpty) ...[
                      _sectionLabel('Assign to'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: members.map((m) {
                          final selected = _assigneeIds.contains(m.id);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (selected) {
                                _assigneeIds.remove(m.id);
                              } else {
                                _assigneeIds.add(m.id);
                              }
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.stone50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected ? AppTheme.primary : AppTheme.stone200,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AvatarInitials(name: provider.memberDisplayName(m), size: 22),
                                  const SizedBox(width: 6),
                                  Text(
                                    provider.memberDisplayName(m).split(' ').first,
                                    style: TextStyle(
                                      fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600,
                                      color: selected ? AppTheme.primary : AppTheme.stone700,
                                    ),
                                  ),
                                  if (selected) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.check_rounded, size: 14, color: AppTheme.primary),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Tags
                    _sectionLabel('Tags'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _tagsCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Home, Shopping, Urgent...',
                        prefixIcon: Icon(Icons.label_outline_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save button
                    ElevatedButton(
                      onPressed: _loading ? null : _save,
                      child: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                          : Text(isEditing ? 'Save Changes' : 'Create Task'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700),
  );

  Color _priorityColor(Priority p) {
    switch (p) {
      case Priority.HIGH: return AppTheme.error;
      case Priority.MEDIUM: return AppTheme.warning;
      case Priority.LOW: return AppTheme.success;
    }
  }

  IconData _priorityIcon(Priority p) {
    switch (p) {
      case Priority.HIGH: return Icons.flag_rounded;
      case Priority.MEDIUM: return Icons.remove_circle_outline_rounded;
      case Priority.LOW: return Icons.arrow_downward_rounded;
    }
  }

  String _recurrenceLabel(Recurrence r) {
    switch (r) {
      case Recurrence.NONE: return 'Once';
      case Recurrence.DAILY: return 'Daily';
      case Recurrence.WEEKLY: return 'Weekly';
      case Recurrence.MONTHLY: return 'Monthly';
    }
  }
}

// ─── Mini chip for form selections ────────────────────────────────────────────

class _MiniChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MiniChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.stone50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.primary.withValues(alpha: 0.4) : AppTheme.stone200,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600,
              color: selected ? AppTheme.primary : AppTheme.stone500,
            ),
          ),
        ),
      ),
    );
  }
}

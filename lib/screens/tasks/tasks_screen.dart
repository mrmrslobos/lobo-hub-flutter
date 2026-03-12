// lib/screens/tasks/tasks_screen.dart
// Task management screen for FamilyHub

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

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
  String? _selectedFolder; // null = All Tasks, otherwise tag name
  String? _selectedMemberId; // null = all members
  String _searchQuery = '';

  static const _folderNames = ['Home', 'Work', 'Personal', 'Shopping', 'AI Generated', 'Event'];

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

      // Folder filter: match by tag (case-insensitive)
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
          return !t.completed &&
              (t.assigneeIds.contains(userId) ||
                  t.createdBy == userId);
        case _TaskFilter.others:
          return !t.completed &&
              !t.assigneeIds.contains(userId) &&
              t.createdBy != userId &&
              t.assigneeIds.isNotEmpty;
        case _TaskFilter.today:
          return !t.completed &&
              t.dueDate != null &&
              _isSameDay(t.dueDate!, today);
        case _TaskFilter.highPriority:
          return !t.completed && t.priority == Priority.HIGH;
        case _TaskFilter.done:
          return t.completed;
      }
    }).toList()
      ..sort((a, b) {
        // Sort: overdue first, then by due date, then by priority
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

  Future<void> _toggleComplete(
      BuildContext context, AppProvider provider, Task task) async {
    final db = provider.db;
    final updated = task.copyWith(completed: !task.completed);
    var tasks = db.tasks.map((t) => t.id == task.id ? updated : t).toList();

    // Generate next recurring instance when completing a recurring task
    if (updated.completed && task.recurrence != Recurrence.NONE && task.dueDate != null) {
      final nextDue = _nextRecurrenceDate(task.dueDate!, task.recurrence);
      final nextTask = task.copyWith(
        id: const Uuid().v4(),
        completed: false,
        completedBy: null,
        dueDate: nextDue,
      );
      tasks = [...tasks, nextTask];
      // Schedule reminder for new instance
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

  Future<void> _deleteTask(
      BuildContext context, AppProvider provider, Task task) async {
    final db = provider.db;
    final tasks = db.tasks.where((t) => t.id != task.id).toList();
    await provider.saveAndSync(db.copyWith(tasks: tasks));
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
        final otherTasks = allTasks.where((t) => !t.assigneeIds.contains(userId) && t.createdBy != userId).toList();
        final dueTodayTasks = allTasks.where((t) => t.dueDate != null && _isSameDay(t.dueDate!, today)).toList();
        final highPriorityTasks = allTasks.where((t) => t.priority == Priority.HIGH).toList();
        final doneTasks = provider.db.tasks.where((t) => t.familyId == familyId && t.completed).toList();

        // Folder counts (by tag, case-insensitive)
        final allCount = allTasks.length;
        int _folderCount(String folder) {
          final fl = folder.toLowerCase();
          return allTasks.where((t) => t.tags.any((tag) => tag.toLowerCase() == fl)).length;
        }

        // Progress
        final totalTasks = provider.db.tasks.where((t) => t.familyId == familyId).length;
        final completedCount = doneTasks.length;

        return Scaffold(
          drawer: const AppDrawer(),
          backgroundColor: AppTheme.background,
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
            actions: const [],
          ),
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Page Header
              PageHeader(
                title: 'Task Management',
                subtitle: 'Collaborate on chores, projects, and reminders.',
              ),

              // Full-width Add New Task button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: () => _showAddTaskSheet(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.stone800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 18, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Add New Task',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // AI Project Planner card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showAiBreakdownSheet(context),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AI Project Planner',
                                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                                  ),
                                  Text(
                                    'Break down goals into actionable tasks',
                                    style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 16, color: Colors.white.withValues(alpha: 0.6)),
                              const SizedBox(width: 10),
                              Text(
                                'Describe a project or goal...',
                                style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Generate',
                              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF7C3AED)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

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
                      _buildFolderItem('All Tasks', Icons.folder_outlined, allCount,
                        isSelected: _selectedFolder == null,
                        onTap: () => setState(() { _selectedFolder = null; _selectedMemberId = null; }),
                      ),
                      for (final folder in _folderNames) ...[
                        const Divider(height: 1),
                        _buildFolderItem(folder, Icons.folder_outlined, _folderCount(folder),
                          isSelected: _selectedFolder == folder,
                          onTap: () => setState(() { _selectedFolder = folder; _selectedMemberId = null; }),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // TEAM section
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
                          onTap: () => setState(() {
                            if (_selectedMemberId == members[i].id) {
                              _selectedMemberId = null; // deselect
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
                                Text(
                                  '${allTasks.where((t) => t.assigneeIds.contains(members[i].id)).length} tasks',
                                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: _selectedMemberId == members[i].id ? AppTheme.primary : AppTheme.stone400),
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
              const SizedBox(height: 16),

              // Filter chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      IndigoChip(
                        label: 'All',
                        selected: _filter == _TaskFilter.all,
                        onTap: () => setState(() => _filter = _TaskFilter.all),
                      ),
                      const SizedBox(width: 8),
                      IndigoChip(
                        label: 'My Tasks',
                        selected: _filter == _TaskFilter.mine,
                        onTap: () => setState(() => _filter = _TaskFilter.mine),
                      ),
                      const SizedBox(width: 8),
                      IndigoChip(
                        label: 'Others',
                        selected: _filter == _TaskFilter.others,
                        onTap: () => setState(() => _filter = _TaskFilter.others),
                      ),
                      const SizedBox(width: 8),
                      IndigoChip(
                        label: 'Due Today',
                        selected: _filter == _TaskFilter.today,
                        onTap: () => setState(() => _filter = _TaskFilter.today),
                      ),
                      const SizedBox(width: 8),
                      IndigoChip(
                        label: 'High Priority',
                        selected: _filter == _TaskFilter.highPriority,
                        onTap: () => setState(() => _filter = _TaskFilter.highPriority),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search tasks...',
                    hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.stone400),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => setState(() => _searchQuery = ''),
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
              const SizedBox(height: 12),

              // Progress indicator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      '$completedCount/$totalTasks done',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone500),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: totalTasks > 0 ? completedCount / totalTasks : 0,
                          minHeight: 6,
                          backgroundColor: AppTheme.stone100,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Task cards list
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        const Text('✅', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 12),
                        Text(
                          _filter == _TaskFilter.done ? 'No completed tasks' : 'No tasks here',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.stone500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _filter == _TaskFilter.done ? 'Complete a task to see it here' : 'Add a task to get started',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: tasks.map((task) => _TaskCard(
                      task: task,
                      provider: provider,
                      onToggle: () => _toggleComplete(context, provider, task),
                      onEdit: () => _showAddTaskSheet(context, editTask: task),
                      onDelete: () => _deleteTask(context, provider, task),
                    )).toList(),
                  ),
                ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
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
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppTheme.primary : AppTheme.stone700,
              ),
            ),
          ),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.stone100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
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
            tags: [],
            creatorId: userId,
          )).toList();

      final updatedTasks = [...db.tasks, ...newTasks];
      await provider.saveAndSync(db.copyWith(tasks: updatedTasks));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${newTasks.length} task${newTasks.length == 1 ? '' : 's'}!'),
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
                  const Text('✨', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'AI Task Breakdown',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: AppTheme.stone900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  // Goal input
                  Text(
                    'Describe your goal',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.stone700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _goalCtrl,
                    autofocus: _subTasks == null,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Plan Sarah\'s birthday party',
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _breakdown,
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Text('✨', style: TextStyle(fontSize: 14)),
                      label: Text(_loading ? 'Breaking down...' : 'Generate Sub-Tasks'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
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
                          child: Text(
                            'Generated sub-tasks',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.stone700,
                            ),
                          ),
                        ),
                        Text(
                          '${_selected.where((s) => s).length} selected',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppTheme.stone500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_subTasks!.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.stone50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'No sub-tasks were generated. Try rephrasing your goal.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppTheme.stone500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...List.generate(_subTasks!.length, (i) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: _selected[i]
                                ? const Color(0xFF8B5CF6).withValues(alpha: 0.06)
                                : AppTheme.stone50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selected[i]
                                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
                                  : AppTheme.stone200,
                            ),
                          ),
                          child: CheckboxListTile(
                            value: _selected[i],
                            onChanged: (v) => setState(() => _selected[i] = v ?? false),
                            title: Text(
                              _subTasks![i],
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _selected[i]
                                    ? AppTheme.stone900
                                    : AppTheme.stone400,
                                decoration: _selected[i]
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                            activeColor: const Color(0xFF8B5CF6),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      }),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_saving || _selected.every((s) => !s))
                            ? null
                            : _addAllTasks,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : Text(
                                'Add ${_selected.where((s) => s).length} Task${_selected.where((s) => s).length == 1 ? '' : 's'}',
                              ),
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
    final assignees = task.assigneeIds
        .map((id) => provider.userById(id))
        .whereType<User>()
        .toList();

    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_outline, color: AppTheme.error),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Task'),
          content: Text('Delete "${task.title}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onLongPress: onEdit,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: task.isOverdue
                  ? AppTheme.error.withValues(alpha: 0.3)
                  : AppTheme.stone100,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Checkbox
                GestureDetector(
                  onTap: onToggle,
                  child: Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: task.completed
                            ? AppTheme.success
                            : task.isOverdue
                                ? AppTheme.error
                                : AppTheme.stone300,
                        width: 2,
                      ),
                      color: task.completed
                          ? AppTheme.success
                          : Colors.transparent,
                    ),
                    child: task.completed
                        ? const Icon(Icons.check,
                            size: 14, color: Colors.white)
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
                          color: task.completed
                              ? AppTheme.stone400
                              : AppTheme.stone900,
                          decoration: task.completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (task.notes != null &&
                          task.notes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          task.notes!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppTheme.stone500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          PriorityBadge(
                              priority:
                                  task.priority.name.toUpperCase()),
                          if (task.dueDate != null)
                            _DueDateChip(dueDate: task.dueDate!,
                                isOverdue: task.isOverdue),
                          if (task.recurrence != Recurrence.NONE)
                            _RecurrenceChip(
                                recurrence: task.recurrence),
                          for (final tag in task.tags)
                            _TagChip(tag: tag),
                        ],
                      ),
                    ],
                  ),
                ),
                // Assignee avatars
                if (assignees.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: assignees.length == 1
                        ? 30
                        : 30 + (assignees.length - 1) * 18.0,
                    height: 30,
                    child: Stack(
                      children: [
                        for (int i = 0; i < assignees.length; i++)
                          Positioned(
                            left: i * 18.0,
                            child: AvatarInitials(
                              name: assignees[i].name,
                              size: 30,
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
    final label = DateFormat('MMM d').format(dueDate);
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
          Icon(Icons.calendar_today_outlined, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter'),
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
      child: Text(
        '↻ ${labels[recurrence] ?? ''}',
        style: const TextStyle(
            fontSize: 11,
            color: AppTheme.primary,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter'),
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
        '#$tag',
        style: const TextStyle(
            fontSize: 11,
            color: AppTheme.stone500,
            fontWeight: FontWeight.w500,
            fontFamily: 'Inter'),
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
    (0, 'At time of task'),
    (5, '5 minutes before'),
    (15, '15 minutes before'),
    (30, '30 minutes before'),
    (60, '1 hour before'),
    (1440, '1 day before'),
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
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
          priority: _priority,
          recurrence: _recurrence,
          dueDate: _dueDate,
          dueTime: dueTimeStr,
          reminderMinutes: _reminderMinutes,
          assignees: _assigneeIds,
          tags: tags,
        );
        final tasks = db.tasks
            .map((t) => t.id == savedTask.id ? savedTask : t)
            .toList();
        await provider.saveAndSync(db.copyWith(tasks: tasks));
      } else {
        savedTask = Task(
          id: uuid.v4(),
          familyId: familyId,
          title: _titleCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
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

        // Notify family about new shared task
        if (_assigneeIds.length > 1 || (_assigneeIds.isNotEmpty && _assigneeIds.first != userId)) {
          NotificationService.notifyFamilyActivity(
            title: 'New Task Assigned',
            body: '${provider.activeUser?.name ?? 'Someone'} created: ${savedTask.title}',
            payload: 'task:${savedTask.id}',
            familyId: provider.activeFamily?.id,
            excludeUserId: provider.activeUser?.id,
          );
        }
      }

      // Schedule reminder notification if configured
      if (savedTask.dueDate != null && dueTimeStr != null && _reminderMinutes != null) {
        await NotificationService.scheduleTaskReminder(
          taskId: savedTask.id,
          taskTitle: savedTask.title,
          dueDate: savedTask.dueDate!,
          dueTime: dueTimeStr,
          reminderMinutes: _reminderMinutes!,
        );
      } else {
        // Cancel any existing reminder if settings removed
        await NotificationService.cancelTaskReminder(savedTask.id);
      }

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppProvider>();
    final members = provider.familyMembers;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                    Text(
                      widget.editTask != null ? 'Edit Task' : 'New Task',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.stone900,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    TextFormField(
                      controller: _titleCtrl,
                      autofocus: true,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Title is required'
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Title *',
                        hintText: 'What needs to be done?',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Notes
                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        hintText: 'Any extra details...',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Due date
                    _sheetSectionLabel('Due date'),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.stone50,
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: AppTheme.stone200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                size: 18, color: AppTheme.stone500),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _dueDate != null
                                    ? DateFormat('EEE, MMM d yyyy')
                                        .format(_dueDate!)
                                    : 'No due date',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  color: _dueDate != null
                                      ? AppTheme.stone800
                                      : AppTheme.stone400,
                                ),
                              ),
                            ),
                            if (_dueDate != null)
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _dueDate = null),
                                child: const Icon(Icons.clear,
                                    size: 18,
                                    color: AppTheme.stone400),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Due time (only shown when due date is set)
                    if (_dueDate != null) ...[
                      _sheetSectionLabel('Due time'),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _dueTime ?? TimeOfDay.now(),
                          );
                          if (picked != null) setState(() => _dueTime = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.stone50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.stone200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time_rounded, size: 18, color: AppTheme.stone500),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _dueTime != null
                                      ? _dueTime!.format(context)
                                      : 'No time set',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 14,
                                    color: _dueTime != null ? AppTheme.stone800 : AppTheme.stone400,
                                  ),
                                ),
                              ),
                              if (_dueTime != null)
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _dueTime = null;
                                    _reminderMinutes = null;
                                  }),
                                  child: const Icon(Icons.clear, size: 18, color: AppTheme.stone400),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Reminder (only shown when due date + time are set)
                    if (_dueDate != null && _dueTime != null) ...[
                      _sheetSectionLabel('Reminder'),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // "None" option
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: IndigoChip(
                                label: 'None',
                                selected: _reminderMinutes == null,
                                onTap: () => setState(() => _reminderMinutes = null),
                              ),
                            ),
                            ..._reminderOptions.map((opt) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: IndigoChip(
                                label: opt.$2,
                                selected: _reminderMinutes == opt.$1,
                                onTap: () => setState(() => _reminderMinutes = opt.$1),
                              ),
                            )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Priority
                    _sheetSectionLabel('Priority'),
                    const SizedBox(height: 8),
                    Row(
                      children: Priority.values
                          .map((p) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                      right: 6),
                                  child: GestureDetector(
                                    onTap: () => setState(
                                        () => _priority = p),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 150),
                                      padding:
                                          const EdgeInsets.symmetric(
                                              vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _priority == p
                                            ? _priorityColor(p)
                                                .withValues(alpha: 0.12)
                                            : AppTheme.stone50,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _priority == p
                                              ? _priorityColor(p)
                                              : AppTheme.stone200,
                                          width:
                                              _priority == p ? 1.5 : 1,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        p.name[0].toUpperCase() +
                                            p.name.substring(1),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight:
                                              FontWeight.w600,
                                          fontFamily: 'Inter',
                                          color: _priority == p
                                              ? _priorityColor(p)
                                              : AppTheme.stone500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),

                    // Recurrence
                    _sheetSectionLabel('Recurrence'),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: Recurrence.values
                            .map((r) => Padding(
                                  padding:
                                      const EdgeInsets.only(right: 8),
                                  child: IndigoChip(
                                    label: _recurrenceLabel(r),
                                    selected: _recurrence == r,
                                    onTap: () => setState(
                                        () => _recurrence = r),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Assignees
                    if (members.isNotEmpty) ...[
                      _sheetSectionLabel('Assignees'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: members.map((m) {
                          final selected =
                              _assigneeIds.contains(m.id);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (selected) {
                                _assigneeIds.remove(m.id);
                              } else {
                                _assigneeIds.add(m.id);
                              }
                            }),
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppTheme.primary.withValues(alpha: 0.1)
                                    : AppTheme.stone100,
                                borderRadius:
                                    BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? AppTheme.primary
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AvatarInitials(
                                      name: provider.memberDisplayName(m), size: 22),
                                  const SizedBox(width: 6),
                                  Text(
                                    provider.memberDisplayName(m).split(' ').first,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? AppTheme.primary
                                          : AppTheme.stone700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Tags
                    TextFormField(
                      controller: _tagsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tags',
                        hintText: 'school, urgent, shopping',
                        prefixIcon: Icon(Icons.label_outline),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save button
                    ElevatedButton(
                      onPressed: _loading ? null : _save,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                    Colors.white),
                              ),
                            )
                          : Text(widget.editTask != null
                              ? 'Save Changes'
                              : 'Add Task'),
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

  Widget _sheetSectionLabel(String label) => Text(
        label,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.stone700,
        ),
      );

  Color _priorityColor(Priority p) {
    switch (p) {
      case Priority.HIGH:
        return AppTheme.error;
      case Priority.MEDIUM:
        return AppTheme.warning;
      case Priority.LOW:
        return AppTheme.success;
    }
  }

  String _recurrenceLabel(Recurrence r) {
    switch (r) {
      case Recurrence.NONE:
        return 'None';
      case Recurrence.DAILY:
        return 'Daily';
      case Recurrence.WEEKLY:
        return 'Weekly';
      case Recurrence.MONTHLY:
        return 'Monthly';
    }
  }
}

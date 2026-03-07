// lib/screens/tasks/tasks_screen.dart
// Task management screen for FamilyHub

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/common_widgets.dart';

// ─── Filter enum ──────────────────────────────────────────────────────────────

enum _TaskFilter { all, mine, today, done }

// ─── Tasks screen ─────────────────────────────────────────────────────────────

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  _TaskFilter _filter = _TaskFilter.all;

  List<Task> _filteredTasks(AppProvider provider) {
    final familyId = provider.activeFamily?.id;
    final userId = provider.activeUser?.id;
    if (familyId == null) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return provider.db.tasks.where((t) {
      if (t.familyId != familyId) return false;
      switch (_filter) {
        case _TaskFilter.all:
          return !t.completed;
        case _TaskFilter.mine:
          return !t.completed &&
              (t.assigneeIds.contains(userId) ||
                  t.createdBy == userId);
        case _TaskFilter.today:
          return !t.completed &&
              t.dueDate != null &&
              _isSameDay(t.dueDate!, today);
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
    final tasks =
        db.tasks.map((t) => t.id == task.id ? updated : t).toList();
    await provider.saveAndSync(db.copyWith(tasks: tasks));
  }

  Future<void> _deleteTask(
      BuildContext context, AppProvider provider, Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task'),
        content: Text('Delete "${task.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final db = provider.db;
      final tasks = db.tasks.where((t) => t.id != task.id).toList();
      await provider.saveAndSync(db.copyWith(tasks: tasks));
    }
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

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final tasks = _filteredTasks(provider);

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Column(
            children: [
              // ─── Header ───────────────────────────────────────────────
              const GradientHeader(
                title: 'Tasks',
                subtitle: 'Manage your family to-dos',
                startColor: AppTheme.primary,
                endColor: Color(0xFF8B5CF6),
              ),
              // ─── Filter tabs ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: AppTabBar(
                  tabs: const ['All', 'Mine', 'Today', 'Done'],
                  selectedIndex: _filter.index,
                  onSelected: (i) =>
                      setState(() => _filter = _TaskFilter.values[i]),
                ),
              ),
              // ─── Task list ────────────────────────────────────────────
              Expanded(
                child: tasks.isEmpty
                    ? EmptyState(
                        emoji: '✅',
                        title: _filter == _TaskFilter.done
                            ? 'No completed tasks'
                            : 'No tasks here',
                        subtitle: _filter == _TaskFilter.done
                            ? 'Complete a task to see it here'
                            : 'Tap + to add a new task',
                        actionLabel: _filter != _TaskFilter.done
                            ? 'Add Task'
                            : null,
                        onAction: () =>
                            _showAddTaskSheet(context),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                            16, 0, 16, 100),
                        itemCount: tasks.length,
                        itemBuilder: (ctx, i) {
                          final task = tasks[i];
                          return _TaskCard(
                            task: task,
                            provider: provider,
                            onToggle: () => _toggleComplete(
                                context, provider, task),
                            onEdit: () => _showAddTaskSheet(
                                context,
                                editTask: task),
                            onDelete: () =>
                                _deleteTask(context, provider, task),
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddTaskSheet(context),
            child: const Icon(Icons.add),
          ),
        );
      },
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
          color: AppTheme.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_outline, color: AppTheme.error),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // We handle deletion ourselves
      },
      child: GestureDetector(
        onLongPress: onEdit,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: task.isOverdue
                  ? AppTheme.error.withOpacity(0.3)
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
                          if (task.recurrence != TaskRecurrence.none)
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
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
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
  final TaskRecurrence recurrence;

  const _RecurrenceChip({required this.recurrence});

  @override
  Widget build(BuildContext context) {
    final labels = {
      TaskRecurrence.daily: 'Daily',
      TaskRecurrence.weekly: 'Weekly',
      TaskRecurrence.monthly: 'Monthly',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
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

  TaskPriority _priority = TaskPriority.medium;
  TaskRecurrence _recurrence = TaskRecurrence.none;
  DateTime? _dueDate;
  List<String> _assigneeIds = [];
  bool _loading = false;

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
      _assigneeIds = List.from(t.assigneeIds);
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

      if (widget.editTask != null) {
        final updated = widget.editTask!.copyWith(
          title: _titleCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
          priority: _priority,
          recurrence: _recurrence,
          dueDate: _dueDate,
          assigneeIds: _assigneeIds,
          tags: tags,
        );
        final tasks = db.tasks
            .map((t) => t.id == updated.id ? updated : t)
            .toList();
        await provider.saveAndSync(db.copyWith(tasks: tasks));
      } else {
        final task = Task(
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
          assigneeIds: _assigneeIds,
          tags: tags,
          createdBy: userId,
          createdAt: DateTime.now(),
        );
        final tasks = [...db.tasks, task];
        await provider.saveAndSync(db.copyWith(tasks: tasks));
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

                    // Priority
                    _sheetSectionLabel('Priority'),
                    const SizedBox(height: 8),
                    Row(
                      children: TaskPriority.values
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
                                                .withOpacity(0.12)
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
                        children: TaskRecurrence.values
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
                                    ? AppTheme.primary.withOpacity(0.1)
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
                                      name: m.name, size: 22),
                                  const SizedBox(width: 6),
                                  Text(
                                    m.name.split(' ').first,
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

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.high:
        return AppTheme.error;
      case TaskPriority.medium:
        return AppTheme.warning;
      case TaskPriority.low:
        return AppTheme.success;
    }
  }

  String _recurrenceLabel(TaskRecurrence r) {
    switch (r) {
      case TaskRecurrence.none:
        return 'None';
      case TaskRecurrence.daily:
        return 'Daily';
      case TaskRecurrence.weekly:
        return 'Weekly';
      case TaskRecurrence.monthly:
        return 'Monthly';
    }
  }
}

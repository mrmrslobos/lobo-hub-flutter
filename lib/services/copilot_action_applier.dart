// lib/services/copilot_action_applier.dart
// Applies validated copilot JSON actions to [AppDB].

import 'package:uuid/uuid.dart';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';

const _uuid = Uuid();

/// Result of applying copilot actions to the database.
class CopilotApplyResult {
  final AppDB db;
  final Set<String> pushTableScope;
  final List<String> appliedSummaries;
  final List<String> errors;

  const CopilotApplyResult({
    required this.db,
    required this.pushTableScope,
    required this.appliedSummaries,
    required this.errors,
  });
}

class CopilotActionApplier {
  CopilotActionApplier._();

  /// Human-readable lines for confirmation UI (Phase 1 trust).
  static List<String> describeActionsForUi(List<dynamic> actions) {
    final out = <String>[];
    for (final raw in actions) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final type = m['type'] as String? ?? '';
      final payload = m['payload'];
      if (payload is! Map) continue;
      final p = Map<String, dynamic>.from(payload);
      switch (type) {
        case 'create_task':
          final t = p['title']?.toString().trim() ?? 'Task';
          out.add('Add task: $t');
          break;
        case 'create_event':
          final t = p['title']?.toString().trim() ?? 'Event';
          out.add('Add calendar event: $t');
          break;
        case 'create_shopping_list':
          final t = p['title']?.toString().trim() ?? 'List';
          final items = p['items'];
          final n = items is List ? items.length : 0;
          out.add(n > 0 ? 'Create list “$t” with $n items' : 'Create list “$t”');
          break;
        case 'add_list_items':
          final sub = p['list_title_substring']?.toString() ?? p['list_id']?.toString() ?? 'list';
          final items = p['items'];
          final n = items is List ? items.length : 0;
          out.add('Add $n item(s) to list matching “$sub”');
          break;
        case 'create_meal_plan_entry':
          final meal = p['custom_meal']?.toString().trim() ?? 'Meal';
          out.add('Add to meal plan: $meal');
          break;
        case 'create_chore':
          final t = p['title']?.toString().trim() ?? 'Chore';
          out.add('Add chore: $t');
          break;
        default:
          break;
      }
    }
    if (out.isEmpty) return ['Review actions in chat above'];
    return out;
  }

  static Priority _parsePriority(dynamic v) {
    final s = v?.toString().toUpperCase() ?? '';
    if (s == 'LOW') return Priority.LOW;
    if (s == 'HIGH') return Priority.HIGH;
    return Priority.MEDIUM;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static ChoreFrequency _parseChoreFreq(dynamic v) {
    final s = v?.toString().toUpperCase() ?? '';
    if (s == 'WEEKLY') return ChoreFrequency.WEEKLY;
    return ChoreFrequency.DAILY;
  }

  /// Parses server-sanitized copilot JSON and applies [actions] to [db].
  static CopilotApplyResult apply({
    required AppDB db,
    required String familyId,
    required String userId,
    required List<dynamic> actions,
  }) {
    final scopes = <String>{};
    final summaries = <String>[];
    final errors = <String>[];

    var next = db;
    var tasks = List<Task>.from(next.tasks);
    var events = List<CalendarEvent>.from(next.events);
    var lists = List<ShoppingList>.from(next.lists);
    var mealPlans = List<MealPlanEntry>.from(next.mealPlans);
    var chores = List<Chore>.from(next.chores);

    for (final raw in actions) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final type = m['type'] as String? ?? '';
      final payload = m['payload'];
      if (payload is! Map) continue;
      final p = Map<String, dynamic>.from(payload);

      try {
        switch (type) {
          case 'create_task':
            final title = p['title']?.toString().trim() ?? '';
            if (title.isEmpty) {
              errors.add('create_task: missing title');
              break;
            }
            final due = _parseDate(p['due_date'] ?? p['dueDate']);
            tasks = [
              ...tasks,
              Task(
                id: _uuid.v4(),
                familyId: familyId,
                creatorId: userId,
                title: title,
                notes: p['notes']?.toString(),
                dueDate: due,
                dueTime: p['due_time']?.toString() ?? p['dueTime']?.toString(),
                reminderMinutes: (p['reminder_minutes'] as num?)?.toInt() ??
                    (p['reminderMinutes'] as num?)?.toInt(),
                priority: _parsePriority(p['priority']),
                visibility: Visibility.FAMILY,
              ),
            ];
            scopes.add(CloudSyncScope.tasks);
            summaries.add('Task: $title');
            break;

          case 'create_event':
            final title = p['title']?.toString().trim() ?? '';
            final start = _parseDate(p['start'] ?? p['start_iso']);
            final end = _parseDate(p['end'] ?? p['end_iso']);
            if (title.isEmpty || start == null || end == null) {
              errors.add('create_event: need title, start, end');
              break;
            }
            var desc = p['description']?.toString();
            if (desc == null || desc.isEmpty) {
              desc = 'Added via Family copilot';
            } else if (!desc.contains('copilot')) {
              desc = '$desc\n(Source: Family copilot)';
            }
            events = [
              ...events,
              CalendarEvent(
                id: _uuid.v4(),
                familyId: familyId,
                creatorId: userId,
                title: title,
                description: desc,
                location: p['location']?.toString(),
                start: start,
                end: end.isBefore(start) ? start.add(const Duration(hours: 1)) : end,
                visibility: Visibility.FAMILY,
              ),
            ];
            scopes.add(CloudSyncScope.events);
            summaries.add('Event: $title');
            break;

          case 'create_shopping_list':
            final title = p['title']?.toString().trim() ?? 'Shopping list';
            final rawItems = p['items'];
            final items = <ListItem>[];
            if (rawItems is List) {
              for (final it in rawItems) {
                if (it is Map) {
                  final im = Map<String, dynamic>.from(it);
                  final text = im['text']?.toString() ?? im['name']?.toString() ?? '';
                  if (text.trim().isEmpty) continue;
                  items.add(ListItem(
                    id: _uuid.v4(),
                    text: text.trim(),
                    quantity: im['quantity']?.toString(),
                  ));
                } else if (it != null) {
                  final text = it.toString().trim();
                  if (text.isNotEmpty) {
                    items.add(ListItem(id: _uuid.v4(), text: text));
                  }
                }
              }
            }
            lists = [
              ...lists,
              ShoppingList(
                id: _uuid.v4(),
                familyId: familyId,
                creatorId: userId,
                title: title,
                items: items,
                category: ListCategory.GROCERY,
                visibility: Visibility.FAMILY,
              ),
            ];
            scopes.add(CloudSyncScope.lists);
            summaries.add('List: $title (${items.length} items)');
            break;

          case 'add_list_items':
            final listId = p['list_id']?.toString() ?? p['listId']?.toString();
            final sub = p['list_title_substring']?.toString().toLowerCase() ??
                p['list_title']?.toString().toLowerCase();
            ShoppingList? target;
            if (listId != null && listId.isNotEmpty) {
              for (final l in lists) {
                if (l.id == listId) {
                  target = l;
                  break;
                }
              }
            }
            if (target == null && sub != null && sub.isNotEmpty) {
              for (final l in lists) {
                if (l.familyId == familyId && l.title.toLowerCase().contains(sub)) {
                  target = l;
                  break;
                }
              }
            }
            if (target == null) {
              errors.add('add_list_items: list not found');
              break;
            }
            final rawItems = p['items'];
            final newItems = List<ListItem>.from(target.items);
            if (rawItems is List) {
              for (final it in rawItems) {
                if (it is Map) {
                  final im = Map<String, dynamic>.from(it);
                  final text = im['text']?.toString() ?? im['name']?.toString() ?? '';
                  if (text.trim().isEmpty) continue;
                  newItems.add(ListItem(
                    id: _uuid.v4(),
                    text: text.trim(),
                    quantity: im['quantity']?.toString(),
                  ));
                }
              }
            }
            final tid = target.id;
            lists = lists
                .map((l) => l.id == tid ? l.copyWith(items: newItems) : l)
                .toList();
            scopes.add(CloudSyncScope.lists);
            summaries.add('Added items to "${target.title}"');
            break;

          case 'create_meal_plan_entry':
            final date = _parseDate(p['date'] ?? p['date_iso']);
            final mealType = (p['meal_type'] ?? p['mealType'] ?? 'dinner').toString().toLowerCase();
            final custom = p['custom_meal']?.toString() ?? p['customMeal']?.toString() ?? '';
            if (date == null || custom.trim().isEmpty) {
              errors.add('create_meal_plan_entry: need date and custom_meal');
              break;
            }
            mealPlans = [
              ...mealPlans,
              MealPlanEntry(
                id: _uuid.v4(),
                familyId: familyId,
                date: DateTime(date.year, date.month, date.day),
                mealType: mealType,
                customMeal: custom.trim(),
                createdBy: userId,
              ),
            ];
            scopes.add(CloudSyncScope.mealPlans);
            summaries.add('Meal: $custom on $mealType');
            break;

          case 'create_chore':
            final title = p['title']?.toString().trim() ?? '';
            if (title.isEmpty) {
              errors.add('create_chore: missing title');
              break;
            }
            chores = [
              ...chores,
              Chore(
                id: _uuid.v4(),
                familyId: familyId,
                creatorId: userId,
                title: title,
                description: p['description']?.toString(),
                points: (p['points'] as num?)?.toInt() ?? 5,
                frequency: _parseChoreFreq(p['frequency']),
                visibility: Visibility.FAMILY,
              ),
            ];
            scopes.add(CloudSyncScope.chores);
            summaries.add('Chore: $title');
            break;

          default:
            break;
        }
      } catch (e) {
        errors.add('$type: $e');
      }
    }

    next = next.copyWith(
      tasks: tasks,
      events: events,
      lists: lists,
      mealPlans: mealPlans,
      chores: chores,
    );

    return CopilotApplyResult(
      db: next,
      pushTableScope: scopes,
      appliedSummaries: summaries,
      errors: errors,
    );
  }
}

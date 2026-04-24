import 'package:flutter/material.dart';

import 'app_config.dart';

/// Module catalogue — defines all available app modules.
class ModuleGroup {
  final String label;
  final List<ModuleInfo> modules;

  const ModuleGroup({required this.label, required this.modules});
}

class ModuleInfo {
  final String path;
  final String name;
  final String emoji;
  final String desc;

  const ModuleInfo({
    required this.path,
    required this.name,
    required this.emoji,
    required this.desc,
  });
}

const moduleGroups = [
  ModuleGroup(
    label: 'Family',
    modules: [
      ModuleInfo(path: '/chat', name: 'Chat', emoji: '💬', desc: 'Messages and reactions'),
      ModuleInfo(path: '/assistant', name: 'Family copilot', emoji: '🤖', desc: 'Ask AI to update tasks, calendar, lists, and meals'),
      ModuleInfo(path: '/tasks', name: 'Tasks', emoji: '✅', desc: 'Shared to-dos and who’s doing what'),
      ModuleInfo(path: '/calendar', name: 'Calendar', emoji: '📅', desc: 'Events and the family schedule'),
      ModuleInfo(path: '/chores', name: 'Chores', emoji: '🧹', desc: 'Chore charts and tracking'),
      ModuleInfo(path: '/lists', name: 'Shopping lists', emoji: '📋', desc: 'Groceries, packing, and shared lists'),
      ModuleInfo(path: '/polls', name: 'Polls', emoji: '🗳️', desc: 'Vote on family decisions'),
      ModuleInfo(path: '/birthdays', name: 'Occasions', emoji: '🎉', desc: 'Birthdays, anniversaries, and special dates'),
      ModuleInfo(path: '/photos', name: 'Photos', emoji: '📸', desc: 'Album and milestones'),
      ModuleInfo(path: '/location', name: 'Locations', emoji: '📍', desc: 'Where everyone is and saved places'),
      ModuleInfo(path: '/health', name: 'Health', emoji: '❤️', desc: 'Records and emergency info'),
    ],
  ),
  ModuleGroup(
    label: 'Daily life',
    modules: [
      ModuleInfo(path: '/habits', name: 'Habits', emoji: '🎯', desc: 'Daily habits and streaks'),
      ModuleInfo(path: '/meals', name: 'Meals', emoji: '🍽️', desc: 'Meal planning and recipes'),
      ModuleInfo(path: '/fitness', name: 'Fitness', emoji: '💪', desc: 'Workouts and activity'),
      ModuleInfo(path: '/period-tracker', name: 'Cycle tracking', emoji: '🌸', desc: 'Period and wellness'),
      ModuleInfo(path: '/devotional', name: 'Reading & faith', emoji: '📖', desc: 'Daily reading and reflection'),
      ModuleInfo(path: '/prayer-wall', name: 'Prayer board', emoji: '🙏', desc: 'Share requests and thanks'),
    ],
  ),
  ModuleGroup(
    label: 'Money',
    modules: [
      ModuleInfo(path: '/budget', name: 'Budget', emoji: '💰', desc: 'Family expense tracking'),
      ModuleInfo(path: '/rewards', name: 'Rewards', emoji: '🎁', desc: 'Earn & redeem rewards'),
    ],
  ),
];

const essentialModules = ['/tasks', '/calendar', '/chores', '/rewards', '/meals', '/habits'];

List<String> get allModulePaths =>
    moduleGroups.expand((g) => g.modules.map((m) => m.path)).toList();

String getModulePath(String moduleName) {
  for (final group in moduleGroups) {
    for (final m in group.modules) {
      if (m.name == moduleName) return m.path;
    }
  }
  return '/';
}

ModuleInfo? getModuleByPath(String path) {
  for (final group in moduleGroups) {
    for (final m in group.modules) {
      if (m.path == path) return m;
    }
  }
  return null;
}

/// Module keys without a leading slash (as stored in `Family.enabledModules`).
List<ModuleInfo> modulesInCatalogOrder(Iterable<String> keysWithoutSlash) {
  final keySet = keysWithoutSlash.map((k) => k.trim()).where((k) => k.isNotEmpty).toSet();
  final out = <ModuleInfo>[];
  for (final g in moduleGroups) {
    for (final m in g.modules) {
      final k = m.path.replaceFirst('/', '');
      if (keySet.contains(k)) out.add(m);
    }
  }
  return out;
}

// ── Drawer + jump menu (single route order; labels from [getModuleByPath]) ──

class DrawerNavEntry {
  final String path;
  final IconData icon;

  const DrawerNavEntry({required this.path, required this.icon});
}

class DrawerNavSectionSpec {
  final String title;
  final List<DrawerNavEntry> entries;

  const DrawerNavSectionSpec({required this.title, required this.entries});
}

/// Side drawer layout: section titles and route order. Labels match [moduleGroups] names.
const drawerNavSectionSpecs = [
  DrawerNavSectionSpec(title: 'Family', entries: [
    DrawerNavEntry(path: '/chat', icon: Icons.chat_bubble_outline_rounded),
    DrawerNavEntry(path: '/assistant', icon: Icons.auto_awesome_rounded),
    DrawerNavEntry(path: '/tasks', icon: Icons.check_circle_outline_rounded),
    DrawerNavEntry(path: '/calendar', icon: Icons.calendar_month_rounded),
    DrawerNavEntry(path: '/chores', icon: Icons.assignment_turned_in_outlined),
    DrawerNavEntry(path: '/lists', icon: Icons.checklist_rounded),
    DrawerNavEntry(path: '/polls', icon: Icons.how_to_vote_outlined),
    DrawerNavEntry(path: '/birthdays', icon: Icons.cake_outlined),
    DrawerNavEntry(path: '/photos', icon: Icons.photo_library_outlined),
    DrawerNavEntry(path: '/location', icon: Icons.location_on_outlined),
    DrawerNavEntry(path: '/health', icon: Icons.favorite_outline_rounded),
  ]),
  DrawerNavSectionSpec(title: 'Daily life', entries: [
    DrawerNavEntry(path: '/habits', icon: Icons.track_changes_rounded),
    DrawerNavEntry(path: '/meals', icon: Icons.restaurant_menu_rounded),
    DrawerNavEntry(path: '/fitness', icon: Icons.fitness_center_rounded),
    DrawerNavEntry(path: '/period-tracker', icon: Icons.spa_outlined),
    DrawerNavEntry(path: '/devotional', icon: Icons.menu_book_rounded),
    DrawerNavEntry(path: '/prayer-wall', icon: Icons.volunteer_activism_outlined),
  ]),
  DrawerNavSectionSpec(title: 'Money', entries: [
    DrawerNavEntry(path: '/budget', icon: Icons.account_balance_wallet_outlined),
    DrawerNavEntry(path: '/rewards', icon: Icons.card_giftcard_rounded),
  ]),
];

/// Routes in the jump menu that are not part of [moduleGroups] (onboarding catalogue).
const accountJumpModules = [
  ModuleInfo(path: '/subscription', name: 'Subscription', emoji: '👑', desc: 'Plans and billing'),
  ModuleInfo(path: '/ai-history', name: 'AI activity', emoji: '🤖', desc: 'Prompt history'),
];

/// Screen title aligned with the module catalogue (and account extras).
String screenTitleForModulePath(String path) {
  final fromCatalog = getModuleByPath(path)?.name;
  if (fromCatalog != null) return fromCatalog;
  for (final m in accountJumpModules) {
    if (m.path == path) return m.name;
  }
  return AppConfig.appName;
}

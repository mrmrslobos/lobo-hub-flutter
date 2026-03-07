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
      ModuleInfo(path: '/chat', name: 'Chat', emoji: '💬', desc: 'Family messages & reactions'),
      ModuleInfo(path: '/tasks', name: 'Tasks', emoji: '✅', desc: 'Shared to-dos & assignments'),
      ModuleInfo(path: '/calendar', name: 'Calendar', emoji: '📅', desc: 'Events & family schedule'),
      ModuleInfo(path: '/chores', name: 'Chores', emoji: '🧹', desc: 'Chore charts & tracking'),
      ModuleInfo(path: '/lists', name: 'Lists', emoji: '📋', desc: 'Shopping & packing lists'),
      ModuleInfo(path: '/polls', name: 'Polls', emoji: '🗳️', desc: 'Vote on family decisions'),
      ModuleInfo(path: '/birthdays', name: 'Occasions', emoji: '🎉', desc: 'Birthdays, anniversaries & special dates'),
      ModuleInfo(path: '/photos', name: 'Photos', emoji: '📸', desc: 'Family album & milestones'),
      ModuleInfo(path: '/location', name: 'Location', emoji: '📍', desc: 'See where everyone is'),
      ModuleInfo(path: '/health', name: 'Health', emoji: '❤️', desc: 'Health records & emergency info'),
    ],
  ),
  ModuleGroup(
    label: 'Lifestyle',
    modules: [
      ModuleInfo(path: '/habits', name: 'Habits', emoji: '🎯', desc: 'Daily habit tracking & streaks'),
      ModuleInfo(path: '/meals', name: 'Meals', emoji: '🍽️', desc: 'Meal planning & recipes'),
      ModuleInfo(path: '/fitness', name: 'Fitness', emoji: '💪', desc: 'Health & workout tracking'),
      ModuleInfo(path: '/period-tracker', name: 'Period Tracker', emoji: '🌸', desc: 'Cycle & wellness tracking'),
      ModuleInfo(path: '/devotional', name: 'Devotional', emoji: '📖', desc: 'Daily faith & reflection'),
      ModuleInfo(path: '/prayer-wall', name: 'Prayer Wall', emoji: '🙏', desc: 'Gratitude & prayer sharing'),
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

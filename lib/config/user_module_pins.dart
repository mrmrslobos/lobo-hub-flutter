import '../models/models.dart' show Family, User;
import 'module_config.dart' show getModuleByPath, homeQuickActionPathsFor, isModulePathEnabledForFamily;

/// Synced in [User.settings] as a JSON list of route paths (e.g. `/tasks`).
const String kUserPinnedModulePathsKey = 'pinned_module_paths';
const int kMaxUserPinnedModulePaths = 6;
const int kMaxDashboardQuickIcons = 5;

List<String> pinnedModulePathsFromUser(User? u) {
  if (u == null) return [];
  final v = u.settings[kUserPinnedModulePathsKey];
  if (v is! List) return [];
  final out = <String>[];
  for (final e in v) {
    var p = e.toString().trim();
    if (p.isEmpty) continue;
    if (!p.startsWith('/')) p = '/$p';
    if (getModuleByPath(p) == null) continue;
    if (out.length >= kMaxUserPinnedModulePaths) break;
    if (!out.contains(p)) out.add(p);
  }
  return out;
}

/// Pinned modules first (when set), then default essentials — max [kMaxDashboardQuickIcons], family-enabled only.
List<String> resolvedDashboardQuickPaths(Family family, User? u) {
  final seen = <String>{};
  final out = <String>[];

  void add(String p) {
    if (out.length >= kMaxDashboardQuickIcons) return;
    if (!isModulePathEnabledForFamily(p, family)) return;
    if (getModuleByPath(p) == null) return;
    if (seen.add(p)) out.add(p);
  }

  for (final p in pinnedModulePathsFromUser(u)) {
    add(p);
  }
  if (out.isEmpty) {
    for (final p in homeQuickActionPathsFor(family)) {
      add(p);
    }
    return out;
  }
  for (final p in homeQuickActionPathsFor(family)) {
    add(p);
  }
  return out;
}

bool isPathPinned(String path, User? u) => pinnedModulePathsFromUser(u).contains(path);

/// Toggle [path] in the pin list. Returns the new list, or null if at cap and not removing.
List<String>? togglePinnedPath(List<String> current, String path) {
  if (current.contains(path)) {
    return List<String>.from(current)..remove(path);
  }
  if (current.length >= kMaxUserPinnedModulePaths) return null;
  return List<String>.from(current)..add(path);
}

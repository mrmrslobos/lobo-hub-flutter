import 'package:flutter_test/flutter_test.dart';
import 'package:lobohub/config/module_config.dart';

void main() {
  test('allModulePaths matches catalogue size', () {
    var count = 0;
    for (final g in moduleGroups) {
      count += g.modules.length;
    }
    expect(allModulePaths.length, count);
    expect(allModulePaths.toSet().length, count);
  });

  test('screenTitleForModulePath matches catalogue for module routes', () {
    for (final g in moduleGroups) {
      for (final m in g.modules) {
        expect(screenTitleForModulePath(m.path), m.name);
      }
    }
    expect(screenTitleForModulePath('/subscription'), 'Subscription');
    expect(screenTitleForModulePath('/ai-history'), 'AI activity');
  });

  test('drawerNavSectionSpecs cover same routes as moduleGroups', () {
    final fromDrawer = <String>{};
    for (final s in drawerNavSectionSpecs) {
      for (final e in s.entries) {
        fromDrawer.add(e.path);
      }
    }
    final fromCatalog = allModulePaths.toSet();
    expect(fromDrawer, fromCatalog);
  });
}

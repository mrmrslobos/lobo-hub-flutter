import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the last few module paths visited (for Home “Recents”).
class RecentRoutesService {
  static const _prefKey = 'lobohub_recent_module_paths_v1';
  static const int _max = 6;

  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static List<String>? _mem;

  static Future<List<String>> getPaths() async {
    if (_mem != null) return List<String>.of(_mem!);
    final p = await SharedPreferences.getInstance();
    _mem = p.getStringList(_prefKey) ?? <String>[];
    return List<String>.of(_mem!);
  }

  static Future<void> recordPath(String path) async {
    if (path.isEmpty || path == '/' || path == '/auth' || path.startsWith('/auth')) {
      return;
    }
    final p = await SharedPreferences.getInstance();
    var list = List<String>.from(p.getStringList(_prefKey) ?? <String>[]);
    list.remove(path);
    list.insert(0, path);
    if (list.length > _max) {
      list = list.sublist(0, _max);
    }
    await p.setStringList(_prefKey, list);
    _mem = list;
    version.value++;
  }
}

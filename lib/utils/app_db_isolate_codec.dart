import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// JSON encode on a worker isolate (VM/desktop/mobile). [map] must be sendable.
String encodeAppDbMap(Map<String, dynamic> map) => jsonEncode(map);

/// Decode prefs JSON inside a worker isolate for large payloads (VM only via [compute]).
AppDB decodeAppDbInWorker(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return AppDB.fromJson(json);
  } catch (e, st) {
    debugPrint('[AppDB] isolate decode failed: $e\n$st');
    return AppDB.empty();
  }
}

/// Decode SharedPreferences JSON into [AppDB]. Uses an isolate when the blob is large (VM).
Future<AppDB> loadAppDbFromPrefsJson(String raw) async {
  if (raw.isEmpty) return AppDB.empty();
  if (kIsWeb || raw.length < 65536) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AppDB.fromJson(json);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AppDB] load decode failed: $e\n$st');
      }
      return AppDB.empty();
    }
  }
  return compute(decodeAppDbInWorker, raw);
}

/// Encode [AppDB] for persistence. Uses a worker isolate on VM to reduce UI jank.
Future<String> encodeAppDbForPrefs(AppDB db) async {
  if (kIsWeb) {
    return jsonEncode(db.toJson());
  }
  final map = db.toJson();
  return compute(encodeAppDbMap, map);
}

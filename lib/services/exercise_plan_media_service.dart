// Resolves exercise illustrations: ExerciseDB public API + cache, then wger fallback.

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_db_service.dart';
import 'wger_exercise_service.dart';

class ExercisePlanMediaService {
  ExercisePlanMediaService._();

  /// Bumped when ExerciseDB host/auth changes (e.g. RapidAPI → exercisedb.dev).
  static const _prefsKey = 'fh_exercise_db_name_cache_v2';

  static Future<Map<String, dynamic>> _loadCache() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final d = jsonDecode(raw);
      if (d is Map) {
        return Map<String, dynamic>.from(d as Map);
      }
    } catch (_) {}
    return {};
  }

  static Future<void> _saveCache(Map<String, dynamic> map) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, jsonEncode(map));
  }

  static String _cacheKey(String exerciseName) {
    var s = exerciseName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  static bool _isLegacyPaidUrl(String url) =>
      url.contains('rapidapi.com') || url.contains('rapidapi-key=');

  /// Strip legacy RapidAPI image URLs before cloud sync.
  static List<dynamic> weeklyPlanForCloud(List<dynamic> weeklyPlan) {
    final out = <dynamic>[];
    for (final day in weeklyPlan) {
      if (day is! Map) {
        out.add(day);
        continue;
      }
      final d = Map<String, dynamic>.from(day as Map);
      final exs = d['exercises'];
      if (exs is! List) {
        out.add(d);
        continue;
      }
      d['exercises'] = exs.map((e) {
        if (e is! Map) {
          return e;
        }
        final m = Map<String, dynamic>.from(e as Map);
        final url = m['imageUrl']?.toString() ?? '';
        if (_isLegacyPaidUrl(url)) {
          m.remove('imageUrl');
        }
        return m;
      }).toList();
      out.add(d);
    }
    return out;
  }

  static void normalizeWeeklyPlanKey(Map<dynamic, dynamic> plan) {
    WgerExerciseImageService.normalizeWeeklyPlanKey(plan);
  }

  static Future<void> enrichPlanMap(Map<String, dynamic> plan) async {
    normalizeWeeklyPlanKey(plan);
    final wp = plan['weeklyPlan'];
    if (wp is List) {
      await enrichWeeklyPlan(wp);
    }
  }

  static Future<({String? imageUrl, String? exerciseDbId})> resolveForExerciseName(
    String exerciseName,
  ) async {
    final key = _cacheKey(exerciseName);
    if (key.isEmpty) {
      return (imageUrl: null, exerciseDbId: null);
    }
    var cache = await _loadCache();
    final hit = cache[key];
    if (hit is Map) {
      final hm = Map<String, dynamic>.from(hit as Map);
      final id = hm['exerciseDbId']?.toString().trim();
      var gif = hm['gifUrl']?.toString().trim();
      if (id != null && id.isNotEmpty) {
        if (gif == null || gif.isEmpty || _isLegacyPaidUrl(gif)) {
          gif = await ExerciseDBService.fetchGifUrl(id);
          if (gif != null && gif.isNotEmpty) {
            cache[key] = {'exerciseDbId': id, 'gifUrl': gif};
            await _saveCache(cache);
          }
        }
        if (gif != null && gif.isNotEmpty && !_isLegacyPaidUrl(gif)) {
          return (imageUrl: gif, exerciseDbId: id);
        }
        return (imageUrl: null, exerciseDbId: id);
      }
    }

    final r = await ExerciseDBService.searchExercise(exerciseName);
    if (r != null) {
      cache[key] = {
        'exerciseDbId': r.id,
        if (r.gifUrl != null && r.gifUrl!.isNotEmpty) 'gifUrl': r.gifUrl,
      };
      await _saveCache(cache);
      final gif = (r.gifUrl != null && !_isLegacyPaidUrl(r.gifUrl!)) ? r.gifUrl : null;
      return (imageUrl: gif, exerciseDbId: r.id);
    }

    final wger = await WgerExerciseImageService.resolveImageUrl(exerciseName);
    return (imageUrl: wger, exerciseDbId: null);
  }

  static Future<void> enrichWeeklyPlan(List<dynamic> weeklyPlan) async {
    var cache = await _loadCache();
    var dirty = false;

    for (final day in weeklyPlan) {
      if (day is! Map) {
        continue;
      }
      final exs = day['exercises'];
      if (exs is! List) {
        continue;
      }
      for (var i = 0; i < exs.length; i++) {
        final e = exs[i];
        if (e is! Map) {
          continue;
        }
        final em = Map<String, dynamic>.from(e as Map);
        final name = em['name']?.toString().trim() ?? '';
        if (name.isEmpty) {
          continue;
        }
        final key = _cacheKey(name);
        if (key.isEmpty) {
          continue;
        }

        final existingEdb = em['exerciseDbId']?.toString().trim();
        var existingImg = em['imageUrl']?.toString().trim();

        if (existingImg != null &&
            existingImg.isNotEmpty &&
            !_isLegacyPaidUrl(existingImg)) {
          continue;
        }

        if (existingImg != null && _isLegacyPaidUrl(existingImg)) {
          em.remove('imageUrl');
          existingImg = null;
        }

        Map<String, dynamic>? cachedEntry;
        final hit = cache[key];
        if (hit is Map) {
          cachedEntry = Map<String, dynamic>.from(hit as Map);
        }

        String? exerciseDbId = cachedEntry?['exerciseDbId']?.toString();
        String? gifUrl = cachedEntry?['gifUrl']?.toString();

        if (exerciseDbId == null || exerciseDbId.isEmpty) {
          final r = await ExerciseDBService.searchExercise(name);
          if (r != null) {
            exerciseDbId = r.id;
            gifUrl = r.gifUrl;
            cache[key] = {
              'exerciseDbId': exerciseDbId,
              if (gifUrl != null && gifUrl.isNotEmpty) 'gifUrl': gifUrl,
            };
            dirty = true;
          }
        } else if ((gifUrl == null || gifUrl.isEmpty || _isLegacyPaidUrl(gifUrl)) &&
            exerciseDbId.isNotEmpty) {
          gifUrl = await ExerciseDBService.fetchGifUrl(exerciseDbId);
          if (gifUrl != null && gifUrl.isNotEmpty) {
            cache[key] = {'exerciseDbId': exerciseDbId, 'gifUrl': gifUrl};
            dirty = true;
          }
        }

        if (exerciseDbId != null && exerciseDbId.isNotEmpty) {
          em['exerciseDbId'] = exerciseDbId;
          var pub = gifUrl != null && gifUrl.isNotEmpty && !_isLegacyPaidUrl(gifUrl)
              ? gifUrl
              : null;
          pub ??= await ExerciseDBService.fetchGifUrl(exerciseDbId);
          if (pub != null && pub.isNotEmpty) {
            em['imageUrl'] = pub;
          }
          exs[i] = em;
          continue;
        }

        if (existingImg == null || existingImg.isEmpty) {
          final wger = await WgerExerciseImageService.resolveImageUrl(name);
          if (wger != null) {
            em['imageUrl'] = wger;
            exs[i] = em;
          }
        }
      }
    }

    if (dirty) {
      await _saveCache(cache);
    }
  }
}

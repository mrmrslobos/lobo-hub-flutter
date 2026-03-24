// Resolves exercise illustrations for AI fitness plans: ExerciseDB (RapidAPI) + cache, then wger fallback.

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_db_service.dart';
import 'wger_exercise_service.dart';

class ExercisePlanMediaService {
  ExercisePlanMediaService._();

  static const _prefsKey = 'fh_exercise_db_name_cache_v1';

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

  /// Strip RapidAPI query keys from plan JSON before cloud sync (belt-and-suspenders).
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
        if (url.contains('rapidapi.com') || url.contains('rapidapi-key=')) {
          m.remove('imageUrl');
        }
        return m;
      }).toList();
      out.add(d);
    }
    return out;
  }

  /// Copy of wger normalizer (single place for plan shape).
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

  /// Resolve media for [exerciseName]; used when logging manual workouts.
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
      final gif = hm['gifUrl']?.toString().trim();
      if (id != null && id.isNotEmpty) {
        final publicGif = (gif != null &&
                gif.isNotEmpty &&
                !gif.contains('rapidapi.com') &&
                !gif.contains('rapidapi-key='))
            ? gif
            : null;
        if (publicGif != null) {
          return (imageUrl: publicGif, exerciseDbId: id);
        }
        if (ExerciseDBService.isConfigured) {
          return (
            imageUrl: ExerciseDBService.gifImageRequestUrl(id),
            exerciseDbId: id,
          );
        }
        return (imageUrl: null, exerciseDbId: id);
      }
    }
    if (ExerciseDBService.isConfigured) {
      final r = await ExerciseDBService.searchExercise(exerciseName);
      if (r != null) {
        cache[key] = {
          'exerciseDbId': r.id,
          if (r.gifUrl != null && r.gifUrl!.isNotEmpty) 'gifUrl': r.gifUrl,
        };
        await _saveCache(cache);
        final publicGif = (r.gifUrl != null &&
                r.gifUrl!.isNotEmpty &&
                !r.gifUrl!.contains('rapidapi.com'))
            ? r.gifUrl
            : null;
        return (
          imageUrl: publicGif ?? ExerciseDBService.gifImageRequestUrl(r.id),
          exerciseDbId: r.id,
        );
      }
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
        final existingImg = em['imageUrl']?.toString().trim();
        if (existingEdb != null &&
            existingEdb.isNotEmpty &&
            (existingImg == null || existingImg.isEmpty) &&
            ExerciseDBService.isConfigured) {
          em['imageUrl'] = ExerciseDBService.gifImageRequestUrl(existingEdb);
          exs[i] = em;
          continue;
        }
        if (existingImg != null &&
            existingImg.isNotEmpty &&
            !existingImg.contains('rapidapi.com')) {
          continue;
        }

        Map<String, dynamic>? cachedEntry;
        final hit = cache[key];
        if (hit is Map) {
          cachedEntry = Map<String, dynamic>.from(hit as Map);
        }

        String? exerciseDbId = cachedEntry?['exerciseDbId']?.toString();
        String? gifUrl = cachedEntry?['gifUrl']?.toString();

        if (exerciseDbId == null || exerciseDbId.isEmpty) {
          if (ExerciseDBService.isConfigured) {
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
          }
        }

        if (exerciseDbId != null && exerciseDbId.isNotEmpty) {
          em['exerciseDbId'] = exerciseDbId;
          final pub = gifUrl != null &&
                  gifUrl.isNotEmpty &&
                  !gifUrl.contains('rapidapi.com') &&
                  !gifUrl.contains('rapidapi-key=')
              ? gifUrl
              : null;
          em['imageUrl'] = pub ?? ExerciseDBService.gifImageRequestUrl(exerciseDbId);
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

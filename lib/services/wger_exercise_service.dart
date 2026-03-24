// Free exercise metadata + images from wger (https://wger.de) — no API key.
// Respect their terms: cache-friendly, low request volume.

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Resolve illustration URLs for movement names (English) via wger.de API.
class WgerExerciseImageService {
  static const _base = 'https://wger.de';
  static final _mem = <String, String?>{};

  static const _headers = {
    'User-Agent': 'FamilyHub/1.0 (+https://github.com/mrmrslobos/lobo-hub-flutter)',
    'Accept': 'application/json',
  };

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();

  /// Meaningful tokens for search (skip generic equipment words).
  static List<String> _searchTokens(String exerciseName) {
    final stop = {
      'barbell', 'dumbbell', 'db', 'kb', 'kettlebell', 'cable', 'machine',
      'smith', 'incline', 'decline', 'seated', 'standing', 'single', 'arm',
      'double', 'alternating', 'reverse', 'front', 'back', 'the', 'a', 'an',
      'leg', 'legs', 'one', 'two',
    };
    return _norm(exerciseName)
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1 && !stop.contains(w))
        .toList();
  }

  /// Primary search query: first non-stop word (legacy behavior).
  static String _primaryQuery(String exerciseName) {
    final t = _searchTokens(exerciseName);
    if (t.isNotEmpty) {
      return t.first;
    }
    final parts = _norm(exerciseName).split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    return parts.isNotEmpty ? parts.first : _norm(exerciseName);
  }

  static Future<String?> _firstImageForExerciseId(int exerciseId) async {
    final imgUri = Uri.parse(
      '$_base/api/v2/exerciseimage/?exercise=$exerciseId&is_main=true',
    );
    var imgRes = await http.get(imgUri, headers: _headers).timeout(const Duration(seconds: 8));
    if (imgRes.statusCode != 200) {
      return null;
    }
    var imgJson = jsonDecode(imgRes.body) as Map<String, dynamic>;
    var imgs = imgJson['results'] as List<dynamic>? ?? [];
    String? url = _imageUrlFromResults(imgs);
    if (url != null) {
      return url;
    }
    final anyUri = Uri.parse('$_base/api/v2/exerciseimage/?exercise=$exerciseId');
    imgRes = await http.get(anyUri, headers: _headers).timeout(const Duration(seconds: 8));
    if (imgRes.statusCode != 200) {
      return null;
    }
    imgJson = jsonDecode(imgRes.body) as Map<String, dynamic>;
    imgs = imgJson['results'] as List<dynamic>? ?? [];
    return _imageUrlFromResults(imgs);
  }

  static String? _imageUrlFromResults(List<dynamic> imgs) {
    for (final item in imgs) {
      if (item is! Map) {
        continue;
      }
      final m = Map<String, dynamic>.from(item as Map);
      final img = m['image']?.toString();
      if (img != null && img.isNotEmpty) {
        return img.startsWith('http') ? img : '$_base$img';
      }
    }
    return null;
  }

  static Future<String?> _resolveWithSearchQuery(String exerciseName, String query) async {
    final qKey = _norm('$exerciseName|q:$query');
    if (_mem.containsKey(qKey)) {
      return _mem[qKey];
    }

    try {
      final q = Uri.encodeComponent(query);
      final searchUri = Uri.parse(
        '$_base/api/v2/exercise/?language=2&limit=12&search=$q',
      );
      final searchRes =
          await http.get(searchUri, headers: _headers).timeout(const Duration(seconds: 8));
      if (searchRes.statusCode != 200) {
        _mem[qKey] = null;
        return null;
      }
      final searchJson = jsonDecode(searchRes.body) as Map<String, dynamic>;
      final results = searchJson['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) {
        _mem[qKey] = null;
        return null;
      }

      final ids = <int>[];
      for (final r in results) {
        if (r is! Map) {
          continue;
        }
        final id = (r['id'] as num?)?.toInt();
        if (id != null && !ids.contains(id)) {
          ids.add(id);
        }
      }

      // First hit often has no images (e.g. abstract variation); try several.
      for (final id in ids.take(10)) {
        final url = await _firstImageForExerciseId(id);
        if (url != null) {
          _mem[qKey] = url;
          return url;
        }
      }
      _mem[qKey] = null;
      return null;
    } catch (e) {
      debugPrint('[Wger] resolve failed for "$exerciseName" query="$query": $e');
      _mem[qKey] = null;
      return null;
    }
  }

  /// Public cache key is normalized exercise name only (so callers share hits).
  static Future<String?> resolveImageUrl(String exerciseName) async {
    final key = _norm(exerciseName);
    if (key.isEmpty) {
      return null;
    }
    if (_mem.containsKey(key)) {
      return _mem[key];
    }

    final primary = _primaryQuery(exerciseName);
    var url = await _resolveWithSearchQuery(exerciseName, primary);
    if (url != null) {
      _mem[key] = url;
      return url;
    }

    final tokens = _searchTokens(exerciseName);
    if (tokens.length >= 2) {
      url = await _resolveWithSearchQuery(exerciseName, tokens.take(2).join(' '));
      if (url != null) {
        _mem[key] = url;
        return url;
      }
    }

    final full = _norm(exerciseName).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (full.isNotEmpty && full != primary) {
      url = await _resolveWithSearchQuery(exerciseName, full);
      if (url != null) {
        _mem[key] = url;
        return url;
      }
    }

    _mem[key] = null;
    return null;
  }

  /// Normalize plan JSON so UI + enrich use `weeklyPlan` (camelCase).
  static void normalizeWeeklyPlanKey(Map<dynamic, dynamic> plan) {
    if (plan['weeklyPlan'] is List) {
      return;
    }
    final wp = plan['weekly_plan'];
    if (wp is List) {
      plan['weeklyPlan'] = wp;
    }
  }

  /// After AI save/refine: ensure list key + illustrations.
  static Future<void> enrichPlanMap(Map<String, dynamic> plan) async {
    normalizeWeeklyPlanKey(plan);
    final wp = plan['weeklyPlan'];
    if (wp is List) {
      await enrichWeeklyPlan(wp);
    }
  }

  /// Attach `imageUrl` to each exercise map in [weeklyPlan] (mutates list items).
  static Future<void> enrichWeeklyPlan(List<dynamic> weeklyPlan) async {
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
        final name = e['name']?.toString() ?? '';
        if (name.isEmpty) {
          continue;
        }
        final existing = e['imageUrl']?.toString().trim();
        if (existing != null && existing.isNotEmpty) {
          continue;
        }
        final url = await resolveImageUrl(name);
        if (url != null) {
          final em = Map<String, dynamic>.from(e as Map);
          exs[i] = {...em, 'imageUrl': url};
        }
      }
    }
  }
}

// ExerciseDB public v1 API (no API key) — used during AI plan enrichment; results cached locally.
// Docs: https://exercisedb.dev/docs

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ExerciseDBService {
  ExerciseDBService._();

  static const _base = 'https://exercisedb.dev/api/v1';

  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'FamilyHub/1.0 (+https://github.com/mrmrslobos/lobo-hub-flutter)',
  };

  /// Public API — always attempt lookups (falls back to wger in caller if needed).
  static bool get isConfigured => true;

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();

  static String _normKey(String exerciseName) =>
      _norm(exerciseName).replaceAll(RegExp(r'\s+'), ' ');

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

  static String _primaryQuery(String exerciseName) {
    final t = _searchTokens(exerciseName);
    if (t.isNotEmpty) return t.first;
    final parts = _norm(exerciseName).split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    return parts.isNotEmpty ? parts.first : _norm(exerciseName);
  }

  static double _nameScore(String query, String candidate) {
    final q = _normKey(query);
    final c = _normKey(candidate);
    if (c.isEmpty) return 0;
    if (c == q) return 1;
    if (c.contains(q) || q.contains(c)) return 0.85;
    final qTokens = q.split(' ').where((t) => t.length > 1).toSet();
    final cTokens = c.split(' ').where((t) => t.length > 1).toSet();
    if (qTokens.isEmpty) return 0;
    final inter = qTokens.intersection(cTokens).length;
    return inter / qTokens.length;
  }

  static String? _gifFromJson(Map<String, dynamic> j) {
    for (final key in const [
      'gifUrl',
      'gif_url',
      'gif',
      'imageUrl',
      'image_url',
    ]) {
      final v = j[key]?.toString().trim();
      if (v != null && v.isNotEmpty) {
        if (v.startsWith('http://') || v.startsWith('https://')) return v;
        if (v.startsWith('//')) return 'https:$v';
      }
    }
    return null;
  }

  static String? _exerciseIdFromMap(Map<String, dynamic> m) {
    final a = m['exerciseId']?.toString().trim();
    if (a != null && a.isNotEmpty) return a;
    final b = m['id']?.toString().trim();
    if (b != null && b.isNotEmpty) return b;
    return null;
  }

  static List<Map<String, dynamic>> _parseSearchList(dynamic decoded) {
    if (decoded is! Map) return [];
    final ok = decoded['success'] == true;
    if (!ok) return [];
    final data = decoded['data'];
    if (data is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in data) {
      if (item is Map) {
        out.add(Map<String, dynamic>.from(item as Map));
      }
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> _searchRaw(String q) async {
    if (q.trim().length < 2) return [];
    final uri = Uri.parse('$_base/exercises/search').replace(
      queryParameters: {
        'q': q.trim(),
        'limit': '12',
        'threshold': '0.25',
      },
    );
    try {
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        debugPrint('[ExerciseDB] search ${res.statusCode} for "$q"');
        return [];
      }
      return _parseSearchList(jsonDecode(res.body));
    } catch (e) {
      debugPrint('[ExerciseDB] search "$q": $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> _fetchExerciseMap(String exerciseId) async {
    final uri = Uri.parse('$_base/exercises/${Uri.encodeComponent(exerciseId)}');
    try {
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['success'] != true) return null;
      final data = decoded['data'];
      if (data is Map) {
        return Map<String, dynamic>.from(data as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Resolve GIF URL for [exerciseId] (detail endpoint).
  static Future<String?> fetchGifUrl(String exerciseId) async {
    if (exerciseId.trim().isEmpty) return null;
    final m = await _fetchExerciseMap(exerciseId.trim());
    if (m == null) return null;
    return _gifFromJson(m);
  }

  /// Search by exercise name; returns best match id + optional direct gifUrl.
  static Future<({String id, String? gifUrl})?> searchExercise(String exerciseName) async {
    final q = exerciseName.trim();
    if (q.length < 2) return null;

    Future<({String id, String? gifUrl})?> pickBest(String searchQuery) async {
      final rows = await _searchRaw(searchQuery);
      if (rows.isEmpty) return null;
      Map<String, dynamic>? best;
      var bestScore = 0.0;
      for (final m in rows) {
        final name = m['name']?.toString() ?? '';
        final id = _exerciseIdFromMap(m);
        if (id == null || id.isEmpty) continue;
        final sc = _nameScore(q, name);
        if (sc > bestScore) {
          bestScore = sc;
          best = m;
        }
      }
      best ??= rows.first;
      final id = _exerciseIdFromMap(best);
      if (id == null || id.isEmpty) return null;
      var gif = _gifFromJson(best);
      gif ??= await fetchGifUrl(id);
      return (id: id, gifUrl: gif);
    }

    var result = await pickBest(q);
    if (result != null) return result;

    final tokens = _searchTokens(q);
    if (tokens.length >= 2) {
      result = await pickBest(tokens.take(2).join(' '));
      if (result != null) return result;
    }

    final primary = _primaryQuery(q);
    if (primary.isNotEmpty && primary != q) {
      result = await pickBest(primary);
    }
    return result;
  }
}

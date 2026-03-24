// ExerciseDB via RapidAPI — used during AI plan enrichment only; results cached locally.
// Set at build time: --dart-define=RAPIDAPI_KEY=your_key
// Docs: https://edb-docs.up.railway.app/

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ExerciseDBService {
  ExerciseDBService._();

  static const _host = 'exercisedb.p.rapidapi.com';
  static const _base = 'https://$_host';

  /// RapidAPI subscription key (never commit real keys).
  static const String rapidApiKeyFromEnv = String.fromEnvironment(
    'RAPIDAPI_KEY',
    defaultValue: '',
  );

  static bool get isConfigured =>
      rapidApiKeyFromEnv.isNotEmpty && !rapidApiKeyFromEnv.startsWith('YOUR_');

  static Map<String, String> rapidApiHeaders() => {
        'X-RapidAPI-Key': rapidApiKeyFromEnv,
        'X-RapidAPI-Host': _host,
        'Accept': 'application/json',
      };

  /// GIF stream URL (requires same headers when fetching).
  static String gifImageRequestUrl(String exerciseId, {String resolution = '360'}) =>
      '$_base/image?exerciseId=${Uri.encodeQueryComponent(exerciseId)}&resolution=$resolution';

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();

  static String _normKey(String exerciseName) =>
      _norm(exerciseName).replaceAll(RegExp(r'\s+'), ' ');

  static double _nameScore(String query, String candidate) {
    final q = _normKey(query);
    final c = _normKey(candidate);
    if (c.isEmpty) {
      return 0;
    }
    if (c == q) {
      return 1;
    }
    if (c.contains(q) || q.contains(c)) {
      return 0.85;
    }
    final qTokens = q.split(' ').where((t) => t.length > 1).toSet();
    final cTokens = c.split(' ').where((t) => t.length > 1).toSet();
    if (qTokens.isEmpty) {
      return 0;
    }
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
        if (v.startsWith('http://') || v.startsWith('https://')) {
          return v;
        }
        if (v.startsWith('//')) {
          return 'https:$v';
        }
      }
    }
    return null;
  }

  static String? _idFromJson(Map<String, dynamic> j) {
    final raw = j['id'];
    if (raw == null) {
      return null;
    }
    return raw.toString();
  }

  /// Search by name; returns best-matching exercise id + optional direct GIF URL.
  static Future<({String id, String? gifUrl})?> searchExercise(String exerciseName) async {
    if (!isConfigured) {
      return null;
    }
    final q = exerciseName.trim();
    if (q.length < 2) {
      return null;
    }
    final pathSeg = Uri.encodeComponent(q);
    final uri = Uri.parse('$_base/exercises/name/$pathSeg?limit=10');
    try {
      final res = await http
          .get(uri, headers: rapidApiHeaders())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        debugPrint('[ExerciseDB] name search ${res.statusCode} for "$q"');
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! List || decoded.isEmpty) {
        return null;
      }
      Map<String, dynamic>? best;
      var bestScore = 0.0;
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final m = Map<String, dynamic>.from(item as Map);
        final name = m['name']?.toString() ?? '';
        final id = _idFromJson(m);
        if (id == null || id.isEmpty) {
          continue;
        }
        final sc = _nameScore(q, name);
        if (sc > bestScore) {
          bestScore = sc;
          best = m;
        }
      }
      best ??= Map<String, dynamic>.from(decoded.first as Map);
      final id = _idFromJson(best);
      if (id == null || id.isEmpty) {
        return null;
      }
      var gif = _gifFromJson(best);
      if (gif == null || gif.isEmpty) {
        gif = await _fetchGifByExerciseId(id);
      }
      return (id: id, gifUrl: gif);
    } catch (e) {
      debugPrint('[ExerciseDB] searchExercise "$q": $e');
      return null;
    }
  }

  static Future<String?> _fetchGifByExerciseId(String id) async {
    final uri = Uri.parse('$_base/exercises/exercise/${Uri.encodeComponent(id)}');
    try {
      final res = await http
          .get(uri, headers: rapidApiHeaders())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        return _gifFromJson(Map<String, dynamic>.from(decoded as Map));
      }
    } catch (_) {}
    return null;
  }
}

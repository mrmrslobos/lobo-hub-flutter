// Free exercise metadata + images from wger (https://wger.de) — no API key.
// Respect their terms: cache-friendly, low request volume.

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Resolve a thumbnail / illustration URL for a movement name (English).
class WgerExerciseImageService {
  static const _base = 'https://wger.de';
  static final _mem = <String, String?>{};

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();

  /// First meaningful token (skip "barbell", "dumbbell", etc.).
  static String _searchQuery(String exerciseName) {
    final stop = {
      'barbell', 'dumbbell', 'db', 'kb', 'kettlebell', 'cable', 'machine',
      'smith', 'incline', 'decline', 'seated', 'standing', 'single', 'arm',
      'double', 'alternating', 'reverse', 'front', 'back', 'the', 'a', 'an',
    };
    final parts = _norm(exerciseName).split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    for (final w in parts) {
      if (!stop.contains(w)) return w;
    }
    return parts.isNotEmpty ? parts.first : _norm(exerciseName);
  }

  static Future<String?> resolveImageUrl(String exerciseName) async {
    final key = _norm(exerciseName);
    if (key.isEmpty) return null;
    if (_mem.containsKey(key)) return _mem[key];

    try {
      final q = Uri.encodeComponent(_searchQuery(exerciseName));
      final searchUri = Uri.parse(
        '$_base/api/v2/exercise/?language=2&limit=5&search=$q',
      );
      final searchRes = await http.get(searchUri).timeout(const Duration(seconds: 6));
      if (searchRes.statusCode != 200) {
        _mem[key] = null;
        return null;
      }
      final searchJson = jsonDecode(searchRes.body) as Map<String, dynamic>;
      final results = searchJson['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) {
        _mem[key] = null;
        return null;
      }
      int? exId;
      for (final r in results) {
        if (r is! Map) continue;
        final id = (r['id'] as num?)?.toInt();
        if (id != null) {
          exId = id;
          break;
        }
      }
      if (exId == null) {
        _mem[key] = null;
        return null;
      }

      final imgUri = Uri.parse(
        '$_base/api/v2/exerciseimage/?exercise=$exId&is_main=true',
      );
      final imgRes = await http.get(imgUri).timeout(const Duration(seconds: 6));
      if (imgRes.statusCode != 200) {
        _mem[key] = null;
        return null;
      }
      final imgJson = jsonDecode(imgRes.body) as Map<String, dynamic>;
      final imgs = imgJson['results'] as List<dynamic>? ?? [];
      String? url;
      if (imgs.isNotEmpty && imgs.first is Map) {
        final m = imgs.first as Map<String, dynamic>;
        final img = m['image']?.toString();
        if (img != null && img.isNotEmpty) {
          url = img.startsWith('http') ? img : '$_base$img';
        }
      }
      if (url == null) {
        final anyUri = Uri.parse('$_base/api/v2/exerciseimage/?exercise=$exId');
        final anyRes = await http.get(anyUri).timeout(const Duration(seconds: 6));
        if (anyRes.statusCode == 200) {
          final anyJson = jsonDecode(anyRes.body) as Map<String, dynamic>;
          final list = anyJson['results'] as List<dynamic>? ?? [];
          if (list.isNotEmpty && list.first is Map) {
            final m = list.first as Map<String, dynamic>;
            final img = m['image']?.toString();
            if (img != null && img.isNotEmpty) {
              url = img.startsWith('http') ? img : '$_base$img';
            }
          }
        }
      }
      _mem[key] = url;
      return url;
    } catch (e) {
      debugPrint('[Wger] resolveImageUrl failed for "$exerciseName": $e');
      _mem[key] = null;
      return null;
    }
  }

  /// Attach `imageUrl` to each exercise map in [weeklyPlan] (mutates copies).
  static Future<void> enrichWeeklyPlan(List<dynamic> weeklyPlan) async {
    for (final day in weeklyPlan) {
      if (day is! Map) continue;
      final exs = day['exercises'];
      if (exs is! List) continue;
      for (var i = 0; i < exs.length; i++) {
        final e = exs[i];
        if (e is! Map) continue;
        final name = e['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        if (e['imageUrl'] != null && e['imageUrl'].toString().isNotEmpty) continue;
        final url = await resolveImageUrl(name);
        if (url != null) {
          final em = Map<String, dynamic>.from(e as Map);
          exs[i] = {...em, 'imageUrl': url};
        }
      }
    }
  }
}

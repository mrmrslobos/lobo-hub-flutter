// Updates per-exercise PR rows from completed workout sets.

import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../models/models.dart';

class ExercisePrService {

  static String stablePrId(String userId, String exerciseKey) {
    final b = utf8.encode('$userId|${exerciseKey.toLowerCase()}');
    final d = sha256.convert(b).toString();
    return 'pr_${d.substring(0, 32)}';
  }

  static String normalizeExerciseKey(String name) {
    var s = name.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  static int? _parseReps(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    if (n != null) return n;
    final m = RegExp(r'(\d+)').firstMatch(s);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  /// Parses a leading number from strings like "135", "135 lb", "60.5 kg".
  static double? _parseWeightKg(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    final m = RegExp(r'(\d+(\.\d+)?)').firstMatch(s);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    if (v == null) return null;
    if (lower.contains('lb') || lower.contains('lbs') || lower.contains('pound')) {
      return v * 0.453592;
    }
    return v;
  }

  static AppDB updateFromSession(
    AppDB db, {
    required String familyId,
    required String userId,
    required WorkoutSession session,
    required List<WorkoutExercise> exercises,
    required List<WorkoutSet> sets,
  }) {
    final byEx = <String, List<WorkoutSet>>{};
    for (final s in sets) {
      if (!s.completed) continue;
      byEx.putIfAbsent(s.exerciseId, () => []).add(s);
    }

    var next = db;
    for (final ex in exercises) {
      if (ex.sessionId != session.id) continue;
      final key = normalizeExerciseKey(ex.exerciseName);
      if (key.isEmpty) continue;
      final mySets = byEx[ex.id] ?? [];
      if (mySets.isEmpty) continue;

      double bestVol = 0;
      String? bestWeightRaw;
      int bestRepsBody = 0;

      for (final st in mySets) {
        final reps = _parseReps(st.reps) ?? 0;
        final wKg = _parseWeightKg(st.weight);
        if (wKg != null && wKg > 0 && reps > 0) {
          final vol = wKg * reps;
          if (vol > bestVol) {
            bestVol = vol;
            bestWeightRaw = st.weight?.trim();
          }
        } else if (reps > bestRepsBody) {
          bestRepsBody = reps;
        }
      }

      final prId = stablePrId(userId, key);
      ExercisePR? existing;
      for (final p in next.exercisePrs) {
        if (p.id == prId) {
          existing = p;
          break;
        }
      }

      final newVol = bestVol > 0 ? bestVol : null;
      final newReps = (bestRepsBody > 0 && (newVol == null)) ? bestRepsBody : null;
      final newWeight = bestWeightRaw;

      bool improved = false;
      if (existing == null) {
        improved = newVol != null || newReps != null;
      } else {
        if (newVol != null) {
          final old = existing.bestVolume ?? 0;
          if (newVol > old + 0.0001) improved = true;
        }
        if (!improved && newReps != null) {
          final oldR = existing.bestReps ?? 0;
          if (newReps > oldR) improved = true;
        }
      }

      if (!improved) continue;

      final row = ExercisePR(
        id: prId,
        userId: userId,
        familyId: familyId,
        exerciseKey: key,
        bestVolume: newVol ?? existing?.bestVolume,
        bestWeight: newWeight ?? existing?.bestWeight,
        bestReps: newReps ?? existing?.bestReps,
        sessionId: session.id,
        exerciseId: ex.id,
        achievedAt: session.date,
        createdAt: existing?.createdAt ?? DateTime.now(),
      );

      final others = next.exercisePrs.where((p) => p.id != prId).toList();
      next = next.copyWith(exercisePrs: [...others, row]);
    }

    return next;
  }
}

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Stable id for an AI fitness plan (multiple per user).
String fitnessPlanStableId(Map<dynamic, dynamic> p) {
  final pid = p['plan_id']?.toString().trim();
  if (pid != null && pid.isNotEmpty) return pid;
  final uid = p['user_id']?.toString() ?? '';
  final ca = p['created_at']?.toString() ?? '';
  if (uid.isNotEmpty && ca.isNotEmpty) return '${uid}_$ca';
  return uid.isNotEmpty ? uid : 'plan';
}

/// Ensures [plan_id] and returns the same map with the field set.
Map<String, dynamic> ensureFitnessPlanHasId(Map<String, dynamic> plan) {
  final existing = plan['plan_id']?.toString().trim();
  if (existing != null && existing.isNotEmpty) return plan;
  return {...plan, 'plan_id': _uuid.v4()};
}

/// Supabase `fitness_plans.id` — one row per plan when [plan_id] is present.
String fitnessPlanCloudRowId(Map<dynamic, dynamic> plan, String familyId) {
  final pid = plan['plan_id']?.toString().trim();
  if (pid != null && pid.isNotEmpty) return pid;
  final uid = plan['user_id']?.toString() ?? '';
  return '${uid}_$familyId';
}

DateTime fitnessPlanCreatedAt(Map<dynamic, dynamic> plan) {
  final s = plan['created_at']?.toString();
  if (s == null || s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
  return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

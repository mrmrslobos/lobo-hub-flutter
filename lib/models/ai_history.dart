// lib/models/ai_history.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class AIHistory {
  final String id;
  final String userId;
  final String familyId;
  final String module;
  final String prompt;
  final String response;
  final DateTime createdAt;

  const AIHistory({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.module,
    required this.prompt,
    required this.response,
    required this.createdAt,
  });

  factory AIHistory.fromJson(Map<String, dynamic> j) => AIHistory(
    id: j['id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    module: j['module'] as String? ?? '',
    prompt: j['prompt'] as String? ?? '',
    response: j['response'] as String? ?? '',
    createdAt: parseDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'family_id': familyId,
    'module': module,
    'prompt': prompt,
    'response': response,
    'created_at': createdAt.toIso8601String(),
  };
}

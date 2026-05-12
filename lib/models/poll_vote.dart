// lib/models/poll_vote.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class PollVote {
  final String id;
  final String pollId;
  final String optionId;
  final String userId;
  final String familyId;
  final DateTime votedAt;

  const PollVote({
    required this.id,
    required this.pollId,
    required this.optionId,
    required this.userId,
    required this.familyId,
    required this.votedAt,
  });

  factory PollVote.fromJson(Map<String, dynamic> j) => PollVote(
    id: j['id'] as String? ?? '',
    pollId: j['poll_id'] as String? ?? '',
    optionId: j['option_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    votedAt: parseDate(j['voted_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'poll_id': pollId,
    'option_id': optionId,
    'user_id': userId,
    'family_id': familyId,
    'voted_at': votedAt.toIso8601String(),
  };
}

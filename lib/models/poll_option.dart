// lib/models/poll_option.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class PollOption {
  final String id;
  final String text;
  final List<String> voterIds;

  const PollOption({required this.id, required this.text, this.voterIds = const []});

  PollOption copyWith({String? id, String? text, List<String>? voterIds}) =>
      PollOption(id: id ?? this.id, text: text ?? this.text, voterIds: voterIds ?? this.voterIds);

  factory PollOption.fromJson(Map<String, dynamic> j) => PollOption(
    id: j['id'] as String? ?? '',
    text: j['text'] as String? ?? '',
    voterIds: strList(j['voter_ids']),
  );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'voter_ids': voterIds};
}

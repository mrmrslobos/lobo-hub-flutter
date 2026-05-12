// lib/models/family_photo.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';
import 'reaction.dart';

class FamilyPhoto {
  final String id;
  final String familyId;
  final String uploaderId;
  final String url;
  final String? caption;
  final DateTime? takenAt;
  final DateTime createdAt;
  final List<Reaction> reactions;
  final String? milestoneId;
  final List<String> tags;
  final Visibility visibility;

  FamilyPhoto({
    required this.id,
    required this.familyId,
    String? uploaderId,
    String? uploadedBy,
    required this.url,
    this.caption,
    this.takenAt,
    DateTime? createdAt,
    this.reactions = const [],
    this.milestoneId,
    this.tags = const [],
    this.visibility = Visibility.FAMILY,
  }) : uploaderId = uploaderId ?? uploadedBy ?? '',
       createdAt = createdAt ?? DateTime.now();

  factory FamilyPhoto.fromJson(Map<String, dynamic> j) => FamilyPhoto(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    uploaderId: j['uploader_id'] as String? ?? '',
    url: j['url'] as String? ?? '',
    caption: j['caption'] as String?,
    takenAt: parseDateOpt(j['taken_at']),
    createdAt: parseDate(j['created_at']),
    reactions: parseList(j['reactions'], Reaction.fromJson),
    milestoneId: j['milestone_id'] as String?,
    tags: strList(j['tags']),
    visibility: visibilityFromString(j['visibility'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'uploader_id': uploaderId,
    'url': url,
    'caption': caption,
    'taken_at': (takenAt ?? createdAt).toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'reactions': reactions.map((r) => r.toJson()).toList(),
    'milestone_id': milestoneId,
    'tags': tags,
    'visibility': visibility.name,
  };

  // Convenience alias
  String get uploadedBy => uploaderId;
}

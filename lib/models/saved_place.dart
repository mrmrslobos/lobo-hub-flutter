// lib/models/saved_place.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class SavedPlace {
  final String id;
  final String familyId;
  final String creatorId;
  final String name;
  final String? emoji;
  final double latitude;
  final double longitude;
  final double radiusMetres;
  final DateTime createdAt;

  const SavedPlace({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.name,
    this.emoji,
    required this.latitude,
    required this.longitude,
    this.radiusMetres = 100,
    required this.createdAt,
  });

  factory SavedPlace.fromJson(Map<String, dynamic> j) => SavedPlace(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    emoji: j['emoji'] as String?,
    latitude: ((j['latitude'] as num?) ?? 0).toDouble(),
    longitude: ((j['longitude'] as num?) ?? 0).toDouble(),
    radiusMetres: (j['radius_metres'] as num? ?? 100).toDouble(),
    createdAt: parseDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'name': name,
    'emoji': emoji,
    'latitude': latitude,
    'longitude': longitude,
    'radius_metres': radiusMetres,
    'created_at': createdAt.toIso8601String(),
  };
}

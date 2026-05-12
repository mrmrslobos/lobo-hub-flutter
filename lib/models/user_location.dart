// lib/models/user_location.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class UserLocation {
  final String id;
  final String familyId;
  final String userId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final String? placeName;
  final String? nearPlace;
  final bool isSharing;
  final DateTime updatedAt;

  const UserLocation({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.placeName,
    this.nearPlace,
    this.isSharing = false,
    required this.updatedAt,
  });

  factory UserLocation.fromJson(Map<String, dynamic> j) => UserLocation(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    latitude: ((j['latitude'] as num?) ?? 0).toDouble(),
    longitude: ((j['longitude'] as num?) ?? 0).toDouble(),
    accuracy: (j['accuracy'] as num?)?.toDouble(),
    placeName: j['place_name'] as String?,
    nearPlace: j['near_place'] as String?,
    isSharing: (j['is_sharing'] ?? false) as bool,
    updatedAt: parseDate(j['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'place_name': placeName,
    'near_place': nearPlace,
    'is_sharing': isSharing,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getter
  String? get address => placeName ?? nearPlace;
}

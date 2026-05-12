// lib/models/family_member.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';

class FamilyMember {
  final String userId;
  final String familyId;
  final Role role;
  final List<String>? moduleAccess;
  final String? displayName;
  final HouseholdRole householdRole;
  /// Self- or parent-declared: this profile is for someone under 16 (AI Family / child pricing UX).
  /// Not verified; [householdRole] may still be [HouseholdRole.teen] etc.
  final bool declaredUnder16;

  const FamilyMember({
    required this.userId,
    required this.familyId,
    this.role = Role.MEMBER,
    this.moduleAccess,
    this.displayName,
    this.householdRole = HouseholdRole.parent,
    this.declaredUnder16 = false,
  });

  // Convenience getters
  String get id => userId;
  /// Composite key for dedup in merge operations.
  String get mergeKey => '${userId}_$familyId';
  String get name => displayName ?? userId;

  factory FamilyMember.fromJson(Map<String, dynamic> j) => FamilyMember(
    userId: j['user_id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    role: roleFromString(j['role'] as String?),
    moduleAccess: j['module_access'] != null
        ? strList(j['module_access'])
        : null,
    displayName: (j['display_name'] ?? j['name']) as String?,
    householdRole: householdRoleFromString(j['household_role'] as String?),
    declaredUnder16: j['declared_under_16'] == true || j['declared_under_16'] == 1,
  );

  FamilyMember copyWith({
    String? userId,
    String? familyId,
    Role? role,
    List<String>? moduleAccess,
    String? displayName,
    HouseholdRole? householdRole,
    bool? declaredUnder16,
  }) => FamilyMember(
    userId: userId ?? this.userId,
    familyId: familyId ?? this.familyId,
    role: role ?? this.role,
    moduleAccess: moduleAccess ?? this.moduleAccess,
    displayName: displayName ?? this.displayName,
    householdRole: householdRole ?? this.householdRole,
    declaredUnder16: declaredUnder16 ?? this.declaredUnder16,
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'family_id': familyId,
    'role': role.name,
    'module_access': moduleAccess,
    'display_name': displayName,
    'household_role': householdRole.name,
    'declared_under_16': declaredUnder16,
  };
}

// lib/models/emergency_contact.dart
// ignore_for_file: constant_identifier_names
class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String? relation;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.relation,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    relation: j['relation'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'relation': relation,
  };
}

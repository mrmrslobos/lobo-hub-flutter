// lib/models/model_json_helpers.dart

bool coerceBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
  if (raw == null) return [];
  if (raw is! List) return [];
  final out = <T>[];
  for (final item in raw) {
    if (item is Map) {
      try {
        out.add(fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {}
    }
  }
  return out;
}

List<String> strList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw.map((e) => e.toString()).toList();
  return [];
}

List<int> intList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw.map((e) => (e as num).toInt()).toList();
  return [];
}

DateTime parseDate(dynamic raw) {
  if (raw == null) return DateTime.now();
  if (raw is DateTime) return raw;
  try { return DateTime.parse(raw.toString()); } catch (_) { return DateTime.now(); }
}

DateTime? parseDateOpt(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  try { return DateTime.parse(raw.toString()); } catch (_) { return null; }
}

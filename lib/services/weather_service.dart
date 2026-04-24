// lib/services/weather_service.dart
// Open-Meteo forecast for a single day (free, no API key).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WeatherService {
  WeatherService._();

  /// Returns e.g. "Partly cloudy, high 22°C" or null on failure.
  static Future<String?> daySummaryForLocation({
    required double latitude,
    required double longitude,
    required DateTime day,
  }) async {
    try {
      final d = DateTime(day.year, day.month, day.day);
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latitude&longitude=$longitude'
        '&daily=weathercode,temperature_2m_max,temperature_2m_min'
        '&timezone=auto&start_date=${d.toIso8601String().split('T').first}'
        '&end_date=${d.toIso8601String().split('T').first}',
      );
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final daily = j['daily'] as Map<String, dynamic>?;
      if (daily == null) return null;
      final codes = daily['weathercode'] as List<dynamic>?;
      final tmax = daily['temperature_2m_max'] as List<dynamic>?;
      final tmin = daily['temperature_2m_min'] as List<dynamic>?;
      if (codes == null || tmax == null || tmin == null || codes.isEmpty) return null;
      final label = _wmoCodeLabel((codes[0] as num).toInt());
      final hi = (tmax[0] as num).round();
      final lo = (tmin[0] as num).round();
      return '$label · high ${hi}° · low ${lo}°';
    } catch (e, st) {
      debugPrint('[WeatherService] $e\n$st');
      return null;
    }
  }

  static String _wmoCodeLabel(int code) {
    if (code == 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 48) return 'Foggy';
    if (code <= 57) return 'Drizzle';
    if (code <= 67) return 'Rain';
    if (code <= 77) return 'Snow';
    if (code <= 82) return 'Rain showers';
    if (code <= 86) return 'Snow showers';
    if (code <= 99) return 'Storm';
    return 'Mixed conditions';
  }
}

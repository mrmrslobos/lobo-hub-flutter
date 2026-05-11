// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../../models/models.dart';

HealthWorkoutActivityType _activityFromTitle(String title) {
  final t = title.toLowerCase();
  if (t.contains('run')) return HealthWorkoutActivityType.RUNNING;
  if (t.contains('walk')) return HealthWorkoutActivityType.WALKING;
  if (t.contains('swim')) return HealthWorkoutActivityType.SWIMMING;
  if (t.contains('bike') || t.contains('cycl')) return HealthWorkoutActivityType.BIKING;
  if (t.contains('yoga')) return HealthWorkoutActivityType.YOGA;
  if (t.contains('hiit')) return HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING;
  if (t.contains('hike')) return HealthWorkoutActivityType.HIKING;
  if (t.contains('pilates')) return HealthWorkoutActivityType.PILATES;
  if (t.contains('elliptical')) return HealthWorkoutActivityType.ELLIPTICAL;
  if (t.contains('row')) return HealthWorkoutActivityType.ROWING;
  return HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING;
}

/// Writes a strength-training style workout to Apple Health / Health Connect.
Future<bool> writeWorkoutSessionToHealth(WorkoutSession session) async {
  if (kIsWeb) return false;
  if (!Platform.isIOS && !Platform.isAndroid) return false;

  if (Platform.isAndroid) {
    try {
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdkInt < 26) return false;
    } catch (_) {
      return false;
    }
  }

  final health = Health();
  await health.configure();

  if (Platform.isAndroid) {
    try {
      final available = await health.isHealthConnectAvailable();
      if (!available) return false;
    } catch (_) {
      return false;
    }
  }

  final types = <HealthDataType>[HealthDataType.WORKOUT];
  try {
    final granted = await health.requestAuthorization(
      types,
      permissions: [HealthDataAccess.READ, HealthDataAccess.WRITE],
    );
    if (granted != true) return false;
  } catch (_) {
    return false;
  }

  final start = session.date;
  final end = start.add(Duration(minutes: session.durationMinutes.clamp(1, 600)));
  final activity = _activityFromTitle(session.title);

  try {
    return await health.writeWorkoutData(
      activityType: activity,
      start: start,
      end: end,
      title: session.title,
      recordingMethod: RecordingMethod.manual,
    );
  } catch (e) {
    debugPrint('[HealthSync] writeWorkoutData failed: $e');
    return false;
  }
}

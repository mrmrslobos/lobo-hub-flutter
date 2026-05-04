import 'package:flutter/material.dart';

/// Phase G — shared motion tokens for shell routes and micro-interactions.
abstract final class HuddleMotion {
  static const Duration routeForward = Duration(milliseconds: 260);
  static const Duration routeReverse = Duration(milliseconds: 220);

  static const Curve routeCurve = Curves.easeOutCubic;
  static const Curve routeReverseCurve = Curves.easeInCubic;

  /// Subtle vertical drift paired with cross-fade on module shell transitions.
  static const Offset routeSlideBegin = Offset(0, 0.024);
}

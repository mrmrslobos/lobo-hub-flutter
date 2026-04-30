import 'package:flutter/material.dart';

/// Phase F — semantic typography for module chrome. Prefer over ad-hoc [TextStyle]s in headers.
abstract final class HuddleTypography {
  static const String fontFamily = 'Inter';

  /// Large module titles ([PageHeader]).
  static TextStyle moduleTitle(ColorScheme cs) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w900,
        height: 1.2,
        color: cs.onSurface,
      );

  /// Supporting line under module title.
  static TextStyle moduleSubtitle(ColorScheme cs, [double opacity = 0.55]) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: cs.onSurface.withValues(alpha: opacity),
      );

  /// Section rails / meta labels (caller sets casing).
  static TextStyle sectionRail(ColorScheme cs, [double opacity = 0.45]) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: cs.onSurface.withValues(alpha: opacity),
      );

  /// [HuddleSectionHeader] primary line when not using [ThemeData.textTheme].
  static TextStyle sectionTitle(ColorScheme cs) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: cs.onSurface,
      );

  /// Secondary line under section title.
  static TextStyle sectionSubtitle(ColorScheme cs, [double opacity = 0.55]) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: cs.onSurface.withValues(alpha: opacity),
      );

  /// Single-line app bar titles (nested routes and shell bar).
  static TextStyle chromeTitle(ColorScheme cs) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: cs.onSurface,
      );

  /// Primary line on modal sheets (e.g. All tools).
  static TextStyle sheetTitle(ColorScheme cs) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        height: 1.25,
        color: cs.onSurface,
      );

  /// Supporting copy under [sheetTitle].
  static TextStyle sheetCaption(ColorScheme cs, [double opacity = 0.6]) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: cs.onSurface.withValues(alpha: opacity),
      );

  /// Group labels in module picker sheets (accent rail).
  static TextStyle sheetGroupLabel(ColorScheme cs) => TextStyle(
        fontFamily: fontFamily,
        fontWeight: FontWeight.w800,
        fontSize: 12,
        letterSpacing: 0.4,
        color: cs.primary.withValues(alpha: 0.9),
      );
}

/// Soft elevation for premium cards/sheets — pair with hairline borders, not heavy strokes.
abstract final class HuddleElevation {
  static List<BoxShadow> cardRest(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = dark ? 0.42 : 0.06;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: a),
        blurRadius: 14,
        offset: const Offset(0, 5),
      ),
    ];
  }
}

// lib/widgets/app_brand_mark.dart
// Huddle app icon (replaces legacy sparkle / three-star brand mark).

import 'package:flutter/material.dart';

import '../config/theme.dart';

class AppBrandMark extends StatelessWidget {
  static const assetPath = 'assets/images/app_icon.png';

  final double size;
  final BorderRadius? borderRadius;

  const AppBrandMark({
    super.key,
    this.size = 24,
    this.borderRadius,
  });

  /// Prominent card for sign-in and splash-style headers.
  static Widget card({
    Key? key,
    double outerSize = 72,
    double cornerRadius = 20,
  }) {
    final pad = outerSize * 0.12;
    return Container(
      key: key,
      width: outerSize,
      height: outerSize,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(cornerRadius),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.22),
            blurRadius: outerSize * 0.28,
            offset: Offset(0, outerSize * 0.11),
          ),
        ],
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadius - 4),
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Image.asset(
            assetPath,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(
              Icons.favorite_rounded,
              size: outerSize * 0.45,
              color: AppTheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(size * 0.22);
    return ClipRRect(
      borderRadius: br,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.favorite_rounded,
            size: size * 0.85,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }
}

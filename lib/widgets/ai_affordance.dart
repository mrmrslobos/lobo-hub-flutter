import 'package:flutter/material.dart';

import '../config/theme.dart';

const Color _kAiGlyphDefault = Color(0xFF7C3AED);

/// Shared visual for AI-powered entry points (Copilot, in-screen AI, paywalls, etc.).
class AiGlyph extends StatelessWidget {
  const AiGlyph({
    super.key,
    this.size = 16,
    this.color,
    this.textColor,
    this.compact = false,
  });

  final double size;
  final Color? color;
  final Color? textColor;
  /// Icon only — useful for dense toolbars.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = color ?? _kAiGlyphDefault;
    final tc = textColor ?? c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.auto_awesome_rounded,
          size: size,
          color: c,
        ),
        if (!compact) ...[
          const SizedBox(width: 4),
          Text(
            'AI',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w800,
              fontSize: (size * 0.7).clamp(10.0, 14.0),
              color: tc,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ],
    );
  }
}

TextStyle homeAiSubtextStyle(BuildContext context) {
  return TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    color: Theme.of(context).brightness == Brightness.dark
        ? AppTheme.stone300
        : AppTheme.stone500,
  );
}

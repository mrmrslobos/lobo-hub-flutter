import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Standard horizontal inset for scrollable module content.
class HuddlePagePadding extends StatelessWidget {
  const HuddlePagePadding({
    super.key,
    required this.child,
    this.horizontal,
    this.vertical = 0,
    this.bottom = 0,
  });

  final Widget child;
  final double? horizontal;
  final double vertical;
  final double bottom;

  static double horizontalOf(BuildContext context) => AppTheme.space5;

  @override
  Widget build(BuildContext context) {
    final h = horizontal ?? AppTheme.space5;
    return Padding(
      padding: EdgeInsets.fromLTRB(h, vertical, h, bottom),
      child: child,
    );
  }
}

/// Section title row: optional overline, title, optional trailing action (e.g. TextButton).
class HuddleSectionHeader extends StatelessWidget {
  const HuddleSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.overline,
    this.trailing,
    this.titleStyle,
  });

  final String title;
  final String? subtitle;
  final String? overline;
  final Widget? trailing;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (overline != null && overline!.isNotEmpty) ...[
          Text(
            overline!.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: AppTheme.space2),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: titleStyle ??
                        tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: tt.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ],
    );
  }
}

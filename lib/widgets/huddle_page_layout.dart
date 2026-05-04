import 'package:flutter/material.dart';

import '../config/app_design_tokens.dart';
import '../config/theme.dart';

export 'module_ui_kit.dart';

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
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (overline != null && overline!.isNotEmpty) ...[
          Text(
            overline!.toUpperCase(),
            style: HuddleTypography.sectionRail(cs),
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
                        HuddleTypography.sectionTitle(cs),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: HuddleTypography.sectionSubtitle(cs),
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

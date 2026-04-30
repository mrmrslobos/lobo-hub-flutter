// Shared patterns for module screens — loading shells, catalogue-backed empty states, trust copy.
// Use these for Phase A consistency across the 20+ module routes.

import 'package:flutter/material.dart';

import '../config/module_config.dart';
import '../config/theme.dart';
import 'common_widgets.dart';

/// Phase I — skeleton row shapes for perceived loading quality.
enum ModuleSkeletonStyle {
  bars,
  listRows,
}

/// Full-screen loading while user/family context is still hydrating.
class ModuleFamilyLoadingScaffold extends StatelessWidget {
  const ModuleFamilyLoadingScaffold({super.key, this.semanticLabel});

  /// Defaults to a short loading hint for screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel ?? 'Loading family data';
    return Scaffold(
      body: Semantics(
        label: label,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 18),
              Text(
                'Loading…',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 300,
                child: ModuleListSkeleton(rows: 4, indent: 0, style: ModuleSkeletonStyle.listRows),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state using the module catalogue emoji/description when [subtitle] is null.
class CatalogModuleEmptyState extends StatelessWidget {
  const CatalogModuleEmptyState({
    super.key,
    required this.modulePath,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.compact = true,
    this.emojiSize = 56,
  });

  final String modulePath;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final double emojiSize;

  @override
  Widget build(BuildContext context) {
    final info = getModuleByPath(modulePath);
    final emoji = info?.emoji ?? '📱';
    final desc = subtitle ?? info?.desc ?? 'Nothing here yet.';
    return EmptyState(
      emoji: emoji,
      title: title,
      subtitle: desc,
      actionLabel: actionLabel,
      onAction: onAction,
      compact: compact,
      emojiSize: emojiSize,
    );
  }
}

/// Compact reassurance copy for screens that handle sensitive family data (budget, health, etc.).
class FamilySyncPrivacyFootnote extends StatelessWidget {
  const FamilySyncPrivacyFootnote({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        'Visible only to your family when you mark entries as shared. Data is encrypted in transit.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.42),
              height: 1.4,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Lightweight placeholder rows while lists hydrate (no shimmer dependency).
class ModuleListSkeleton extends StatelessWidget {
  const ModuleListSkeleton({
    super.key,
    this.rows = 5,
    this.indent = 20,
    this.style = ModuleSkeletonStyle.bars,
  });

  final int rows;
  final double indent;
  final ModuleSkeletonStyle style;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.72);
    final soft = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    if (style == ModuleSkeletonStyle.listRows) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: indent),
        child: Column(
          children: [
            for (var i = 0; i < rows; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 14,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: base,
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 11,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: soft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: indent),
      child: Column(
        children: [
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Container(
              height: 14 + (i % 3) * 4,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

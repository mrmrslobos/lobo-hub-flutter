import 'package:flutter/material.dart';

import 'common_widgets.dart' show EmptyState;

/// Centered loading state aligned with app theme.
class HuddleLoadingView extends StatelessWidget {
  const HuddleLoadingView({
    super.key,
    this.message,
    this.compact = false,
  });

  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final gap = compact ? 12.0 : 16.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 20 : 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: compact ? 28 : 32,
              height: compact ? 28 : 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              SizedBox(height: gap),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard error state with optional retry.
class HuddleErrorView extends StatelessWidget {
  const HuddleErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.emoji = '😕',
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final String emoji;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      emoji: emoji,
      title: 'Something went wrong',
      subtitle: message,
      actionLabel: onRetry != null ? 'Try again' : null,
      onAction: onRetry,
      compact: compact,
    );
  }
}

/// Optional sliver-friendly loading placeholder with theme padding.
class HuddleLoadingSliver extends StatelessWidget {
  const HuddleLoadingSliver({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: HuddleLoadingView(message: message),
    );
  }
}

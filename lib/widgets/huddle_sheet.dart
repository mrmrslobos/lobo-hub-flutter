import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Modal bottom sheet using [Theme.bottomSheetTheme] and [AppTheme] corner radius.
Future<T?> showHuddleModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = true,
  double? maxHeightFactor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.32),
    builder: (ctx) {
      final child = builder(ctx);
      final content = Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
          boxShadow: [
            BoxShadow(
              color: Theme.of(ctx).colorScheme.shadow.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (maxHeightFactor != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * maxHeightFactor,
                ),
                child: child,
              )
            else
              child,
          ],
        ),
      );
      if (useSafeArea) {
        return SafeArea(top: false, child: content);
      }
      return content;
    },
  );
}

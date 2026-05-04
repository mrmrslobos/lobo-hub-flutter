import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Rounded top surface, drag handle, and shadow used by Huddle bottom sheets.
class HuddleBottomSheetSurface extends StatelessWidget {
  const HuddleBottomSheetSurface({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.12),
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
              color: Theme.of(context).dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Modal bottom sheet with [HuddleBottomSheetSurface] and optional max height.
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
      final content = HuddleBottomSheetSurface(
        child: maxHeightFactor != null
            ? ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * maxHeightFactor,
                ),
                child: child,
              )
            : child,
      );
      if (useSafeArea) {
        return SafeArea(top: false, child: content);
      }
      return content;
    },
  );
}

/// Draggable sheet (e.g. Jump to) sharing the same chrome as [showHuddleModalBottomSheet].
Future<T?> showHuddleDraggableScrollableSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController scrollController) builder,
  double initialChildSize = 0.55,
  double minChildSize = 0.35,
  double maxChildSize = 0.92,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.32),
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        expand: false,
        builder: (scrollCtx, scrollController) {
          return SafeArea(
            top: false,
            child: HuddleBottomSheetSurface(
              child: builder(scrollCtx, scrollController),
            ),
          );
        },
      );
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_design_tokens.dart';

/// How the [SubpageAppBar] leading control behaves.
enum SubpageLeading {
  /// Standard back chevron; calls [onBack] or [Navigator.maybePop].
  back,

  /// Close (X) for fullscreen or modal subflows; calls [onBack] or pop.
  close,

  /// No leading widget (e.g. embedded in a dialog that supplies its own chrome).
  none,
}

/// Themed app bar for nested routes, detail views, and fullscreen helpers.
/// Matches [MainAppBar] surface styling without drawer / jump / sync.
class SubpageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SubpageAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.onBack,
    this.leading = SubpageLeading.back,
    this.centerTitle = false,
    this.automaticallyImplyLeading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation = 0,
  });

  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final VoidCallback? onBack;
  final SubpageLeading leading;
  final bool centerTitle;
  final bool automaticallyImplyLeading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double elevation;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? cs.surface;
    final fg = foregroundColor ?? cs.onSurface;
    final titleStyle =
        Theme.of(context).appBarTheme.titleTextStyle ?? HuddleTypography.chromeTitle(cs);

    void handleBack() {
      HapticFeedback.lightImpact();
      if (onBack != null) {
        onBack!();
      } else {
        Navigator.maybePop(context);
      }
    }

    Widget? leadingW;
    switch (leading) {
      case SubpageLeading.back:
        leadingW = IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: fg.withValues(alpha: 0.88)),
          onPressed: handleBack,
          tooltip: 'Back',
        );
        break;
      case SubpageLeading.close:
        leadingW = IconButton(
          icon: Icon(Icons.close_rounded, color: fg.withValues(alpha: 0.88)),
          onPressed: handleBack,
          tooltip: 'Close',
        );
        break;
      case SubpageLeading.none:
        leadingW = null;
    }

    final Color onBarFg = backgroundColor == Colors.black
        ? (foregroundColor ?? Colors.white)
        : (foregroundColor ?? cs.onSurface);

    final Widget t = titleWidget ??
        (title == null
            ? const SizedBox.shrink()
            : Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle.copyWith(color: onBarFg),
              ));

    return AppBar(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: elevation,
      scrolledUnderElevation: 0,
      centerTitle: centerTitle,
      titleSpacing: centerTitle ? null : 0,
      leading: leadingW,
      automaticallyImplyLeading: automaticallyImplyLeading,
      title: t,
      actions: actions,
    );
  }
}

/// Thin [Scaffold] for sub-routes: [SubpageAppBar] + [body] with no drawer/copilot.
class HuddleSubpageScaffold extends StatelessWidget {
  const HuddleSubpageScaffold({
    super.key,
    this.title,
    this.titleWidget,
    required this.body,
    this.actions,
    this.onBack,
    this.leading = SubpageLeading.back,
    this.centerTitle = false,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset = true,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String? title;
  final Widget? titleWidget;
  final Widget body;
  final List<Widget>? actions;
  final VoidCallback? onBack;
  final SubpageLeading leading;
  final bool centerTitle;
  final Widget? floatingActionButton;
  final bool resizeToAvoidBottomInset;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: backgroundColor,
      appBar: SubpageAppBar(
        title: title,
        titleWidget: titleWidget,
        actions: actions,
        onBack: onBack,
        leading: leading,
        centerTitle: centerTitle,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
      ),
      floatingActionButton: floatingActionButton,
      body: body,
    );
  }
}

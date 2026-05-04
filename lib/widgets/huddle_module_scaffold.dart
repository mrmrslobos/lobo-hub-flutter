import 'package:flutter/material.dart';

import 'app_drawer.dart';
import 'common_widgets.dart';
import 'copilot_entry_bar.dart';

/// Consistent module shell: [MainAppBar], optional [drawer], then [CopilotEntryBar]
/// (when [showCopilotBar]) and scrollable [child] in an [Expanded] region.
class HuddleModuleScaffold extends StatelessWidget {
  const HuddleModuleScaffold({
    super.key,
    required this.modulePath,
    required this.child,
    this.drawer = const AppDrawer(),
    this.appBar = const MainAppBar(),
    this.floatingActionButton,
    this.showCopilotBar = true,
    this.resizeToAvoidBottomInset = true,
    this.bottomNavigationBar,
  });

  /// GoRouter path for this screen (e.g. `/tasks`, `/` for home).
  final String modulePath;
  final Widget child;
  final Widget? drawer;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final bool showCopilotBar;
  final bool resizeToAvoidBottomInset;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      drawer: drawer,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: showCopilotBar
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CopilotEntryBar(modulePath: modulePath),
                Expanded(child: child),
              ],
            )
          : child,
    );
  }
}

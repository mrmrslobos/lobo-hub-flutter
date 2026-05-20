import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/supabase_service.dart';
import '../utils/user_facing_errors.dart' show humanizeCloudSyncError;
import 'app_drawer.dart';
import 'common_widgets.dart';
import 'copilot_entry_bar.dart';

/// Consistent module shell: [MainAppBar], optional [drawer], then [CopilotEntryBar]
/// (when [showCopilotBar]) and scrollable [child] in an [Expanded] region.
///
/// When [enterPullTables] is set and the user is signed in with Supabase, triggers a
/// scoped cloud pull shortly after the module opens (see [AppProvider.scheduleModuleEnterCloudPull]).
class HuddleModuleScaffold extends StatefulWidget {
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
    this.enterPullTables,
    this.pullAllTablesOnEnter = false,
    this.showSyncErrorSnackBar = true,
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

  /// Tables to reconcile when this module opens (scoped pull).
  final Set<String>? enterPullTables;

  /// When true, reconcile all family tables on enter ([enterPullTables] ignored).
  final bool pullAllTablesOnEnter;

  /// Brief snackbar when [AppProvider.lastSyncError] becomes set while this module is open.
  final bool showSyncErrorSnackBar;

  @override
  State<HuddleModuleScaffold> createState() => _HuddleModuleScaffoldState();
}

class _HuddleModuleScaffoldState extends State<HuddleModuleScaffold> {
  String? _lastSnackError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleEnterPull());
    if (widget.showSyncErrorSnackBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AppProvider>().addListener(_onProviderSyncState);
      });
    }
  }

  @override
  void didUpdateWidget(covariant HuddleModuleScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enterPullTables != widget.enterPullTables ||
        oldWidget.pullAllTablesOnEnter != widget.pullAllTablesOnEnter) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleEnterPull());
    }
  }

  @override
  void dispose() {
    if (widget.showSyncErrorSnackBar) {
      try {
        context.read<AppProvider>().removeListener(_onProviderSyncState);
      } catch (_) {}
    }
    super.dispose();
  }

  void _scheduleEnterPull() {
    if (!mounted) return;
    final provider = context.read<AppProvider>();
    if (!SupabaseService.isConfigured || !provider.isAuthenticated) return;
    if (provider.activeFamily == null) return;
    if (!widget.pullAllTablesOnEnter &&
        (widget.enterPullTables == null || widget.enterPullTables!.isEmpty)) {
      return;
    }
    provider.scheduleModuleEnterCloudPull(
      widget.pullAllTablesOnEnter ? null : widget.enterPullTables,
    );
  }

  void _onProviderSyncState() {
    if (!mounted || !widget.showSyncErrorSnackBar) return;
    final err = context.read<AppProvider>().lastSyncError;
    if (err == null || err.isEmpty) {
      _lastSnackError = null;
      return;
    }
    if (err == _lastSnackError) return;
    _lastSnackError = err;
    final message = humanizeCloudSyncError(err);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () {
              context.read<AppProvider>().refreshFromCloud();
            },
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      drawer: widget.drawer,
      appBar: widget.appBar,
      floatingActionButton: widget.floatingActionButton,
      bottomNavigationBar: widget.bottomNavigationBar,
      body: widget.showCopilotBar
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CopilotEntryBar(modulePath: widget.modulePath),
                Expanded(child: widget.child),
              ],
            )
          : widget.child,
    );
  }
}

// lib/screens/assistant/assistant_screen.dart
// Full-screen Family copilot route — body is [FamilyCopilotPanel].

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/family_copilot_panel.dart';
import '../../widgets/huddle_module_scaffold.dart';
import '../../widgets/huddle_page_layout.dart';

class AssistantScreen extends StatelessWidget {
  const AssistantScreen({
    super.key,
    this.initialQuery,
    this.fromPath,
    this.startDictation = false,
  });

  final String? initialQuery;
  final String? fromPath;
  final bool startDictation;

  @override
  Widget build(BuildContext context) {
    final from = fromPath ?? '/assistant';
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        if (provider.activeUser == null || provider.activeFamily == null) {
          return const ModuleFamilyLoadingScaffold();
        }
        return HuddleModuleScaffold(
          modulePath: '/assistant',
          showCopilotBar: false,
          drawer: const AppDrawer(),
          appBar: const MainAppBar(),
          child: FamilyCopilotPanel(
            fromPath: from,
            initialQuery: initialQuery,
            startDictation: startDictation,
            layout: FamilyCopilotLayout.fullScreen,
          ),
        );
      },
    );
  }
}

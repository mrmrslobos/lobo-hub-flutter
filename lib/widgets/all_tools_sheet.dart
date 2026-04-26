import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/module_config.dart';
import '../config/user_module_pins.dart';
import '../models/models.dart' show Family;
import '../providers/app_provider.dart';
import '../services/recent_routes_service.dart';

/// Full module catalogue (filtered by [Family.enabledModules]) with per-user pin toggles.
void showAllToolsBottomSheet(BuildContext context, {required Family family}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Text(
                    'All tools',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Every family module in one list. Star up to $kMaxUserPinnedModulePaths to show them on your home row. Search on the app bar still works for quick jumps.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      height: 1.35,
                      color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 28),
                    children: [
                      for (final g in moduleGroups) ..._groupTiles(ctx, g, family),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

List<Widget> _groupTiles(BuildContext context, ModuleGroup g, Family family) {
  final items = g.modules.where((m) => isModulePathEnabledForFamily(m.path, family)).toList();
  if (items.isEmpty) return const [];
  return [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        g.label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.4,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
        ),
      ),
    ),
    for (final m in items)
      Consumer<AppProvider>(
        builder: (context, app, _) {
          final u = app.activeUser;
          final pins = pinnedModulePathsFromUser(u);
          final isPinned = pins.contains(m.path);
          return ListTile(
            leading: Text(m.emoji, style: const TextStyle(fontSize: 24)),
            title: Text(m.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
            subtitle: Text(
              m.desc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            trailing: IconButton(
              tooltip: isPinned ? 'Remove from home favorites' : 'Pin to home row',
              icon: Icon(
                isPinned ? Icons.star_rounded : Icons.star_border_rounded,
                color: isPinned
                    ? const Color(0xFFF59E0B)
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              onPressed: u == null
                  ? null
                  : () async {
                      final next = togglePinnedPath(pins, m.path);
                      if (next == null) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('You can pin up to $kMaxUserPinnedModulePaths modules — remove one first.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      await app.updateActiveUserSettings({kUserPinnedModulePathsKey: next});
                    },
            ),
            onTap: () {
              Navigator.of(context).pop();
              unawaited(RecentRoutesService.recordPath(m.path));
              context.go(m.path);
            },
          );
        },
      ),
  ];
}

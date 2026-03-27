import 'package:flutter/material.dart' hide Visibility;
import 'package:go_router/go_router.dart';

import '../config/module_config.dart';
import '../config/theme.dart';
import '../models/models.dart';

// ─── Rounded Section Card ───────────────────────────────────────────────────
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final VoidCallback? onTap;

  const SectionCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).dividerColor;
    final card = Container(
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: outline),
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: card,
      );
    }
    return card;
  }
}

// ─── Empty State ─────────────────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Priority Badge ──────────────────────────────────────────────────────────
class PriorityBadge extends StatelessWidget {
  final String priority;

  const PriorityBadge({super.key, required this.priority});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (priority.toUpperCase()) {
      case 'HIGH':
        color = AppTheme.error;
        label = 'High';
        break;
      case 'MEDIUM':
        color = AppTheme.warning;
        label = 'Med';
        break;
      default:
        color = AppTheme.success;
        label = 'Low';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

// ─── Avatar Initials ─────────────────────────────────────────────────────────
class AvatarInitials extends StatelessWidget {
  final String name;
  final double size;
  final Color? backgroundColor;

  const AvatarInitials({
    super.key,
    required this.name,
    this.size = 36,
    this.backgroundColor,
  });

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  Color _colorFromName(String name) {
    final colors = [
      const Color(0xFF6366F1),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFFEF4444),
      const Color(0xFFF97316),
      const Color(0xFF10B981),
      const Color(0xFF14B8A6),
      const Color(0xFF3B82F6),
      const Color(0xFFA855F7),
      const Color(0xFFF59E0B),
    ];
    final idx = name.codeUnits.fold(0, (a, b) => a + b) % colors.length;
    return colors[idx];
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? _colorFromName(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

// ─── Section Header ──────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.stone400,
              letterSpacing: 1.2,
              fontFamily: 'Inter',
            ),
          ),
          const Spacer(),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
              ),
              child: Text(action!, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

// ─── Loading Overlay ─────────────────────────────────────────────────────────
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;

  const LoadingOverlay({super.key, required this.isLoading, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            alignment: Alignment.center,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Custom Tab Bar ──────────────────────────────────────────────────────────
class AppTabBar extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const AppTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.stone100,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = i == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: active
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? AppTheme.stone900 : AppTheme.stone500,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Indigo Chip ─────────────────────────────────────────────────────────────
class IndigoChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const IndigoChip({super.key, required this.label, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.stone100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.stone200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.stone600,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

// ─── Bottom Sheet Handle ─────────────────────────────────────────────────────
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.stone200,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ─── Module Icon Card (for dashboard grid) ───────────────────────────────────
class ModuleCard extends StatelessWidget {
  final String emoji;
  final String name;
  final String? badge;
  final VoidCallback onTap;
  final Color? color;

  const ModuleCard({
    super.key,
    required this.emoji,
    required this.name,
    required this.onTap,
    this.badge,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color?.withValues(alpha: 0.08) ?? AppTheme.stone50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color?.withValues(alpha: 0.15) ?? AppTheme.stone100),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                if (badge != null)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppTheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.stone800,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat Card ───────────────────────────────────────────────────────────────
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? emoji;
  final Color? color;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.emoji,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (color ?? AppTheme.primary).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (color ?? AppTheme.primary).withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (emoji != null) Text(emoji!, style: const TextStyle(fontSize: 20)),
          if (emoji != null) const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: color ?? AppTheme.primary,
              fontFamily: 'Inter',
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.stone500,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Gradient Header ─────────────────────────────────────────────────────────
class GradientHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color startColor;
  final Color endColor;

  const GradientHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.startColor = AppTheme.primary,
    this.endColor = const Color(0xFF8B5CF6),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [startColor, endColor],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontFamily: 'Inter',
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

// ─── Page Header (consistent across all screens) ─────────────────────────────
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                height: 1.2,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: cs.onSurface.withValues(alpha: 0.55),
                  height: 1.4,
                ),
              ),
            ],
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: actions!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Action Chip Button (for page header actions) ────────────────────────────
class ActionChipButton extends StatelessWidget {
  final IconData? icon;
  final String? emoji;
  final String label;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isPrimary;

  const ActionChipButton({
    super.key,
    this.icon,
    this.emoji,
    required this.label,
    required this.onTap,
    this.backgroundColor,
    this.foregroundColor,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? (isPrimary ? AppTheme.primary : AppTheme.stone800);
    final fg = foregroundColor ?? Colors.white;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              if (emoji != null) ...[
                Text(emoji!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Onboarding Card (empty state with bullet points) ────────────────────────
class OnboardingCard extends StatelessWidget {
  final String emoji;
  final String title;
  final List<String> bullets;
  final String? actionLabel;
  final VoidCallback? onAction;

  const OnboardingCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.bullets,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.stone100),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.stone900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          ...bullets.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('› ', style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: AppTheme.stone400,
                  fontWeight: FontWeight.w600,
                )),
                Expanded(
                  child: Text(
                    b,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppTheme.stone600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Custom App Bar for FamilyHub ────────────────────────────────────────────
class FamilyHubAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onMenuTap;
  final List<Widget>? actions;

  const FamilyHubAppBar({super.key, this.onMenuTap, this.actions});

  void _openJumpTo(BuildContext context) {
    final q = ValueNotifier<String>('');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: ValueListenableBuilder<String>(
                      valueListenable: q,
                      builder: (_, query, __) {
                        return TextField(
                          autofocus: true,
                          onChanged: (v) => q.value = v,
                          decoration: InputDecoration(
                            hintText: 'Jump to a screen…',
                            prefixIcon: const Icon(Icons.search_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            isDense: true,
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: q,
                      builder: (_, query, __) {
                        final qq = query.trim().toLowerCase();
                        final extra = [
                          (path: '/subscription', name: 'Subscription', emoji: '👑', group: 'Account'),
                          (path: '/ai-history', name: 'AI History', emoji: '🤖', group: 'Account'),
                          (path: '/habits', name: 'Habits', emoji: '🎯', group: 'Lifestyle'),
                          (path: '/period-tracker', name: 'Period Tracker', emoji: '🌸', group: 'Lifestyle'),
                          (path: '/health', name: 'Health', emoji: '❤️', group: 'Family'),
                          (path: '/location', name: 'Location', emoji: '📍', group: 'Family'),
                        ];
                        final items = <({String path, String name, String emoji, String group})>[];
                        for (final g in moduleGroups) {
                          for (final m in g.modules) {
                            items.add((path: m.path, name: m.name, emoji: m.emoji, group: g.label));
                          }
                        }
                        items.addAll(extra);
                        final filtered = qq.isEmpty
                            ? items
                            : items
                                .where((e) =>
                                    e.name.toLowerCase().contains(qq) ||
                                    e.path.toLowerCase().contains(qq) ||
                                    e.group.toLowerCase().contains(qq))
                                .toList();
                        return ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final e = filtered[i];
                            return ListTile(
                              leading: Text(e.emoji, style: const TextStyle(fontSize: 22)),
                              title: Text(e.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                              subtitle: Text('${e.group} · ${e.path}', style: const TextStyle(fontFamily: 'Inter', fontSize: 11)),
                              onTap: () {
                                Navigator.pop(ctx);
                                context.go(e.path);
                              },
                            );
                          },
                        );
                      },
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

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurf = cs.onSurface;
    final mergedActions = <Widget>[
      IconButton(
        tooltip: 'Jump to',
        icon: Icon(Icons.search_rounded, color: onSurf.withValues(alpha: 0.85)),
        onPressed: () => _openJumpTo(context),
      ),
      ...?actions,
    ];
    return AppBar(
      backgroundColor: cs.surface,
      foregroundColor: onSurf,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(Icons.menu_rounded, color: onSurf.withValues(alpha: 0.8)),
        onPressed: onMenuTap ?? () => Scaffold.of(context).openDrawer(),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            String.fromCharCode(0x2728), // sparkle
            style: TextStyle(fontSize: 18, color: onSurf.withValues(alpha: 0.9)),
          ),
          const SizedBox(width: 6),
          Text(
            'FamilyHub',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: cs.primary,
            ),
          ),
        ],
      ),
      centerTitle: false,
      titleSpacing: 0,
      actions: mergedActions,
    );
  }
}

// ─── Share Picker ───────────────────────────────────────────────────────────
/// A reusable widget that lets you choose between sharing with the whole family
/// or picking specific members. Returns [Visibility] + [List<String>] of selected IDs.

class SharePicker extends StatefulWidget {
  final List<SharePickerMember> members;
  final Visibility initialVisibility;
  final List<String> initialSharedWith;
  final ValueChanged<SharePickerResult> onChanged;

  const SharePicker({
    super.key,
    required this.members,
    this.initialVisibility = Visibility.FAMILY,
    this.initialSharedWith = const [],
    required this.onChanged,
  });

  @override
  State<SharePicker> createState() => _SharePickerState();
}

class SharePickerResult {
  final Visibility visibility;
  final List<String> sharedWith;
  const SharePickerResult({required this.visibility, required this.sharedWith});
}

class SharePickerMember {
  final String id;
  final String name;
  const SharePickerMember({required this.id, required this.name});
}

class _SharePickerState extends State<SharePicker> {
  late Visibility _visibility;
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _visibility = widget.initialVisibility;
    _selected = Set.from(widget.initialSharedWith);
  }

  void _emit() {
    widget.onChanged(SharePickerResult(
      visibility: _visibility,
      sharedWith: _visibility == Visibility.SPECIFIC ? _selected.toList() : [],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Share with',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.stone700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _visibility = Visibility.FAMILY);
                  _emit();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _visibility == Visibility.FAMILY
                        ? AppTheme.primary.withValues(alpha: 0.12)
                        : AppTheme.stone50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _visibility == Visibility.FAMILY
                          ? AppTheme.primary
                          : AppTheme.stone200,
                      width: _visibility == Visibility.FAMILY ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.family_restroom_rounded,
                          size: 16,
                          color: _visibility == Visibility.FAMILY
                              ? AppTheme.primary
                              : AppTheme.stone500),
                      const SizedBox(width: 6),
                      Text(
                        'Whole Family',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _visibility == Visibility.FAMILY
                              ? AppTheme.primary
                              : AppTheme.stone500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _visibility = Visibility.SPECIFIC);
                  _emit();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _visibility == Visibility.SPECIFIC
                        ? AppTheme.primary.withValues(alpha: 0.12)
                        : AppTheme.stone50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _visibility == Visibility.SPECIFIC
                          ? AppTheme.primary
                          : AppTheme.stone200,
                      width: _visibility == Visibility.SPECIFIC ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_add_rounded,
                          size: 16,
                          color: _visibility == Visibility.SPECIFIC
                              ? AppTheme.primary
                              : AppTheme.stone500),
                      const SizedBox(width: 6),
                      Text(
                        'Specific People',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _visibility == Visibility.SPECIFIC
                              ? AppTheme.primary
                              : AppTheme.stone500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_visibility == Visibility.SPECIFIC) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.members.map((m) {
              final isOn = _selected.contains(m.id);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isOn) {
                      _selected.remove(m.id);
                    } else {
                      _selected.add(m.id);
                    }
                  });
                  _emit();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOn
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : AppTheme.stone100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOn ? AppTheme.primary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AvatarInitials(name: m.name, size: 22),
                      const SizedBox(width: 6),
                      Text(
                        m.name.split(' ').first,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isOn ? AppTheme.primary : AppTheme.stone700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

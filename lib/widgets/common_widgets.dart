import 'package:flutter/material.dart';
import '../config/theme.dart';

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
    final card = Container(
      decoration: BoxDecoration(
        color: color ?? AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.stone100),
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
                color: AppTheme.stone700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.stone400,
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
        color = const Color(0xFFDC2626);
        label = 'High';
        break;
      case 'MEDIUM':
        color = const Color(0xFFD97706);
        label = 'Med';
        break;
      default:
        color = const Color(0xFF16A34A);
        label = 'Low';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
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
            color: Colors.black.withOpacity(0.3),
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
                      ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 1))]
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
          color: color?.withOpacity(0.08) ?? AppTheme.stone50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color?.withOpacity(0.15) ?? AppTheme.stone100),
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
        color: (color ?? AppTheme.primary).withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (color ?? AppTheme.primary).withOpacity(0.12)),
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

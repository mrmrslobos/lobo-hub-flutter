// lib/widgets/app_drawer.dart
// Side navigation drawer for FamilyHub

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/app_provider.dart';

// ─────────────────────────────────────────────
// Data model for nav items
// ─────────────────────────────────────────────

class _NavItem {
  final String emoji;
  final String label;
  final String route;
  final int unreadCount;

  const _NavItem({
    required this.emoji,
    required this.label,
    required this.route,
    this.unreadCount = 0,
  });
}

class _NavSection {
  final String title;
  final List<_NavItem> items;

  const _NavSection({required this.title, required this.items});
}

// ─────────────────────────────────────────────
// AppDrawer widget
// ─────────────────────────────────────────────

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  static const List<_NavSection> _sections = [
    _NavSection(title: 'Family', items: [
      _NavItem(emoji: '💬', label: 'Chat', route: '/chat'),
      _NavItem(emoji: '✅', label: 'Tasks', route: '/tasks'),
      _NavItem(emoji: '📅', label: 'Calendar', route: '/calendar'),
      _NavItem(emoji: '🧹', label: 'Chores', route: '/chores'),
      _NavItem(emoji: '📋', label: 'Lists', route: '/lists'),
      _NavItem(emoji: '🗳️', label: 'Polls', route: '/polls'),
      _NavItem(emoji: '🎉', label: 'Occasions', route: '/birthdays'),
      _NavItem(emoji: '📸', label: 'Photos', route: '/photos'),
      _NavItem(emoji: '📍', label: 'Location', route: '/location'),
      _NavItem(emoji: '❤️', label: 'Health', route: '/health'),
    ]),
    _NavSection(title: 'Lifestyle', items: [
      _NavItem(emoji: '🍽️', label: 'Meals', route: '/meals'),
      _NavItem(emoji: '💪', label: 'Fitness', route: '/fitness'),
      _NavItem(emoji: '🌸', label: 'Period Tracker', route: '/period-tracker'),
      _NavItem(emoji: '📖', label: 'Devotional', route: '/devotional'),
      _NavItem(emoji: '🙏', label: 'Prayer Wall', route: '/prayer-wall'),
    ]),
    _NavSection(title: 'Money', items: [
      _NavItem(emoji: '💰', label: 'Budget', route: '/budget'),
      _NavItem(emoji: '🎁', label: 'Rewards', route: '/rewards'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    final currentRoute = GoRouterState.of(context).matchedLocation;

    return Drawer(
      backgroundColor: AppTheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────
            _DrawerHeader(user: user, family: family),
            const Divider(height: 1),

            // ── Nav items ───────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // Dashboard
                  _NavTile(
                    emoji: '🏠',
                    label: 'Dashboard',
                    route: '/',
                    isActive: currentRoute == '/',
                    canAccess: true,
                  ),
                  const SizedBox(height: 4),

                  // Sections
                  for (final section in _sections) ...[
                    _SectionHeader(title: section.title),
                    for (final item in section.items)
                      _NavTile(
                        emoji: item.emoji,
                        label: item.label,
                        route: item.route,
                        isActive: currentRoute == item.route,
                        canAccess: provider.canAccess(item.route),
                        unreadCount: item.unreadCount,
                      ),
                    const SizedBox(height: 4),
                  ],

                  // AI History at the end
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  _NavTile(
                    emoji: '🤖',
                    label: 'AI History',
                    route: '/ai-history',
                    isActive: currentRoute == '/ai-history',
                    canAccess: true,
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── Footer ──────────────────────────────
            _DrawerFooter(provider: provider),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Drawer Header
// ─────────────────────────────────────────────

class _DrawerHeader extends StatelessWidget {
  final dynamic user;
  final dynamic family;

  const _DrawerHeader({required this.user, required this.family});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              _UserAvatar(user: user),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? 'Family Member',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppTheme.stone900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: AppTheme.stone500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (family != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Text(
                    '🏡',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          family!.name as String,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppTheme.primaryDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Text(
                              'Code: ${family!.joinCode}',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w500,
                                fontSize: 11,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: family!.joinCode as String));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Join code copied!'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: const Icon(
                                Icons.copy_rounded,
                                size: 12,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// User Avatar
// ─────────────────────────────────────────────

class _UserAvatar extends StatelessWidget {
  final dynamic user;
  const _UserAvatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final String initials = user?.initials ?? '?';
    final String? avatarUrl = user?.avatarUrl as String?;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(avatarUrl),
        backgroundColor: AppTheme.primaryLight,
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: AppTheme.primary,
      child: Text(
        initials,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 1.2,
          color: AppTheme.stone400,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Nav tile
// ─────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String route;
  final bool isActive;
  final bool canAccess;
  final int unreadCount;

  const _NavTile({
    required this.emoji,
    required this.label,
    required this.route,
    required this.isActive,
    required this.canAccess,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        canAccess ? AppTheme.stone800 : AppTheme.stone400;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: isActive ? AppTheme.primaryLight : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: canAccess
              ? () {
                  Navigator.of(context).pop(); // close drawer
                  context.go(route);
                }
              : null,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Text(
                  emoji,
                  style: TextStyle(
                    fontSize: 18,
                    color:
                        canAccess ? null : const Color(0x66000000),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                      color: isActive ? AppTheme.primary : effectiveColor,
                    ),
                  ),
                ),
                if (!canAccess)
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: AppTheme.stone400,
                  ),
                if (unreadCount > 0 && canAccess)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Drawer Footer
// ─────────────────────────────────────────────

class _DrawerFooter extends StatelessWidget {
  final AppProvider provider;
  const _DrawerFooter({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                // TODO: open settings screen
              },
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Settings'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await provider.logout();
            },
            icon: const Icon(
              Icons.logout_rounded,
              color: AppTheme.error,
              size: 20,
            ),
            tooltip: 'Log out',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x1ADC2626),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Public helper: UserAvatarWidget (reusable across screens)
// ─────────────────────────────────────────────

class UserAvatarWidget extends StatelessWidget {
  final String? name;
  final String? avatarUrl;
  final double radius;
  final Color? backgroundColor;

  const UserAvatarWidget({
    super.key,
    this.name,
    this.avatarUrl,
    this.radius = 18,
    this.backgroundColor,
  });

  String get _initials {
    if (name == null || name!.isEmpty) return '?';
    final parts = name!.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name![0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(avatarUrl!),
        backgroundColor: AppTheme.primaryLight,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? AppTheme.primary,
      child: Text(
        _initials,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.65,
          color: Colors.white,
        ),
      ),
    );
  }
}

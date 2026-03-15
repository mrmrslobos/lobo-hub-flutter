// lib/widgets/app_drawer.dart
// Side navigation drawer for FamilyHub

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/calendar_sync_service.dart';
import '../services/supabase_service.dart';
import 'biometric_lock.dart';

// ─────────────────────────────────────────────
// Data model for nav items
// ─────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;
  final String route;
  final int unreadCount;

  const _NavItem({
    required this.icon,
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

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  static const List<_NavSection> _sections = [
    _NavSection(title: 'Family', items: [
      _NavItem(icon: Icons.chat_bubble_outline_rounded, label: 'Chat', route: '/chat'),
      _NavItem(icon: Icons.check_circle_outline_rounded, label: 'Tasks', route: '/tasks'),
      _NavItem(icon: Icons.calendar_month_rounded, label: 'Calendar', route: '/calendar'),
      _NavItem(icon: Icons.assignment_turned_in_outlined, label: 'Chores', route: '/chores'),
      _NavItem(icon: Icons.checklist_rounded, label: 'Lists', route: '/lists'),
      _NavItem(icon: Icons.how_to_vote_outlined, label: 'Polls', route: '/polls'),
      _NavItem(icon: Icons.cake_outlined, label: 'Occasions', route: '/birthdays'),
      _NavItem(icon: Icons.photo_library_outlined, label: 'Photos', route: '/photos'),
      _NavItem(icon: Icons.location_on_outlined, label: 'Location', route: '/location'),
      _NavItem(icon: Icons.favorite_outline_rounded, label: 'Health', route: '/health'),
    ]),
    _NavSection(title: 'Lifestyle', items: [
      _NavItem(icon: Icons.track_changes_rounded, label: 'Habits', route: '/habits'),
      _NavItem(icon: Icons.restaurant_menu_rounded, label: 'Meals', route: '/meals'),
      _NavItem(icon: Icons.fitness_center_rounded, label: 'Fitness', route: '/fitness'),
      _NavItem(icon: Icons.spa_outlined, label: 'Period Tracker', route: '/period-tracker'),
      _NavItem(icon: Icons.menu_book_rounded, label: 'Devotional', route: '/devotional'),
      _NavItem(icon: Icons.volunteer_activism_outlined, label: 'Prayer Wall', route: '/prayer-wall'),
    ]),
    _NavSection(title: 'Money', items: [
      _NavItem(icon: Icons.account_balance_wallet_outlined, label: 'Budget', route: '/budget'),
      _NavItem(icon: Icons.card_giftcard_rounded, label: 'Rewards', route: '/rewards'),
    ]),
  ];

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final Set<String> _collapsedSections = {};

  void _showManageMembersSheet(BuildContext context) {
    Navigator.pop(context); // close drawer
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ManageMembersSheet(),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SettingsBottomSheet(),
    );
  }

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
            _DrawerHeader(
              user: user,
              family: family,
              onAvatarTap: () {
                Navigator.of(context).pop();
                _showSettingsSheet(context);
              },
            ),
            const Divider(height: 1),

            // ── Nav items ───────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // Dashboard
                  _NavTile(
                    icon: Icons.home_outlined,
                    label: 'Dashboard',
                    route: '/',
                    isActive: currentRoute == '/',
                    canAccess: true,
                  ),
                  const SizedBox(height: 4),

                  // Sections — collapsible, hide inaccessible modules
                  for (final section in AppDrawer._sections) ...[
                    if (section.items.any((item) => provider.canAccess(item.route))) ...[
                      _CollapsibleSectionHeader(
                        title: section.title,
                        isCollapsed: _collapsedSections.contains(section.title),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (_collapsedSections.contains(section.title)) {
                              _collapsedSections.remove(section.title);
                            } else {
                              _collapsedSections.add(section.title);
                            }
                          });
                        },
                      ),
                      if (!_collapsedSections.contains(section.title))
                        for (final item in section.items)
                          if (provider.canAccess(item.route))
                            _NavTile(
                              icon: item.icon,
                              label: item.label,
                              route: item.route,
                              isActive: currentRoute == item.route,
                              canAccess: true,
                              unreadCount: item.unreadCount,
                            ),
                      const SizedBox(height: 4),
                    ],
                  ],

                  // AI History at the end
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  _NavTile(
                    icon: Icons.psychology_outlined,
                    label: 'AI History',
                    route: '/ai-history',
                    isActive: currentRoute == '/ai-history',
                    canAccess: true,
                  ),

                  // Settings section
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  _SectionHeader(title: 'Settings'),
                  if (provider.isAdmin)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showManageMembersSheet(context),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Icon(Icons.group_outlined, size: 20, color: AppTheme.stone600),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Manage Members',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                      color: AppTheme.stone800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _showSettingsSheet(context),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.settings_outlined, size: 20, color: AppTheme.stone600),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Settings',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: AppTheme.stone800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
// Settings Bottom Sheet
// ─────────────────────────────────────────────

class _SettingsBottomSheet extends StatefulWidget {
  const _SettingsBottomSheet();

  @override
  State<_SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<_SettingsBottomSheet> {
  bool _biometricEnabled = false;
  String _selectedLocale = 'US';
  bool _loading = true;

  static const _countries = [
    ('🇺🇸', 'United States', 'US'),
    ('🇬🇧', 'United Kingdom', 'GB'),
    ('🇨🇦', 'Canada', 'CA'),
    ('🇦🇺', 'Australia', 'AU'),
    ('🇮🇳', 'India', 'IN'),
  ];

  static const _dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _biometricEnabled = prefs.getBool('lobohub_biometric_enabled') ?? false;
      _selectedLocale = prefs.getString('lobohub_locale') ?? 'US';
      _loading = false;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    await BiometricLockScreen.setBiometricEnabled(value);
    setState(() => _biometricEnabled = value);
  }

  Future<void> _selectLocale(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lobohub_locale', code);
    setState(() => _selectedLocale = code);
  }

  Future<void> _importGoogleTasks(
    BuildContext context,
    AppProvider provider,
    Family family,
    User user,
  ) async {
    // Sign in to Google (or use existing session)
    var account = CalendarSyncService.currentGoogleUser;
    account ??= await CalendarSyncService.signInGoogle();
    if (account == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in cancelled')),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Importing Google Tasks...')),
      );
    }

    final imported = await CalendarSyncService.fetchGoogleTasks(
      familyId: family.id,
      userId: user.id,
    );

    if (imported.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tasks found in Google Tasks')),
        );
      }
      return;
    }

    // Merge: skip tasks already imported (by id prefix)
    final existingIds = provider.db.tasks.map((t) => t.id).toSet();
    final newTasks = imported.where((t) => !existingIds.contains(t.id)).toList();

    if (newTasks.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All Google Tasks already imported')),
        );
      }
      return;
    }

    await provider.saveAndSync(provider.db.copyWith(
      tasks: [...provider.db.tasks, ...newTasks],
    ));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${newTasks.length} task${newTasks.length == 1 ? '' : 's'} from Google')),
      );
    }
  }

  /// Convert local day-of-week + hour to UTC day + hour.
  (int, int) _localToUtc(int localDay, int localHour) {
    final now = DateTime.now();
    final offset = now.timeZoneOffset.inHours;
    var utcHour = localHour - offset;
    var utcDay = localDay;
    if (utcHour < 0) {
      utcHour += 24;
      utcDay = (utcDay - 1) % 7;
    } else if (utcHour >= 24) {
      utcHour -= 24;
      utcDay = (utcDay + 1) % 7;
    }
    return (utcDay, utcHour);
  }

  /// Convert UTC day-of-week + hour to local day + hour.
  (int, int) _utcToLocal(int utcDay, int utcHour) {
    final now = DateTime.now();
    final offset = now.timeZoneOffset.inHours;
    var localHour = utcHour + offset;
    var localDay = utcDay;
    if (localHour < 0) {
      localHour += 24;
      localDay = (localDay - 1) % 7;
    } else if (localHour >= 24) {
      localHour -= 24;
      localDay = (localDay + 1) % 7;
    }
    return (localDay, localHour);
  }

  /// Save weekly digest settings to the family record via provider.
  Future<void> _saveDigestSettings(AppProvider provider, {bool? enabled, int? localDay, int? localHour}) async {
    final family = provider.activeFamily;
    if (family == null) return;

    // Get current local values
    final (curLocalDay, curLocalHour) = _utcToLocal(family.weeklyDigestDay, family.weeklyDigestHour);
    final newLocalDay = localDay ?? curLocalDay;
    final newLocalHour = localHour ?? curLocalHour;
    final (utcDay, utcHour) = _localToUtc(newLocalDay, newLocalHour);

    final updated = family.copyWith(
      weeklyDigest: enabled ?? family.weeklyDigest,
      weeklyDigestDay: utcDay,
      weeklyDigestHour: utcHour,
    );

    // Update the family in the DB
    final db = provider.db;
    final families = db.families.map((f) => f.id == updated.id ? updated : f).toList();
    await provider.saveAndSync(db.copyWith(families: families));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: _loading
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.stone200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Settings',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: AppTheme.stone900,
                  ),
                ),
                const SizedBox(height: 20),

                // Biometric Lock toggle
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.stone50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    title: const Text(
                      'Biometric Lock',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppTheme.stone900,
                      ),
                    ),
                    subtitle: const Text(
                      'Require fingerprint or face to open app',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppTheme.stone500,
                      ),
                    ),
                    value: _biometricEnabled,
                    onChanged: _toggleBiometric,
                    secondary: const Icon(Icons.fingerprint_rounded, color: AppTheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),

                // Weekly Digest settings
                Builder(builder: (ctx) {
                  final provider = ctx.watch<AppProvider>();
                  final family = provider.activeFamily;
                  if (family == null) return const SizedBox.shrink();
                  final isOwner = family.ownerId == provider.activeUser?.id;
                  final digestEnabled = family.weeklyDigest;
                  final (localDay, localHour) = _utcToLocal(family.weeklyDigestDay, family.weeklyDigestHour);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'WEEKLY DIGEST',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.5,
                          color: AppTheme.stone500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.stone50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text(
                                'Weekly Summary',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: AppTheme.stone900,
                                ),
                              ),
                              subtitle: const Text(
                                'Get a weekly notification with upcoming events, tasks, and chore stats',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: AppTheme.stone500,
                                ),
                              ),
                              value: digestEnabled,
                              onChanged: isOwner
                                  ? (val) => _saveDigestSettings(provider, enabled: val)
                                  : null,
                              secondary: const Icon(Icons.summarize_rounded, color: AppTheme.primary),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            if (digestEnabled) ...[
                              const Divider(height: 1, indent: 16, endIndent: 16),
                              ListTile(
                                leading: const Icon(Icons.calendar_today_rounded, color: AppTheme.primary, size: 20),
                                title: const Text(
                                  'Day',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: AppTheme.stone800,
                                  ),
                                ),
                                trailing: DropdownButton<int>(
                                  value: localDay,
                                  underline: const SizedBox.shrink(),
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: AppTheme.primary,
                                  ),
                                  items: List.generate(7, (i) => DropdownMenuItem(
                                    value: i,
                                    child: Text(_dayNames[i]),
                                  )),
                                  onChanged: isOwner
                                      ? (val) {
                                          if (val != null) _saveDigestSettings(provider, localDay: val);
                                        }
                                      : null,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              const Divider(height: 1, indent: 16, endIndent: 16),
                              ListTile(
                                leading: const Icon(Icons.access_time_rounded, color: AppTheme.primary, size: 20),
                                title: const Text(
                                  'Time',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: AppTheme.stone800,
                                  ),
                                ),
                                trailing: DropdownButton<int>(
                                  value: localHour,
                                  underline: const SizedBox.shrink(),
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: AppTheme.primary,
                                  ),
                                  items: List.generate(24, (h) {
                                    final display = h == 0 ? '12 AM' : h < 12 ? '$h AM' : h == 12 ? '12 PM' : '${h - 12} PM';
                                    return DropdownMenuItem(value: h, child: Text(display));
                                  }),
                                  onChanged: isOwner
                                      ? (val) {
                                          if (val != null) _saveDigestSettings(provider, localHour: val);
                                        }
                                      : null,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!isOwner && digestEnabled)
                        const Padding(
                          padding: EdgeInsets.only(top: 4, left: 4),
                          child: Text(
                            'Only the family owner can change digest settings',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              color: AppTheme.stone400,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                  );
                }),

                // Import from Google Tasks
                Builder(builder: (ctx) {
                  final provider = ctx.watch<AppProvider>();
                  final family = provider.activeFamily;
                  final user = provider.activeUser;
                  if (family == null || user == null) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'IMPORT',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.5,
                          color: AppTheme.stone500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.stone50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.download_rounded, color: AppTheme.stone600, size: 22),
                          title: const Text(
                            'Import Google Tasks',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: AppTheme.stone900,
                            ),
                          ),
                          subtitle: const Text(
                            'One-time import of your Google Tasks',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppTheme.stone500,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.stone400),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onTap: () => _importGoogleTasks(ctx, provider, family, user),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }),

                // Country/Region selector
                const Text(
                  'Country / Region',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.5,
                    color: AppTheme.stone500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.stone50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: _countries.map((c) {
                      final (flag, name, code) = c;
                      final isSelected = _selectedLocale == code;
                      return ListTile(
                        leading: Text(flag, style: const TextStyle(fontSize: 22)),
                        title: Text(
                          name,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 14,
                            color: isSelected ? AppTheme.primary : AppTheme.stone800,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 20)
                            : null,
                        onTap: () => _selectLocale(code),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // Subscription / Plan
                Builder(builder: (ctx) {
                  final provider = ctx.watch<AppProvider>();
                  final family = provider.activeFamily;
                  if (family == null) return const SizedBox.shrink();
                  final tier = family.subscriptionTier;
                  final isOnTrial = tier == SubscriptionTier.trial;
                  final trialDays = family.trialDaysRemaining;
                  final trialExpired = family.isTrialExpired;

                  String planLabel;
                  Color planColor;
                  String planDesc;
                  switch (tier) {
                    case SubscriptionTier.base:
                      planLabel = 'Base';
                      planColor = const Color(0xFF0EA5E9);
                      planDesc = 'Essential family organisation';
                    case SubscriptionTier.ai:
                      planLabel = 'AI';
                      planColor = const Color(0xFF8B5CF6);
                      planDesc = 'Smart AI-powered features';
                    case SubscriptionTier.ai_family:
                      planLabel = 'AI Family';
                      planColor = const Color(0xFF16A34A);
                      planDesc = '2 adults + 4 children covered';
                    case SubscriptionTier.trial:
                      planLabel = trialExpired ? 'Trial Expired' : 'Free Trial';
                      planColor = trialExpired ? const Color(0xFFDC2626) : const Color(0xFF6366F1);
                      planDesc = trialExpired
                          ? 'Limited to Tasks, Lists & Calendar'
                          : '$trialDays day${trialDays == 1 ? '' : 's'} remaining';
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SUBSCRIPTION',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.5,
                          color: AppTheme.stone500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                          context.go('/subscription');
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: planColor.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: planColor.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: planColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isOnTrial ? Icons.timer_rounded : Icons.workspace_premium_rounded,
                                  size: 20,
                                  color: planColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(planLabel, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: planColor)),
                                  Text(planDesc, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
                                ],
                              )),
                              Icon(Icons.chevron_right_rounded, color: planColor, size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }),

                // About section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'FamilyHub',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppTheme.stone900,
                        ),
                      ),
                      Text(
                        'Version 1.0.0',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: AppTheme.stone500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────
// Drawer Header
// ─────────────────────────────────────────────

class _DrawerHeader extends StatefulWidget {
  final dynamic user;
  final dynamic family;
  final VoidCallback? onAvatarTap;

  const _DrawerHeader({required this.user, required this.family, this.onAvatarTap});

  @override
  State<_DrawerHeader> createState() => _DrawerHeaderState();
}

class _DrawerHeaderState extends State<_DrawerHeader> {
  bool _showCode = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar — tappable to open settings
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onAvatarTap?.call();
                },
                child: _UserAvatar(user: widget.user),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user?.name ?? 'Family Member',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppTheme.stone900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.user?.email ?? '',
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
          if (widget.family != null) ...[
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
                          widget.family!.name as String,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppTheme.primaryDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        GestureDetector(
                          onTap: () {
                            if (_showCode) {
                              Clipboard.setData(
                                  ClipboardData(text: widget.family!.joinCode as String));
                              HapticFeedback.lightImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Join code copied!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            } else {
                              HapticFeedback.selectionClick();
                              setState(() => _showCode = true);
                            }
                          },
                          child: Row(
                            children: [
                              Text(
                                _showCode
                                    ? 'Code: ${widget.family!.joinCode}'
                                    : 'Tap to show join code',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _showCode ? Icons.copy_rounded : Icons.visibility_outlined,
                                size: 12,
                                color: AppTheme.primary,
                              ),
                            ],
                          ),
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

class _CollapsibleSectionHeader extends StatelessWidget {
  final String title;
  final bool isCollapsed;
  final VoidCallback onTap;
  const _CollapsibleSectionHeader({required this.title, required this.isCollapsed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
        child: Row(
          children: [
            Expanded(
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
            ),
            AnimatedRotation(
              turns: isCollapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.expand_more, size: 16, color: AppTheme.stone400),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Nav tile
// ─────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final bool isActive;
  final bool canAccess;
  final int unreadCount;

  const _NavTile({
    required this.icon,
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
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop(); // close drawer
                  context.go(route);
                }
              : null,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Material 3 active indicator bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 3,
                  height: isActive ? 20 : 0,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isActive ? AppTheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? AppTheme.primary : (canAccess ? AppTheme.stone500 : AppTheme.stone300),
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
                if (unreadCount > 0)
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
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const _SettingsBottomSheet(),
                );
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

// ─────────────────────────────────────────────
// Manage Members Bottom Sheet
// ─────────────────────────────────────────────

class _ManageMembersSheet extends StatefulWidget {
  const _ManageMembersSheet();

  @override
  State<_ManageMembersSheet> createState() => _ManageMembersSheetState();
}

class _ManageMembersSheetState extends State<_ManageMembersSheet> {
  static const _kidsPresetRoutes = ['/', '/calendar', '/meals', '/chores', '/rewards'];

  static const _allModules = [
    ('/', '🏠', 'Dashboard'),
    ('/chat', '💬', 'Chat'),
    ('/tasks', '✅', 'Tasks'),
    ('/calendar', '📅', 'Calendar'),
    ('/chores', '🧹', 'Chores'),
    ('/lists', '📋', 'Lists'),
    ('/meals', '🍽️', 'Meals'),
    ('/polls', '🗳️', 'Polls'),
    ('/birthdays', '🎉', 'Occasions'),
    ('/photos', '📸', 'Photos'),
    ('/location', '📍', 'Location'),
    ('/health', '❤️', 'Health'),
    ('/habits', '🎯', 'Habits'),
    ('/fitness', '💪', 'Fitness'),
    ('/period-tracker', '🌸', 'Period Tracker'),
    ('/devotional', '📖', 'Devotional'),
    ('/prayer-wall', '🙏', 'Prayer Wall'),
    ('/budget', '💰', 'Budget'),
    ('/rewards', '🎁', 'Rewards'),
  ];

  // Mutable copy of members to edit before saving
  late List<_EditableMember> _members;
  String? _expandedUserId;

  @override
  void initState() {
    super.initState();
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final familyId = provider.activeFamily?.id;
    _members = db.familyMembers
        .where((m) => m.familyId == familyId)
        .map((m) {
      // Resolve display name from users list
      final user = db.users.where((u) => u.id == m.userId).firstOrNull;
      return _EditableMember(
        userId: m.userId,
        familyId: m.familyId,
        role: m.role,
        moduleAccess: m.moduleAccess != null ? List<String>.from(m.moduleAccess!) : null,
        displayName: m.displayName ?? user?.name ?? m.userId,
      );
    }).toList();
  }

  bool _isKidsPreset(List<String>? access) {
    if (access == null) return false;
    if (access.length != _kidsPresetRoutes.length) return false;
    return _kidsPresetRoutes.every(access.contains);
  }

  void _applyKidsPreset(int index) {
    setState(() {
      _members[index].moduleAccess = List<String>.from(_kidsPresetRoutes);
    });
  }

  void _removeRestrictions(int index) {
    setState(() {
      _members[index].moduleAccess = null;
    });
  }

  void _toggleModule(int memberIdx, String route) {
    setState(() {
      final m = _members[memberIdx];
      if (m.moduleAccess == null) {
        // Currently unrestricted → restrict to all except this one
        m.moduleAccess = _allModules.map((e) => e.$1).where((r) => r != route).toList();
      } else if (m.moduleAccess!.contains(route)) {
        m.moduleAccess!.remove(route);
      } else {
        m.moduleAccess!.add(route);
      }
    });
  }

  Future<void> _save() async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final familyId = provider.activeFamily?.id;
    if (familyId == null) return;

    // Build updated familyMembers list
    final updated = db.familyMembers.map((m) {
      if (m.familyId != familyId) return m;
      final edited = _members.where((e) => e.userId == m.userId).firstOrNull;
      if (edited == null) return m;
      return m.copyWith(
        role: edited.role,
        moduleAccess: edited.moduleAccess,
        displayName: edited.displayName,
      );
    }).toList();

    try {
      await provider.saveAndSync(db.copyWith(familyMembers: updated));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: const Text('Member settings saved', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: const Text('Failed to save — please try again', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: AppTheme.error,
          ));
      }
    }
  }

  Future<void> _removeMember(int index) async {
    final m = _members[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${m.displayName} from this family? They will lose access to all shared data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final provider = context.read<AppProvider>();
    final db = provider.db;
    final removedUserId = m.userId;

    // Remove from familyMembers locally
    final updatedMembers = db.familyMembers
        .where((fm) => !(fm.userId == removedUserId && fm.familyId == m.familyId))
        .toList();

    await provider.saveAndSync(db.copyWith(familyMembers: updatedMembers));

    // Delete from cloud so the member doesn't return on next sync
    if (SupabaseService.isConfigured) {
      try {
        await SupabaseService.deleteRows('family_members', {
          'userId': removedUserId,
          'familyId': m.familyId,
        });
      } catch (e) {
        debugPrint('[Drawer] cloud delete member failed: $e');
      }
    }
    setState(() => _members.removeAt(index));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${m.displayName} removed from family'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.stone200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Manage Members',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: AppTheme.stone900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              itemCount: _members.length,
              itemBuilder: (context, i) => _buildMemberCard(i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(int index) {
    final m = _members[index];
    final isExpanded = _expandedUserId == m.userId;
    final isKid = _isKidsPreset(m.moduleAccess);
    final isRestricted = m.moduleAccess != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppTheme.stone50,
      elevation: 0,
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() {
              _expandedUserId = isExpanded ? null : m.userId;
            }),
            leading: UserAvatarWidget(name: m.displayName, radius: 20),
            title: Text(
              m.displayName,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: AppTheme.stone900,
              ),
            ),
            subtitle: Text(
              isKid
                  ? 'Kids Preset'
                  : isRestricted
                      ? 'Custom Access (${m.moduleAccess!.length} modules)'
                      : 'Full Access',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: isKid ? AppTheme.primary : AppTheme.stone500,
                fontWeight: isKid ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: m.role == Role.OWNER
                        ? const Color(0xFFFEF3C7)
                        : m.role == Role.ADMIN
                            ? AppTheme.primaryLight
                            : AppTheme.stone100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    m.role.name,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                      color: m.role == Role.OWNER
                          ? const Color(0xFF92400E)
                          : m.role == Role.ADMIN
                              ? AppTheme.primaryDark
                              : AppTheme.stone600,
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppTheme.stone400,
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _applyKidsPreset(index),
                          icon: const Icon(Icons.child_care, size: 16),
                          label: const Text('Kids Preset'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isKid ? Colors.white : AppTheme.primary,
                            backgroundColor: isKid ? AppTheme.primary : null,
                            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            textStyle: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _removeRestrictions(index),
                          icon: const Icon(Icons.lock_open, size: 16),
                          label: const Text('Full Access'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: !isRestricted ? Colors.white : AppTheme.stone600,
                            backgroundColor: !isRestricted ? AppTheme.stone600 : null,
                            side: BorderSide(color: AppTheme.stone300),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            textStyle: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'MODULE ACCESS',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      letterSpacing: 1.0,
                      color: AppTheme.stone400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _allModules.map((mod) {
                      final (route, emoji, label) = mod;
                      final hasAccess = m.moduleAccess == null || m.moduleAccess!.contains(route);
                      return FilterChip(
                        selected: hasAccess,
                        label: Text('$emoji $label', style: const TextStyle(fontSize: 12)),
                        onSelected: (_) => _toggleModule(index, route),
                        selectedColor: AppTheme.primaryLight,
                        checkmarkColor: AppTheme.primary,
                        backgroundColor: AppTheme.stone100,
                        side: BorderSide.none,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  // Remove member button (not for owner)
                  if (m.role != Role.OWNER) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _removeMember(index),
                        icon: const Icon(Icons.person_remove_rounded, size: 16),
                        label: const Text('Remove from Family'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red, width: 1),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          textStyle: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditableMember {
  final String userId;
  final String familyId;
  final Role role;
  List<String>? moduleAccess;
  final String displayName;

  _EditableMember({
    required this.userId,
    required this.familyId,
    required this.role,
    this.moduleAccess,
    required this.displayName,
  });
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

// lib/widgets/app_drawer.dart
// Side navigation drawer for FamilyHub

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/calendar_sync_service.dart';
import '../services/family_activity_service.dart';
import '../services/locale_service.dart';
import '../services/supabase_service.dart';
import '../utils/ai_family_household.dart';
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

  void _showActivityLogSheet(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ActivityLogSheet(),
    );
  }

  void _showWellnessSheet(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _WellnessPulseSheet(),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                  if (provider.isAdmin)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showActivityLogSheet(context),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Icon(Icons.history_rounded, size: 20, color: AppTheme.stone600),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Activity log',
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
                        onTap: () => _showWellnessSheet(context),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.favorite_outline_rounded, size: 20, color: AppTheme.stone600),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Family pulse',
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
  NotificationPrefs _notifPrefs = const NotificationPrefs();
  bool _notifLoaded = false;
  bool _resettingData = false;
  bool _deletingCloudData = false;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_notifLoaded) {
      _notifLoaded = true;
      _notifPrefs = context.read<AppProvider>().deviceNotificationPrefs;
    }
  }

  Future<void> _persistNotif(NotificationPrefs next) async {
    await context.read<AppProvider>().setDeviceNotificationPrefs(next);
    if (mounted) setState(() => _notifPrefs = next);
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

  Widget _notifSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
      value: value,
      onChanged: onChanged,
      dense: true,
      visualDensity: VisualDensity.compact,
    );
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

  Future<void> _confirmResetLocalData(BuildContext sheetContext) async {
    final ok = await showDialog<bool>(
      context: sheetContext,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Reset data on this device?',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'This signs you out and permanently deletes all FamilyHub data stored on this phone or tablet '
          '(your home, tasks, lists, and other synced copies saved locally). '
          'It does not remove data from our servers for other family members.\n\n'
          'You can sign in again afterward; your account will reload from the cloud if you use the same login.',
          style: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset data'),
          ),
        ],
      ),
    );
    if (ok != true || !sheetContext.mounted) return;

    setState(() => _resettingData = true);
    try {
      await sheetContext.read<AppProvider>().resetAllLocalDataAndSignOut();
      await sheetContext.read<LocaleService>().reloadFromPrefs();
      if (!sheetContext.mounted) return;
      Navigator.of(sheetContext).pop();
      if (!sheetContext.mounted) return;
      sheetContext.go('/auth');
    } catch (e) {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(content: Text('Could not reset: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _resettingData = false);
    }
  }

  Future<void> _confirmDeleteCloudAndLocalData(BuildContext sheetContext) async {
    final provider = sheetContext.read<AppProvider>();
    final fam = provider.activeFamily;
    final uid = provider.activeUser?.id;
    if (fam == null || uid == null) return;
    if (!SupabaseService.isConfigured) {
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        const SnackBar(
          content: Text('Cloud delete requires an online account (Supabase). Use “Reset data” to clear this device only.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (fam.ownerId != uid) {
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        const SnackBar(
          content: Text('Only the home owner can delete data for everyone in the cloud.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final proceed = await showDialog<bool>(
      context: sheetContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Delete your home from the cloud?',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800),
        ),
        content: Text(
          'This will permanently remove “${fam.name}” and all related data from our servers for every family member '
          '(tasks, lists, calendar, photos, chat, and more). This cannot be undone.\n\n'
          'Your login account will remain — you can create a new home after.\n\n'
          'Continue only if everyone agrees.',
          style: const TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !sheetContext.mounted) return;

    final typed = await showDialog<bool>(
      context: sheetContext,
      barrierDismissible: false,
      builder: (ctx) => const _DeleteCloudDataDialog(),
    );
    if (typed != true || !sheetContext.mounted) return;

    setState(() => _deletingCloudData = true);
    try {
      await SupabaseService.deleteFamilyCloudData(familyId: fam.id);
      await provider.resetAllLocalDataAndSignOut();
      await sheetContext.read<LocaleService>().reloadFromPrefs();
      if (!sheetContext.mounted) return;
      Navigator.of(sheetContext).pop();
      if (!sheetContext.mounted) return;
      sheetContext.go('/auth');
    } catch (e) {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(
            content: Text(
              'Could not delete cloud data. Apply Supabase migration 26_delete_family_cloud_data.sql or try again. ($e)',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingCloudData = false);
    }
  }

  /// 0=Sun … 6=Sat (matches weekly-digest edge function).
  /// Converts using full timezone offset (minutes), not integer hours only.
  (int, int) _localToUtc(int localDay, int localHour) {
    final now = DateTime.now();
    final offMin = now.timeZoneOffset.inMinutes;
    var utcTotalMin = localHour * 60 - offMin;
    var dayRoll = 0;
    while (utcTotalMin < 0) {
      utcTotalMin += 24 * 60;
      dayRoll--;
    }
    while (utcTotalMin >= 24 * 60) {
      utcTotalMin -= 24 * 60;
      dayRoll++;
    }
    var utcDay = (localDay + dayRoll) % 7;
    if (utcDay < 0) utcDay += 7;
    return (utcDay, utcTotalMin ~/ 60);
  }

  (int, int) _utcToLocal(int utcDay, int utcHour) {
    final now = DateTime.now();
    final offMin = now.timeZoneOffset.inMinutes;
    var localTotalMin = utcHour * 60 + offMin;
    var dayRoll = 0;
    while (localTotalMin < 0) {
      localTotalMin += 24 * 60;
      dayRoll--;
    }
    while (localTotalMin >= 24 * 60) {
      localTotalMin -= 24 * 60;
      dayRoll++;
    }
    var localDay = (utcDay + dayRoll) % 7;
    if (localDay < 0) localDay += 7;
    return (localDay, localTotalMin ~/ 60);
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
          : SingleChildScrollView(
              child: Column(
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

                const Text(
                  'FAMILY PUSH (THIS DEVICE)',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.5,
                    color: AppTheme.stone500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'When others add tasks, lists, events, etc., we can notify the rest of the family. Quiet hours apply to these pushes.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
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
                      _notifSwitch('Chat', _notifPrefs.chat, (v) => _persistNotif(_notifPrefs.copyWith(chat: v))),
                      _notifSwitch('Tasks', _notifPrefs.tasks, (v) => _persistNotif(_notifPrefs.copyWith(tasks: v))),
                      _notifSwitch('Calendar', _notifPrefs.calendar, (v) => _persistNotif(_notifPrefs.copyWith(calendar: v))),
                      _notifSwitch('Chores', _notifPrefs.chores, (v) => _persistNotif(_notifPrefs.copyWith(chores: v))),
                      _notifSwitch('Lists', _notifPrefs.lists, (v) => _persistNotif(_notifPrefs.copyWith(lists: v))),
                      _notifSwitch('Polls', _notifPrefs.polls, (v) => _persistNotif(_notifPrefs.copyWith(polls: v))),
                      _notifSwitch('Meals', _notifPrefs.meals, (v) => _persistNotif(_notifPrefs.copyWith(meals: v))),
                      _notifSwitch('Occasions', _notifPrefs.birthdays, (v) => _persistNotif(_notifPrefs.copyWith(birthdays: v))),
                      _notifSwitch('Photos', _notifPrefs.photos, (v) => _persistNotif(_notifPrefs.copyWith(photos: v))),
                      _notifSwitch('Location', _notifPrefs.location, (v) => _persistNotif(_notifPrefs.copyWith(location: v))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Quiet hours (local time)',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppTheme.stone800,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: _notifPrefs.quietHoursStart,
                        decoration: const InputDecoration(
                          labelText: 'From hour',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Off')),
                          ...List.generate(24, (h) => DropdownMenuItem<int?>(value: h, child: Text('$h:00'))),
                        ],
                        onChanged: (v) => _persistNotif(_notifPrefs.copyWith(quietHoursStart: v)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: _notifPrefs.quietHoursEnd,
                        decoration: const InputDecoration(
                          labelText: 'Until hour',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Off')),
                          ...List.generate(24, (h) => DropdownMenuItem<int?>(value: h, child: Text('$h:00'))),
                        ],
                        onChanged: (v) => _persistNotif(_notifPrefs.copyWith(quietHoursEnd: v)),
                      ),
                    ),
                  ],
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

                const SizedBox(height: 8),
                const Text(
                  'DATA ON THIS DEVICE',
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
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.25)),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.delete_forever_rounded, color: AppTheme.error,
                        size: _resettingData ? 18 : 22),
                    title: const Text(
                      'Reset data',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppTheme.stone900,
                      ),
                    ),
                    subtitle: const Text(
                      'Sign out and erase local data (tasks, lists, family cache on this device)',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppTheme.stone500,
                      ),
                    ),
                    trailing: _resettingData
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded, color: AppTheme.stone400),
                    onTap: (_resettingData || _deletingCloudData)
                        ? null
                        : () => _confirmResetLocalData(context),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                Builder(builder: (ctx) {
                  final provider = ctx.watch<AppProvider>();
                  final fam = provider.activeFamily;
                  final user = provider.activeUser;
                  if (fam == null || user == null) return const SizedBox.shrink();
                  if (!SupabaseService.isConfigured) return const SizedBox.shrink();
                  if (fam.ownerId != user.id) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF450A0A).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.error.withValues(alpha: 0.35)),
                        ),
                        child: ListTile(
                          leading: Icon(
                            Icons.cloud_off_rounded,
                            color: AppTheme.error,
                            size: _deletingCloudData ? 18 : 22,
                          ),
                          title: const Text(
                            'Delete all data (cloud + device)',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppTheme.stone900,
                            ),
                          ),
                          subtitle: const Text(
                            'Permanently remove this home from the server for all members, then sign out',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppTheme.stone500,
                            ),
                          ),
                          trailing: _deletingCloudData
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.chevron_right_rounded, color: AppTheme.stone400),
                          onTap: (_resettingData || _deletingCloudData)
                              ? null
                              : () => _confirmDeleteCloudAndLocalData(context),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 16),

                // About section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'About',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'FamilyHub',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppTheme.stone900,
                        ),
                      ),
                      const Text(
                        'Version 1.0.0',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: AppTheme.stone500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => launchUrl(Uri.parse(AppConfig.privacyPolicyUrl), mode: LaunchMode.externalApplication),
                        child: const Row(
                          children: [
                            Icon(Icons.privacy_tip_outlined, size: 16, color: AppTheme.primary),
                            SizedBox(width: 6),
                            Text(
                              'Privacy Policy',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Delete Account section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Danger Zone',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                title: Row(children: [
                                  Container(
                                    width: 36, height: 36,
                                    decoration: BoxDecoration(
                                      color: AppTheme.error.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.warning_amber_rounded, size: 18, color: AppTheme.error),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text('Delete My Account', style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800)),
                                  ),
                                ]),
                                content: const Text(
                                  'This will permanently delete your account and remove you from all families. This cannot be undone.',
                                  style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppTheme.stone500)),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      Navigator.pop(context);
                                      final provider = context.read<AppProvider>();
                                      provider.deleteAccount().then((_) {
                                        if (context.mounted) {
                                          GoRouter.of(context).go('/');
                                        }
                                      });
                                    },
                                    child: const Text('Delete Account', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppTheme.error)),
                                  ),
                                ],
                              ),
                            );
                          },
                          icon: const Icon(Icons.delete_forever_rounded, size: 18),
                          label: const Text('Delete My Account'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: const BorderSide(color: AppTheme.error),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ],
              ),
            ),
    );
  }
}

/// Second step: user must type DELETE to confirm cloud wipe.
class _DeleteCloudDataDialog extends StatefulWidget {
  const _DeleteCloudDataDialog();

  @override
  State<_DeleteCloudDataDialog> createState() => _DeleteCloudDataDialogState();
}

class _DeleteCloudDataDialogState extends State<_DeleteCloudDataDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _ctrl.text.trim() == 'DELETE';
    return AlertDialog(
      title: const Text(
        'Type DELETE to confirm',
        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes your home in the cloud for everyone.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Type DELETE',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          child: const Text('Delete forever'),
        ),
      ],
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
  final Map<String, TextEditingController> _nameControllers = {};

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
      late final String initialName;
      if (m.displayName != null && m.displayName!.trim().isNotEmpty) {
        initialName = m.displayName!.trim();
      } else if (user != null && user.name.trim().isNotEmpty) {
        initialName = user.name.trim();
      } else {
        initialName = (user?.email != null && user!.email.isNotEmpty)
            ? user.email
            : m.userId;
      }
      _nameControllers[m.userId] ??= TextEditingController(text: initialName);
      return _EditableMember(
        userId: m.userId,
        familyId: m.familyId,
        role: m.role,
        householdRole: m.householdRole,
        moduleAccess: m.moduleAccess != null ? List<String>.from(m.moduleAccess!) : null,
        displayName: initialName,
        declaredUnder16: m.declaredUnder16,
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    super.dispose();
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
    final family = provider.activeFamily;
    final familyId = family?.id;
    if (familyId == null) return;

    for (final e in _members) {
      final trimmed =
          (_nameControllers[e.userId]?.text ?? e.displayName).trim();
      if (trimmed.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please enter a display name for every family member.',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }
    }

    // Build updated familyMembers list
    final updated = db.familyMembers.map((m) {
      if (m.familyId != familyId) return m;
      final edited = _members.where((e) => e.userId == m.userId).firstOrNull;
      if (edited == null) return m;
      final displayName =
          (_nameControllers[edited.userId]?.text ?? edited.displayName).trim();
      final ownerId = family!.ownerId;
      final resolvedRole = m.userId == ownerId
          ? Role.OWNER
          : (provider.isOwner ? edited.role : m.role);
      return m.copyWith(
        role: resolvedRole,
        moduleAccess: edited.moduleAccess,
        displayName: displayName,
        householdRole: edited.householdRole,
        declaredUnder16: edited.declaredUnder16,
      );
    }).toList();

    // Keep local User rows aligned for code paths that read user.name directly.
    final users = List<User>.from(db.users);
    for (final e in _members) {
      final displayName =
          (_nameControllers[e.userId]?.text ?? e.displayName).trim();
      final idx = users.indexWhere((u) => u.id == e.userId);
      if (idx >= 0) {
        users[idx] = users[idx].copyWith(name: displayName);
      } else {
        users.add(User(id: e.userId, name: displayName, email: ''));
      }
    }

    try {
      var nextDb = db.copyWith(familyMembers: updated, users: users);
      final actorId = provider.activeUser?.id ?? '';
      if (actorId.isNotEmpty) {
        for (final edited in _members) {
          final old = db.familyMembers.firstWhereOrNull(
            (x) => x.userId == edited.userId && x.familyId == familyId,
          );
          if (old == null) continue;
          final newName =
              (_nameControllers[edited.userId]?.text ?? edited.displayName).trim();
          if (old.displayName?.trim() != newName ||
              old.role != edited.role ||
              old.householdRole != edited.householdRole ||
              old.declaredUnder16 != edited.declaredUnder16) {
            nextDb = FamilyActivityService.append(
              nextDb,
              familyId: familyId,
              actorUserId: actorId,
              action: 'member_profile_updated',
              detail: newName,
              relatedUserId: edited.userId,
            );
          }
        }
      }

      await provider.saveAndSync(nextDb);
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

    var nextDb = db.copyWith(familyMembers: updatedMembers);
    final actorId = provider.activeUser?.id ?? '';
    if (actorId.isNotEmpty) {
      nextDb = FamilyActivityService.append(
        nextDb,
        familyId: m.familyId,
        actorUserId: actorId,
        action: 'member_removed',
        detail: m.displayName,
        relatedUserId: removedUserId,
      );
    }
    await provider.saveAndSync(nextDb);

    // Delete from cloud so the member doesn't return on next sync
    if (SupabaseService.isConfigured) {
      try {
        await SupabaseService.deleteRows('family_members', {
          'user_id': removedUserId,
          'family_id': m.familyId,
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
    final provider = context.watch<AppProvider>();
    final family = provider.activeFamily;
    final ownerId = family?.ownerId;
    final isFamilyOwner = provider.isOwner;
    final activeUid = provider.activeUser?.id;
    final m = _members[index];
    final canEditUnder16 =
        provider.isAdmin || (activeUid != null && m.userId == activeUid);
    final isExpanded = _expandedUserId == m.userId;
    final isKid = _isKidsPreset(m.moduleAccess);
    final isRestricted = m.moduleAccess != null;
    final isMemberOwner = ownerId != null && m.userId == ownerId;
    final nameController = _nameControllers[m.userId]!;

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
            leading: UserAvatarWidget(name: nameController.text, radius: 20),
            title: Text(
              nameController.text.isEmpty ? '…' : nameController.text,
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
                  if (provider.isAdmin) ...[
                    const Text(
                      'DISPLAY NAME',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 1.0,
                        color: AppTheme.stone400,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      onChanged: (v) => setState(() => m.displayName = v),
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Name shown to your family',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.stone200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.stone200),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        isDense: true,
                      ),
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (provider.isAdmin) ...[
                    const Text(
                      'HOUSEHOLD TYPE',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 1.0,
                        color: AppTheme.stone400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<HouseholdRole>(
                      segments: const [
                        ButtonSegment(
                          value: HouseholdRole.parent,
                          label: Text('Parent', style: TextStyle(fontFamily: 'Inter', fontSize: 11)),
                        ),
                        ButtonSegment(
                          value: HouseholdRole.teen,
                          label: Text('Teen', style: TextStyle(fontFamily: 'Inter', fontSize: 11)),
                        ),
                        ButtonSegment(
                          value: HouseholdRole.child,
                          label: Text('Child', style: TextStyle(fontFamily: 'Inter', fontSize: 11)),
                        ),
                        ButtonSegment(
                          value: HouseholdRole.other,
                          label: Text('Other', style: TextStyle(fontFamily: 'Inter', fontSize: 11)),
                        ),
                      ],
                      selected: {m.householdRole},
                      onSelectionChanged: (set) =>
                          setState(() => m.householdRole = set.first),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Used for presets and guidance (Kids Preset still controls module access).',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: AppTheme.stone500,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (canEditUnder16) ...[
                    const Text(
                      'AI FAMILY — UNDER 16',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 1.0,
                        color: AppTheme.stone400,
                      ),
                    ),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      value: m.declaredUnder16,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => m.declaredUnder16 = v);
                      },
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'This person is under 16',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.stone800,
                        ),
                      ),
                      subtitle: const Text(
                        'Tick for child pricing on AI Family. Parents can set this for children; the member can set it for their own account. This is a household declaration, not ID verification — false statements may breach app store terms.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: AppTheme.stone500,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ] else if (m.declaredUnder16) ...[
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Marked as under 16 (AI Family)',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.stone600,
                        ),
                      ),
                    ),
                  ],
                  if (isFamilyOwner && !isMemberOwner) ...[
                    const Text(
                      'ROLE',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 1.0,
                        color: AppTheme.stone400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<Role>(
                      segments: const [
                        ButtonSegment<Role>(
                          value: Role.MEMBER,
                          label: Text('Member', style: TextStyle(fontFamily: 'Inter', fontSize: 12)),
                        ),
                        ButtonSegment<Role>(
                          value: Role.ADMIN,
                          label: Text('Admin', style: TextStyle(fontFamily: 'Inter', fontSize: 12)),
                        ),
                      ],
                      selected: {
                        m.role == Role.ADMIN ? Role.ADMIN : Role.MEMBER,
                      },
                      onSelectionChanged: (set) {
                        final r = set.first;
                        setState(() => m.role = r);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Admins can manage members and module access. Only the family owner can change roles.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: AppTheme.stone500,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
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

class _ActivityLogSheet extends StatelessWidget {
  const _ActivityLogSheet();

  static String _actionLabel(String action) {
    switch (action) {
      case 'member_profile_updated':
        return 'Updated a member profile';
      case 'member_removed':
        return 'Removed a member';
      default:
        return action.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (ctx, p, _) {
        final fid = p.activeFamily?.id;
        final logs = fid == null
            ? <FamilyActivityLog>[]
            : (p.db.familyActivityLogs.where((e) => e.familyId == fid).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.stone200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Activity log',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: AppTheme.stone900,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Sensitive changes like member updates and removals. Add more events over time as you use the app.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: logs.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No entries yet.',
                            style: TextStyle(fontFamily: 'Inter', color: AppTheme.stone400),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = logs[i];
                          final who = p.displayNameForUserId(e.actorUserId);
                          final when = DateFormat('MMM d, h:mm a').format(e.createdAt);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            title: Text(
                              _actionLabel(e.action),
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '$who · $when${e.detail != null && e.detail!.isNotEmpty ? '\n${e.detail}' : ''}',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WellnessPulseSheet extends StatefulWidget {
  const _WellnessPulseSheet();

  @override
  State<_WellnessPulseSheet> createState() => _WellnessPulseSheetState();
}

class _WellnessPulseSheetState extends State<_WellnessPulseSheet> {
  String _mood = 'ok';
  final _note = TextEditingController();
  bool _saving = false;

  static const _moods = [
    ('great', '😄', 'Great'),
    ('good', '🙂', 'Good'),
    ('ok', '😐', 'OK'),
    ('low', '😔', 'Low'),
    ('rough', '😢', 'Rough'),
  ];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(AppProvider p) async {
    final fam = p.activeFamily;
    final uid = p.activeUser?.id;
    if (fam == null || uid == null) return;
    setState(() => _saving = true);
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final entry = WellnessCheckIn(
      id: const Uuid().v4(),
      familyId: fam.id,
      userId: uid,
      mood: _mood,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      day: day,
      createdAt: DateTime.now(),
    );
    final db = p.db;
    await p.saveAndSync(db.copyWith(wellnessCheckIns: [...db.wellnessCheckIns, entry]));
    if (mounted) {
      setState(() => _saving = false);
      _note.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — your check-in was saved'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (ctx, p, _) {
        final fid = p.activeFamily?.id;
        final recent = fid == null
            ? <WellnessCheckIn>[]
            : p.db.wellnessCheckIns
                .where((w) => w.familyId == fid)
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final last7 = recent.take(14).toList();

        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.stone200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Family pulse',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: AppTheme.stone900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'A light check-in for how you are doing today. Optional note is visible to your family.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _moods.map((m) {
                    final sel = _mood == m.$1;
                    return ChoiceChip(
                      label: Text('${m.$2} ${m.$3}', style: const TextStyle(fontFamily: 'Inter', fontSize: 12)),
                      selected: sel,
                      onSelected: (_) => setState(() => _mood = m.$1),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Optional note',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : () => _submit(p),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save check-in', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Recent',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.stone700,
                  ),
                ),
                const SizedBox(height: 8),
                if (last7.isEmpty)
                  const Text('No check-ins yet.', style: TextStyle(fontFamily: 'Inter', color: AppTheme.stone400))
                else
                  ...last7.map((w) {
                    final name = p.displayNameForUserId(w.userId);
                    final emoji = _moods.firstWhere((m) => m.$1 == w.mood, orElse: () => _moods[2]).$2;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text(emoji, style: const TextStyle(fontSize: 22)),
                      title: Text(name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${DateFormat('MMM d').format(w.day)} · ${w.note ?? w.mood}',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EditableMember {
  final String userId;
  final String familyId;
  Role role;
  HouseholdRole householdRole;
  List<String>? moduleAccess;
  String displayName;
  bool declaredUnder16;

  _EditableMember({
    required this.userId,
    required this.familyId,
    required this.role,
    required this.householdRole,
    this.moduleAccess,
    required this.displayName,
    this.declaredUnder16 = false,
  });
}

// ─────────────────────────────────────────────
// Theme option tile
// ─────────────────────────────────────────────

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: selected ? AppTheme.primary : AppTheme.stone500),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 14,
          color: selected ? AppTheme.primary : AppTheme.stone800,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 20)
          : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      dense: true,
      visualDensity: VisualDensity.compact,
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

// lib/screens/onboarding/welcome_module_tour_screen.dart
// Full-screen welcome + per-module overview after creating a home (module setup)
// or joining a home (family’s enabled modules).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import '../../config/module_config.dart';
import '../../config/theme.dart';
import '../../widgets/app_brand_mark.dart';

/// Prefs: set after module setup or join; dashboard opens this tour once.
const kPrefPendingWelcomeTour = 'pending_welcome_tour';
const kPrefPendingWelcomeTourPaths = 'pending_welcome_tour_paths';
const kPrefWalkthroughCompleted = 'walkthrough_completed';

/// Extra line under each module’s catalogue description.
const Map<String, String> _moduleTourHint = {
  '/chat': 'Share updates and react without leaving the family bubble.',
  '/tasks': 'Assign work, set due dates, and see what is done at a glance.',
  '/calendar': 'Keep school, sports, and trips on one shared timeline.',
  '/chores': 'Make routines visible so everyone knows what is theirs.',
  '/lists': 'Groceries, packing, and to-buys that stay in sync.',
  '/polls': 'Let the group vote: dinner, movie night, or next outing.',
  '/birthdays': 'Never miss a birthday, anniversary, or special date.',
  '/photos': 'Drop memories and milestones into a shared album.',
  '/location': 'Optional sharing so you know everyone is safe (and saved places).',
  '/health': 'Keep important health notes and contacts within reach.',
  '/habits': 'Build streaks for water, reading, or anything that matters.',
  '/meals': 'Plan the week, save recipes, and shop with confidence.',
  '/fitness': 'Log workouts and cheer each other on.',
  '/period-tracker': 'Track cycles privately with gentle reminders.',
  '/devotional': 'Start the day with a short, grounded reading.',
  '/prayer-wall': 'Share thanks and requests the family can see.',
  '/budget': 'See spending by category and stay on the same page.',
  '/rewards': 'Turn completed chores into points and real rewards.',
};

const List<Color> _accentColors = [
  Color(0xFF6366F1),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
  Color(0xFF06B6D4),
];

/// Normalizes module keys to the form stored in module pickers (no leading `/`).
List<String> normalizeModuleKeysForTour(Iterable<String> raw) {
  return raw
      .map((k) => k.trim())
      .map((k) => k.startsWith('/') ? k.substring(1) : k)
      .where((k) => k.isNotEmpty)
      .toList();
}

Future<void> markWelcomeTourPending(List<String> moduleKeys) async {
  final normalized = normalizeModuleKeysForTour(moduleKeys);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kPrefPendingWelcomeTour, true);
  await prefs.setString(
    kPrefPendingWelcomeTourPaths,
    normalized.join(','),
  );
}

Future<void> clearWelcomeTourPendingAndMarkCompleted() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kPrefWalkthroughCompleted, true);
  await prefs.setBool(kPrefPendingWelcomeTour, false);
  await prefs.remove(kPrefPendingWelcomeTourPaths);
}

class WelcomeModuleTourScreen extends StatefulWidget {
  final List<ModuleInfo> modules;
  final VoidCallback onComplete;

  const WelcomeModuleTourScreen({
    super.key,
    required this.modules,
    required this.onComplete,
  });

  @override
  State<WelcomeModuleTourScreen> createState() => _WelcomeModuleTourScreenState();
}

class _WelcomeModuleTourScreenState extends State<WelcomeModuleTourScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  int get _totalPages => 1 + widget.modules.length;

  Future<void> _finish() async {
    await clearWelcomeTourPendingAndMarkCompleted();
    if (mounted) widget.onComplete();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Color _accent(int i) => _accentColors[i % _accentColors.length];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFEEF2FF),
              Color(0xFFFAFAF9),
              Color(0xFFFFF7ED),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                child: Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _finish,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.stone500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _totalPages,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    if (i == 0) return _buildWelcomePage();
                    return _buildModulePage(widget.modules[i - 1], i - 1);
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomInset),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_page + 1) / _totalPages,
                        minHeight: 4,
                        backgroundColor: AppTheme.stone200,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_totalPages, (i) {
                        final active = i == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active ? AppTheme.primary : AppTheme.stone300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          if (_page < _totalPages - 1) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 380),
                              curve: Curves.easeOutCubic,
                            );
                          } else {
                            _finish();
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _page < _totalPages - 1 ? 'Next' : 'Get started',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 112,
                height: 112,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 112,
                  height: 112,
                  color: AppTheme.primaryLight,
                  alignment: Alignment.center,
                  child: const AppBrandMark(size: 80, borderRadius: BorderRadius.all(Radius.circular(20))),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'Welcome to ${AppConfig.appName}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 36,
              fontWeight: FontWeight.w900,
              height: 1.05,
              letterSpacing: -0.5,
              color: AppTheme.stone900,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppConfig.appDescription,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w500,
              height: 1.45,
              color: AppTheme.stone600,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.stone100),
            ),
            child: Row(
              children: [
                Icon(Icons.swipe_rounded, color: AppTheme.primary, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Swipe or tap Next for a quick tour of each area in your family space.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      height: 1.4,
                      color: AppTheme.stone600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildModulePage(ModuleInfo m, int index) {
    final accent = _accent(index);
    final hint = _moduleTourHint[m.path] ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.12),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.2),
                  blurRadius: 48,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              m.emoji,
              style: const TextStyle(fontSize: 96),
            ),
          ),
          const SizedBox(height: 36),
          Text(
            m.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -0.4,
              color: AppTheme.stone900,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            m.desc,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              fontWeight: FontWeight.w500,
              height: 1.45,
              color: AppTheme.stone600,
            ),
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                height: 1.5,
                color: AppTheme.stone500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

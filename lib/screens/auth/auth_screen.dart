// lib/screens/auth/auth_screen.dart
// Authentication and onboarding flow for FamilyHub

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../config/theme.dart';
import '../../config/module_config.dart';
import '../../config/app_config.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/database_service.dart';

// ─── Auth view enum ───────────────────────────────────────────────────────────

enum _AuthView {
  login,
  signup,
  forgotPassword,
  resetPassword,
  onboarding,
  createFamily,
  joinFamily,
  moduleSetup,
}

// ─── Country data ─────────────────────────────────────────────────────────────

class _Country {
  final String flag;
  final String name;
  final String code;
  const _Country(this.flag, this.name, this.code);
}

const List<_Country> _countries = [
  _Country('🇺🇸', 'United States', 'US'),
  _Country('🇦🇺', 'Australia', 'AU'),
  _Country('🇬🇧', 'United Kingdom', 'GB'),
  _Country('🇨🇦', 'Canada', 'CA'),
  _Country('🇳🇿', 'New Zealand', 'NZ'),
  _Country('🇩🇪', 'Germany', 'DE'),
  _Country('🇫🇷', 'France', 'FR'),
  _Country('🇯🇵', 'Japan', 'JP'),
  _Country('🇮🇳', 'India', 'IN'),
  _Country('🇧🇷', 'Brazil', 'BR'),
  _Country('🇲🇽', 'Mexico', 'MX'),
  _Country('🇿🇦', 'South Africa', 'ZA'),
];

// ─── AuthScreen ───────────────────────────────────────────────────────────────

class AuthScreen extends StatefulWidget {
  final bool showResetPassword;
  const AuthScreen({super.key, this.showResetPassword = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _AuthView _view = _AuthView.login;

  // Controllers
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _familyNameCtrl = TextEditingController();
  final _joinCodeCtrl = TextEditingController();

  // Form keys
  final _loginKey = GlobalKey<FormState>();
  final _signupKey = GlobalKey<FormState>();
  final _forgotKey = GlobalKey<FormState>();
  final _resetPasswordKey = GlobalKey<FormState>();
  final _familyNameKey = GlobalKey<FormState>();
  final _joinCodeKey = GlobalKey<FormState>();

  // UI state
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;
  bool _resetSent = false;
  bool _passwordUpdated = false;
  bool _staySignedIn = true;

  @override
  void initState() {
    super.initState();
    if (widget.showResetPassword) {
      _view = _AuthView.resetPassword;
    }
    _loadStaySignedIn();
    _passwordCtrl.addListener(() => setState(() {}));
  }

  Future<void> _loadStaySignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _staySignedIn = prefs.getBool('stay_signed_in') ?? true);
  }

  Future<void> _saveStaySignedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('stay_signed_in', value);
    setState(() => _staySignedIn = value);
  }

  // Pending data accumulated across steps
  User? _pendingUser;
  Family? _pendingFamily;

  // Module setup
  String _selectedCountry = 'US';
  final Set<String> _selectedModules = {
    for (final p in essentialModules) p.replaceFirst('/', ''),
  };

  // ─── Supabase check ────────────────────────────────────────────────────────

  bool get _supabaseConfigured {
    try {
      // Accessing .client throws if not initialized
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _familyNameCtrl.dispose();
    _joinCodeCtrl.dispose();
    super.dispose();
  }

  // ─── State helpers ─────────────────────────────────────────────────────────

  void _setView(_AuthView v) => setState(() {
        _view = v;
        _error = null;
      });

  void _setLoading(bool v) => setState(() => _loading = v);
  void _setError(String? e) => setState(() => _error = e);

  // ─── Auth actions ──────────────────────────────────────────────────────────

  Future<void> _login() async {
    if (!(_loginKey.currentState?.validate() ?? false)) return;
    _setLoading(true);
    _setError(null);
    try {
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text;
      final provider = context.read<AppProvider>();

      User? user;
      Family? family;

      if (_supabaseConfigured) {
        final res = await Supabase.instance.client.auth
            .signInWithPassword(email: email, password: password);
        if (res.user == null) throw Exception('Login failed. Check your credentials.');
        final su = res.user!;
        user = User(
          id: su.id,
          name: su.userMetadata?['name'] as String? ??
              email.split('@').first,
          email: email,
          createdAt: DateTime.now(),
        );
      }

      // Fall back: look up in local DB
      user ??= provider.db.users.where((u) => u.email == email).firstOrNull;

      if (user == null) {
        _setError('No account found with that email. Please sign up.');
        return;
      }

      // Resolve family membership — try local first
      var membership = provider.db.familyMembers
          .cast<FamilyMember?>()
          .firstWhere((m) => m?.userId == user!.id, orElse: () => null);
      if (membership != null) {
        family = provider.db.families
            .cast<Family?>()
            .firstWhere((f) => f?.id == membership!.familyId,
                orElse: () => null);
      }

      // If no family found locally, try fetching from Supabase cloud
      if (family == null && _supabaseConfigured) {
        try {
          // Look up the user's family membership from cloud
          final memberships = await Supabase.instance.client
              .from('family_members')
              .select()
              .eq('user_id', user.id);
          if (memberships is List && memberships.isNotEmpty) {
            final cloudMembership = memberships.first as Map<String, dynamic>;
            final familyId = cloudMembership['family_id'] as String?;
            if (familyId != null) {
              // Fetch all cloud data for this family and merge
              final db = await DatabaseService.reconcileCloud(provider.db, familyId);
              provider.setDb(db);

              // Now resolve from the merged DB
              membership = db.familyMembers
                  .cast<FamilyMember?>()
                  .firstWhere((m) => m?.userId == user!.id, orElse: () => null);
              if (membership != null) {
                family = db.families
                    .cast<Family?>()
                    .firstWhere((f) => f?.id == membership!.familyId,
                        orElse: () => null);
              }
            }
          }
        } catch (e) {
          debugPrint('[Auth] Cloud family lookup failed: $e');
        }
      }

      if (family == null) {
        _pendingUser = user;
        _setView(_AuthView.onboarding);
      } else {
        provider.authenticate(user, family);
        if (mounted) context.go('/');
      }
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _signup() async {
    if (!(_signupKey.currentState?.validate() ?? false)) return;
    _setLoading(true);
    _setError(null);
    try {
      final name = _nameCtrl.text.trim();
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text;
      const uuid = Uuid();

      User user;

      if (_supabaseConfigured) {
        final res = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {'name': name},
        );
        if (res.user == null) throw Exception('Sign up failed. Please try again.');
        user = User(
          id: res.user!.id,
          name: name,
          email: email,
          createdAt: DateTime.now(),
        );
      } else {
        user = User(
          id: uuid.v4(),
          name: name,
          email: email,
          createdAt: DateTime.now(),
        );
      }

      _pendingUser = user;
      _setView(_AuthView.onboarding);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _sendResetLink() async {
    if (!(_forgotKey.currentState?.validate() ?? false)) return;
    _setLoading(true);
    _setError(null);
    try {
      if (_supabaseConfigured) {
        await Supabase.instance.client.auth.resetPasswordForEmail(
          _emailCtrl.text.trim(),
          redirectTo: AppConfig.passwordResetRedirect,
        );
      }
      setState(() => _resetSent = true);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _createFamily() async {
    if (!(_familyNameKey.currentState?.validate() ?? false)) return;
    _setLoading(true);
    _setError(null);
    try {
      const uuid = Uuid();
      final joinCode = uuid.v4().substring(0, 6).toUpperCase();
      final user = _pendingUser!;
      final family = Family(
        id: uuid.v4(),
        name: _familyNameCtrl.text.trim(),
        joinCode: joinCode,
        ownerId: user.id,
        enabledModules: const [],
        createdAt: DateTime.now(),
        trialStartDate: DateTime.now(),
      );
      _pendingFamily = family;
      _setView(_AuthView.moduleSetup);
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _joinFamily() async {
    if (!(_joinCodeKey.currentState?.validate() ?? false)) return;
    _setLoading(true);
    _setError(null);
    try {
      final code = _joinCodeCtrl.text.trim().toUpperCase();
      final provider = context.read<AppProvider>();
      final user = _pendingUser!;

      // Try local first
      Family? family = provider.db.families
          .cast<Family?>()
          .firstWhere((f) => f?.joinCode == code, orElse: () => null);

      // If not found locally, try cloud lookup
      if (family == null && _supabaseConfigured) {
        try {
          final result =
              await Supabase.instance.client.rpc(
            'find_family_by_join_code',
            params: {'code': code},
          );
          if (result != null && (result as List).isNotEmpty) {
            final data = result[0] as Map<String, dynamic>;
            final familyId = data['id'] as String;
            // Reconcile cloud data for this family
            final db =
                await DatabaseService.reconcileCloud(provider.db, familyId);
            provider.setDb(db);
            family = db.families
                .cast<Family?>()
                .firstWhere((f) => f?.id == familyId, orElse: () => null);
          }
        } catch (e) {
          debugPrint('[Auth] Cloud join code lookup failed: $e');
        }
      }

      if (family == null) {
        _setError('No home found with that code. Check and try again.');
        return;
      }

      // Create membership linking user to family
      final membership = FamilyMember(
        userId: user.id,
        familyId: family.id,
        role: Role.MEMBER,
        displayName: user.name,
      );

      // Add user and membership to DB, then persist + sync
      final db = provider.db.copyWith(
        users: [...provider.db.users, user],
        familyMembers: [...provider.db.familyMembers, membership],
      );
      provider.setDb(db);
      provider.authenticate(user, family);
      await DatabaseService.saveAndSync(db, family.id);

      if (mounted) context.go('/');
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _finishModuleSetup() async {
    _setLoading(true);
    _setError(null);
    try {
      final provider = context.read<AppProvider>();
      final user = _pendingUser!;
      final family = _pendingFamily!.copyWith(
        enabledModules: _selectedModules.toList(),
      );

      // Create the membership linking user to family
      final membership = FamilyMember(
        userId: user.id,
        familyId: family.id,
        role: Role.OWNER,
        displayName: user.name,
      );

      // Build DB with the new records and persist + sync
      final db = provider.db.copyWith(
        users: [...provider.db.users, user],
        families: [...provider.db.families, family],
        familyMembers: [...provider.db.familyMembers, membership],
      );
      provider.setDb(db);
      provider.authenticate(user, family);
      await DatabaseService.saveAndSync(db, family.id);

      if (mounted) context.go('/');
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _oauthSignIn(String providerName) async {
    if (!_supabaseConfigured) return;
    _setLoading(true);
    _setError(null);
    try {
      final OAuthProvider p;
      switch (providerName) {
        case 'google':
          p = OAuthProvider.google;
          break;
        case 'apple':
          p = OAuthProvider.apple;
          break;
        default:
          p = OAuthProvider.azure;
      }
      await Supabase.instance.client.auth.signInWithOAuth(
        p,
        redirectTo: AppConfig.oauthRedirectScheme,
      );
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      _setLoading(false);
    }
  }

  // ─── Validators ────────────────────────────────────────────────────────────

  String? _requiredValidator(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _passwordValidator(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCFCF9),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 32),
                child: _buildCard(),
              ),
            ),
          ),
          if (_loading)
            Container(
              color: Colors.black.withValues(alpha: 0.25),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppTheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome,
              color: Colors.white, size: 34),
        ),
        const SizedBox(height: 12),
        const Text(
          'FamilyHub',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppTheme.stone900,
          ),
        ),
      ],
    );
  }

  Widget _buildCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 440),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.stone100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey(_view),
          child: _buildCurrentView(),
        ),
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_view) {
      case _AuthView.login:
        return _buildLogin();
      case _AuthView.signup:
        return _buildSignup();
      case _AuthView.forgotPassword:
        return _buildForgotPassword();
      case _AuthView.resetPassword:
        return _buildResetPassword();
      case _AuthView.onboarding:
        return _buildOnboarding();
      case _AuthView.createFamily:
        return _buildCreateFamily();
      case _AuthView.joinFamily:
        return _buildJoinFamily();
      case _AuthView.moduleSetup:
        return _buildModuleSetup();
    }
  }

  // ─── Login view ────────────────────────────────────────────────────────────

  Widget _buildLogin() {
    return Form(
      key: _loginKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 14),
                const Text(
                  'FamilyHub',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.stone900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Welcome back.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: AppTheme.stone500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _emailField(),
          const SizedBox(height: 12),
          _passwordField(),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                height: 24,
                width: 24,
                child: Checkbox(
                  value: _staySignedIn,
                  onChanged: (v) => _saveStaySignedIn(v ?? true),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _saveStaySignedIn(!_staySignedIn),
                child: const Text('Stay signed in',
                    style: TextStyle(fontSize: 13, fontFamily: 'Inter', color: AppTheme.stone600)),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  _resetSent = false;
                  _setView(_AuthView.forgotPassword);
                },
                child: const Text('Forgot password?',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          if (_error != null) _errorBanner(_error!),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _login,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Sign In'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 18),
              ],
            ),
          ),
          if (_supabaseConfigured) ...[
            const SizedBox(height: 20),
            _divider(),
            const SizedBox(height: 16),
            _oauthButtons(),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Don't have an account?",
                  style: TextStyle(
                      color: AppTheme.stone500,
                      fontSize: 13,
                      fontFamily: 'Inter')),
              TextButton(
                onPressed: () => _setView(_AuthView.signup),
                child: const Text('Sign Up'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Signup view ───────────────────────────────────────────────────────────

  Widget _buildSignup() {
    return Form(
      key: _signupKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Create your account.'),
          const SizedBox(height: 6),
          _subtitle('Join your family hub today'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _nameCtrl,
            validator: _requiredValidator,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          _emailField(),
          const SizedBox(height: 12),
          _passwordField(isNewPassword: true),
          const SizedBox(height: 6),
          _PasswordStrengthBar(password: _passwordCtrl.text),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _errorBanner(_error!),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _signup,
            child: const Text('Create Account'),
          ),
          if (_supabaseConfigured) ...[
            const SizedBox(height: 20),
            _divider(),
            const SizedBox(height: 16),
            _oauthButtons(),
          ],
          const SizedBox(height: 12),
          Text(
            'By creating an account, you agree to our Terms of Service and Privacy Policy.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'Inter',
              color: AppTheme.stone400,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Already have an account?',
                  style: TextStyle(
                      color: AppTheme.stone500,
                      fontSize: 13,
                      fontFamily: 'Inter')),
              TextButton(
                onPressed: () => _setView(_AuthView.login),
                child: const Text('Sign In'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Forgot password view ──────────────────────────────────────────────────

  Widget _buildForgotPassword() {
    if (_resetSent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Center(
            child: Icon(Icons.mark_email_read_outlined,
                size: 60, color: AppTheme.success),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Check your inbox'),
          const SizedBox(height: 8),
          _subtitle(
              'We sent a password reset link to ${_emailCtrl.text.trim()}'),
          const SizedBox(height: 28),
          OutlinedButton(
            onPressed: () => _setView(_AuthView.login),
            child: const Text('Back to Sign In'),
          ),
        ],
      );
    }

    return Form(
      key: _forgotKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _backButton(() => _setView(_AuthView.login)),
          _sectionTitle('Reset your password'),
          const SizedBox(height: 6),
          _subtitle("We'll send a reset link to your email"),
          const SizedBox(height: 24),
          _emailField(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _errorBanner(_error!),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _sendResetLink,
            child: const Text('Send Reset Link'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _setView(_AuthView.login),
            child: const Text('Back to Sign In'),
          ),
        ],
      ),
    );
  }

  // ─── Reset password view (set new password) ─────────────────────────────

  Future<void> _updatePassword() async {
    if (!(_resetPasswordKey.currentState?.validate() ?? false)) return;
    _setLoading(true);
    _setError(null);
    try {
      if (_supabaseConfigured) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: _passwordCtrl.text),
        );
      }
      setState(() => _passwordUpdated = true);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      _setLoading(false);
    }
  }

  Widget _buildResetPassword() {
    if (_passwordUpdated) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Center(
            child: Icon(Icons.check_circle_outline,
                size: 60, color: AppTheme.success),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Password updated'),
          const SizedBox(height: 8),
          _subtitle('Your password has been changed successfully.'),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: () {
              _passwordUpdated = false;
              _passwordCtrl.clear();
              _confirmPasswordCtrl.clear();
              // Sign out the recovery session so user can log in fresh
              if (_supabaseConfigured) {
                Supabase.instance.client.auth.signOut();
              }
              context.go('/auth');
            },
            child: const Text('Sign In'),
          ),
        ],
      );
    }

    return Form(
      key: _resetPasswordKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Set new password'),
          const SizedBox(height: 6),
          _subtitle('Enter your new password below'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _passwordCtrl,
            validator: _passwordValidator,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              hintText: 'New password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmPasswordCtrl,
            obscureText: _obscureConfirmPassword,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please confirm your password';
              if (v != _passwordCtrl.text) return 'Passwords do not match';
              return null;
            },
            decoration: InputDecoration(
              hintText: 'Confirm new password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _errorBanner(_error!),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _updatePassword,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Update Password'),
          ),
        ],
      ),
    );
  }

  // ─── Onboarding view ──────────────────────────────────────────────────────

  Widget _buildOnboarding() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Set up your home.'),
        const SizedBox(height: 6),
        _subtitle('Create or join a family space'),
        const SizedBox(height: 28),
        _onboardingOptionCard(
          icon: Icons.home_outlined,
          title: AppConfig.createHubLabel,
          subtitle: AppConfig.createHubSubLabel,
          color: AppTheme.primary,
          onTap: () => _setView(_AuthView.createFamily),
        ),
        const SizedBox(height: 12),
        _onboardingOptionCard(
          icon: Icons.group_add_outlined,
          title: AppConfig.joinHubLabel,
          subtitle: AppConfig.joinHubSubLabel,
          color: const Color(0xFF8B5CF6),
          onTap: () => _setView(_AuthView.joinFamily),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorBanner(_error!),
        ],
      ],
    );
  }

  Widget _onboardingOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppTheme.stone900)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppTheme.stone500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }

  // ─── Create family view ───────────────────────────────────────────────────

  Widget _buildCreateFamily() {
    return Form(
      key: _familyNameKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _backButton(() => _setView(_AuthView.onboarding)),
          _sectionTitle('Name your home'),
          const SizedBox(height: 6),
          _subtitle('Give your family space a friendly name'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _familyNameCtrl,
            validator: _requiredValidator,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Home name',
              hintText: AppConfig.familyNamePlaceholder,
              prefixIcon: const Icon(Icons.home_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _errorBanner(_error!),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _createFamily,
            child: const Text('Create Home'),
          ),
        ],
      ),
    );
  }

  // ─── Join family view ─────────────────────────────────────────────────────

  Widget _buildJoinFamily() {
    return Form(
      key: _joinCodeKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _backButton(() => _setView(_AuthView.onboarding)),
          _sectionTitle('Join a home'),
          const SizedBox(height: 6),
          _subtitle('Enter the 6-character invite code'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _joinCodeCtrl,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Please enter the invite code';
              }
              if (v.trim().length != 6) {
                return 'Code must be exactly 6 characters';
              }
              return null;
            },
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Invite code',
              hintText: 'ABC123',
              prefixIcon: Icon(Icons.vpn_key_outlined),
              counterText: '',
            ),
            style: const TextStyle(
              letterSpacing: 8,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              fontFamily: 'Inter',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _errorBanner(_error!),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _joinFamily,
            child: const Text('Join Home'),
          ),
        ],
      ),
    );
  }

  // ─── Module setup view ────────────────────────────────────────────────────

  Widget _buildModuleSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Choose your modules'),
        const SizedBox(height: 6),
        _subtitle('Pick the features your family needs'),
        const SizedBox(height: 20),

        // Country selector
        _sectionLabel('Your country'),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _countries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final c = _countries[i];
              final selected = _selectedCountry == c.code;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedCountry = c.code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : AppTheme.stone100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? AppTheme.primary
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    '${c.flag}  ${c.name}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.stone600,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),

        // Quick select row
        _sectionLabel('Quick select'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _selectedModules
                    ..clear()
                    ..addAll(essentialModules
                        .map((p) => p.replaceFirst('/', '')));
                }),
                style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 10)),
                child: const Text('Essentials',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _selectedModules
                    ..clear()
                    ..addAll(allModulePaths
                        .map((p) => p.replaceFirst('/', '')));
                }),
                style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 10)),
                child: const Text('Everything',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Module groups grid
        for (final group in moduleGroups) ...[
          _sectionLabel(group.label),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.8,
            ),
            itemCount: group.modules.length,
            itemBuilder: (ctx, i) {
              final mod = group.modules[i];
              final key = mod.path.replaceFirst('/', '');
              final selected = _selectedModules.contains(key);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _selectedModules.remove(key);
                  } else {
                    _selectedModules.add(key);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primary.withValues(alpha: 0.08)
                        : AppTheme.stone50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.stone200,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Text(mod.emoji,
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          mod.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.stone700,
                            fontFamily: 'Inter',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selected)
                        const Icon(Icons.check_circle,
                            size: 16, color: AppTheme.primary),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],

        if (_error != null) _errorBanner(_error!),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed:
              _selectedModules.isEmpty ? null : _finishModuleSetup,
          child: const Text("Let's go!"),
        ),
      ],
    );
  }

  // ─── Shared building blocks ────────────────────────────────────────────────

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppTheme.stone900,
        ),
      );

  Widget _subtitle(String text) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AppTheme.stone500,
        ),
      );

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppTheme.stone400,
          letterSpacing: 1.2,
          fontFamily: 'Inter',
        ),
      );

  Widget _emailField() => TextFormField(
        controller: _emailCtrl,
        validator: _emailValidator,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          hintText: 'Email Address',
          prefixIcon: Icon(Icons.email_outlined),
        ),
      );

  Widget _passwordField({bool isNewPassword = false}) => TextFormField(
        controller: _passwordCtrl,
        validator: _passwordValidator,
        obscureText: _obscurePassword,
        autofillHints: [isNewPassword ? AutofillHints.newPassword : AutofillHints.password],
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: 'Password',
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
      );

  Widget _divider() => Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'or continue with',
              style: const TextStyle(
                color: AppTheme.stone400,
                fontSize: 12,
                fontFamily: 'Inter',
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      );

  Widget _oauthButtons() {
    final isApplePlatform = !kIsWeb && Platform.isIOS;
    final buttons = <Widget>[
      if (isApplePlatform) ...[
        _oauthBtn(
          label: 'Continue with Apple',
          leading: const Icon(Icons.apple, size: 20, color: AppTheme.stone800),
          onTap: () => _oauthSignIn('apple'),
        ),
        const SizedBox(height: 8),
      ],
      _oauthBtn(
        label: 'Continue with Google',
        leading: _googleIcon(),
        onTap: () => _oauthSignIn('google'),
      ),
      if (!isApplePlatform) ...[
        const SizedBox(height: 8),
        _oauthBtn(
          label: 'Continue with Apple',
          leading: const Icon(Icons.apple, size: 20, color: AppTheme.stone800),
          onTap: () => _oauthSignIn('apple'),
        ),
      ],
      const SizedBox(height: 8),
      _oauthBtn(
        label: 'Continue with Microsoft',
        leading: _microsoftIcon(),
        onTap: () => _oauthSignIn('microsoft'),
      ),
    ];
    return Column(children: buttons);
  }

  Widget _googleIcon() => SizedBox(
        width: 20,
        height: 20,
        child: CustomPaint(painter: _GoogleLogoPainter()),
      );

  Widget _microsoftIcon() => SizedBox(
        width: 20,
        height: 20,
        child: Row(
          children: [
            Column(
              children: [
                Container(width: 9, height: 9, color: const Color(0xFFF25022)),
                Container(width: 9, height: 9, color: const Color(0xFF00A4EF)),
              ],
            ),
            const SizedBox(width: 2),
            Column(
              children: [
                Container(width: 9, height: 9, color: const Color(0xFF7FBA00)),
                Container(width: 9, height: 9, color: const Color(0xFFFFB900)),
              ],
            ),
          ],
        ),
      );

  Widget _oauthBtn({
    required String label,
    required Widget leading,
    required VoidCallback onTap,
  }) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          alignment: Alignment.centerLeft,
          side: const BorderSide(color: AppTheme.stone200),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.stone800)),
          ],
        ),
      );

  Widget _errorBanner(String message) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.error.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                size: 16, color: AppTheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppTheme.error,
                  fontSize: 13,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ),
      );

  Widget _backButton(VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: GestureDetector(
          onTap: onTap,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_ios,
                  size: 15, color: AppTheme.stone500),
              SizedBox(width: 4),
              Text('Back',
                  style: TextStyle(
                    color: AppTheme.stone500,
                    fontSize: 13,
                    fontFamily: 'Inter',
                  )),
            ],
          ),
        ),
      );
}

// ─── Google Logo Painter ──────────────────────────────────────────────────────

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()..style = PaintingStyle.fill;

    // Blue segment
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s / 2, s / 2), radius: s / 2),
      -0.52, 1.04, true, paint,
    );
    // Red segment
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s / 2, s / 2), radius: s / 2),
      -2.62, 1.57, true, paint,
    );
    // Yellow segment
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s / 2, s / 2), radius: s / 2),
      2.09, 0.53, true, paint,
    );
    // Green segment
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s / 2, s / 2), radius: s / 2),
      0.52, 1.57, true, paint,
    );
    // White center circle
    paint.color = Colors.white;
    canvas.drawCircle(Offset(s / 2, s / 2), s * 0.35, paint);
    // Blue bar (right side)
    paint.color = const Color(0xFF4285F4);
    canvas.drawRect(Rect.fromLTWH(s / 2, s * 0.35, s / 2, s * 0.3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Password Strength Indicator ────────────────────────────────────────────

class _PasswordStrengthBar extends StatelessWidget {
  final String password;
  const _PasswordStrengthBar({required this.password});

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final strength = _calculateStrength(password);
    final label = strength <= 1 ? 'Weak' : strength == 2 ? 'Fair' : strength == 3 ? 'Good' : 'Strong';
    final color = strength <= 1 ? AppTheme.error : strength == 2 ? const Color(0xFFF59E0B) : strength == 3 ? const Color(0xFF10B981) : AppTheme.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) => Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
              decoration: BoxDecoration(
                color: i < strength ? color : AppTheme.stone200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  static int _calculateStrength(String password) {
    int score = 0;
    if (password.length >= 6) score++;
    if (password.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password) || RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) score++;
    return score;
  }
}

// lib/widgets/biometric_lock.dart
// Biometric / PIN lock screen that wraps the app

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/theme.dart';

class BiometricLockScreen extends StatefulWidget {
  final Widget child;
  const BiometricLockScreen({super.key, required this.child});

  // ── Static helpers ────────────────────────────────────────────────────────
  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lobohub_biometric_enabled', enabled);
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('lobohub_biometric_enabled') ?? false;
  }

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen>
    with WidgetsBindingObserver {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  bool _unlocked = false;
  bool _biometricEnabled = false;
  bool _authFailed = false;
  bool _checking = true;

  // PIN entry state
  bool _showPinEntry = false;
  bool _isSettingPin = false; // true when creating a new PIN
  bool _biometricsAvailable = true;
  final TextEditingController _pinController = TextEditingController();
  String? _pinError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAndAuthenticate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pinController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock when app is resumed from background (if biometric is enabled)
    if (state == AppLifecycleState.resumed && _biometricEnabled && _unlocked) {
      // Only re-lock after being paused for a while (not for quick app switches)
      // For now, don't auto-re-lock to avoid annoying UX
    }
  }

  Future<void> _checkAndAuthenticate() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('lobohub_biometric_enabled') ?? false;

    if (!enabled) {
      setState(() {
        _biometricEnabled = false;
        _unlocked = true;
        _checking = false;
      });
      return;
    }

    setState(() {
      _biometricEnabled = true;
      _checking = false;
    });

    await _authenticate();
  }

  Future<void> _authenticate() async {
    setState(() {
      _authFailed = false;
      _showPinEntry = false;
      _pinError = null;
    });

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final availableBiometrics = await _localAuth.getAvailableBiometrics();

      // Check if actual biometrics (fingerprint/face) are enrolled
      final hasBiometrics = canCheck && availableBiometrics.isNotEmpty;

      if (hasBiometrics) {
        // Try biometric-first authentication (fingerprint / face)
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Unlock FamilyHub with your fingerprint or face',
          options: const AuthenticationOptions(
            biometricOnly: true, // Only allow fingerprint/face, not device PIN
            stickyAuth: true,
          ),
        );

        if (authenticated) {
          setState(() {
            _unlocked = true;
            _authFailed = false;
          });
          return;
        } else {
          // Biometric failed/cancelled → offer PIN fallback
          setState(() {
            _authFailed = true;
            _biometricsAvailable = true;
          });
          return;
        }
      }

      // No biometrics available → try device credentials (system PIN/pattern)
      if (isDeviceSupported) {
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Unlock FamilyHub',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
          ),
        );

        if (authenticated) {
          setState(() {
            _unlocked = true;
            _authFailed = false;
          });
          return;
        }
      }

      // Nothing worked → fall back to app PIN
      await _showPinFallback();
    } on PlatformException catch (e) {
      debugPrint('[BiometricLock] PlatformException: $e');
      // Platform doesn't support any auth → fall back to app PIN
      await _showPinFallback();
    }
  }

  Future<void> _showPinFallback() async {
    final storedPin = await _secureStorage.read(key: 'lobohub_pin');
    setState(() {
      _biometricsAvailable = false;
      _showPinEntry = true;
      _isSettingPin = storedPin == null;
    });
  }

  void _switchToPinEntry() async {
    final storedPin = await _secureStorage.read(key: 'lobohub_pin');
    setState(() {
      _showPinEntry = true;
      _authFailed = false;
      _isSettingPin = storedPin == null;
    });
  }

  Future<void> _verifyPin() async {
    final enteredPin = _pinController.text.trim();
    if (enteredPin.length < 4) {
      setState(() => _pinError = 'PIN must be 4 digits');
      return;
    }

    final storedPin = await _secureStorage.read(key: 'lobohub_pin');

    if (storedPin == null) {
      // No PIN stored — save this one as the new PIN
      await _secureStorage.write(key: 'lobohub_pin', value: enteredPin);
      setState(() {
        _unlocked = true;
        _pinError = null;
      });
      return;
    }

    if (enteredPin == storedPin) {
      setState(() {
        _unlocked = true;
        _pinError = null;
      });
    } else {
      setState(() {
        _pinError = 'Incorrect PIN. Try again.';
        _pinController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF6366F1),
          body: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    if (_unlocked) {
      return widget.child;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _LockScreen(
        authFailed: _authFailed,
        showPinEntry: _showPinEntry,
        isSettingPin: _isSettingPin,
        biometricsAvailable: _biometricsAvailable,
        pinController: _pinController,
        pinError: _pinError,
        onAuthenticate: _authenticate,
        onVerifyPin: _verifyPin,
        onPinChanged: (_) => setState(() => _pinError = null),
        onSwitchToPin: _switchToPinEntry,
      ),
    );
  }
}

// ── Lock Screen UI ────────────────────────────────────────────────────────────

class _LockScreen extends StatelessWidget {
  final bool authFailed;
  final bool showPinEntry;
  final bool isSettingPin;
  final bool biometricsAvailable;
  final TextEditingController pinController;
  final String? pinError;
  final VoidCallback onAuthenticate;
  final VoidCallback onVerifyPin;
  final ValueChanged<String> onPinChanged;
  final VoidCallback onSwitchToPin;

  const _LockScreen({
    required this.authFailed,
    required this.showPinEntry,
    required this.isSettingPin,
    required this.biometricsAvailable,
    required this.pinController,
    required this.pinError,
    required this.onAuthenticate,
    required this.onVerifyPin,
    required this.onPinChanged,
    required this.onSwitchToPin,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6366F1), // indigo
              Color(0xFF7C3AED), // purple
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🏠', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                const Text(
                  'FamilyHub',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  showPinEntry
                      ? (isSettingPin
                          ? 'Create a 4-digit PIN'
                          : 'Enter your PIN')
                      : 'Tap to unlock with biometrics',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 48),

                if (showPinEntry)
                  _PinEntryWidget(
                    controller: pinController,
                    error: pinError,
                    isSettingPin: isSettingPin,
                    onChanged: onPinChanged,
                    onSubmit: onVerifyPin,
                  )
                else ...[
                  GestureDetector(
                    onTap: onAuthenticate,
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.15),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.fingerprint,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (authFailed) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.4), width: 1),
                      ),
                      child: const Text(
                        'Biometric authentication failed. Try again or use PIN.',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 32),

                // Always show "Use PIN instead" when on biometric screen
                if (!showPinEntry)
                  TextButton(
                    onPressed: onSwitchToPin,
                    child: Text(
                      'Use PIN instead',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),

                // Show "Try biometrics" when on PIN screen and biometrics are available
                if (showPinEntry && biometricsAvailable)
                  TextButton(
                    onPressed: onAuthenticate,
                    child: Text(
                      'Use fingerprint / face instead',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white.withValues(alpha: 0.8),
                      ),
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

class _PinEntryWidget extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final bool isSettingPin;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  const _PinEntryWidget({
    required this.controller,
    required this.error,
    required this.isSettingPin,
    required this.onChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isSettingPin)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: const Text(
                'No PIN set yet. Enter a 4-digit PIN to use as your backup unlock method.',
                style: TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        SizedBox(
          width: 200,
          child: TextField(
            controller: controller,
            obscureText: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            onChanged: onChanged,
            onSubmitted: (_) => onSubmit(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              letterSpacing: 12,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '• • • •',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 32,
                letterSpacing: 12,
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 2),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white, width: 2),
              ),
              errorText: error,
              errorStyle: const TextStyle(color: Colors.orange),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.primary,
            padding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: Text(
            isSettingPin ? 'Set PIN & Unlock' : 'Unlock',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    );
  }
}

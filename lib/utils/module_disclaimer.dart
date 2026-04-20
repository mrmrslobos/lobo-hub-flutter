// lib/utils/module_disclaimer.dart
// One-time disclaimer dialogs for health-related modules.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Legacy global key (pre–per-user); removed when a user accepts the new scoped key.
String _legacyModuleDisclaimerKey(String moduleKey) =>
    'disclaimer_accepted_$moduleKey';

/// Per signed-in user so a new account on the same device sees disclaimers again.
String moduleDisclaimerPrefsKey(String moduleKey, String userId) =>
    'disclaimer_accepted_${moduleKey}_$userId';

// ── Dashboard medical disclaimer (same scoping story) ───────────────────────

/// Legacy: single `medical_disclaimer_accepted` flag for the whole device.
const legacyMedicalDisclaimerKey = 'medical_disclaimer_accepted';

String medicalDisclaimerPrefsKey(String userId) =>
    '${legacyMedicalDisclaimerKey}_$userId';

Future<bool> isMedicalDisclaimerAcceptedForUser(
  SharedPreferences prefs,
  String userId,
) async {
  return prefs.getBool(medicalDisclaimerPrefsKey(userId)) == true;
}

Future<void> setMedicalDisclaimerAcceptedForUser(
  SharedPreferences prefs,
  String userId,
) async {
  await prefs.setBool(medicalDisclaimerPrefsKey(userId), true);
  await prefs.remove(legacyMedicalDisclaimerKey);
}

/// Shows a one-time disclaimer dialog for a module ([userId] = current auth user).
/// Acceptance is stored per user so switching accounts does not skip the dialog.
Future<void> showModuleDisclaimer({
  required BuildContext context,
  required String userId,
  required String moduleKey,
  required String title,
  required IconData icon,
  required String body,
}) async {
  if (userId.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  final prefsKey = moduleDisclaimerPrefsKey(moduleKey, userId);
  if (prefs.getBool(prefsKey) == true) return;
  if (!context.mounted) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DisclaimerDialog(
      title: title,
      icon: icon,
      body: body,
      onAccepted: () async {
        await prefs.setBool(prefsKey, true);
        await prefs.remove(_legacyModuleDisclaimerKey(moduleKey));
        if (ctx.mounted) Navigator.pop(ctx);
      },
    ),
  );
}

class _DisclaimerDialog extends StatefulWidget {
  final String title;
  final IconData icon;
  final String body;
  final VoidCallback onAccepted;

  const _DisclaimerDialog({
    required this.title,
    required this.icon,
    required this.body,
    required this.onAccepted,
  });

  @override
  State<_DisclaimerDialog> createState() => _DisclaimerDialogState();
}

class _DisclaimerDialogState extends State<_DisclaimerDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(widget.icon, color: const Color(0xFFDC2626), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.title, style: const TextStyle(fontSize: 18)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.body,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() => _accepted = !_accepted),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _accepted,
                      onChanged: (v) => setState(() => _accepted = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'I understand and accept',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _accepted ? widget.onAccepted : null,
            child: const Text('OK'),
          ),
        ),
      ],
    );
  }
}

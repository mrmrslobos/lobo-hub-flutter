// lib/utils/module_disclaimer.dart
// One-time disclaimer dialogs for health-related modules.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows a one-time disclaimer dialog for a module. Once accepted,
/// it is stored in SharedPreferences and never shown again.
Future<void> showModuleDisclaimer({
  required BuildContext context,
  required String moduleKey,
  required String title,
  required IconData icon,
  required String body,
}) async {
  final prefsKey = 'disclaimer_accepted_$moduleKey';
  final prefs = await SharedPreferences.getInstance();
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

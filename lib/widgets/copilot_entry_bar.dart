import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/module_config.dart';
import '../config/theme.dart';
import 'ai_affordance.dart';
import 'family_copilot_panel.dart';

/// Fixed strip under the app bar: type a request or open copilot in a sheet (stay on module).
class CopilotEntryBar extends StatefulWidget {
  const CopilotEntryBar({
    super.key,
    required this.modulePath,
  });

  final String modulePath;

  @override
  State<CopilotEntryBar> createState() => _CopilotEntryBarState();
}

class _CopilotEntryBarState extends State<CopilotEntryBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final moduleName = screenTitleForModulePath(widget.modulePath);
    final hint = 'Ask Huddle about $moduleName…';

    return Material(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, right: 4),
              child: AiGlyph(size: 18, compact: true),
            ),
            Expanded(
              child: TextField(
                controller: _ctrl,
                textInputAction: TextInputAction.send,
                onSubmitted: (text) {
                  final t = text.trim();
                  if (t.isEmpty) {
                    showFamilyCopilotSheet(context, modulePath: widget.modulePath);
                    return;
                  }
                  _ctrl.clear();
                  showFamilyCopilotSheet(
                    context,
                    modulePath: widget.modulePath,
                    initialQuery: t,
                  );
                },
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.stone50,
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: AppTheme.stone500.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w400,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppTheme.stone200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppTheme.stone200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.65)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: kIsWeb ? 'Ask Huddle (voice in the app)' : 'Speak your request',
              child: IconButton.filledTonal(
                onPressed: () {
                  final t = _ctrl.text.trim();
                  _ctrl.clear();
                  if (t.isNotEmpty) {
                    showFamilyCopilotSheet(
                      context,
                      modulePath: widget.modulePath,
                      initialQuery: t,
                    );
                  } else {
                    showFamilyCopilotSheet(
                      context,
                      modulePath: widget.modulePath,
                      startDictation: true,
                    );
                  }
                },
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(10),
                ),
                icon: const Icon(Icons.mic_rounded, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/widgets/ai_refine_input.dart
// Reusable AI prompt input widget for FamilyHub

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/ai_service.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// AiRefineInput — embeddable chat-style input bar
// ─────────────────────────────────────────────────────────────────────────────

class AiRefineInput extends StatefulWidget {
  final String feature;
  final String placeholder;
  final String? systemPrompt;
  final void Function(String response) onResult;
  final bool showHistory;

  const AiRefineInput({
    super.key,
    required this.feature,
    required this.placeholder,
    this.systemPrompt,
    required this.onResult,
    this.showHistory = true,
  });

  @override
  State<AiRefineInput> createState() => _AiRefineInputState();
}

class _AiRefineInputState extends State<AiRefineInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() => _loading = true);

    try {
      final provider = context.read<AppProvider>();
      final familyId = provider.activeFamily?.id ?? '';

      // Prepend system prompt to the user prompt if provided
      final fullPrompt = widget.systemPrompt != null
          ? '${widget.systemPrompt}\n\n$text'
          : text;

      final response = await AiService.ask(
        prompt: fullPrompt,
        feature: widget.feature,
        familyId: familyId,
      );

      if (!mounted) return;

      if (response == null) {
        _showError('AI is unavailable right now. Please try again.');
        return;
      }

      // Save to AI history if requested
      if (widget.showHistory) {
        final user = provider.activeUser;
        final family = provider.activeFamily;
        if (user != null && family != null) {
          final entry = AIHistoryEntry(
            id: _uuid.v4(),
            familyId: family.id,
            userId: user.id,
            prompt: text,
            response: response,
            module: widget.feature,
            createdAt: DateTime.now(),
          );
          final updatedDb = provider.db.copyWith(
            aiHistory: [...provider.db.aiHistory, entry],
          );
          await provider.saveAndSync(updatedDb);
        }
      }

      _controller.clear();
      widget.onResult(response);
    } catch (e) {
      if (mounted) {
        _showError('Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.stone200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Sparkle prefix icon
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 12),
            child: Icon(
              Icons.auto_awesome,
              size: 20,
              color: AppTheme.primary.withOpacity(0.6),
            ),
          ),
          // Text field
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: widget.placeholder,
                hintStyle: TextStyle(color: AppTheme.stone400, fontSize: 15),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
              ),
            ),
          ),
          // Send button
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 6),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _loading
                  ? const SizedBox(
                      key: ValueKey('spinner'),
                      width: 40,
                      height: 40,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(AppTheme.primary),
                        ),
                      ),
                    )
                  : Material(
                      key: const ValueKey('send'),
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        onTap: _submit,
                        borderRadius: BorderRadius.circular(22),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// showAiInputSheet — bottom sheet wrapper
// ─────────────────────────────────────────────────────────────────────────────

Future<String?> showAiInputSheet(
  BuildContext context, {
  required String feature,
  required String placeholder,
  String? systemPrompt,
}) async {
  String? result;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      return _AiInputSheet(
        feature: feature,
        placeholder: placeholder,
        systemPrompt: systemPrompt,
        onResult: (response) {
          result = response;
          Navigator.of(sheetCtx).pop();
        },
      );
    },
  );

  return result;
}

class _AiInputSheet extends StatelessWidget {
  final String feature;
  final String placeholder;
  final String? systemPrompt;
  final void Function(String) onResult;

  const _AiInputSheet({
    required this.feature,
    required this.placeholder,
    required this.systemPrompt,
    required this.onResult,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.stone300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Ask AI',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.stone900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AiRefineInput(
            feature: feature,
            placeholder: placeholder,
            systemPrompt: systemPrompt,
            onResult: onResult,
            showHistory: true,
          ),
          const SizedBox(height: 8),
          Text(
            'Powered by AI — results may vary.',
            style: TextStyle(fontSize: 11, color: AppTheme.stone400),
          ),
        ],
      ),
    );
  }
}

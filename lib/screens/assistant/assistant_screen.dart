// lib/screens/assistant/assistant_screen.dart
// Family copilot — natural language actions across tasks, calendar, lists, meals.

import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../config/cloud_sync_scope.dart';
import '../../config/module_config.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../services/calendar_external_links.dart';
import '../../services/copilot_action_applier.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/ai_affordance.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/huddle_module_scaffold.dart';
import '../../widgets/subscription_modal.dart';

const _uuid = Uuid();

class _ChatTurn {
  final bool user;
  final String text;
  final List<dynamic>? pendingActions;
  final String? assistantReply;

  _ChatTurn.user(this.text)
      : user = true,
        pendingActions = null,
        assistantReply = null;

  _ChatTurn.assistant(this.assistantReply, this.pendingActions)
      : user = false,
        text = assistantReply ?? '';
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    this.initialQuery,
    this.fromPath,
    this.startDictation = false,
  });

  /// Pre-filled input (from module copilot strip or deep link).
  final String? initialQuery;

  /// Module path user came from (`/tasks`, `/`, etc.) for model context.
  final String? fromPath;

  /// Open mic after load (native only; web shows a hint).
  final bool startDictation;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  bool _loading = false;
  final List<_ChatTurn> _turns = [];
  List<dynamic>? _pendingActions;

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery;
    if (q != null && q.trim().isNotEmpty) {
      _ctrl.text = q.trim();
    }
    if (!kIsWeb) {
      _speech.initialize().then((ok) {
        if (!mounted) return;
        setState(() => _speechReady = ok);
        if (ok &&
            widget.startDictation &&
            (widget.initialQuery == null || widget.initialQuery!.trim().isEmpty)) {
          Future<void>.delayed(const Duration(milliseconds: 450), () {
            if (mounted) unawaited(_toggleListen());
          });
        }
      });
    } else if (widget.startDictation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice capture works best in the mobile app. Type your request here on web.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    if (_speech.isListening) {
      _speech.stop();
    }
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _buildContext(AppProvider provider) {
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) return '';
    final db = provider.db;
    final familyId = family.id;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tasksDue = db.tasks
        .where((t) => t.familyId == familyId && !t.completed && t.dueDate != null && _sameDay(t.dueDate!, today))
        .length;
    final upcoming = db.events
        .where((e) => e.familyId == familyId && !e.start.isBefore(today))
        .take(5)
        .map((e) => '${e.title} (${DateFormat.MMMd().format(e.start)})')
        .join('; ');
    var block =
        'Family: ${family.name}. Tasks due today: $tasksDue. Next events: $upcoming.';
    final from = widget.fromPath;
    if (from != null && from.isNotEmpty) {
      final title = screenTitleForModulePath(from);
      block += ' User opened copilot from: $title ($from).';
    }
    return block;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.copilot)) return;

    final provider = context.read<AppProvider>();
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) return;

    setState(() {
      _turns.add(_ChatTurn.user(text));
      _ctrl.clear();
      _loading = true;
      _pendingActions = null;
    });
    _scrollBottom();

    final ctx = _buildContext(provider);
    final decoded = await AiService.askCopilot(
      userMessage: text,
      familyId: family.id,
      contextBlock: ctx,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (decoded == null) {
      setState(() {
        _turns.add(_ChatTurn.assistant('Something went wrong. Try again.', null));
      });
      _scrollBottom();
      return;
    }

    final reply = decoded['reply']?.toString() ?? 'Here is what I can do.';
    final actions = decoded['actions'];
    final list = actions is List ? actions : <dynamic>[];

    setState(() {
      _pendingActions = list;
      _turns.add(_ChatTurn.assistant(reply, list.isNotEmpty ? List.from(list) : null));
    });
    _scrollBottom();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _applyPending() async {
    final actions = _pendingActions;
    if (actions == null || actions.isEmpty) return;

    final provider = context.read<AppProvider>();
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) return;

    setState(() => _loading = true);
    final result = CopilotActionApplier.apply(
      db: provider.db,
      familyId: family.id,
      userId: user.id,
      actions: actions,
    );

    final entry = AIHistory(
      id: _uuid.v4(),
      familyId: family.id,
      userId: user.id,
      prompt: 'Apply copilot actions',
      response: jsonEncode({'applied': result.appliedSummaries, 'errors': result.errors}),
      module: 'assistant',
      createdAt: DateTime.now(),
    );
    var db = result.db.copyWith(aiHistory: [...result.db.aiHistory, entry]);

    await provider.saveAndSync(db, pushTableScope: {
      ...result.pushTableScope,
      CloudSyncScope.aiHistory,
    });

    if (!mounted) return;
    setState(() {
      _loading = false;
      _pendingActions = null;
      final msg = result.appliedSummaries.isEmpty
          ? (result.errors.isNotEmpty ? result.errors.join('\n') : 'Nothing applied.')
          : 'Done: ${result.appliedSummaries.join(' · ')}';
      _turns.add(_ChatTurn.assistant(msg, null));
    });
    _scrollBottom();

    if (mounted && result.errors.isNotEmpty && result.appliedSummaries.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errors.join('; ')), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _toggleListen() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice capture works best in the mobile app. Type your request here on web.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_speechReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition is not available on this device.')),
      );
      return;
    }
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        if (r.finalResult) {
          _ctrl.text = r.recognizedWords;
          setState(() => _listening = false);
        }
      },
      listenMode: stt.ListenMode.dictation,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HuddleModuleScaffold(
      modulePath: '/assistant',
      showCopilotBar: false,
      drawer: const AppDrawer(),
      appBar: const MainAppBar(),
      child: Column(
        children: [
          PageHeader(
            title: screenTitleForModulePath('/assistant'),
            titlePrefix: const AiGlyph(size: 24),
            subtitle: 'Describe what you need — review actions before they are saved.',
            actions: [
              ActionChipButton(
                icon: Icons.restaurant_menu_outlined,
                label: 'OpenTable',
                onTap: () => launchUrl(
                  Uri.parse(CalendarExternalLinks.openTableSearchUrl('dinner near me')),
                  mode: LaunchMode.externalApplication,
                ),
                backgroundColor: cs.surface,
                foregroundColor: cs.onSurface,
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _turns.length + (_loading ? 1 : 0),
              itemBuilder: (context, i) {
                if (_loading && i == _turns.length) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final t = _turns[i];
                return Align(
                  alignment: t.user ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
                    decoration: BoxDecoration(
                      color: t.user ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.stone100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.stone200),
                    ),
                    child: Text(
                      t.text,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 15, height: 1.35),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_pendingActions != null && _pendingActions!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _applyPending,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Reviewed — apply actions'),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton.filledTonal(
                    onPressed: _toggleListen,
                    icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'e.g. Add dog food to groceries and remind us Saturday 10am…',
                        filled: true,
                        fillColor: AppTheme.stone50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _loading ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

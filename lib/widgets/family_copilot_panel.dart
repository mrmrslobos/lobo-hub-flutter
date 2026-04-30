// lib/widgets/family_copilot_panel.dart
// Family copilot UI — full-screen (Assistant route) or embedded sheet (Ask Huddle bar).
// Phases 1–3: conversation memory, spoken replies, auto-send after dictation, barge-in, haptics.

import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../config/cloud_sync_scope.dart';
import '../config/module_config.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/ai_service.dart';
import '../services/calendar_external_links.dart';
import '../services/copilot_action_applier.dart';
import 'ai_affordance.dart';
import 'common_widgets.dart';
import 'huddle_sheet.dart';
import 'subscription_modal.dart';

const _uuid = Uuid();

const int _kMaxCopilotHistoryPairs = 12;

enum FamilyCopilotLayout { sheet, fullScreen }

/// Opens the copilot in a bottom sheet (stays on the current module).
Future<void> showFamilyCopilotSheet(
  BuildContext context, {
  required String modulePath,
  String? initialQuery,
  bool startDictation = false,
}) {
  return showHuddleModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    maxHeightFactor: 0.84,
    builder: (ctx) => FamilyCopilotPanel(
      fromPath: modulePath,
      initialQuery: initialQuery,
      startDictation: startDictation,
      layout: FamilyCopilotLayout.sheet,
    ),
  );
}

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

class FamilyCopilotPanel extends StatefulWidget {
  const FamilyCopilotPanel({
    super.key,
    required this.fromPath,
    this.initialQuery,
    this.startDictation = false,
    required this.layout,
  });

  final String fromPath;
  final String? initialQuery;
  final bool startDictation;
  final FamilyCopilotLayout layout;

  @override
  State<FamilyCopilotPanel> createState() => _FamilyCopilotPanelState();
}

class _FamilyCopilotPanelState extends State<FamilyCopilotPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechReady = false;
  bool _listening = false;
  bool _loading = false;
  final List<_ChatTurn> _turns = [];
  List<dynamic>? _pendingActions;

  /// Prior turns sent to the model (Phase 1–2), excluding the message about to be sent.
  final List<Map<String, String>> _conversationForApi = [];

  /// Voice chat: auto-send after dictation + speak replies + shorter model replies.
  bool _voiceChatEnabled = !kIsWeb;

  String _partialTranscript = '';

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery;
    if (q != null && q.trim().isNotEmpty) {
      _ctrl.text = q.trim();
    }
    if (!kIsWeb) {
      unawaited(_initSpeech());
      unawaited(_initTts());
    } else if (widget.startDictation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Voice capture works best in the mobile app. Type your request here on web.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
  }

  Future<void> _initTts() async {
    if (kIsWeb) return;
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      final loc = WidgetsBinding.instance.platformDispatcher.locale;
      var tag = '${loc.languageCode}-${loc.countryCode ?? 'US'}';
      if (await _tts.isLanguageAvailable(tag) == true) {
        await _tts.setLanguage(tag);
      } else {
        await _tts.setLanguage('en-US');
      }
    } catch (e) {
      debugPrint('[tts] init: $e');
    }
  }

  Future<void> _stopSpeaking() async {
    if (kIsWeb) return;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> _speakReply(String raw) async {
    if (kIsWeb || !_voiceChatEnabled || raw.trim().isEmpty) return;
    var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > 900) t = '${t.substring(0, 897)}…';
    try {
      await _stopSpeaking();
      await _tts.speak(t);
    } catch (e) {
      debugPrint('[tts] speak: $e');
    }
  }

  Future<void> _initSpeech() async {
    final ok = await _speech.initialize(
      onError: (e) => debugPrint('[speech] error: ${e.errorMsg}'),
      onStatus: (s) => debugPrint('[speech] status: $s'),
    );
    if (!mounted) return;
    setState(() => _speechReady = ok);
    if (!ok) {
      debugPrint('[speech] initialize returned false (check RECORD_AUDIO / Google app)');
    }
    if (ok &&
        widget.startDictation &&
        (widget.initialQuery == null || widget.initialQuery!.trim().isEmpty)) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (mounted) unawaited(_toggleListen());
    }
  }

  void _trimApiHistory() {
    while (_conversationForApi.length > _kMaxCopilotHistoryPairs * 2) {
      _conversationForApi.removeAt(0);
      _conversationForApi.removeAt(0);
    }
  }

  @override
  void dispose() {
    if (_speech.isListening) {
      _speech.stop();
    }
    unawaited(_stopSpeaking());
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
        .where((t) =>
            t.familyId == familyId &&
            !t.completed &&
            t.dueDate != null &&
            _sameDay(t.dueDate!, today))
        .length;
    final upcoming = db.events
        .where((e) => e.familyId == familyId && !e.start.isBefore(today))
        .take(5)
        .map((e) => '${e.title} (${DateFormat.MMMd().format(e.start)})')
        .join('; ');
    var block =
        'Family: ${family.name}. Tasks due today: $tasksDue. Next events: $upcoming.';

    final listTitles = db.lists
        .where((l) => l.familyId == familyId)
        .map((l) => '"${l.title}" (${l.items.length} items)')
        .join('; ');
    block += listTitles.isEmpty
        ? ' Shopping lists: none yet.'
        : ' Shopping lists: $listTitles';

    final from = widget.fromPath;
    if (from.isNotEmpty) {
      final title = screenTitleForModulePath(from);
      block += ' User is in module: $title ($from).';
    }
    return block;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _send({String? textOverride}) async {
    final text = (textOverride ?? _ctrl.text).trim();
    if (text.isEmpty || _loading) return;
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.copilot)) {
      return;
    }

    final provider = context.read<AppProvider>();
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) return;

    final prior = List<Map<String, String>>.from(_conversationForApi);

    setState(() {
      _turns.add(_ChatTurn.user(text));
      _ctrl.clear();
      _partialTranscript = '';
      _loading = true;
      _pendingActions = null;
    });
    unawaited(_stopSpeaking());
    _scrollBottom();

    final ctx = _buildContext(provider);
    final decoded = await AiService.askCopilot(
      userMessage: text,
      familyId: family.id,
      contextBlock: ctx,
      conversationHistory: prior,
      preferShortReplies: _voiceChatEnabled,
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

    _conversationForApi.add({'role': 'user', 'content': text});
    _conversationForApi.add({'role': 'assistant', 'content': reply});
    _trimApiHistory();

    setState(() {
      _pendingActions = list;
      _turns.add(_ChatTurn.assistant(reply, list.isNotEmpty ? List.from(list) : null));
    });
    _scrollBottom();
    unawaited(_speakReply(reply));
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

  AppDB _snapshotDb(AppDB db) {
    final raw = jsonDecode(jsonEncode(db.toJson())) as Map<String, dynamic>;
    return AppDB.fromJson(raw);
  }

  void _clearPendingSuggestions() {
    setState(() => _pendingActions = null);
  }

  Future<void> _applyPending() async {
    final actions = _pendingActions;
    if (actions == null || actions.isEmpty) return;

    final provider = context.read<AppProvider>();
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) return;

    final bullets = CopilotActionApplier.describeActionsForUi(actions);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply these changes?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: bullets
                .map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(child: Text(line, style: const TextStyle(fontFamily: 'Inter'))),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final before = _snapshotDb(provider.db);
    final syncScope = <String>{};

    setState(() => _loading = true);
    unawaited(_stopSpeaking());
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

    syncScope
      ..addAll(result.pushTableScope)
      ..add(CloudSyncScope.aiHistory);

    await provider.saveAndSync(db, pushTableScope: syncScope);

    if (!mounted) return;
    final msg = result.appliedSummaries.isEmpty
        ? (result.errors.isNotEmpty ? result.errors.join('\n') : 'Nothing applied.')
        : 'Done: ${result.appliedSummaries.join(' · ')}';

    _conversationForApi.add({'role': 'assistant', 'content': msg});
    _trimApiHistory();

    setState(() {
      _loading = false;
      _pendingActions = null;
      _turns.add(_ChatTurn.assistant(msg, null));
    });
    _scrollBottom();

    if (mounted && result.errors.isNotEmpty && result.appliedSummaries.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errors.join('; ')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (_voiceChatEnabled && result.appliedSummaries.isNotEmpty) {
      unawaited(_speakReply(msg));
    }

    if (mounted && result.appliedSummaries.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: const Text('Changes saved'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              if (!mounted) return;
              await context.read<AppProvider>().saveAndSync(before, pushTableScope: syncScope);
            },
          ),
        ),
      );
    }
  }

  Future<void> _toggleListen() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice capture works best in the mobile app. Type your request here on web.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_speechReady) {
      final ok = await _speech.initialize();
      if (!mounted) return;
      setState(() => _speechReady = ok);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not start speech recognition. Check the microphone permission for Huddle in Settings.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    if (_listening) {
      await _speech.stop();
      setState(() {
        _listening = false;
        _partialTranscript = '';
      });
      return;
    }

    // Phase 3: barge-in on TTS + haptic when starting to listen.
    HapticFeedback.lightImpact();
    await _stopSpeaking();
    if (!mounted) return;

    setState(() {
      _listening = true;
      _partialTranscript = '';
    });
    await _speech.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => _partialTranscript = r.recognizedWords);
        if (r.finalResult) {
          final words = r.recognizedWords.trim();
          setState(() {
            _listening = false;
            _partialTranscript = '';
            if (words.isNotEmpty) {
              _ctrl.text = words;
            }
          });
          if (words.isEmpty) return;
          HapticFeedback.selectionClick();
          if (_voiceChatEnabled) {
            unawaited(_send(textOverride: words));
          }
        }
      },
      listenMode: stt.ListenMode.dictation,
      cancelOnError: true,
      partialResults: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    if ((provider.activeUser == null || provider.activeFamily == null) &&
        widget.layout == FamilyCopilotLayout.sheet) {
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const SheetHandle(),
            const SizedBox(height: 28),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary),
            ),
            const SizedBox(height: 14),
            Text(
              'Loading family…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          if (widget.layout == FamilyCopilotLayout.sheet)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 4, 8),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8, right: 6),
                    child: AiGlyph(size: 22, compact: true),
                  ),
                  Expanded(
                    child: Text(
                      'Ask Huddle',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Inter',
                          ),
                    ),
                  ),
                  if (!kIsWeb)
                    IconButton(
                      tooltip: _voiceChatEnabled
                          ? 'Voice chat on — spoken replies & send after you stop talking'
                          : 'Voice chat off — mic only fills the text field',
                      onPressed: () {
                        setState(() {
                          _voiceChatEnabled = !_voiceChatEnabled;
                          if (!_voiceChatEnabled) {
                            unawaited(_stopSpeaking());
                          }
                        });
                      },
                      icon: Icon(
                        _voiceChatEnabled ? Icons.record_voice_over_rounded : Icons.mic_none_rounded,
                        color: _voiceChatEnabled ? cs.primary : null,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          if (widget.layout == FamilyCopilotLayout.fullScreen)
            PageHeader(
              title: screenTitleForModulePath('/assistant'),
              titlePrefix: const AiGlyph(size: 24),
              subtitle:
                  'Turn plain language into calendar updates, lists, and tasks — review each change before it saves. '
                  '${!kIsWeb ? 'Toggle voice for hands-free replies.' : ''}',
              actions: [
                if (!kIsWeb)
                  ActionChipButton(
                    icon: _voiceChatEnabled ? Icons.record_voice_over_rounded : Icons.mic_none_rounded,
                    label: _voiceChatEnabled ? 'Voice on' : 'Voice off',
                    onTap: () {
                      setState(() {
                        _voiceChatEnabled = !_voiceChatEnabled;
                        if (!_voiceChatEnabled) {
                          unawaited(_stopSpeaking());
                        }
                      });
                    },
                    backgroundColor: cs.surface,
                    foregroundColor: cs.onSurface,
                  ),
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
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.88,
                    ),
                    decoration: BoxDecoration(
                      color: t.user
                          ? AppTheme.primary.withValues(alpha: 0.12)
                          : AppTheme.stone100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.stone200),
                    ),
                    child: Text(
                      t.text,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_listening && _partialTranscript.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _partialTranscript,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          if (_pendingActions != null && _pendingActions!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _applyPending,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Reviewed — apply actions'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: _loading ? null : _clearPendingSuggestions,
                      child: const Text('Dismiss suggestions'),
                    ),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
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
                        hintText: widget.layout == FamilyCopilotLayout.sheet
                            ? 'e.g. Add nails and screws to Bunnings list…'
                            : 'e.g. Add dog food to groceries and remind us Saturday 10am…',
                        filled: true,
                        fillColor: AppTheme.stone50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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

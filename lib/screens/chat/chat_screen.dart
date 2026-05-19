// lib/screens/chat/chat_screen.dart
// Family chat screen for Huddle

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

import '../../config/cloud_sync_scope.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/family_activity_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/huddle_module_scaffold.dart';
import '../../widgets/module_ui_kit.dart';
import '../../utils/debounce.dart';
import '../../utils/sync_after_save.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    duration: const Duration(seconds: 1),
  ));
}

Future<void> _reportContent(
  BuildContext context,
  String contentType,
  String contentId,
) async {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Report Content'),
      content: Text('Report this $contentType? The family admin will be notified.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            final provider = ctx.read<AppProvider>();
            final familyId = provider.activeFamily?.id;
            final actorUserId = provider.activeUser?.id;
            if (familyId != null && actorUserId != null) {
              final nextDb = FamilyActivityService.append(
                provider.db,
                familyId: familyId,
                actorUserId: actorUserId,
                action: 'content_reported',
                detail: '$contentType:$contentId',
              );
              await provider.saveAndSync(
                nextDb,
                pushTableScope: {CloudSyncScope.familyActivityLogs},
              );
            }
            if (!ctx.mounted) return; // FIXED: async gap — use dialog context only
            Navigator.pop(ctx);
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: const Text('Report saved for family admin review'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ));
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Report'),
        ),
      ],
    ),
  );
}

// ─── Chat screen ──────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _searchDebounce = Debouncer();
  final _scrollCtrl = ScrollController();
  ChatMessage? _replyTo;
  bool _sending = false;
  String _searchQuery = '';
  bool _showSearch = false;

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchCtrl.dispose();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDateSeparator(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return 'Today';
    if (_isSameDay(date, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat('EEEE, MMMM d').format(date);
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        if (animated) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      }
    });
  }

  Future<void> _sendMessage(AppProvider provider) async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    if (provider.activeUser == null || provider.activeFamily == null) return;

    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    try {
      const uuid = Uuid();
      final msg = ChatMessage(
        id: uuid.v4(),
        familyId: provider.activeFamily!.id,
        userId: provider.activeUser!.id,
        text: text,
        replyToId: _replyTo?.id,
        reactions: {},
        createdAt: DateTime.now(),
      );

      final db = provider.db;
      await saveAndSyncWithImmediatePush(
        provider,
        db.copyWith(messages: [...db.messages, msg]),
        pushTableScope: {CloudSyncScope.messages},
      );

      _textCtrl.clear();
      setState(() => _replyTo = null);
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      _showSnack(context, 'Failed to send message. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _addReaction(
      AppProvider provider, ChatMessage msg, String emoji) async {
    HapticFeedback.selectionClick();
    final userId = provider.activeUser!.id;
    final reactions = Map<String, List<String>>.from(
      msg.reactions.map((k, v) => MapEntry(k, List<String>.from(v))),
    );

    final users = reactions.putIfAbsent(emoji, () => []);
    if (users.contains(userId)) {
      users.remove(userId);
      if (users.isEmpty) reactions.remove(emoji);
    } else {
      users.add(userId);
    }

    final updated = msg.copyWith(reactions: reactions);
    final db = provider.db;
    final messages =
        db.messages.map((m) => m.id == msg.id ? updated : m).toList();
    try {
      await saveAndSyncWithImmediatePush(
        provider,
        db.copyWith(messages: messages),
        pushTableScope: {CloudSyncScope.messages},
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack(context, 'Could not update reaction.');
    }
  }

  Future<void> _deleteMessage(
    AppProvider provider,
    ChatMessage msg, {
    bool confirm = true,
  }) async {
    if (provider.activeUser?.id != msg.senderId) {
      if (mounted) _showSnack(context, 'You can only delete your own messages.');
      return;
    }
    if (confirm) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Message'),
          content: const Text('Delete this message? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final db = provider.db;
    try {
      await saveAndSyncWithImmediatePush(
        provider,
        db.copyWith(
          messages: db.messages.where((m) => m.id != msg.id).toList(),
        ),
        pushTableScope: {CloudSyncScope.messages},
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack(context, 'Could not delete message.');
    }
  }

  void _showMessageActions(AppProvider provider, ChatMessage msg) {
    HapticFeedback.mediumImpact();
    final isMe = msg.senderId == provider.activeUser?.id;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _replyTo = msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: const Text('React'),
              onTap: () {
                Navigator.pop(ctx);
                _showReactionPicker(provider, msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy Text'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: msg.content));
                Navigator.pop(ctx);
                _showSnack(context, 'Copied to clipboard');
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: const Text('Report'),
              onTap: () {
                Navigator.pop(ctx);
                _reportContent(context, 'message', msg.id);
              },
            ),
            if (isMe)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                title: Text('Delete', style: TextStyle(color: AppTheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(provider, msg);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showReactionPicker(AppProvider provider, ChatMessage msg) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            const SizedBox(height: 8),
            const Text(
              'React to message',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.stone900,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: emojis
                  .map((e) => GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _addReaction(provider, msg, e);
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppTheme.stone100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: Text(e,
                              style:
                                  const TextStyle(fontSize: 28)),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        if (provider.activeUser == null || provider.activeFamily == null) {
          return const ModuleFamilyLoadingScaffold();
        }
        final familyId = provider.activeFamily?.id;
        final myId = provider.activeUser?.id;

        final messages = familyId == null
            ? <ChatMessage>[]
            : (provider.db.messages
                .where((m) => m.familyId == familyId)
                .toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));

        // Scroll to bottom only if already near bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            final maxScroll = _scrollCtrl.position.maxScrollExtent;
            final currentScroll = _scrollCtrl.position.pixels;
            if (maxScroll - currentScroll < 150) {
              _scrollToBottom(animated: false);
            }
          }
        });

        return HuddleModuleScaffold(
          modulePath: '/chat',
          enterPullTables: {CloudSyncScope.messages},
          resizeToAvoidBottomInset: true,
          drawer: const AppDrawer(),
          appBar: MainAppBar(
            actions: [
              IconButton(
                icon: Icon(
                  _showSearch ? Icons.close_rounded : Icons.search_rounded,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                ),
                onPressed: () => setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchDebounce.cancel();
                    _searchCtrl.clear();
                    _searchQuery = '';
                  }
                }),
              ),
            ],
          ),
          child: Column(
            children: [
              // ─── Search bar ────────────────────────────────────────────
              if (_showSearch)
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    onChanged: (v) {
                      _searchDebounce.run(() {
                        if (!mounted) return;
                        setState(() => _searchQuery = v);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search messages...',
                      hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.stone400),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchDebounce.cancel();
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.stone50,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),

              // ─── Message list ──────────────────────────────────────────
              Expanded(
                child: () {
                  final filteredMessages = _searchQuery.isEmpty
                      ? messages
                      : messages.where((m) => m.text.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
                  if (filteredMessages.isEmpty) {
                    if (_searchQuery.isNotEmpty) {
                      return CatalogModuleEmptyState(
                        modulePath: '/chat',
                        title: 'No matches',
                        subtitle: 'Try a different search term',
                      );
                    }
                    return CatalogModuleEmptyState(
                      modulePath: '/chat',
                      title: 'No messages yet',
                      subtitle: 'Send the first message to your family!',
                    );
                  }
                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                    itemCount: filteredMessages.length,
                    itemBuilder: (ctx, i) {
                      final msg = filteredMessages[i];
                      final isMe = msg.senderId == myId;
                      final sender = provider.userById(msg.senderId);

                      final showSenderInfo = !isMe &&
                          (i == 0 || filteredMessages[i - 1].senderId != msg.senderId);

                      final showDateSep = i == 0 ||
                          !_isSameDay(filteredMessages[i - 1].createdAt, msg.createdAt);

                      ChatMessage? replyMsg;
                      if (msg.replyToId != null) {
                        replyMsg = messages.where((m) => m.id == msg.replyToId).firstOrNull;
                      }

                      return Column(
                        children: [
                          if (showDateSep)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                _formatDateSeparator(msg.createdAt),
                                style: const TextStyle(
                                  fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600,
                                  color: AppTheme.stone400,
                                ),
                              ),
                            ),
                          Dismissible(
                            key: ValueKey(msg.id),
                            direction: isMe
                                ? DismissDirection.endToStart
                                : DismissDirection.none,
                            confirmDismiss: (direction) async {
                              if (!isMe) return false;
                              return await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Message'),
                                  content: const Text('Delete this message?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete',
                                          style: TextStyle(color: AppTheme.error)),
                                    ),
                                  ],
                                ),
                              ) ?? false;
                            },
                            onDismissed: (_) =>
                                _deleteMessage(provider, msg, confirm: false),
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                color: AppTheme.error,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text('Delete',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                  SizedBox(width: 8),
                                  Icon(Icons.delete, color: Colors.white),
                                ],
                              ),
                            ),
                            child: _MessageBubble(
                              msg: msg,
                              isMe: isMe,
                              sender: sender,
                              showSenderInfo: showSenderInfo,
                              replyMsg: replyMsg,
                              provider: provider,
                              onLongPress: () => _showMessageActions(provider, msg),
                              onReply: () => setState(() => _replyTo = msg),
                              onReact: (emoji) => _addReaction(provider, msg, emoji),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                }(),
              ),

              // ─── Reply preview ────────────────────────────────────────
              if (_replyTo != null)
                Container(
                  color: AppTheme.stone50,
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Replying to ${provider.userById(_replyTo!.senderId)?.name.split(' ').first ?? 'message'}',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                            ),
                            Text(
                              _replyTo!.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: AppTheme.stone500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 18, color: AppTheme.stone400),
                        onPressed: () =>
                            setState(() => _replyTo = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

              // ─── Input bar ────────────────────────────────────────────
              Container(
                color: AppTheme.surface,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.stone100,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: TextField(
                            controller: _textCtrl,
                            maxLines: null,
                            textCapitalization:
                                TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Message your family…',
                              hintStyle: TextStyle(
                                  color: AppTheme.stone400,
                                  fontFamily: 'Inter'),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              isDense: true,
                            ),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              color: AppTheme.stone900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _sending
                            ? null
                            : () => _sendMessage(provider),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _sending
                                ? AppTheme.stone300
                                : AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: _sending
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(
                                            Colors.white),
                                  ),
                                )
                              : const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Message bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;
  final User? sender;
  final bool showSenderInfo;
  final ChatMessage? replyMsg;
  final AppProvider provider;
  final VoidCallback onLongPress;
  final VoidCallback onReply;
  final ValueChanged<String> onReact;

  const _MessageBubble({
    required this.msg,
    required this.isMe,
    required this.sender,
    required this.showSenderInfo,
    required this.replyMsg,
    required this.provider,
    required this.onLongPress,
    required this.onReply,
    required this.onReact,
  });

  Color get _bubbleColor =>
      isMe ? AppTheme.primary : AppTheme.surface;

  Color get _textColor =>
      isMe ? Colors.white : AppTheme.stone900;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: showSenderInfo ? 12 : 2,
        bottom: 0,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar on the left for others
          if (!isMe) ...[
            if (showSenderInfo)
              AvatarInitials(
                  name: sender?.name ?? '?', size: 32)
            else
              const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],

          // Bubble
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Sender name (others only)
                if (!isMe && showSenderInfo && sender != null)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 4, bottom: 4),
                    child: Text(
                      sender!.name.split(' ').first,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.stone500,
                      ),
                    ),
                  ),

                // Bubble container
                GestureDetector(
                  onLongPress: onLongPress,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth:
                          MediaQuery.of(context).size.width * 0.72,
                    ),
                    decoration: BoxDecoration(
                      color: _bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 18),
                      ),
                      border: isMe
                          ? null
                          : Border.all(color: AppTheme.stone100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Reply preview
                        if (replyMsg != null)
                          _ReplyPreview(
                            replyMsg: replyMsg!,
                            isMe: isMe,
                            provider: provider,
                          ),

                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              12, 10, 12, 10),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.content,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  color: _textColor,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment:
                                    MainAxisAlignment.end,
                                children: [
                                  Text(
                                    _formatTime(msg.createdAt),
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 10,
                                      color: isMe
                                          ? Colors.white60
                                          : AppTheme.stone400,
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.done_all_rounded,
                                      size: 14,
                                      color: Colors.white.withValues(alpha: 0.7),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Reply button + reactions row
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: isMe
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      // Reactions
                      ...msg.reactions.entries
                          .where((e) => e.value.isNotEmpty)
                          .map((e) => _ReactionChip(
                                emoji: e.key,
                                count: e.value.length,
                                reacted: e.value.contains(
                                    provider.activeUser?.id),
                                onTap: () => onReact(e.key),
                              )),

                      // Reply icon
                      GestureDetector(
                        onTap: onReply,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Icon(
                            Icons.reply_outlined,
                            size: 16,
                            color: AppTheme.stone400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Spacer on the right for others
          if (!isMe) const SizedBox(width: 40),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day) {
      return DateFormat('h:mm a').format(dt);
    }
    return DateFormat('MMM d, h:mm a').format(dt);
  }
}

// ─── Reply preview inside bubble ─────────────────────────────────────────────

class _ReplyPreview extends StatelessWidget {
  final ChatMessage replyMsg;
  final bool isMe;
  final AppProvider provider;

  const _ReplyPreview({
    required this.replyMsg,
    required this.isMe,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final replySender = provider.userById(replyMsg.senderId);
    final bgColor = isMe
        ? Colors.white.withValues(alpha: 0.15)
        : AppTheme.stone100;
    final textColor = isMe ? Colors.white70 : AppTheme.stone500;
    final nameColor = isMe ? Colors.white : AppTheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white54 : AppTheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replySender != null)
            Text(
              replySender.name.split(' ').first,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: nameColor,
              ),
            ),
          Text(
            replyMsg.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reaction chip ────────────────────────────────────────────────────────────

class _ReactionChip extends StatelessWidget {
  final String emoji;
  final int count;
  final bool reacted;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.reacted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: reacted
              ? AppTheme.primary.withValues(alpha: 0.12)
              : AppTheme.stone100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: reacted ? AppTheme.primary : AppTheme.stone100,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            if (count > 1) ...[
              const SizedBox(width: 3),
              Text(
                count.toString(),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: reacted ? AppTheme.primary : AppTheme.stone500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// lib/screens/chat/chat_screen.dart
// Family chat screen for FamilyHub

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

// ─── Chat screen ──────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  ChatMessage? _replyTo;
  bool _sending = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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
      await provider.saveAndSync(db.copyWith(messages: [...db.messages, msg]));

      _textCtrl.clear();
      setState(() => _replyTo = null);
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _addReaction(
      AppProvider provider, ChatMessage msg, String emoji) async {
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
    await provider.saveAndSync(db.copyWith(messages: messages));
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
                            borderRadius: BorderRadius.circular(14),
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
        final familyId = provider.activeFamily?.id;
        final myId = provider.activeUser?.id;

        final messages = familyId == null
            ? <ChatMessage>[]
            : (provider.db.messages
                .where((m) => m.familyId == familyId)
                .toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));

        // Scroll to bottom on first build or new message
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom(animated: false);
        });

        return Scaffold(
          backgroundColor: AppTheme.background,
          resizeToAvoidBottomInset: true,
          drawer: const AppDrawer(),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: AppTheme.stone700),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 20, color: AppTheme.primary),
                const SizedBox(width: 6),
                const Text('FamilyHub', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary)),
              ],
            ),
            centerTitle: false,
            titleSpacing: 0,
            actions: [
              IconButton(icon: const Icon(Icons.menu_rounded, color: AppTheme.stone500), onPressed: () {}),
            ],
          ),
          body: Column(
            children: [
              // ─── Message list ──────────────────────────────────────────
              Expanded(
                child: messages.isEmpty
                    ? const EmptyState(
                        emoji: '💬',
                        title: 'No messages yet',
                        subtitle:
                            'Send the first message to your family!',
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(
                            12, 16, 12, 16),
                        itemCount: messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = messages[i];
                          final isMe = msg.senderId == myId;
                          final sender =
                              provider.userById(msg.senderId);

                          // Group: show avatar + name only if
                          // different sender than previous
                          final showSenderInfo = !isMe &&
                              (i == 0 ||
                                  messages[i - 1].senderId !=
                                      msg.senderId);

                          // Reply reference
                          ChatMessage? replyMsg;
                          if (msg.replyToId != null) {
                            replyMsg = messages
                                .cast<ChatMessage?>()
                                .firstWhere(
                                    (m) => m?.id == msg.replyToId,
                                    orElse: () => null);
                          }

                          return _MessageBubble(
                            msg: msg,
                            isMe: isMe,
                            sender: sender,
                            showSenderInfo: showSenderInfo,
                            replyMsg: replyMsg,
                            provider: provider,
                            onLongPress: () =>
                                _showReactionPicker(provider, msg),
                            onReply: () =>
                                setState(() => _replyTo = msg),
                            onReact: (emoji) =>
                                _addReaction(provider, msg, emoji),
                          );
                        },
                      ),
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
                color: Colors.white,
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
      isMe ? AppTheme.primary : Colors.white;

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
                          : Border.all(color: AppTheme.stone200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
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
            color: reacted ? AppTheme.primary : AppTheme.stone200,
            width: 1,
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

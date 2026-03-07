
import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { Send, Smile, Reply, Edit2, Trash2, X, Check, MessageSquare } from 'lucide-react';
import { User, Family, ChatMessage } from '../types';
import { useRealtimeDB } from '../hooks/useRealtimeDB';
import { broadcastChatMessage, onChatMessage, ChatBroadcast } from '../services/realtime';
import { createId } from '../services/id';
import { format, isToday, isYesterday, isSameDay } from 'date-fns';

const EMOJI_REACTIONS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

const AVATAR_COLORS = [
  'bg-indigo-500', 'bg-violet-500', 'bg-pink-500', 'bg-teal-500',
  'bg-amber-500', 'bg-emerald-500', 'bg-sky-500', 'bg-rose-500',
];

function avatarColor(userId: string): string {
  let hash = 0;
  for (let i = 0; i < userId.length; i++) hash = (hash * 31 + userId.charCodeAt(i)) >>> 0;
  return AVATAR_COLORS[hash % AVATAR_COLORS.length];
}

function initials(name: string): string {
  if (!name?.trim()) return '?';
  return name.split(' ').map(p => p[0]).filter(Boolean).join('').toUpperCase().slice(0, 2) || '?';
}

function formatDayHeader(date: Date): string {
  if (isToday(date)) return 'Today';
  if (isYesterday(date)) return 'Yesterday';
  return format(date, 'EEEE, MMMM d');
}

interface UserMap {
  [id: string]: { name: string; avatar?: string };
}

interface Props {
  user: User;
  family: Family;
}

const Chat: React.FC<Props> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const dbRef = useRef(db);
  dbRef.current = db;
  const saveRef = useRef(save);
  saveRef.current = save;
  const [text, setText] = useState('');
  const [replyTo, setReplyTo] = useState<ChatMessage | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editText, setEditText] = useState('');
  const [emojiPickerFor, setEmojiPickerFor] = useState<string | null>(null);
  const [userMap, setUserMap] = useState<UserMap>({});
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const messages = useMemo(
    () => (db?.messages ?? []).filter(m => m.familyId === family.id)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt)),
    [db?.messages, family.id],
  );

  // Build user map from users table (FamilyMember only has userId/role, no name/avatar)
  useEffect(() => {
    const map: UserMap = {};
    (db?.familyMembers ?? []).forEach(m => {
      const u = (db?.users ?? []).find(u => u.id === m.userId);
      if (u) map[u.id] = { name: u.name, avatar: u.avatar };
    });
    // Always include current user
    map[user.id] = { name: user.name, avatar: user.avatar };
    setUserMap(map);
  }, [db?.familyMembers, db?.users, user]);

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length]);

  // Listen for incoming realtime messages.
  // Uses refs so the listener is registered once (no teardown/re-register on every db change)
  // and always reads the latest db snapshot, preventing stale-closure message loss.
  useEffect(() => {
    const unsub = onChatMessage((broadcast: ChatBroadcast) => {
      const currentDb = dbRef.current;
      if (!currentDb) return;
      const already = (currentDb.messages ?? []).some(m => m.id === broadcast.id);
      if (already) return;
      const msg: ChatMessage = {
        id: broadcast.id,
        familyId: broadcast.familyId,
        userId: broadcast.userId,
        text: broadcast.text,
        replyToId: broadcast.replyToId,
        reactions: broadcast.reactions ?? {},
        createdAt: broadcast.createdAt,
      };
      const updated = [...(currentDb.messages ?? []), msg].slice(-500);
      saveRef.current({ ...currentDb, messages: updated });
    });
    return unsub;
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const persistMessage = useCallback((msg: ChatMessage) => {
    if (!db) return;
    const updated = [...(db.messages ?? []), msg].slice(-500);
    save({ ...db, messages: updated });
  }, [db, save]);

  const handleSend = useCallback(() => {
    const trimmed = text.trim();
    if (!trimmed) return;

    const msg: ChatMessage = {
      id: createId(),
      familyId: family.id,
      userId: user.id,
      text: trimmed,
      replyToId: replyTo?.id,
      reactions: {},
      createdAt: new Date().toISOString(),
    };

    persistMessage(msg);
    broadcastChatMessage({
      id: msg.id,
      familyId: msg.familyId,
      userId: msg.userId,
      text: msg.text,
      replyToId: msg.replyToId,
      reactions: msg.reactions,
      createdAt: msg.createdAt,
    });

    setText('');
    setReplyTo(null);
    inputRef.current?.focus();
  }, [text, replyTo, family.id, user.id, persistMessage]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
    if (e.key === 'Escape') {
      setReplyTo(null);
      setEditingId(null);
    }
  };

  const startEdit = (msg: ChatMessage) => {
    setEditingId(msg.id);
    setEditText(msg.text);
    setEmojiPickerFor(null);
  };

  const saveEdit = () => {
    if (!db || !editingId || !editText.trim()) return;
    const updated = (db.messages ?? []).map(m =>
      m.id === editingId ? { ...m, text: editText.trim(), editedAt: new Date().toISOString() } : m,
    );
    save({ ...db, messages: updated });
    setEditingId(null);
    setEditText('');
  };

  const deleteMessage = (id: string) => {
    if (!db) return;
    save({ ...db, messages: (db.messages ?? []).filter(m => m.id !== id) });
  };

  const toggleReaction = (msgId: string, emoji: string) => {
    if (!db) return;
    const updated = (db.messages ?? []).map(m => {
      if (m.id !== msgId) return m;
      const users = (m.reactions ?? {})[emoji] ?? [];
      const hasIt = users.includes(user.id);
      const newUsers = hasIt ? users.filter(id => id !== user.id) : [...users, user.id];
      const newReactions = { ...m.reactions };
      if (newUsers.length === 0) delete newReactions[emoji];
      else newReactions[emoji] = newUsers;
      return { ...m, reactions: newReactions };
    });
    save({ ...db, messages: updated });
    setEmojiPickerFor(null);
  };

  // Group messages by day
  const grouped = useMemo(() => {
    const groups: { date: Date; msgs: ChatMessage[] }[] = [];
    messages.forEach(msg => {
      const d = new Date(msg.createdAt);
      const last = groups[groups.length - 1];
      if (!last || !isSameDay(last.date, d)) groups.push({ date: d, msgs: [msg] });
      else last.msgs.push(msg);
    });
    return groups;
  }, [messages]);

  const replyMsg = replyTo ? messages.find(m => m.id === replyTo.id) : null;

  return (
    <div className="flex flex-col h-full max-h-[calc(100vh-120px)]">
      {/* Header */}
      <div className="px-4 py-3 border-b border-gray-200 dark:border-gray-700 flex items-center gap-2">
        <MessageSquare className="w-5 h-5 text-indigo-500" />
        <h1 className="text-lg font-semibold text-gray-900 dark:text-white">Family Chat</h1>
        <span className="ml-auto text-xs text-gray-400">{messages.length} messages</span>
      </div>

      {/* Message list */}
      <div className="flex-1 overflow-y-auto px-4 py-3 space-y-1" onClick={() => setEmojiPickerFor(null)}>
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full text-gray-400 gap-3">
            <MessageSquare className="w-12 h-12 opacity-30" />
            <p className="text-sm">No messages yet. Say hello!</p>
          </div>
        )}

        {grouped.map(({ date, msgs }) => (
          <div key={date.toISOString()}>
            {/* Day separator */}
            <div className="flex items-center gap-2 my-3">
              <div className="flex-1 h-px bg-gray-200 dark:bg-gray-700" />
              <span className="text-xs text-gray-400 px-2">{formatDayHeader(date)}</span>
              <div className="flex-1 h-px bg-gray-200 dark:bg-gray-700" />
            </div>

            {msgs.map((msg, idx) => {
              const isMine = msg.userId === user.id;
              const sender = userMap[msg.userId];
              const senderName = sender?.name ?? 'Unknown';
              const showAvatar = !isMine && (idx === 0 || msgs[idx - 1].userId !== msg.userId);
              const repliedMsg = msg.replyToId ? messages.find(m => m.id === msg.replyToId) : null;
              const repliedSender = repliedMsg ? (userMap[repliedMsg.userId]?.name ?? 'Unknown') : null;
              const reactionEntries = (Object.entries(msg.reactions ?? {}) as [string, string[]][]).filter(([, users]) => users.length > 0);

              return (
                <div key={msg.id} className={`flex gap-2 group ${isMine ? 'flex-row-reverse' : 'flex-row'} mb-1`}>
                  {/* Avatar */}
                  <div className="w-8 flex-shrink-0 mt-auto">
                    {showAvatar && !isMine && (
                      sender?.avatar
                        ? <img src={sender.avatar} className="w-8 h-8 rounded-full object-cover" alt={senderName} />
                        : <div className={`w-8 h-8 rounded-full flex items-center justify-center text-white text-xs font-bold ${avatarColor(msg.userId)}`}>{initials(senderName)}</div>
                    )}
                  </div>

                  {/* Bubble */}
                  <div className={`flex flex-col max-w-[72%] ${isMine ? 'items-end' : 'items-start'}`}>
                    {showAvatar && !isMine && (
                      <span className="text-xs text-gray-500 mb-0.5 ml-1">{senderName}</span>
                    )}

                    {/* Replied-to preview */}
                    {repliedMsg && (
                      <div className={`text-xs px-2 py-1 mb-0.5 rounded border-l-2 border-indigo-400 bg-gray-100 dark:bg-gray-700 text-gray-500 max-w-full truncate`}>
                        <span className="font-medium text-indigo-500">{repliedSender}: </span>
                        {repliedMsg.text}
                      </div>
                    )}

                    {editingId === msg.id ? (
                      <div className="flex items-center gap-1">
                        <input
                          autoFocus
                          className="text-sm border border-indigo-400 rounded-lg px-3 py-1.5 bg-white dark:bg-gray-800 text-gray-900 dark:text-white min-w-[180px]"
                          value={editText}
                          onChange={e => setEditText(e.target.value)}
                          onKeyDown={e => { if (e.key === 'Enter') saveEdit(); if (e.key === 'Escape') setEditingId(null); }}
                        />
                        <button onClick={saveEdit} className="text-green-500 hover:text-green-600"><Check className="w-4 h-4" /></button>
                        <button onClick={() => setEditingId(null)} className="text-gray-400 hover:text-gray-600"><X className="w-4 h-4" /></button>
                      </div>
                    ) : (
                      <div className={`relative px-3 py-2 rounded-2xl text-sm leading-relaxed break-words
                        ${isMine
                          ? 'bg-indigo-500 text-white rounded-br-sm'
                          : 'bg-white dark:bg-gray-800 text-gray-900 dark:text-white border border-gray-200 dark:border-gray-700 rounded-bl-sm'
                        }`}>
                        {msg.text}
                        {msg.editedAt && (
                          <span className="text-[10px] opacity-60 ml-1">(edited)</span>
                        )}
                      </div>
                    )}

                    {/* Reactions */}
                    {reactionEntries.length > 0 && (
                      <div className="flex flex-wrap gap-1 mt-0.5">
                        {reactionEntries.map(([emoji, users]) => (
                          <button
                            key={emoji}
                            onClick={e => { e.stopPropagation(); toggleReaction(msg.id, emoji); }}
                            className={`flex items-center gap-0.5 text-xs px-1.5 py-0.5 rounded-full border transition-colors
                              ${users.includes(user.id)
                                ? 'bg-indigo-100 dark:bg-indigo-900 border-indigo-300 dark:border-indigo-600'
                                : 'bg-gray-100 dark:bg-gray-700 border-gray-200 dark:border-gray-600'
                              }`}
                          >
                            <span>{emoji}</span>
                            <span className="text-gray-600 dark:text-gray-300">{users.length}</span>
                          </button>
                        ))}
                      </div>
                    )}

                    {/* Timestamp */}
                    <span className="text-[10px] text-gray-400 mt-0.5 px-1">
                      {format(new Date(msg.createdAt), 'h:mm a')}
                    </span>
                  </div>

                  {/* Action buttons (hover) */}
                  <div className={`relative flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity self-center
                    ${isMine ? 'flex-row-reverse mr-1' : 'ml-1'}`}>
                    <button
                      onClick={e => { e.stopPropagation(); setEmojiPickerFor(emojiPickerFor === msg.id ? null : msg.id); }}
                      className="p-1 rounded-full hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-400 hover:text-gray-600"
                      title="React with emoji"
                      aria-label="React with emoji"
                    >
                      <Smile className="w-3.5 h-3.5" />
                    </button>
                    <button
                      onClick={() => { setReplyTo(msg); inputRef.current?.focus(); }}
                      className="p-1 rounded-full hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-400 hover:text-gray-600"
                      title="Reply to message"
                      aria-label="Reply to message"
                    >
                      <Reply className="w-3.5 h-3.5" />
                    </button>
                    {isMine && (
                      <>
                        <button
                          onClick={() => startEdit(msg)}
                          className="p-1 rounded-full hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-400 hover:text-gray-600"
                          title="Edit message"
                          aria-label="Edit message"
                        >
                          <Edit2 className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={() => deleteMessage(msg.id)}
                          className="p-1 rounded-full hover:bg-red-50 dark:hover:bg-red-900/20 text-gray-400 hover:text-red-500"
                          title="Delete message"
                          aria-label="Delete message"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </>
                    )}

                    {/* Emoji picker */}
                    {emojiPickerFor === msg.id && (
                      <div
                        className="absolute z-50 flex gap-1 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-full shadow-lg px-2 py-1"
                        onClick={e => e.stopPropagation()}
                      >
                        {EMOJI_REACTIONS.map(emoji => (
                          <button
                            key={emoji}
                            className="text-lg hover:scale-125 transition-transform"
                            onClick={() => toggleReaction(msg.id, emoji)}
                          >
                            {emoji}
                          </button>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        ))}
        <div ref={bottomRef} />
      </div>

      {/* Reply preview */}
      {replyTo && (
        <div className="mx-4 mb-1 px-3 py-2 bg-indigo-50 dark:bg-indigo-900/30 rounded-lg border-l-2 border-indigo-400 flex items-start justify-between gap-2">
          <div className="text-xs text-gray-600 dark:text-gray-300 truncate">
            <span className="font-medium text-indigo-600 dark:text-indigo-400">
              Replying to {userMap[replyTo.userId]?.name ?? 'Unknown'}:
            </span>{' '}
            {replyTo.text}
          </div>
          <button onClick={() => setReplyTo(null)} className="text-gray-400 hover:text-gray-600 flex-shrink-0">
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}

      {/* Input bar */}
      <div className="px-4 py-3 border-t border-gray-200 dark:border-gray-700 flex items-center gap-2">
        <input
          ref={inputRef}
          type="text"
          value={text}
          onChange={e => setText(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Type a message…"
          className="flex-1 px-4 py-2 rounded-full border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-400"
          maxLength={2000}
        />
        <button
          onClick={handleSend}
          disabled={!text.trim()}
          className="w-9 h-9 rounded-full bg-indigo-500 hover:bg-indigo-600 disabled:opacity-40 flex items-center justify-center text-white transition-colors"
        >
          <Send className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};

export default Chat;

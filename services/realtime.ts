import { supabase, isSupabaseConfigured } from './supabase';

export interface FamilyBroadcast {
  userId: string;
  userName: string;
  action: string;   // e.g. "checked off an item", "added a task"
  module: string;    // e.g. "Lists", "Tasks", "Calendar"
  detail: string;    // e.g. "Milk from Grocery List"
  timestamp: number;
}

type BroadcastListener = (msg: FamilyBroadcast) => void;
type DbRefreshListener = () => void;

export interface ChatBroadcast {
  /** Message id — same as ChatMessage.id */
  id: string;
  userId: string;
  text: string;
  familyId: string;
  replyToId?: string;
  reactions: Record<string, string[]>;
  createdAt: string;
  timestamp: number;
}
type ChatListener = (msg: ChatBroadcast) => void;

let activeChannel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null;
let currentFamilyId: string | null = null;
let currentUserId: string | null = null;
const listeners: Set<BroadcastListener> = new Set();
const chatListeners: Set<ChatListener> = new Set();
// Listeners notified when Postgres Changes detects any remote DB write.
// Provides a second, broadcast-independent update path so live sync works
// even when broadcasts are missed (network hiccup, stale channel, etc.).
const dbRefreshListeners: Set<DbRefreshListener> = new Set();
// Debounce timer so rapid writes (e.g. bulk operations) coalesce into one fetch.
let _pgDebounceTimer: ReturnType<typeof setTimeout> | null = null;

/**
 * Join the family's realtime channel. Any member's changes will be
 * broadcast to all other members currently online.
 */
export function joinFamilyChannel(familyId: string, userId: string) {
  if (!supabase || !isSupabaseConfigured()) return;
  if (currentFamilyId === familyId && activeChannel) return; // Already joined

  // Leave old channel first
  leaveFamilyChannel();

  currentFamilyId = familyId;
  currentUserId = userId;

  activeChannel = supabase.channel(`family:${familyId}`, {
    config: { broadcast: { self: false } },
  });

  activeChannel
    .on('broadcast', { event: 'change' }, (payload) => {
      const msg = payload.payload as FamilyBroadcast;
      // Ignore own broadcasts (safety net - self:false should handle this)
      if (msg.userId === currentUserId) return;
      listeners.forEach(fn => fn(msg));
    })
    .on('broadcast', { event: 'chat_msg' }, (payload) => {
      const msg = payload.payload as ChatBroadcast;
      if (msg.userId === currentUserId) return;
      chatListeners.forEach(fn => fn(msg));
    })
    // Postgres Changes fires for every DB write, giving a second independent
    // path for live updates that doesn't rely on broadcasts being delivered.
    // Debounced so bulk writes (e.g. completing multiple chores) trigger one fetch.
    // If Realtime isn't enabled on a table in Supabase it just won't fire — safe.
    .on('postgres_changes', { event: '*', schema: 'public' }, () => {
      if (_pgDebounceTimer) clearTimeout(_pgDebounceTimer);
      _pgDebounceTimer = setTimeout(() => {
        _pgDebounceTimer = null;
        dbRefreshListeners.forEach(fn => fn());
      }, 1500);
    })
    .subscribe();
}

/**
 * Leave the current family channel.
 */
export function leaveFamilyChannel() {
  if (_pgDebounceTimer) { clearTimeout(_pgDebounceTimer); _pgDebounceTimer = null; }
  if (activeChannel && supabase) {
    supabase.removeChannel(activeChannel);
    activeChannel = null;
    currentFamilyId = null;
    currentUserId = null;
  }
}

/**
 * Broadcast a chat message to all family members in real-time.
 * The message should also be saved to the local DB via useRealtimeDB.save()
 * so it persists for the sender and is synced for other members.
 */
export function broadcastChatMessage(msg: Omit<ChatBroadcast, 'timestamp'>) {
  if (!activeChannel) return;
  activeChannel.send({
    type: 'broadcast',
    event: 'chat_msg',
    payload: { ...msg, timestamp: Date.now() },
  }).catch(() => {
    console.warn('[Realtime] Chat broadcast failed');
    rejoinFamilyChannel();
  });
}

/**
 * Subscribe to incoming chat messages from other family members.
 * Returns an unsubscribe function.
 */
export function onChatMessage(listener: ChatListener): () => void {
  chatListeners.add(listener);
  return () => chatListeners.delete(listener);
}

/**
 * Subscribe to Postgres Changes notifications — fires when any table in the
 * public schema changes (debounced 1.5 s).  Use this as a backup to the
 * broadcast listener: if a broadcast is missed, this ensures the DB is still
 * refreshed.  Returns an unsubscribe function.
 */
export function onDbRefreshNeeded(listener: DbRefreshListener): () => void {
  dbRefreshListeners.add(listener);
  return () => dbRefreshListeners.delete(listener);
}

/**
 * Force-rejoin the current family channel.
 *
 * Use this when the app returns to the foreground after being backgrounded:
 * iOS/Android kill WebSockets to save battery, so the existing channel object
 * becomes a dead connection.  Unlike joinFamilyChannel(), this bypasses the
 * "already joined" guard and tears down the stale channel before resubscribing.
 */
export function rejoinFamilyChannel() {
  if (!currentFamilyId || !currentUserId) return;
  // Capture before leaveFamilyChannel clears them.
  const familyId = currentFamilyId;
  const userId = currentUserId;
  leaveFamilyChannel();
  joinFamilyChannel(familyId, userId);
}

/**
 * Broadcast a change to all family members in the channel.
 */
export function broadcastChange(msg: Omit<FamilyBroadcast, 'timestamp'>) {
  if (!activeChannel) return;
  activeChannel.send({
    type: 'broadcast',
    event: 'change',
    payload: { ...msg, timestamp: Date.now() },
  }).then((result: string) => {
    if (result !== 'ok') {
      console.warn('[Realtime] Broadcast failed, attempting rejoin...', result);
      rejoinFamilyChannel();
    }
  }).catch(() => {
    console.warn('[Realtime] Broadcast error, attempting rejoin...');
    rejoinFamilyChannel();
  });
}

/**
 * Register a listener for incoming family broadcasts.
 * Returns an unsubscribe function.
 */
export function onFamilyChange(listener: BroadcastListener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

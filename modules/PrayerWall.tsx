
import React, { useState, useMemo } from 'react';
import { createId } from '../services/id';
import {
  Heart,
  HandHeart,
  Plus,
  X,
  Check,
  Sparkles,
  Globe,
  Lock,
  ChevronDown,
  Loader2,
  MessageCircleHeart,
  PartyPopper,
  Send,
} from 'lucide-react';
import { PrayerWallEntry, PrayerWallType, Visibility, User, Family } from '../types';
import { useRealtimeDB } from '../hooks/useRealtimeDB';
import { formatDistanceToNow } from 'date-fns';
import ModuleHint from '../components/ModuleHint';

const REACTION_EMOJIS = [
  { emoji: '🙏', label: 'Praying' },
  { emoji: '❤️', label: 'Love' },
  { emoji: '🕊️', label: 'Peace' },
];

const TYPE_CONFIG: Record<PrayerWallType, { label: string; color: string; bg: string; border: string; icon: React.ElementType; emoji: string }> = {
  GRATITUDE: { label: 'Gratitude', color: 'text-amber-700', bg: 'bg-amber-50', border: 'border-amber-200', icon: Heart, emoji: '🌟' },
  REQUEST: { label: 'Prayer Request', color: 'text-indigo-700', bg: 'bg-indigo-50', border: 'border-indigo-200', icon: HandHeart, emoji: '🙏' },
  ANSWERED: { label: 'Answered Prayer', color: 'text-emerald-700', bg: 'bg-emerald-50', border: 'border-emerald-200', icon: PartyPopper, emoji: '✨' },
};

const PrayerWall: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const [activeTab, setActiveTab] = useState<PrayerWallType | 'ALL'>('ALL');
  const [isComposing, setIsComposing] = useState(false);
  const [composeType, setComposeType] = useState<PrayerWallType>('GRATITUDE');
  const [composeText, setComposeText] = useState('');
  const [composeVisibility, setComposeVisibility] = useState<Visibility>('FAMILY');
  const [markingAnswered, setMarkingAnswered] = useState<string | null>(null);
  const [answeredNote, setAnsweredNote] = useState('');

  const members = useMemo(() => {
    return db.users.reduce<Record<string, string>>((acc, u) => {
      acc[u.id] = u.name;
      return acc;
    }, {});
  }, [db.users]);

  const visibleEntries = useMemo(() => {
    return db.prayerWall
      .filter(e =>
        (e.visibility === 'FAMILY' || e.creatorId === user.id) &&
        (!e.familyId || e.familyId === family.id)
      )
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  }, [db.prayerWall, family.id, user.id]);

  const filteredEntries = useMemo(() => {
    if (activeTab === 'ALL') return visibleEntries;
    return visibleEntries.filter(e => e.type === activeTab);
  }, [visibleEntries, activeTab]);

  const stats = useMemo(() => {
    const thisMonth = visibleEntries.filter(e => {
      const d = new Date(e.date);
      const now = new Date();
      return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear();
    });
    return {
      gratitudes: thisMonth.filter(e => e.type === 'GRATITUDE').length,
      requests: thisMonth.filter(e => e.type === 'REQUEST').length,
      answered: thisMonth.filter(e => e.type === 'ANSWERED').length,
    };
  }, [visibleEntries]);

  const handlePost = () => {
    if (!composeText.trim()) return;
    const entry: PrayerWallEntry = {
      id: createId(),
      familyId: family.id,
      creatorId: user.id,
      type: composeType,
      text: composeText.trim(),
      reactions: [],
      date: new Date().toISOString(),
      visibility: composeVisibility,
    };
    const newDb = { ...db, prayerWall: [entry, ...db.prayerWall] };
    save(newDb, `shared a ${composeType === 'GRATITUDE' ? 'gratitude' : composeType === 'REQUEST' ? 'prayer request' : 'answered prayer'}`, 'Prayer Wall', '');
    setComposeText('');
    setIsComposing(false);
  };

  const handleReaction = (entryId: string, emoji: string) => {
    const updated = db.prayerWall.map(e => {
      if (e.id !== entryId) return e;
      const existing = e.reactions.find(r => r.userId === user.id && r.emoji === emoji);
      const newReactions = existing
        ? e.reactions.filter(r => !(r.userId === user.id && r.emoji === emoji))
        : [...e.reactions, { userId: user.id, emoji }];
      return { ...e, reactions: newReactions };
    });
    save({ ...db, prayerWall: updated }, 'reacted to a prayer', 'Prayer Wall', '');
  };

  const handleMarkAnswered = (requestId: string) => {
    const original = db.prayerWall.find(e => e.id === requestId);
    if (!original) return;

    // Create an ANSWERED entry linked to the original
    const answeredEntry: PrayerWallEntry = {
      id: createId(),
      familyId: family.id,
      creatorId: user.id,
      type: 'ANSWERED',
      text: answeredNote.trim() || `Prayer answered: "${original.text}"`,
      originalRequestId: requestId,
      reactions: [],
      date: new Date().toISOString(),
      visibility: original.visibility,
    };

    // Mark the original request as answered
    const updated = db.prayerWall.map(e =>
      e.id === requestId ? { ...e, answeredAt: new Date().toISOString() } : e
    );

    save(
      { ...db, prayerWall: [answeredEntry, ...updated] },
      'marked a prayer as answered',
      'Prayer Wall',
      ''
    );
    setMarkingAnswered(null);
    setAnsweredNote('');
  };

  const handleDelete = (entryId: string) => {
    const updated = db.prayerWall.filter(e => e.id !== entryId);
    save({ ...db, prayerWall: updated }, 'removed a prayer wall entry', 'Prayer Wall', '');
  };

  const tabs: { key: PrayerWallType | 'ALL'; label: string; count?: number }[] = [
    { key: 'ALL', label: 'All' },
    { key: 'GRATITUDE', label: 'Gratitude', count: stats.gratitudes },
    { key: 'REQUEST', label: 'Requests', count: stats.requests },
    { key: 'ANSWERED', label: 'Answered', count: stats.answered },
  ];

  return (
    <div className="space-y-8">
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Prayer Wall</h1>
          <p className="text-stone-500">Share gratitude, lift up prayers, and celebrate answered ones.</p>
        </div>
        <button
          onClick={() => setIsComposing(true)}
          className="flex items-center gap-2 bg-indigo-600 text-white px-5 py-2.5 rounded-2xl font-bold hover:bg-indigo-700 transition-colors shadow-sm shadow-indigo-100"
        >
          <Plus size={18} />
          New Post
        </button>
      </header>

      {/* Monthly Stats */}
      <div className="grid grid-cols-3 gap-3">
        <div className="bg-amber-50 border border-amber-100 rounded-2xl p-4 text-center">
          <p className="text-2xl font-black text-amber-700">{stats.gratitudes}</p>
          <p className="text-[10px] font-bold text-amber-500 uppercase tracking-widest">Gratitudes</p>
        </div>
        <div className="bg-indigo-50 border border-indigo-100 rounded-2xl p-4 text-center">
          <p className="text-2xl font-black text-indigo-700">{stats.requests}</p>
          <p className="text-[10px] font-bold text-indigo-500 uppercase tracking-widest">Requests</p>
        </div>
        <div className="bg-emerald-50 border border-emerald-100 rounded-2xl p-4 text-center">
          <p className="text-2xl font-black text-emerald-700">{stats.answered}</p>
          <p className="text-[10px] font-bold text-emerald-500 uppercase tracking-widest">Answered</p>
        </div>
      </div>

      {/* Compose Modal */}
      {isComposing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-lg rounded-3xl shadow-2xl overflow-hidden">
            <div className="p-6 border-b border-stone-100 flex items-center justify-between">
              <h2 className="text-xl font-bold text-stone-800">Share with your family</h2>
              <button onClick={() => setIsComposing(false)} className="p-2 text-stone-400 hover:text-stone-600 rounded-xl hover:bg-stone-100">
                <X size={20} />
              </button>
            </div>
            <div className="p-6 space-y-5">
              {/* Type selector */}
              <div className="flex gap-2">
                {(['GRATITUDE', 'REQUEST'] as PrayerWallType[]).map(t => {
                  const cfg = TYPE_CONFIG[t];
                  const active = composeType === t;
                  return (
                    <button
                      key={t}
                      onClick={() => setComposeType(t)}
                      className={`flex-1 flex items-center justify-center gap-2 py-3 rounded-2xl font-bold text-sm transition-all ${
                        active
                          ? `${cfg.bg} ${cfg.color} ${cfg.border} border-2`
                          : 'bg-stone-100 text-stone-500 border-2 border-transparent hover:bg-stone-200'
                      }`}
                    >
                      <span>{cfg.emoji}</span>
                      {cfg.label}
                    </button>
                  );
                })}
              </div>

              {/* Text input */}
              <textarea
                value={composeText}
                onChange={(e) => setComposeText(e.target.value)}
                placeholder={composeType === 'GRATITUDE'
                  ? "What are you thankful for today?"
                  : "What would you like your family to pray about?"
                }
                rows={4}
                autoFocus
                className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl text-stone-700 placeholder:text-stone-400 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm leading-relaxed resize-none"
              />

              {/* Visibility */}
              <div className="flex items-center justify-between">
                <div className="flex bg-stone-100 rounded-xl overflow-hidden border border-stone-200">
                  <button
                    onClick={() => setComposeVisibility('FAMILY')}
                    className={`flex items-center gap-1 px-3 py-2 text-xs font-bold transition-all ${composeVisibility === 'FAMILY' ? 'bg-indigo-600 text-white' : 'text-stone-500'}`}
                  >
                    <Globe size={12} /> Shared
                  </button>
                  <button
                    onClick={() => setComposeVisibility('PRIVATE')}
                    className={`flex items-center gap-1 px-3 py-2 text-xs font-bold transition-all ${composeVisibility === 'PRIVATE' ? 'bg-stone-700 text-white' : 'text-stone-500'}`}
                  >
                    <Lock size={12} /> Private
                  </button>
                </div>
                <button
                  onClick={handlePost}
                  disabled={!composeText.trim()}
                  className="flex items-center gap-2 bg-indigo-600 text-white px-6 py-2.5 rounded-xl font-bold hover:bg-indigo-700 disabled:opacity-50 transition-colors"
                >
                  <Send size={16} />
                  Post
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Mark Answered Modal */}
      {markingAnswered && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-md rounded-3xl shadow-2xl overflow-hidden">
            <div className="p-6 border-b border-stone-100">
              <h2 className="text-xl font-bold text-stone-800 flex items-center gap-2">
                <PartyPopper size={20} className="text-emerald-500" />
                Mark as Answered
              </h2>
              <p className="text-sm text-stone-500 mt-1">Celebrate how this prayer was answered!</p>
            </div>
            <div className="p-6 space-y-4">
              <textarea
                value={answeredNote}
                onChange={(e) => setAnsweredNote(e.target.value)}
                placeholder="How was this prayer answered? (optional)"
                rows={3}
                autoFocus
                className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl text-stone-700 placeholder:text-stone-400 focus:outline-none focus:ring-2 focus:ring-emerald-600/20 text-sm resize-none"
              />
              <div className="flex gap-2 justify-end">
                <button
                  onClick={() => { setMarkingAnswered(null); setAnsweredNote(''); }}
                  className="px-4 py-2.5 text-sm font-bold text-stone-500 hover:text-stone-700 transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={() => handleMarkAnswered(markingAnswered)}
                  className="flex items-center gap-2 bg-emerald-600 text-white px-5 py-2.5 rounded-xl font-bold hover:bg-emerald-700 transition-colors"
                >
                  <Check size={16} />
                  Mark Answered
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Filter Tabs */}
      <div className="flex gap-2 overflow-x-auto pb-1">
        {tabs.map(tab => (
          <button
            key={tab.key}
            onClick={() => setActiveTab(tab.key)}
            className={`flex items-center gap-1.5 px-4 py-2 rounded-full text-sm font-bold whitespace-nowrap transition-all ${
              activeTab === tab.key
                ? 'bg-indigo-600 text-white shadow-sm'
                : 'bg-stone-100 text-stone-500 hover:bg-stone-200'
            }`}
          >
            {tab.label}
            {tab.count !== undefined && (
              <span className={`text-[10px] font-black px-1.5 py-0.5 rounded-full ${
                activeTab === tab.key ? 'bg-white/20 text-white' : 'bg-stone-200 text-stone-500'
              }`}>{tab.count}</span>
            )}
          </button>
        ))}
      </div>

      {/* Prayer Wall Feed */}
      <div className="space-y-4">
        {filteredEntries.length === 0 && (
          <ModuleHint
            emoji="🙏"
            title="Share what's on your heart"
            tips={[
              '🌟 Gratitude — share something good that happened',
              '🙏 Prayer Request — invite the family to pray with you',
              '✨ Answered — celebrate when a prayer comes through',
              'React with 🙏 ❤️ or 🕊️ to encourage each other',
            ]}
          />
        )}

        {filteredEntries.map(entry => {
          const cfg = TYPE_CONFIG[entry.type];
          const isOwner = entry.creatorId === user.id;
          const isRequest = entry.type === 'REQUEST';
          const isAnswered = !!entry.answeredAt;
          const timeAgo = formatDistanceToNow(new Date(entry.date), { addSuffix: true });

          // Group reactions by emoji
          const reactionCounts = entry.reactions.reduce((acc: Record<string, { count: number; hasUser: boolean }>, r) => {
            if (!acc[r.emoji]) acc[r.emoji] = { count: 0, hasUser: false };
            acc[r.emoji].count++;
            if (r.userId === user.id) acc[r.emoji].hasUser = true;
            return acc;
          }, {});

          return (
            <div
              key={entry.id}
              className={`${cfg.bg} border ${cfg.border} rounded-3xl p-5 space-y-3 transition-all ${
                isAnswered ? 'opacity-70' : ''
              }`}
            >
              {/* Header */}
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-2.5">
                  <span className="text-xl">{cfg.emoji}</span>
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-bold text-stone-800 text-sm">{members[entry.creatorId] || 'Unknown'}</span>
                      <span className={`text-[10px] font-black uppercase tracking-widest px-2 py-0.5 rounded-full ${cfg.bg} ${cfg.color} border ${cfg.border}`}>
                        {cfg.label}
                      </span>
                      {entry.visibility === 'PRIVATE' && (
                        <Lock size={10} className="text-stone-400" />
                      )}
                      {isAnswered && (
                        <span className="text-[10px] font-black uppercase tracking-widest px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-700">
                          Answered
                        </span>
                      )}
                    </div>
                    <p className="text-[10px] text-stone-400 font-medium">{timeAgo}</p>
                  </div>
                </div>
                {isOwner && (
                  <button
                    onClick={() => handleDelete(entry.id)}
                    className="p-1.5 text-stone-300 hover:text-red-500 rounded-lg hover:bg-white/50 transition-colors"
                  >
                    <X size={14} />
                  </button>
                )}
              </div>

              {/* Content */}
              <p className="text-stone-700 leading-relaxed whitespace-pre-wrap">{entry.text}</p>

              {/* Actions */}
              <div className="flex items-center justify-between pt-1">
                {/* Reaction buttons */}
                <div className="flex items-center gap-1.5">
                  {REACTION_EMOJIS.map(r => {
                    const data = reactionCounts[r.emoji];
                    const active = data?.hasUser;
                    return (
                      <button
                        key={r.emoji}
                        onClick={() => handleReaction(entry.id, r.emoji)}
                        className={`flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-bold transition-all ${
                          active
                            ? 'bg-white shadow-sm border border-stone-200 text-stone-700'
                            : 'bg-white/50 text-stone-400 hover:bg-white hover:text-stone-600'
                        }`}
                        title={r.label}
                      >
                        <span>{r.emoji}</span>
                        {data && data.count > 0 && <span>{data.count}</span>}
                      </button>
                    );
                  })}
                </div>

                {/* Mark as answered (only for unanswered requests) */}
                {isRequest && !isAnswered && (
                  <button
                    onClick={() => setMarkingAnswered(entry.id)}
                    className="flex items-center gap-1.5 text-xs font-bold text-emerald-600 hover:text-emerald-700 bg-emerald-50 hover:bg-emerald-100 px-3 py-1.5 rounded-full transition-colors"
                  >
                    <PartyPopper size={12} />
                    Answered!
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

export default PrayerWall;

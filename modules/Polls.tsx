
import React, { useState, useMemo, useCallback, useEffect } from 'react';
import {
  Plus,
  X,
  Trash2,
  Vote,
  BarChart3,
  Clock,
  Lock,
  Eye,
  EyeOff,
  Users,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  CircleDot,
  Archive,
  Megaphone,
  Pencil,
} from 'lucide-react';
import { User, Family, Poll, PollOption, PollVote } from '../types';
import { useRealtimeDB } from '../hooks/useRealtimeDB';

const POLL_COLORS = [
  '#6366f1', '#8b5cf6', '#ec4899', '#f43f5e',
  '#f97316', '#eab308', '#22c55e', '#06b6d4',
];

function timeAgo(dateStr: string): string {
  const now = Date.now();
  const then = new Date(dateStr).getTime();
  const diff = now - then;
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(dateStr).toLocaleDateString();
}

const Polls: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);

  const [isModalOpen, setIsModalOpen] = useState(false);
  const [filter, setFilter] = useState<'OPEN' | 'CLOSED' | 'ALL'>('OPEN');
  const [expandedPoll, setExpandedPoll] = useState<string | null>(null);

  // Edit poll state
  const [editingPoll, setEditingPoll] = useState<Poll | null>(null);
  const [editQuestion, setEditQuestion] = useState('');
  const [editOptions, setEditOptions] = useState<string[]>(['', '']);
  const [editOptionKeys, setEditOptionKeys] = useState<string[]>(['', '']);
  const [editAllowMultiple, setEditAllowMultiple] = useState(false);
  const [editAnonymous, setEditAnonymous] = useState(false);
  const [editHasDeadline, setEditHasDeadline] = useState(false);
  const [editDeadline, setEditDeadline] = useState('');

  // Form state
  const [question, setQuestion] = useState('');
  const [options, setOptions] = useState<string[]>(['', '']);
  const [optionKeys, setOptionKeys] = useState<string[]>(() => [Math.random().toString(36).slice(2), Math.random().toString(36).slice(2)]);
  const [allowMultiple, setAllowMultiple] = useState(false);
  const [anonymous, setAnonymous] = useState(false);
  const [hasDeadline, setHasDeadline] = useState(false);
  const [deadline, setDeadline] = useState('');

  // Family members lookup
  const familyMembers = useMemo(() => {
    const memberIds = (Array.isArray(db.familyMembers) ? db.familyMembers : [])
      .filter((m) => m.familyId === family.id)
      .map((m) => m.userId);
    return (Array.isArray(db.users) ? db.users : []).filter((u) => memberIds.includes(u.id));
  }, [db.familyMembers, db.users, family.id]);

  const getUserName = useCallback(
    (id: string) => {
      const u = familyMembers.find((m) => m.id === id);
      return u?.name || 'Unknown';
    },
    [familyMembers],
  );

  // Polls for this family
  const polls = useMemo(() => {
    return (Array.isArray(db.polls) ? db.polls : [])
      .filter(
        (p) =>
          p.familyId === family.id &&
          (p.visibility === 'FAMILY' || p.creatorId === user.id),
      )
      .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
  }, [db.polls, family.id, user.id]);

  const filteredPolls = useMemo(() => {
    if (filter === 'ALL') return polls;
    return polls.filter((p) => p.status === filter);
  }, [polls, filter]);

  const votes = useMemo(() => {
    return (Array.isArray(db.pollVotes) ? db.pollVotes : []).filter((v) => v.familyId === family.id);
  }, [db.pollVotes, family.id]);

  // Auto-close expired polls on mount and family switch.
  // Depend only on family.id (not db.polls) to avoid re-triggering when save()
  // updates db.polls, which would cause a wasteful render loop.
  useEffect(() => {
    const now = new Date().toISOString();
    const allPolls = Array.isArray(db.polls) ? db.polls : [];
    const toClose = allPolls.filter(
      (p) => p.familyId === family.id && p.status === 'OPEN' && p.deadline && p.deadline < now,
    );
    if (toClose.length > 0) {
      const newPolls = allPolls.map((p) =>
        toClose.some((tc) => tc.id === p.id) ? { ...p, status: 'CLOSED' as const } : p,
      );
      save({ ...db, polls: newPolls });
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [family.id]);

  // Helpers
  const getVotesForPoll = (pollId: string) => votes.filter((v) => v.pollId === pollId);

  const getMyVotes = (pollId: string) =>
    votes.filter((v) => v.pollId === pollId && v.userId === user.id);

  const hasVoted = (pollId: string) => getMyVotes(pollId).length > 0;

  const genKey = () => Math.random().toString(36).slice(2);

  const resetForm = () => {
    setQuestion('');
    setOptions(['', '']);
    setOptionKeys([genKey(), genKey()]);
    setAllowMultiple(false);
    setAnonymous(false);
    setHasDeadline(false);
    setDeadline('');
  };

  const addOption = () => {
    if (options.length < 8) { setOptions([...options, '']); setOptionKeys([...optionKeys, genKey()]); }
  };

  const removeOption = (idx: number) => {
    if (options.length > 2) { setOptions(options.filter((_, i) => i !== idx)); setOptionKeys(optionKeys.filter((_, i) => i !== idx)); }
  };

  const updateOption = (idx: number, value: string) => {
    setOptions(options.map((o, i) => (i === idx ? value : o)));
  };

  const createPoll = () => {
    const validOptions = options.filter((o) => o.trim());
    if (!question.trim() || validOptions.length < 2) return;

    const newPoll: Poll = {
      id: Math.random().toString(36).substr(2, 9),
      familyId: family.id,
      creatorId: user.id,
      question: question.trim(),
      options: validOptions.map((text) => ({
        id: Math.random().toString(36).substr(2, 9),
        text: text.trim(),
      })),
      allowMultiple,
      anonymous,
      status: 'OPEN',
      deadline: hasDeadline && deadline ? new Date(deadline).toISOString() : undefined,
      visibility: 'FAMILY',
      createdAt: new Date().toISOString(),
    };

    const newDb = { ...db, polls: [...(Array.isArray(db.polls) ? db.polls : []), newPoll] };
    save(newDb, 'created a poll', 'Polls', question.trim());
    setIsModalOpen(false);
    resetForm();
  };

  const castVote = (pollId: string, optionId: string) => {
    const poll = polls.find((p) => p.id === pollId);
    if (!poll || poll.status === 'CLOSED') return;

    const myVotes = getMyVotes(pollId);
    const alreadyVotedThis = myVotes.find((v) => v.optionId === optionId);

    if (alreadyVotedThis) {
      // Unvote
      const newVotes = (Array.isArray(db.pollVotes) ? db.pollVotes : []).filter((v) => v.id !== alreadyVotedThis.id);
      const newDb = { ...db, pollVotes: newVotes };
      save(newDb, 'changed their vote', 'Polls', poll.question);
      return;
    }

    if (!poll.allowMultiple && myVotes.length > 0) {
      // Replace existing vote
      const newVote: PollVote = {
        id: Math.random().toString(36).substr(2, 9),
        pollId,
        optionId,
        userId: user.id,
        familyId: family.id,
        votedAt: new Date().toISOString(),
      };
      const cleaned = (Array.isArray(db.pollVotes) ? db.pollVotes : []).filter(
        (v) => !(v.pollId === pollId && v.userId === user.id),
      );
      const newDb = { ...db, pollVotes: [...cleaned, newVote] };
      save(newDb, 'voted on a poll', 'Polls', poll.question);
    } else {
      // Add new vote
      const newVote: PollVote = {
        id: Math.random().toString(36).substr(2, 9),
        pollId,
        optionId,
        userId: user.id,
        familyId: family.id,
        votedAt: new Date().toISOString(),
      };
      const newDb = { ...db, pollVotes: [...(Array.isArray(db.pollVotes) ? db.pollVotes : []), newVote] };
      save(newDb, 'voted on a poll', 'Polls', poll.question);
    }
  };

  const closePoll = (pollId: string) => {
    const poll = polls.find((p) => p.id === pollId);
    const newPolls = (Array.isArray(db.polls) ? db.polls : []).map((p) =>
      p.id === pollId ? { ...p, status: 'CLOSED' as const } : p,
    );
    const newDb = { ...db, polls: newPolls };
    save(newDb, 'closed a poll', 'Polls', poll?.question || '');
  };

  const reopenPoll = (pollId: string) => {
    const poll = polls.find((p) => p.id === pollId);
    const newPolls = (Array.isArray(db.polls) ? db.polls : []).map((p) =>
      p.id === pollId ? { ...p, status: 'OPEN' as const } : p,
    );
    const newDb = { ...db, polls: newPolls };
    save(newDb, 'reopened a poll', 'Polls', poll?.question || '');
  };

  const openEditPoll = (poll: Poll) => {
    setEditingPoll(poll);
    setEditQuestion(poll.question);
    setEditOptions(poll.options.map(o => o.text));
    setEditOptionKeys(poll.options.map(o => o.id));
    setEditAllowMultiple(poll.allowMultiple);
    setEditAnonymous(poll.anonymous);
    setEditHasDeadline(!!poll.deadline);
    setEditDeadline(poll.deadline ? new Date(poll.deadline).toISOString().slice(0, 16) : '');
  };

  const addEditOption = () => {
    if (editOptions.length < 8) { setEditOptions([...editOptions, '']); setEditOptionKeys([...editOptionKeys, genKey()]); }
  };

  const removeEditOption = (idx: number) => {
    if (editOptions.length > 2) { setEditOptions(editOptions.filter((_, i) => i !== idx)); setEditOptionKeys(editOptionKeys.filter((_, i) => i !== idx)); }
  };

  const updateEditOption = (idx: number, value: string) => {
    setEditOptions(editOptions.map((o, i) => (i === idx ? value : o)));
  };

  const updatePoll = () => {
    if (!editingPoll) return;
    const validOptions = editOptions.filter(o => o.trim());
    if (!editQuestion.trim() || validOptions.length < 2) return;

    // Map existing options by matching text to preserve vote associations
    const usedIds = new Set<string>();
    const newOptions: PollOption[] = validOptions.map((text) => {
      const trimmed = text.trim();
      const textMatch = editingPoll.options.find(o => o.text === trimmed && !usedIds.has(o.id));
      if (textMatch) { usedIds.add(textMatch.id); return { id: textMatch.id, text: trimmed }; }
      return { id: Math.random().toString(36).substr(2, 9), text: trimmed };
    });

    // Remove votes for options that no longer exist
    const validOptionIds = new Set(newOptions.map(o => o.id));
    const cleanedVotes = (Array.isArray(db.pollVotes) ? db.pollVotes : []).filter(
      v => v.pollId !== editingPoll.id || validOptionIds.has(v.optionId)
    );

    const newPolls = (Array.isArray(db.polls) ? db.polls : []).map(p =>
      p.id === editingPoll.id
        ? {
            ...p,
            question: editQuestion.trim(),
            options: newOptions,
            allowMultiple: editAllowMultiple,
            anonymous: editAnonymous,
            deadline: editHasDeadline && editDeadline ? new Date(editDeadline).toISOString() : undefined,
          }
        : p
    );
    save({ ...db, polls: newPolls, pollVotes: cleanedVotes }, 'updated a poll', 'Polls', editQuestion.trim());
    setEditingPoll(null);
  };

  const deletePoll = (pollId: string) => {
    if (!window.confirm('Delete this poll and all its votes? This cannot be undone.')) return;
    const poll = polls.find((p) => p.id === pollId);
    const newPolls = (Array.isArray(db.polls) ? db.polls : []).filter((p) => p.id !== pollId);
    const newVotes = (Array.isArray(db.pollVotes) ? db.pollVotes : []).filter((v) => v.pollId !== pollId);
    const newDb = { ...db, polls: newPolls, pollVotes: newVotes };
    save(newDb, 'deleted a poll', 'Polls', poll?.question || '');
  };

  const openCount = polls.filter((p) => p.status === 'OPEN').length;
  const closedCount = polls.filter((p) => p.status === 'CLOSED').length;

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-black text-stone-800 tracking-tight">Family Polls</h1>
          <p className="text-stone-500 text-sm mt-1">Decide things together</p>
        </div>
        <button
          onClick={() => {
            resetForm();
            setIsModalOpen(true);
          }}
          className="flex items-center space-x-2 bg-indigo-600 text-white px-5 py-3 rounded-2xl font-bold hover:bg-indigo-700 shadow-lg shadow-indigo-100 transition-all"
        >
          <Plus size={18} />
          <span>New Poll</span>
        </button>
      </div>

      {/* Stats Bar */}
      <div className="grid grid-cols-3 gap-4">
        <div className="bg-white rounded-2xl border border-stone-200 p-4 shadow-sm">
          <div className="flex items-center justify-between mb-1">
            <Megaphone size={18} className="text-indigo-500" />
          </div>
          <p className="text-2xl font-black text-stone-900">{polls.length}</p>
          <p className="text-xs text-stone-400 font-medium">Total Polls</p>
        </div>
        <div className="bg-white rounded-2xl border border-stone-200 p-4 shadow-sm">
          <div className="flex items-center justify-between mb-1">
            <Vote size={18} className="text-emerald-500" />
          </div>
          <p className="text-2xl font-black text-stone-900">{openCount}</p>
          <p className="text-xs text-stone-400 font-medium">Open Now</p>
        </div>
        <div className="bg-white rounded-2xl border border-stone-200 p-4 shadow-sm">
          <div className="flex items-center justify-between mb-1">
            <BarChart3 size={18} className="text-violet-500" />
          </div>
          <p className="text-2xl font-black text-stone-900">
            {votes.filter((v) => v.userId === user.id).length}
          </p>
          <p className="text-xs text-stone-400 font-medium">My Votes</p>
        </div>
      </div>

      {/* Filter Tabs */}
      <div className="flex space-x-2">
        {(['OPEN', 'CLOSED', 'ALL'] as const).map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`px-4 py-2 rounded-xl text-sm font-bold transition-all ${
              filter === f
                ? 'bg-indigo-100 text-indigo-700 ring-2 ring-indigo-400'
                : 'bg-stone-50 text-stone-500 hover:bg-stone-100'
            }`}
          >
            {f === 'OPEN' ? `Open (${openCount})` : f === 'CLOSED' ? `Closed (${closedCount})` : `All (${polls.length})`}
          </button>
        ))}
      </div>

      {/* Poll List */}
      {filteredPolls.length === 0 ? (
        <div className="bg-white rounded-3xl border border-stone-200 p-12 text-center">
          <Vote size={40} className="mx-auto mb-3 text-stone-300" />
          <p className="font-medium text-stone-500">
            {filter === 'OPEN' ? 'No open polls' : filter === 'CLOSED' ? 'No closed polls' : 'No polls yet'}
          </p>
          <p className="text-sm text-stone-400 mt-1">Create one to get the family voting!</p>
        </div>
      ) : (
        <div className="space-y-4">
          {filteredPolls.map((poll) => {
            const pollVotes = getVotesForPoll(poll.id);
            const totalVotes = pollVotes.length;
            const myVotes = getMyVotes(poll.id);
            const voted = myVotes.length > 0;
            const isExpanded = expandedPoll === poll.id;
            const isCreator = poll.creatorId === user.id;
            const isOpen = poll.status === 'OPEN';

            // Unique voters
            const uniqueVoters = new Set(pollVotes.map((v) => v.userId)).size;

            // Winner(s) - option(s) with most votes
            const optionCounts = poll.options.map((opt) => ({
              ...opt,
              count: pollVotes.filter((v) => v.optionId === opt.id).length,
            }));
            const maxVotes = Math.max(...optionCounts.map((o) => o.count), 0);

            return (
              <div
                key={poll.id}
                className={`bg-white rounded-3xl border shadow-sm overflow-hidden transition-all ${
                  isOpen ? 'border-stone-200' : 'border-stone-100 opacity-80'
                }`}
              >
                {/* Poll Header */}
                <div className="p-6">
                  <div className="flex items-start justify-between mb-1">
                    <div className="flex items-center space-x-2 flex-1 min-w-0">
                      {isOpen ? (
                        <div className="shrink-0 w-8 h-8 rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center">
                          <CircleDot size={16} />
                        </div>
                      ) : (
                        <div className="shrink-0 w-8 h-8 rounded-full bg-stone-100 text-stone-400 flex items-center justify-center">
                          <Archive size={16} />
                        </div>
                      )}
                      <div className="min-w-0 flex-1">
                        <h3 className="font-bold text-stone-800 text-lg leading-tight">{poll.question}</h3>
                        <div className="flex items-center space-x-3 mt-1 text-xs text-stone-400">
                          <span>by {poll.creatorId === user.id ? 'You' : getUserName(poll.creatorId)}</span>
                          <span>{timeAgo(poll.createdAt)}</span>
                          {poll.anonymous && (
                            <span className="flex items-center space-x-1">
                              <EyeOff size={10} />
                              <span>Anonymous</span>
                            </span>
                          )}
                          {poll.allowMultiple && (
                            <span className="flex items-center space-x-1">
                              <CheckCircle2 size={10} />
                              <span>Multi-select</span>
                            </span>
                          )}
                          {poll.deadline && (
                            <span className="flex items-center space-x-1">
                              <Clock size={10} />
                              <span>Ends {new Date(poll.deadline).toLocaleDateString()}</span>
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                    <div className="flex items-center space-x-2 shrink-0 ml-3">
                      <span className="text-xs font-bold text-stone-400">
                        {uniqueVoters} voter{uniqueVoters !== 1 ? 's' : ''}
                      </span>
                      {isCreator && (
                        <div className="flex items-center space-x-1">
                          <button
                            onClick={() => openEditPoll(poll)}
                            className="p-1.5 hover:bg-indigo-50 rounded-lg transition-colors text-stone-400 hover:text-indigo-600"
                            title="Edit poll"
                          >
                            <Pencil size={14} />
                          </button>
                          {isOpen ? (
                            <button
                              onClick={() => closePoll(poll.id)}
                              className="p-1.5 hover:bg-stone-100 rounded-lg transition-colors text-stone-400 hover:text-stone-600"
                              title="Close poll"
                            >
                              <Lock size={14} />
                            </button>
                          ) : (
                            <button
                              onClick={() => reopenPoll(poll.id)}
                              className="p-1.5 hover:bg-emerald-50 rounded-lg transition-colors text-stone-400 hover:text-emerald-600"
                              title="Reopen poll"
                            >
                              <Vote size={14} />
                            </button>
                          )}
                          <button
                            onClick={() => deletePoll(poll.id)}
                            className="p-1.5 hover:bg-red-50 rounded-lg transition-colors text-stone-400 hover:text-red-500"
                            title="Delete poll"
                          >
                            <Trash2 size={14} />
                          </button>
                        </div>
                      )}
                    </div>
                  </div>

                  {/* Options / Results */}
                  <div className="mt-4 space-y-2">
                    {optionCounts.map((opt, idx) => {
                      const pct = totalVotes > 0 ? Math.round((opt.count / totalVotes) * 100) : 0;
                      const isMyVote = myVotes.some((v) => v.optionId === opt.id);
                      const isWinner = !isOpen && opt.count === maxVotes && maxVotes > 0;
                      const barColor = POLL_COLORS[idx % POLL_COLORS.length];

                      return (
                        <button
                          key={opt.id}
                          onClick={() => isOpen && castVote(poll.id, opt.id)}
                          disabled={!isOpen}
                          className={`w-full text-left p-3 rounded-2xl border transition-all relative overflow-hidden group ${
                            isMyVote
                              ? 'border-indigo-300 bg-indigo-50/50'
                              : isOpen
                                ? 'border-stone-200 hover:border-stone-300 bg-stone-50/50'
                                : 'border-stone-100 bg-stone-50/30'
                          }`}
                        >
                          {/* Background bar */}
                          {(voted || !isOpen) && (
                            <div
                              className="absolute inset-y-0 left-0 transition-all duration-500 rounded-2xl opacity-15"
                              style={{
                                width: `${pct}%`,
                                backgroundColor: barColor,
                              }}
                            />
                          )}
                          <div className="relative flex items-center justify-between">
                            <div className="flex items-center space-x-3 min-w-0">
                              {isOpen && !voted ? (
                                <div
                                  className={`w-5 h-5 rounded-full border-2 shrink-0 transition-all ${
                                    isMyVote
                                      ? 'border-indigo-500 bg-indigo-500'
                                      : 'border-stone-300 group-hover:border-stone-400'
                                  }`}
                                >
                                  {isMyVote && (
                                    <svg className="w-full h-full text-white" viewBox="0 0 20 20" fill="currentColor">
                                      <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                                    </svg>
                                  )}
                                </div>
                              ) : isMyVote ? (
                                <div className="w-5 h-5 rounded-full bg-indigo-500 shrink-0 flex items-center justify-center">
                                  <svg className="w-3 h-3 text-white" viewBox="0 0 20 20" fill="currentColor">
                                    <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                                  </svg>
                                </div>
                              ) : null}
                              <span
                                className={`text-sm font-semibold truncate ${
                                  isWinner ? 'text-stone-900' : 'text-stone-700'
                                }`}
                              >
                                {opt.text}
                                {isWinner && ' 🏆'}
                              </span>
                            </div>
                            {(voted || !isOpen) && (
                              <div className="flex items-center space-x-2 shrink-0">
                                <span className="text-xs font-bold" style={{ color: barColor }}>
                                  {pct}%
                                </span>
                                <span className="text-xs text-stone-400">({opt.count})</span>
                              </div>
                            )}
                          </div>
                        </button>
                      );
                    })}
                  </div>

                  {/* Expand for voter details */}
                  {!poll.anonymous && totalVotes > 0 && (
                    <button
                      onClick={() => setExpandedPoll(isExpanded ? null : poll.id)}
                      className="flex items-center space-x-1 mt-3 text-xs text-stone-400 hover:text-stone-600 transition-colors"
                    >
                      {isExpanded ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                      <span>{isExpanded ? 'Hide' : 'Show'} who voted</span>
                    </button>
                  )}
                </div>

                {/* Voter details */}
                {isExpanded && !poll.anonymous && (
                  <div className="px-6 pb-5 border-t border-stone-100 pt-4">
                    <div className="space-y-3">
                      {poll.options.map((opt, idx) => {
                        const optVotes = pollVotes.filter((v) => v.optionId === opt.id);
                        if (optVotes.length === 0) return null;
                        return (
                          <div key={opt.id}>
                            <p className="text-xs font-bold text-stone-500 mb-1.5">{opt.text}</p>
                            <div className="flex flex-wrap gap-1.5">
                              {optVotes.map((v) => (
                                <span
                                  key={v.id}
                                  className="inline-flex items-center space-x-1.5 px-2.5 py-1 rounded-full text-xs font-medium"
                                  style={{
                                    backgroundColor: POLL_COLORS[idx % POLL_COLORS.length] + '15',
                                    color: POLL_COLORS[idx % POLL_COLORS.length],
                                  }}
                                >
                                  <div
                                    className="w-4 h-4 rounded-full flex items-center justify-center text-[8px] font-black text-white"
                                    style={{ backgroundColor: POLL_COLORS[idx % POLL_COLORS.length] }}
                                  >
                                    {getUserName(v.userId)[0]}
                                  </div>
                                  <span>{v.userId === user.id ? 'You' : getUserName(v.userId).split(' ')[0]}</span>
                                </span>
                              ))}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Create Poll Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-3xl max-w-lg w-full max-h-[90vh] overflow-y-auto p-6 shadow-2xl">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold text-stone-800">New Poll</h2>
              <button
                onClick={() => {
                  setIsModalOpen(false);
                  resetForm();
                }}
                className="p-2 hover:bg-stone-100 rounded-xl transition-colors"
              >
                <X size={20} className="text-stone-400" />
              </button>
            </div>

            <div className="space-y-5">
              {/* Question */}
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                  Question
                </label>
                <input
                  type="text"
                  placeholder="What should we decide?"
                  value={question}
                  onChange={(e) => setQuestion(e.target.value)}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
                  autoFocus
                />
              </div>

              {/* Options */}
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                  Options
                </label>
                <div className="space-y-2">
                  {options.map((opt, idx) => (
                    <div key={optionKeys[idx] ?? idx} className="flex items-center space-x-2">
                      <div
                        className="w-3 h-3 rounded-full shrink-0"
                        style={{ backgroundColor: POLL_COLORS[idx % POLL_COLORS.length] }}
                      />
                      <input
                        type="text"
                        placeholder={`Option ${idx + 1}`}
                        value={opt}
                        onChange={(e) => updateOption(idx, e.target.value)}
                        className="flex-1 px-4 py-2.5 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm text-stone-900 placeholder:text-stone-400"
                      />
                      {options.length > 2 && (
                        <button
                          onClick={() => removeOption(idx)}
                          className="p-1.5 hover:bg-red-50 rounded-lg text-stone-300 hover:text-red-400 transition-colors"
                        >
                          <X size={14} />
                        </button>
                      )}
                    </div>
                  ))}
                </div>
                {options.length < 8 && (
                  <button
                    onClick={addOption}
                    className="mt-2 text-sm text-indigo-600 font-semibold hover:text-indigo-700 flex items-center space-x-1"
                  >
                    <Plus size={14} />
                    <span>Add Option</span>
                  </button>
                )}
              </div>

              {/* Settings */}
              <div className="space-y-3">
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider">
                  Settings
                </label>
                <div className="grid grid-cols-2 gap-3">
                  <button
                    onClick={() => setAllowMultiple(!allowMultiple)}
                    className={`flex items-center space-x-2 p-3 rounded-xl border text-sm font-medium transition-all ${
                      allowMultiple
                        ? 'border-indigo-300 bg-indigo-50 text-indigo-700'
                        : 'border-stone-200 bg-stone-50 text-stone-500'
                    }`}
                  >
                    <CheckCircle2 size={16} />
                    <span>Multi-select</span>
                  </button>
                  <button
                    onClick={() => setAnonymous(!anonymous)}
                    className={`flex items-center space-x-2 p-3 rounded-xl border text-sm font-medium transition-all ${
                      anonymous
                        ? 'border-indigo-300 bg-indigo-50 text-indigo-700'
                        : 'border-stone-200 bg-stone-50 text-stone-500'
                    }`}
                  >
                    <EyeOff size={16} />
                    <span>Anonymous</span>
                  </button>
                </div>

                {/* Deadline */}
                <button
                  onClick={() => setHasDeadline(!hasDeadline)}
                  className={`flex items-center space-x-2 p-3 rounded-xl border text-sm font-medium transition-all w-full ${
                    hasDeadline
                      ? 'border-indigo-300 bg-indigo-50 text-indigo-700'
                      : 'border-stone-200 bg-stone-50 text-stone-500'
                  }`}
                >
                  <Clock size={16} />
                  <span>Set Deadline</span>
                </button>
                {hasDeadline && (
                  <input
                    type="datetime-local"
                    value={deadline}
                    onChange={(e) => setDeadline(e.target.value)}
                    className="w-full px-4 py-2.5 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm text-stone-900"
                  />
                )}
              </div>

              {/* Create Button */}
              <button
                onClick={createPoll}
                disabled={!question.trim() || options.filter((o) => o.trim()).length < 2}
                className="w-full bg-indigo-600 text-white py-3.5 rounded-2xl font-bold hover:bg-indigo-700 shadow-lg shadow-indigo-100 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
              >
                Create Poll
              </button>
            </div>
          </div>
        </div>
      )}
      {/* Edit Poll Modal */}
      {editingPoll && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-3xl max-w-lg w-full max-h-[90vh] overflow-y-auto p-6 shadow-2xl">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold text-stone-800">Edit Poll</h2>
              <button onClick={() => setEditingPoll(null)} className="p-2 hover:bg-stone-100 rounded-xl transition-colors">
                <X size={20} className="text-stone-400" />
              </button>
            </div>

            <div className="space-y-5">
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">Question</label>
                <input type="text" placeholder="What should we decide?" value={editQuestion}
                  onChange={(e) => setEditQuestion(e.target.value)}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
                  autoFocus />
              </div>

              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">Options</label>
                <div className="space-y-2">
                  {editOptions.map((opt, idx) => (
                    <div key={editOptionKeys[idx] ?? idx} className="flex items-center space-x-2">
                      <div className="w-3 h-3 rounded-full shrink-0" style={{ backgroundColor: POLL_COLORS[idx % POLL_COLORS.length] }} />
                      <input type="text" placeholder={`Option ${idx + 1}`} value={opt}
                        onChange={(e) => updateEditOption(idx, e.target.value)}
                        className="flex-1 px-4 py-2.5 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm text-stone-900 placeholder:text-stone-400" />
                      {editOptions.length > 2 && (
                        <button onClick={() => removeEditOption(idx)} className="p-1.5 hover:bg-red-50 rounded-lg text-stone-300 hover:text-red-400 transition-colors">
                          <X size={14} />
                        </button>
                      )}
                    </div>
                  ))}
                </div>
                {editOptions.length < 8 && (
                  <button onClick={addEditOption} className="mt-2 text-sm text-indigo-600 font-semibold hover:text-indigo-700 flex items-center space-x-1">
                    <Plus size={14} /><span>Add Option</span>
                  </button>
                )}
              </div>

              <div className="space-y-3">
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider">Settings</label>
                <div className="grid grid-cols-2 gap-3">
                  <button onClick={() => setEditAllowMultiple(!editAllowMultiple)}
                    className={`flex items-center space-x-2 p-3 rounded-xl border text-sm font-medium transition-all ${editAllowMultiple ? 'border-indigo-300 bg-indigo-50 text-indigo-700' : 'border-stone-200 bg-stone-50 text-stone-500'}`}>
                    <CheckCircle2 size={16} /><span>Multi-select</span>
                  </button>
                  <button onClick={() => setEditAnonymous(!editAnonymous)}
                    className={`flex items-center space-x-2 p-3 rounded-xl border text-sm font-medium transition-all ${editAnonymous ? 'border-indigo-300 bg-indigo-50 text-indigo-700' : 'border-stone-200 bg-stone-50 text-stone-500'}`}>
                    <EyeOff size={16} /><span>Anonymous</span>
                  </button>
                </div>
                <button onClick={() => setEditHasDeadline(!editHasDeadline)}
                  className={`flex items-center space-x-2 p-3 rounded-xl border text-sm font-medium transition-all w-full ${editHasDeadline ? 'border-indigo-300 bg-indigo-50 text-indigo-700' : 'border-stone-200 bg-stone-50 text-stone-500'}`}>
                  <Clock size={16} /><span>Set Deadline</span>
                </button>
                {editHasDeadline && (
                  <input type="datetime-local" value={editDeadline} onChange={(e) => setEditDeadline(e.target.value)}
                    className="w-full px-4 py-2.5 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm text-stone-900" />
                )}
              </div>

              <button onClick={updatePoll}
                disabled={!editQuestion.trim() || editOptions.filter(o => o.trim()).length < 2}
                className="w-full bg-indigo-600 text-white py-3.5 rounded-2xl font-bold hover:bg-indigo-700 shadow-lg shadow-indigo-100 transition-all disabled:opacity-40 disabled:cursor-not-allowed">
                Save Changes
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default Polls;


import React, { useState, useMemo, useCallback, useEffect } from 'react';
import { useLocale } from '../contexts/LocaleContext';
import {
  Plus,
  Check,
  X,
  Trash2,
  Edit3,
  Star,
  Trophy,
  Flame,
  RotateCcw,
  ChevronLeft,
  ChevronRight,
  Crown,
  Sparkles,
  Users,
  Clock,
  CheckCircle2,
  XCircle,
  ShieldCheck,
} from 'lucide-react';
import { User, Family, Chore, ChoreCompletion } from '../types';
import { useRealtimeDB } from '../hooks/useRealtimeDB';
import { createId } from '../services/id';
import ModuleHint from '../components/ModuleHint';

const CHORE_ICONS = ['🧹', '🍽️', '🗑️', '🐕', '🧺', '🛁', '🌿', '🚗', '📚', '🛏️', '🧽', '💊', '🐱', '🏠', '🪣', '🧸'];
const CHORE_COLORS = [
  '#6366f1', '#8b5cf6', '#a855f7', '#d946ef',
  '#ec4899', '#f43f5e', '#ef4444', '#f97316',
  '#f59e0b', '#eab308', '#84cc16', '#22c55e',
  '#14b8a6', '#06b6d4', '#3b82f6', '#6366f1',
];

const DAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const DAY_LABELS_SHORT = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

// Returns yyyy-MM-dd in the browser's local timezone (fixes the UTC date bug)
function toLocalDateStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function getWeekDates(offset: number): string[] {
  const now = new Date();
  now.setDate(now.getDate() + offset * 7);
  const dayOfWeek = now.getDay();
  const startOfWeek = new Date(now);
  startOfWeek.setDate(now.getDate() - dayOfWeek);
  const dates: string[] = [];
  for (let i = 0; i < 7; i++) {
    const d = new Date(startOfWeek);
    d.setDate(startOfWeek.getDate() + i);
    dates.push(toLocalDateStr(d));
  }
  return dates;
}

function getStreak(choreId: string, userId: string, completions: ChoreCompletion[], chore: Chore): number {
  const today = new Date();
  let streak = 0;
  for (let i = 0; i < 365; i++) {
    const d = new Date(today);
    d.setDate(today.getDate() - i);
    const dateStr = toLocalDateStr(d);
    const dayOfWeek = d.getDay();

    // Check if this day is a scheduled day for the chore
    const isScheduled =
      chore.frequency === 'DAILY' ||
      chore.daysOfWeek.includes(dayOfWeek);

    if (!isScheduled) continue;

    const done = completions.some(
      (c) => c.choreId === choreId && c.userId === userId && c.date === dateStr,
    );
    if (done) {
      streak++;
    } else {
      // Skip today if not yet done (don't break streak)
      if (i === 0) continue;
      break;
    }
  }
  return streak;
}

const Chores: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const { todayStr, fmtCurrency, currencySymbol } = useLocale();

  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingChore, setEditingChore] = useState<Chore | null>(null);
  const [weekOffset, setWeekOffset] = useState(0);

  // Form state
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [icon, setIcon] = useState('🧹');
  const [points, setPoints] = useState(10);
  const [frequency, setFrequency] = useState<'DAILY' | 'WEEKLY' | 'CUSTOM'>('DAILY');
  const [daysOfWeek, setDaysOfWeek] = useState<number[]>([1, 2, 3, 4, 5]); // weekdays
  const [selectedAssignees, setSelectedAssignees] = useState<string[]>([user.id]);
  const [color, setColor] = useState(CHORE_COLORS[0]);
  const [reward, setReward] = useState(0);
  const [requiresApproval, setRequiresApproval] = useState(false);

  // Family members lookup
  const familyMembers = useMemo(() => {
    const memberIds = (Array.isArray(db.familyMembers) ? db.familyMembers : [])
      .filter((m) => m.familyId === family.id)
      .map((m) => m.userId);
    return (Array.isArray(db.users) ? db.users : []).filter((u) => memberIds.includes(u.id));
  }, [db.familyMembers, db.users, family.id]);

  const isAdmin = useMemo(() => {
    const membership = (Array.isArray(db.familyMembers) ? db.familyMembers : []).find(m => m.userId === user.id && m.familyId === family.id);
    return membership?.role === 'ADMIN' || membership?.role === 'PARENT';
  }, [db.familyMembers, user.id, family.id]);

  const getUserName = useCallback(
    (id: string) => {
      const u = familyMembers.find((m) => m.id === id);
      return u?.name || 'Unknown';
    },
    [familyMembers],
  );

  // Chores for this family
  const chores = useMemo(() => {
    return (Array.isArray(db.chores) ? db.chores : []).filter(
      (c) =>
        c.familyId === family.id &&
        (c.visibility === 'FAMILY' || c.creatorId === user.id),
    );
  }, [db.chores, family.id, user.id]);

  const completions = useMemo(() => {
    return (Array.isArray(db.choreCompletions) ? db.choreCompletions : []).filter((c) => c.familyId === family.id);
  }, [db.choreCompletions, family.id]);

  const weekDates = useMemo(() => getWeekDates(weekOffset), [weekOffset]);
  const today = todayStr();

  // Leaderboard — only count approved completions (or completions without approval requirement)
  const leaderboard = useMemo(() => {
    const scores: Record<string, number> = {};
    completions
      .filter(c => !c.approvalStatus || c.approvalStatus === 'APPROVED')
      .forEach((c) => {
        const chore = (Array.isArray(db.chores) ? db.chores : []).find((ch) => ch.id === c.choreId);
        if (chore) {
          scores[c.userId] = (scores[c.userId] || 0) + chore.points;
        }
      });
    return Object.entries(scores)
      .map(([userId, totalPoints]) => ({ userId, name: getUserName(userId), totalPoints }))
      .sort((a, b) => b.totalPoints - a.totalPoints);
  }, [completions, db.chores, getUserName]);

  // Today's progress — include `today` in deps so it re-evaluates after midnight
  const todaysChores = useMemo(() => {
    const dayOfWeek = new Date(today + 'T12:00:00').getDay();
    return chores.filter(
      (c) =>
        c.frequency === 'DAILY' || c.daysOfWeek.includes(dayOfWeek),
    );
  }, [chores, today]);

  const todaysCompletions = useMemo(() => {
    return completions.filter((c) => c.date === today && c.userId === user.id);
  }, [completions, today, user.id]);

  const myTodayChores = useMemo(() => {
    return todaysChores.filter((c) => c.assignees.includes(user.id));
  }, [todaysChores, user.id]);

  const myTodayDone = useMemo(() => {
    return myTodayChores.filter((c) =>
      todaysCompletions.some((tc) => tc.choreId === c.id),
    ).length;
  }, [myTodayChores, todaysCompletions]);

  // Helpers
  // Check if any family member completed this chore on the given date (excluding rejected).
  const isChoreCompletedOnDate = (choreId: string, date: string) => {
    return completions.some(
      (c) => c.choreId === choreId && c.date === date && c.approvalStatus !== 'REJECTED',
    );
  };

  const toggleCompletion = (choreId: string, date: string) => {
    const chore = chores.find((c) => c.id === choreId);
    const existing = completions.find(
      (c) => c.choreId === choreId && c.userId === user.id && c.date === date,
    );
    if (existing) {
      // Undo — only if not yet approved
      if (existing.approvalStatus === 'APPROVED') return; // can't undo an approved completion
      const newCompletions = (Array.isArray(db.choreCompletions) ? db.choreCompletions : []).filter((c) => c.id !== existing.id);
      const newDb = { ...db, choreCompletions: newCompletions };
      save(newDb, 'unchecked a chore', 'Chores', chore?.title || '');
    } else {
      // Complete — set to PENDING if approval required and user is not admin
      const needsApproval = chore?.requiresApproval && !isAdmin;
      const newCompletion: ChoreCompletion = {
        id: createId(),
        choreId,
        userId: user.id,
        familyId: family.id,
        date,
        completedAt: new Date().toISOString(),
        ...(needsApproval ? { approvalStatus: 'PENDING' as const } : {}),
      };
      const newDb = {
        ...db,
        choreCompletions: [...(Array.isArray(db.choreCompletions) ? db.choreCompletions : []), newCompletion],
      };
      save(newDb, needsApproval ? 'submitted chore for approval' : 'completed a chore', 'Chores', chore?.title || '');
    }
  };

  const approveCompletion = (completionId: string, approved: boolean) => {
    const updated = (Array.isArray(db.choreCompletions) ? db.choreCompletions : []).map(c =>
      c.id === completionId
        ? { ...c, approvalStatus: (approved ? 'APPROVED' : 'REJECTED') as 'APPROVED' | 'REJECTED', approvedBy: user.id, approvedAt: new Date().toISOString() }
        : c
    );
    save({ ...db, choreCompletions: updated }, approved ? 'approved a chore' : 'rejected a chore', 'Chores', '');
  };

  // Pending approvals visible to admins
  const pendingApprovals = useMemo(() => {
    if (!isAdmin) return [];
    return completions.filter(c => c.approvalStatus === 'PENDING').map(c => ({
      completion: c,
      chore: chores.find(ch => ch.id === c.choreId),
      member: familyMembers.find(m => m.id === c.userId),
    })).filter(p => p.chore && p.member);
  }, [completions, chores, familyMembers, isAdmin]);

  const resetForm = () => {
    setTitle('');
    setDescription('');
    setIcon('🧹');
    setPoints(10);
    setFrequency('DAILY');
    setDaysOfWeek([1, 2, 3, 4, 5]);
    setSelectedAssignees([user.id]);
    setColor(CHORE_COLORS[0]);
    setReward(0);
    setRequiresApproval(false);
    setEditingChore(null);
  };

  const openModal = (chore?: Chore) => {
    if (chore) {
      setEditingChore(chore);
      setTitle(chore.title);
      setDescription(chore.description || '');
      setIcon(chore.icon);
      setPoints(chore.points);
      setFrequency(chore.frequency);
      setDaysOfWeek(chore.daysOfWeek);
      setSelectedAssignees(chore.assignees);
      setColor(chore.color);
      setReward(chore.reward || 0);
      setRequiresApproval(chore.requiresApproval || false);
    } else {
      resetForm();
    }
    setIsModalOpen(true);
  };

  const saveChore = () => {
    if (!title.trim()) return;

    if (editingChore) {
      const updated: Chore = {
        ...editingChore,
        title: title.trim(),
        description: description.trim() || undefined,
        icon,
        points,
        reward: reward > 0 ? reward : undefined,
        frequency,
        daysOfWeek: frequency === 'DAILY' ? [0, 1, 2, 3, 4, 5, 6] : daysOfWeek,
        assignees: selectedAssignees,
        color,
        requiresApproval: requiresApproval || undefined,
      };
      const newChores = (Array.isArray(db.chores) ? db.chores : []).map((c) => (c.id === editingChore.id ? updated : c));
      const newDb = { ...db, chores: newChores };
      save(newDb, 'updated a chore', 'Chores', title.trim());
    } else {
      const newChore: Chore = {
        id: createId(),
        familyId: family.id,
        creatorId: user.id,
        title: title.trim(),
        description: description.trim() || undefined,
        icon,
        points,
        reward: reward > 0 ? reward : undefined,
        frequency,
        daysOfWeek: frequency === 'DAILY' ? [0, 1, 2, 3, 4, 5, 6] : daysOfWeek,
        assignees: selectedAssignees,
        color,
        visibility: 'FAMILY',
        createdAt: new Date().toISOString(),
        requiresApproval: requiresApproval || undefined,
      };
      const newDb = { ...db, chores: [...(Array.isArray(db.chores) ? db.chores : []), newChore] };
      save(newDb, 'created a chore', 'Chores', title.trim());
    }

    setIsModalOpen(false);
    resetForm();
  };

  const deleteChore = (id: string) => {
    const chore = chores.find((c) => c.id === id);
    if (!window.confirm(`Delete "${chore?.title || 'this chore'}" and all its completion history? This cannot be undone.`)) return;
    const newChores = (Array.isArray(db.chores) ? db.chores : []).filter((c) => c.id !== id);
    const newCompletions = (Array.isArray(db.choreCompletions) ? db.choreCompletions : []).filter((c) => c.choreId !== id);
    const newDb = { ...db, chores: newChores, choreCompletions: newCompletions };
    save(newDb, 'deleted a chore', 'Chores', chore?.title || '');
  };

  const toggleDay = (day: number) => {
    setDaysOfWeek((prev) =>
      prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day],
    );
  };

  const toggleAssignee = (userId: string) => {
    setSelectedAssignees((prev) =>
      prev.includes(userId)
        ? prev.length > 1
          ? prev.filter((id) => id !== userId)
          : prev
        : [...prev, userId],
    );
  };

  // Pre-compute streaks for all chores once per render (Bug 30 — avoid O(chores×365×completions) in JSX)
  const streakMap = useMemo(() => {
    const map: Record<string, number> = {};
    chores.forEach(chore => { map[chore.id] = getStreak(chore.id, user.id, completions, chore); });
    return map;
  }, [chores, completions, user.id]);

  const progressPercent = myTodayChores.length > 0 ? Math.round((myTodayDone / myTodayChores.length) * 100) : 0;

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-black text-stone-800 tracking-tight">Chore Chart</h1>
          <p className="text-stone-500 text-sm mt-1">Keep the pack accountable</p>
        </div>
        <button
          onClick={() => openModal()}
          className="flex items-center space-x-2 bg-indigo-600 text-white px-5 py-3 rounded-2xl font-bold hover:bg-indigo-700 shadow-lg shadow-indigo-100 transition-all"
        >
          <Plus size={18} />
          <span>Add Chore</span>
        </button>
      </div>

      {/* Pending Approvals (admin only) */}
      {pendingApprovals.length > 0 && (
        <div className="bg-amber-50 rounded-3xl border border-amber-200 p-6">
          <h2 className="text-lg font-bold text-amber-800 flex items-center space-x-2 mb-4">
            <ShieldCheck size={20} className="text-amber-600" />
            <span>Needs Approval</span>
            <span className="ml-auto bg-amber-200 text-amber-800 text-xs font-bold px-2 py-0.5 rounded-full">{pendingApprovals.length}</span>
          </h2>
          <div className="space-y-3">
            {pendingApprovals.map(({ completion, chore, member }) => (
              <div key={completion.id} className="flex items-center justify-between bg-white rounded-2xl p-4 border border-amber-100 shadow-sm">
                <div className="flex items-center space-x-3">
                  <div className="w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0"
                    style={{ backgroundColor: (chore!.color || '#6366f1') + '20', color: chore!.color || '#6366f1' }}>
                    {chore!.icon}
                  </div>
                  <div>
                    <div className="font-semibold text-stone-800 text-sm">{chore!.title}</div>
                    <div className="text-xs text-stone-400">{member!.name} · {completion.date}</div>
                  </div>
                </div>
                <div className="flex items-center space-x-2">
                  <button onClick={() => approveCompletion(completion.id, false)}
                    className="p-2 rounded-xl hover:bg-red-50 text-red-400 hover:text-red-600 transition-colors">
                    <XCircle size={20} />
                  </button>
                  <button onClick={() => approveCompletion(completion.id, true)}
                    className="p-2 rounded-xl hover:bg-emerald-50 text-emerald-400 hover:text-emerald-600 transition-colors">
                    <CheckCircle2 size={20} />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Today's Progress Card */}
      {myTodayChores.length > 0 && (
        <div className="bg-gradient-to-br from-indigo-500 to-violet-600 rounded-3xl p-6 text-white shadow-xl">
          <div className="flex items-center justify-between mb-4">
            <div>
              <p className="text-indigo-100 text-sm font-medium">Today's Progress</p>
              <p className="text-3xl font-black mt-1">
                {myTodayDone}/{myTodayChores.length}
              </p>
            </div>
            {progressPercent === 100 ? (
              <div className="bg-white/20 backdrop-blur p-3 rounded-2xl">
                <Trophy size={28} className="text-yellow-300" />
              </div>
            ) : (
              <div className="bg-white/20 backdrop-blur p-3 rounded-2xl">
                <Sparkles size={28} className="text-indigo-100" />
              </div>
            )}
          </div>
          <div className="w-full bg-white/20 rounded-full h-3">
            <div
              className="h-3 rounded-full bg-white transition-all duration-500"
              style={{ width: `${progressPercent}%` }}
            />
          </div>
          {progressPercent === 100 && (
            <p className="text-indigo-100 text-sm font-medium mt-3 flex items-center space-x-1">
              <Star size={14} className="text-yellow-300" />
              <span>All done! Great work!</span>
            </p>
          )}
        </div>
      )}

      {/* Leaderboard */}
      {leaderboard.length > 0 && (
        <div className="bg-white rounded-3xl border border-stone-200 p-6">
          <h2 className="text-lg font-bold text-stone-800 flex items-center space-x-2 mb-4">
            <Crown size={20} className="text-amber-500" />
            <span>Leaderboard</span>
          </h2>
          <div className="space-y-3">
            {leaderboard.map((entry, idx) => (
              <div
                key={entry.userId}
                className={`flex items-center justify-between p-3 rounded-2xl ${
                  idx === 0
                    ? 'bg-amber-50 border border-amber-200'
                    : idx === 1
                      ? 'bg-stone-50 border border-stone-200'
                      : 'bg-stone-50/50'
                }`}
              >
                <div className="flex items-center space-x-3">
                  <div
                    className={`w-8 h-8 rounded-full flex items-center justify-center font-black text-sm ${
                      idx === 0
                        ? 'bg-amber-400 text-white'
                        : idx === 1
                          ? 'bg-stone-400 text-white'
                          : idx === 2
                            ? 'bg-orange-400 text-white'
                            : 'bg-stone-200 text-stone-600'
                    }`}
                  >
                    {idx + 1}
                  </div>
                  <span className="font-semibold text-stone-700">{entry.name}</span>
                  {entry.userId === user.id && (
                    <span className="text-xs bg-indigo-100 text-indigo-600 px-2 py-0.5 rounded-full font-bold">
                      You
                    </span>
                  )}
                </div>
                <div className="flex items-center space-x-1">
                  <Star size={14} className="text-amber-500" />
                  <span className="font-bold text-stone-700">{entry.totalPoints}</span>
                  <span className="text-stone-400 text-xs">pts</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Weekly Chart */}
      <div className="bg-white rounded-3xl border border-stone-200 p-6">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-bold text-stone-800">Weekly View</h2>
          <div className="flex items-center space-x-2">
            <button
              onClick={() => setWeekOffset((o) => o - 1)}
              className="p-2 hover:bg-stone-100 rounded-xl transition-colors"
            >
              <ChevronLeft size={18} className="text-stone-500" />
            </button>
            <button
              onClick={() => setWeekOffset(0)}
              className="px-3 py-1 text-sm font-semibold text-indigo-600 hover:bg-indigo-50 rounded-xl transition-colors"
            >
              {weekOffset === 0 ? 'This Week' : 'Today'}
            </button>
            <button
              onClick={() => setWeekOffset((o) => o + 1)}
              className="p-2 hover:bg-stone-100 rounded-xl transition-colors"
            >
              <ChevronRight size={18} className="text-stone-500" />
            </button>
          </div>
        </div>

        {chores.length === 0 ? (
          <ModuleHint
            emoji="🧹"
            title="Assign chores, earn points, climb the leaderboard"
            tips={[
              'Create chores and assign them to specific family members or everyone',
              'Each completion earns points — the leaderboard updates in real time',
              'Set chores to repeat daily, weekly, or as a one-off',
              'Parents can require approval before points are awarded',
            ]}
          />
        ) : (
          <div className="overflow-x-auto -mx-2">
            <table className="w-full min-w-[600px]">
              <thead>
                <tr>
                  <th className="text-left text-xs font-bold text-stone-400 uppercase tracking-wider pb-3 pl-2 w-[200px]">
                    Chore
                  </th>
                  {weekDates.map((date, i) => {
                    const isToday = date === today;
                    return (
                      <th key={date} className="text-center pb-3 w-[60px]">
                        <div
                          className={`text-xs font-bold ${isToday ? 'text-indigo-600' : 'text-stone-400'}`}
                        >
                          {DAY_LABELS[new Date(date + 'T12:00:00').getDay()]}
                        </div>
                        <div
                          className={`text-xs mt-0.5 ${
                            isToday
                              ? 'bg-indigo-600 text-white w-6 h-6 rounded-full flex items-center justify-center mx-auto font-bold'
                              : 'text-stone-300'
                          }`}
                        >
                          {new Date(date + 'T12:00:00').getDate()}
                        </div>
                      </th>
                    );
                  })}
                  <th className="w-[80px]" />
                </tr>
              </thead>
              <tbody>
                {chores.map((chore) => {
                  const streak = streakMap[chore.id] ?? 0;
                  return (
                    <tr key={chore.id} className="group border-t border-stone-100">
                      <td className="py-3 pl-2">
                        <div className="flex items-center space-x-3">
                          <div
                            className="w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0"
                            style={{ backgroundColor: chore.color + '20', color: chore.color }}
                          >
                            {chore.icon}
                          </div>
                          <div className="min-w-0">
                            <div className="font-semibold text-stone-800 text-sm truncate flex items-center gap-1">
                              {chore.title}
                              {chore.requiresApproval && (
                                <ShieldCheck size={12} className="text-indigo-400 shrink-0" title="Requires approval" />
                              )}
                            </div>
                            <div className="flex items-center space-x-2 mt-0.5">
                              <span className="text-xs text-stone-400">
                                {chore.assignees.map((id) => getUserName(id).split(' ')[0]).join(', ')}
                              </span>
                              {streak > 0 && (
                                <span className="flex items-center space-x-0.5 text-xs text-orange-500 font-bold">
                                  <Flame size={10} />
                                  <span>{streak}</span>
                                </span>
                              )}
                            </div>
                          </div>
                        </div>
                      </td>
                      {weekDates.map((date) => {
                        const dayOfWeek = new Date(date + 'T12:00:00').getDay();
                        const isScheduled =
                          chore.frequency === 'DAILY' || chore.daysOfWeek.includes(dayOfWeek);
                        const myCompletion = completions.find(c => c.choreId === chore.id && c.userId === user.id && c.date === date);
                        const isCompleted = !!myCompletion && myCompletion.approvalStatus !== 'REJECTED';
                        const isPending = myCompletion?.approvalStatus === 'PENDING';
                        const isToday = date === today;

                        if (!isScheduled) {
                          return (
                            <td key={date} className="text-center py-3">
                              <div className="w-8 h-8 mx-auto rounded-lg bg-stone-50" />
                            </td>
                          );
                        }

                        return (
                          <td key={date} className="text-center py-3">
                            <button
                              onClick={() => toggleCompletion(chore.id, date)}
                              title={isPending ? 'Awaiting approval' : undefined}
                              className={`w-8 h-8 mx-auto rounded-lg flex items-center justify-center transition-all ${
                                isPending
                                  ? 'bg-amber-100 text-amber-600 border border-amber-300'
                                  : isCompleted
                                    ? 'text-white shadow-sm scale-100'
                                    : isToday
                                      ? 'border-2 border-dashed hover:border-solid hover:scale-110'
                                      : 'border border-stone-200 hover:border-stone-300'
                              }`}
                              style={
                                !isPending && isCompleted
                                  ? { backgroundColor: chore.color }
                                  : !isPending && isToday
                                    ? { borderColor: chore.color + '80' }
                                    : undefined
                              }
                            >
                              {isPending ? <Clock size={12} /> : isCompleted ? <Check size={14} strokeWidth={3} /> : null}
                            </button>
                          </td>
                        );
                      })}
                      <td className="py-3 text-right pr-2">
                        <div className="flex items-center justify-end space-x-1">
                          <button
                            onClick={() => openModal(chore)}
                            className="p-2 hover:bg-stone-100 active:bg-stone-200 rounded-lg transition-colors text-stone-400 hover:text-stone-600 active:text-stone-600"
                          >
                            <Edit3 size={16} />
                          </button>
                          <button
                            onClick={() => deleteChore(chore.id)}
                            className="p-2 hover:bg-red-50 active:bg-red-100 rounded-lg transition-colors text-stone-400 hover:text-red-500 active:text-red-500"
                          >
                            <Trash2 size={16} />
                          </button>
                        </div>
                        <div className="flex items-center justify-end space-x-0.5 mt-1">
                          <Star size={10} className="text-amber-400" />
                          <span className="text-xs font-bold text-stone-400">{chore.points}</span>
                        </div>
                        {chore.reward && chore.reward > 0 && (
                          <div className="flex items-center justify-end mt-0.5">
                            <span className="text-xs font-bold text-emerald-500">{fmtCurrency(chore.reward)}</span>
                          </div>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Today's Chores Quick View (for all family members) */}
      {todaysChores.length > 0 && familyMembers.length > 1 && (
        <div className="bg-white rounded-3xl border border-stone-200 p-6">
          <h2 className="text-lg font-bold text-stone-800 flex items-center space-x-2 mb-4">
            <Users size={20} className="text-indigo-500" />
            <span>Family Status Today</span>
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {familyMembers.map((member) => {
              const memberChores = todaysChores.filter((c) => c.assignees.includes(member.id));
              if (memberChores.length === 0) return null;
              const memberDone = memberChores.filter((c) =>
                completions.some(
                  (comp) => comp.choreId === c.id && comp.userId === member.id && comp.date === today && comp.approvalStatus !== 'REJECTED',
                ),
              ).length;
              const pct = Math.round((memberDone / memberChores.length) * 100);
              return (
                <div key={member.id} className="p-4 rounded-2xl bg-stone-50 border border-stone-100">
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center space-x-2">
                      <div className="w-8 h-8 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-bold text-sm">
                        {member.name[0]}
                      </div>
                      <span className="font-semibold text-stone-700 text-sm">
                        {member.id === user.id ? 'You' : member.name.split(' ')[0]}
                      </span>
                    </div>
                    <span className="text-xs font-bold text-stone-400">
                      {memberDone}/{memberChores.length}
                    </span>
                  </div>
                  <div className="w-full bg-stone-200 rounded-full h-2">
                    <div
                      className={`h-2 rounded-full transition-all duration-500 ${
                        pct === 100 ? 'bg-emerald-500' : 'bg-indigo-500'
                      }`}
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                  <div className="flex flex-wrap gap-1 mt-3">
                    {memberChores.map((c) => {
                      const done = completions.some(
                        (comp) =>
                          comp.choreId === c.id && comp.userId === member.id && comp.date === today && comp.approvalStatus !== 'REJECTED',
                      );
                      return (
                        <span
                          key={c.id}
                          className={`text-xs px-2 py-1 rounded-lg font-medium ${
                            done
                              ? 'bg-emerald-100 text-emerald-700 line-through'
                              : 'bg-white text-stone-500 border border-stone-200'
                          }`}
                        >
                          {c.icon} {c.title}
                        </span>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Add/Edit Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-3xl max-w-lg w-full max-h-[90vh] overflow-y-auto p-6 shadow-2xl">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold text-stone-800">
                {editingChore ? 'Edit Chore' : 'New Chore'}
              </h2>
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
              {/* Title */}
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                  Chore Name
                </label>
                <input
                  type="text"
                  placeholder="e.g., Wash the dishes"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
                  autoFocus
                />
              </div>

              {/* Description */}
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                  Description (optional)
                </label>
                <input
                  type="text"
                  placeholder="Any extra details..."
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm text-stone-900 placeholder:text-stone-400"
                />
              </div>

              {/* Icon + Points + Color row */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                    Icon
                  </label>
                  <div className="grid grid-cols-8 gap-1">
                    {CHORE_ICONS.map((ic) => (
                      <button
                        key={ic}
                        onClick={() => setIcon(ic)}
                        className={`w-8 h-8 rounded-lg flex items-center justify-center text-sm transition-all ${
                          icon === ic
                            ? 'bg-indigo-100 ring-2 ring-indigo-400 scale-110'
                            : 'hover:bg-stone-100'
                        }`}
                      >
                        {ic}
                      </button>
                    ))}
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                    Points
                  </label>
                  <div className="flex items-center space-x-2">
                    {[5, 10, 15, 20, 25, 50].map((p) => (
                      <button
                        key={p}
                        onClick={() => setPoints(p)}
                        className={`px-3 py-2 rounded-xl text-xs font-bold transition-all ${
                          points === p
                            ? 'bg-amber-100 text-amber-700 ring-2 ring-amber-400'
                            : 'bg-stone-50 text-stone-500 hover:bg-stone-100'
                        }`}
                      >
                        {p}
                      </button>
                    ))}
                  </div>
                </div>
              </div>

              {/* Color */}
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                  Color
                </label>
                <div className="flex flex-wrap gap-2">
                  {CHORE_COLORS.map((c) => (
                    <button
                      key={c}
                      onClick={() => setColor(c)}
                      className={`w-7 h-7 rounded-full transition-all ${
                        color === c ? 'ring-2 ring-offset-2 ring-stone-400 scale-110' : 'hover:scale-110'
                      }`}
                      style={{ backgroundColor: c }}
                    />
                  ))}
                </div>
              </div>

              {/* Reward */}
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                  Reward per Completion (optional)
                </label>
                <div className="relative">
                  <span className="absolute left-4 top-1/2 -translate-y-1/2 text-stone-400 font-bold text-sm">{currencySymbol}</span>
                  <input
                    type="number"
                    step="0.50"
                    min="0"
                    placeholder="0.00"
                    value={reward || ''}
                    onChange={(e) => setReward(parseFloat(e.target.value) || 0)}
                    className="w-full pl-8 pr-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900"
                  />
                </div>
                <div className="flex gap-2 mt-2 flex-wrap">
                  {[0, 0.5, 1, 2, 5].map((v) => (
                    <button
                      key={v}
                      onClick={() => setReward(v)}
                      className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all ${
                        reward === v
                          ? 'bg-emerald-100 text-emerald-700 ring-2 ring-emerald-400'
                          : 'bg-stone-50 text-stone-500 hover:bg-stone-100'
                      }`}
                    >
                      {v === 0 ? 'None' : fmtCurrency(v)}
                    </button>
                  ))}
                </div>
              </div>

              {/* Frequency */}
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                  Frequency
                </label>
                <div className="flex space-x-2">
                  {(['DAILY', 'WEEKLY', 'CUSTOM'] as const).map((f) => (
                    <button
                      key={f}
                      onClick={() => {
                        setFrequency(f);
                        if (f === 'DAILY') setDaysOfWeek([0, 1, 2, 3, 4, 5, 6]);
                        if (f === 'WEEKLY') setDaysOfWeek([1, 2, 3, 4, 5]); // Mon–Fri
                      }}
                      className={`flex-1 py-2.5 rounded-xl text-sm font-bold transition-all ${
                        frequency === f
                          ? 'bg-indigo-100 text-indigo-700 ring-2 ring-indigo-400'
                          : 'bg-stone-50 text-stone-500 hover:bg-stone-100'
                      }`}
                    >
                      {f === 'DAILY' ? 'Every Day' : f === 'WEEKLY' ? 'Weekdays' : 'Custom'}
                    </button>
                  ))}
                </div>
                {frequency !== 'DAILY' && (
                  <div className="flex space-x-2 mt-3">
                    {DAY_LABELS.map((label, i) => (
                      <button
                        key={i}
                        onClick={() => toggleDay(i)}
                        className={`flex-1 py-2 rounded-xl text-xs font-bold transition-all ${
                          daysOfWeek.includes(i)
                            ? 'bg-indigo-600 text-white'
                            : 'bg-stone-100 text-stone-400 hover:bg-stone-200'
                        }`}
                      >
                        {DAY_LABELS_SHORT[i]}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              {/* Assignees */}
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                  Assign To
                </label>
                <div className="flex flex-wrap gap-2">
                  {familyMembers.map((member) => (
                    <button
                      key={member.id}
                      onClick={() => toggleAssignee(member.id)}
                      className={`flex items-center space-x-2 px-3 py-2 rounded-xl text-sm font-medium transition-all ${
                        selectedAssignees.includes(member.id)
                          ? 'bg-indigo-100 text-indigo-700 ring-2 ring-indigo-400'
                          : 'bg-stone-50 text-stone-500 hover:bg-stone-100'
                      }`}
                    >
                      <div className="w-6 h-6 rounded-full bg-indigo-200 text-indigo-600 flex items-center justify-center text-xs font-bold">
                        {member.name[0]}
                      </div>
                      <span>{member.id === user.id ? 'Me' : member.name.split(' ')[0]}</span>
                    </button>
                  ))}
                </div>
              </div>

              {/* Requires Approval Toggle */}
              <div className="flex items-center justify-between p-4 bg-stone-50 rounded-2xl border border-stone-200">
                <div>
                  <div className="text-sm font-bold text-stone-700 flex items-center gap-2">
                    <ShieldCheck size={16} className="text-indigo-500" />
                    Requires Parental Approval
                  </div>
                  <div className="text-xs text-stone-400 mt-0.5">Parents must approve before points are awarded</div>
                </div>
                <button
                  onClick={() => setRequiresApproval(v => !v)}
                  className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${requiresApproval ? 'bg-indigo-600' : 'bg-stone-300'}`}
                >
                  <span className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform shadow ${requiresApproval ? 'translate-x-6' : 'translate-x-1'}`} />
                </button>
              </div>

              {/* Save Button */}
              <button
                onClick={saveChore}
                disabled={!title.trim()}
                className="w-full bg-indigo-600 text-white py-3.5 rounded-2xl font-bold hover:bg-indigo-700 shadow-lg shadow-indigo-100 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {editingChore ? 'Save Changes' : 'Create Chore'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default Chores;

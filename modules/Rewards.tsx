
import React, { useState, useMemo } from 'react';
import {
  Plus,
  X,
  Trash2,
  Edit3,
  CheckCircle2,
  XCircle,
  PiggyBank,
  ImagePlus,
} from 'lucide-react';
import { User, Family, RewardItem, RewardRedemption, SavingsGoal } from '../types';
import { useRealtimeDB } from '../hooks/useRealtimeDB';
import { useLocale } from '../contexts/LocaleContext';
import ModuleHint from '../components/ModuleHint';

const REWARD_ICONS = ['🎮', '🍕', '🎬', '🍦', '🎯', '⭐', '🏖️', '🎉', '🎁', '💰', '🎠', '🎪', '🏆', '🛍️', '🍔', '🎈'];
const GOAL_ICONS = ['🎮', '🛹', '🎸', '📱', '🎧', '👟', '🧸', '🎨', '📚', '🚲', '⚽', '🏀', '🎠', '💎', '🐶', '✈️'];

const Rewards: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const { fmtCurrency: formatCurrency, currencySymbol } = useLocale();

  // Access control
  const userMembership = db.familyMembers.find(m => m.userId === user.id && m.familyId === family.id);
  const isKid = !!(userMembership?.moduleAccess && userMembership.moduleAccess.length > 0);

  // Safe array access
  const rewardItems = useMemo(() => (db.rewardItems || []).filter(r => r.familyId === family.id), [db.rewardItems, family.id]);
  const activeRewards = useMemo(() => rewardItems.filter(r => r.active), [rewardItems]);
  const familyRedemptions = useMemo(() => (db.rewardRedemptions || []).filter(r => r.familyId === family.id), [db.rewardRedemptions, family.id]);
  const familyChores = useMemo(() => (db.chores || []).filter(c => c.familyId === family.id), [db.chores, family.id]);
  const familyCompletions = useMemo(() => (db.choreCompletions || []).filter(c => c.familyId === family.id), [db.choreCompletions, family.id]);
  const allSavingsGoals = useMemo(() => (db.savingsGoals || []).filter(g => g.familyId === family.id), [db.savingsGoals, family.id]);

  const familyKids = useMemo(() => {
    const kidMembers = (db.familyMembers || []).filter(
      m => m.familyId === family.id && m.moduleAccess && m.moduleAccess.length > 0
    );
    return kidMembers
      .map(m => (db.users || []).find(u => u.id === m.userId))
      .filter(Boolean) as typeof db.users;
  }, [db.familyMembers, db.users, family.id]);

  const getBalance = (userId: string): number => {
    const earned = familyCompletions
      .filter(c => c.userId === userId)
      .reduce((sum, c) => {
        const chore = familyChores.find(ch => ch.id === c.choreId);
        return sum + (chore?.reward || 0);
      }, 0);
    const spent = familyRedemptions
      .filter(r => r.userId === userId && (r.status === 'APPROVED' || r.status === 'PENDING'))
      .reduce((sum, r) => sum + r.amount, 0);
    return Math.max(0, earned - spent);
  };

  const getTotalEarned = (userId: string): number => {
    return familyCompletions
      .filter(c => c.userId === userId)
      .reduce((sum, c) => {
        const chore = familyChores.find(ch => ch.id === c.choreId);
        return sum + (chore?.reward || 0);
      }, 0);
  };

  const myBalance = getBalance(user.id);

  const myRedemptions = useMemo(
    () =>
      familyRedemptions
        .filter(r => r.userId === user.id)
        .sort((a, b) => new Date(b.requestedAt).getTime() - new Date(a.requestedAt).getTime()),
    [familyRedemptions, user.id]
  );

  const mySavingsGoals = useMemo(
    () => allSavingsGoals.filter(g => g.userId === user.id).sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()),
    [allSavingsGoals, user.id]
  );

  const pendingApprovals = useMemo(
    () =>
      familyRedemptions
        .filter(r => r.status === 'PENDING')
        .sort((a, b) => new Date(a.requestedAt).getTime() - new Date(b.requestedAt).getTime()),
    [familyRedemptions]
  );

  const requestReward = (item: RewardItem) => {
    if (myBalance < item.cost) return;
    const alreadyPending = myRedemptions.some(r => r.rewardId === item.id && r.status === 'PENDING');
    if (alreadyPending) return;
    const newRedemption: RewardRedemption = {
      id: Math.random().toString(36).substr(2, 9),
      familyId: family.id,
      userId: user.id,
      rewardId: item.id,
      rewardTitle: item.title,
      amount: item.cost,
      status: 'PENDING',
      requestedAt: new Date().toISOString(),
    };
    save({ ...db, rewardRedemptions: [...(db.rewardRedemptions || []), newRedemption] }, 'requested a reward', 'Rewards', item.title);
  };

  const resolveRedemption = (redemptionId: string, status: 'APPROVED' | 'DENIED') => {
    const redemption = (db.rewardRedemptions || []).find(r => r.id === redemptionId);
    const updated = (db.rewardRedemptions || []).map(r =>
      r.id === redemptionId
        ? { ...r, status, resolvedAt: new Date().toISOString(), resolvedBy: user.id }
        : r
    );
    save({ ...db, rewardRedemptions: updated }, status === 'APPROVED' ? 'approved a reward' : 'denied a reward', 'Rewards', redemption?.rewardTitle || '');
  };

  // ---------------------------------------------------------------------------
  // Reward modal state
  // ---------------------------------------------------------------------------
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingReward, setEditingReward] = useState<RewardItem | null>(null);
  const [rTitle, setRTitle] = useState('');
  const [rDescription, setRDescription] = useState('');
  const [rCost, setRCost] = useState(5);
  const [rIcon, setRIcon] = useState('🎁');

  const openModal = (reward?: RewardItem) => {
    if (reward) {
      setEditingReward(reward);
      setRTitle(reward.title);
      setRDescription(reward.description || '');
      setRCost(reward.cost);
      setRIcon(reward.icon);
    } else {
      setEditingReward(null);
      setRTitle('');
      setRDescription('');
      setRCost(5);
      setRIcon('🎁');
    }
    setIsModalOpen(true);
  };

  const saveReward = () => {
    if (!rTitle.trim() || rCost <= 0) return;
    if (editingReward) {
      const updated = (db.rewardItems || []).map(r =>
        r.id === editingReward.id
          ? { ...r, title: rTitle.trim(), description: rDescription.trim() || undefined, cost: rCost, icon: rIcon }
          : r
      );
      save({ ...db, rewardItems: updated }, 'updated a reward', 'Rewards', rTitle.trim());
    } else {
      const newItem: RewardItem = {
        id: Math.random().toString(36).substr(2, 9),
        familyId: family.id,
        creatorId: user.id,
        title: rTitle.trim(),
        description: rDescription.trim() || undefined,
        cost: rCost,
        icon: rIcon,
        active: true,
        createdAt: new Date().toISOString(),
      };
      save({ ...db, rewardItems: [...(db.rewardItems || []), newItem] }, 'added a reward', 'Rewards', rTitle.trim());
    }
    setIsModalOpen(false);
  };

  const deleteReward = (id: string) => {
    const reward = (db.rewardItems || []).find(r => r.id === id);
    const updated = (db.rewardItems || []).filter(r => r.id !== id);
    save({ ...db, rewardItems: updated }, 'deleted a reward', 'Rewards', reward?.title || '');
  };

  // ---------------------------------------------------------------------------
  // Savings Goal modal state
  // ---------------------------------------------------------------------------
  const [isGoalModalOpen, setIsGoalModalOpen] = useState(false);
  const [editingGoal, setEditingGoal] = useState<SavingsGoal | null>(null);
  const [gTitle, setGTitle] = useState('');
  const [gIcon, setGIcon] = useState('🎮');
  const [gImageUrl, setGImageUrl] = useState('');
  const [gTargetAmount, setGTargetAmount] = useState(50);
  const [gSavedAmount, setGSavedAmount] = useState(0);
  const [goalOwnerId, setGoalOwnerId] = useState(user.id);
  const [imgError, setImgError] = useState(false);

  const openGoalModal = (goal?: SavingsGoal) => {
    if (goal) {
      setEditingGoal(goal);
      setGTitle(goal.title);
      setGIcon(goal.icon);
      setGImageUrl(goal.imageUrl || '');
      setGTargetAmount(goal.targetAmount);
      setGSavedAmount(goal.savedAmount);
      setGoalOwnerId(goal.userId);
    } else {
      setEditingGoal(null);
      setGTitle('');
      setGIcon('🎮');
      setGImageUrl('');
      setGTargetAmount(50);
      setGSavedAmount(0);
      setGoalOwnerId(isKid ? user.id : (familyKids.length > 0 ? familyKids[0].id : user.id));
    }
    setImgError(false);
    setIsGoalModalOpen(true);
  };

  const saveGoal = () => {
    if (!gTitle.trim() || gTargetAmount <= 0) return;
    if (editingGoal) {
      const updated = (db.savingsGoals || []).map(g =>
        g.id === editingGoal.id
          ? {
              ...g,
              title: gTitle.trim(),
              icon: gIcon,
              imageUrl: gImageUrl.trim() || undefined,
              targetAmount: gTargetAmount,
              savedAmount: Math.max(0, gSavedAmount),
              completedAt: gSavedAmount >= gTargetAmount && !g.completedAt ? new Date().toISOString() : g.completedAt,
            }
          : g
      );
      save({ ...db, savingsGoals: updated }, 'updated a savings goal', 'Rewards', gTitle.trim());
    } else {
      const newGoal: SavingsGoal = {
        id: Math.random().toString(36).substr(2, 9),
        familyId: family.id,
        userId: goalOwnerId,
        title: gTitle.trim(),
        icon: gIcon,
        imageUrl: gImageUrl.trim() || undefined,
        targetAmount: gTargetAmount,
        savedAmount: Math.max(0, gSavedAmount),
        createdAt: new Date().toISOString(),
      };
      save({ ...db, savingsGoals: [...(db.savingsGoals || []), newGoal] }, 'added a savings goal', 'Rewards', gTitle.trim());
    }
    setIsGoalModalOpen(false);
  };

  const deleteGoal = (id: string) => {
    const goal = (db.savingsGoals || []).find(g => g.id === id);
    const updated = (db.savingsGoals || []).filter(g => g.id !== id);
    save({ ...db, savingsGoals: updated }, 'deleted a savings goal', 'Rewards', goal?.title || '');
  };

  // ---------------------------------------------------------------------------
  // Add funds modal state
  // ---------------------------------------------------------------------------
  const [isAddFundsOpen, setIsAddFundsOpen] = useState(false);
  const [addFundsGoalId, setAddFundsGoalId] = useState('');
  const [addFundsAmount, setAddFundsAmount] = useState(0);

  const openAddFunds = (goalId: string) => {
    setAddFundsGoalId(goalId);
    setAddFundsAmount(0);
    setIsAddFundsOpen(true);
  };

  const handleAddFunds = () => {
    if (addFundsAmount <= 0) return;
    const updated = (db.savingsGoals || []).map(g => {
      if (g.id !== addFundsGoalId) return g;
      const newSaved = g.savedAmount + addFundsAmount;
      return {
        ...g,
        savedAmount: newSaved,
        completedAt: newSaved >= g.targetAmount && !g.completedAt ? new Date().toISOString() : g.completedAt,
      };
    });
    const goal = (db.savingsGoals || []).find(g => g.id === addFundsGoalId);
    save({ ...db, savingsGoals: updated }, 'added money to savings', 'Rewards', goal?.title || '');
    setIsAddFundsOpen(false);
  };

  // ---------------------------------------------------------------------------
  // Reusable: Savings Goal Card
  // ---------------------------------------------------------------------------
  const GoalCard: React.FC<{ goal: SavingsGoal; showActions?: boolean; showKidName?: boolean }> = ({ goal, showActions = true, showKidName = false }) => {
    const progress = goal.targetAmount > 0 ? Math.min(100, (goal.savedAmount / goal.targetAmount) * 100) : 0;
    const isComplete = goal.savedAmount >= goal.targetAmount;
    const kidUser = showKidName ? (db.users || []).find(u => u.id === goal.userId) : null;

    return (
      <div className={`bg-white border-2 rounded-3xl overflow-hidden shadow-sm transition-all ${isComplete ? 'border-emerald-300' : 'border-stone-100'}`}>
        {/* Image header or icon */}
        {goal.imageUrl ? (
          <div className="h-36 bg-stone-100 relative overflow-hidden">
            <img
              src={goal.imageUrl}
              alt={goal.title}
              className="w-full h-full object-cover"
              onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }}
            />
            {isComplete && (
              <div className="absolute inset-0 bg-emerald-600/80 flex items-center justify-center">
                <div className="text-center text-white">
                  <CheckCircle2 size={32} className="mx-auto mb-1" />
                  <p className="font-black text-sm">GOAL REACHED!</p>
                </div>
              </div>
            )}
          </div>
        ) : (
          <div className={`h-28 flex items-center justify-center ${isComplete ? 'bg-emerald-50' : 'bg-stone-50'}`}>
            <span className="text-6xl">{goal.icon}</span>
            {isComplete && (
              <div className="absolute">
                <span className="text-sm font-black text-emerald-600 bg-white/90 px-3 py-1 rounded-full shadow-sm">GOAL REACHED!</span>
              </div>
            )}
          </div>
        )}

        <div className="p-5">
          {showKidName && kidUser && (
            <p className="text-[10px] font-black text-indigo-500 uppercase tracking-wider mb-1">
              {kidUser.name.split(' ')[0]}'s goal
            </p>
          )}
          <p className="font-bold text-stone-800 text-lg leading-tight mb-3">{goal.title}</p>

          {/* Progress bar */}
          <div className="mb-2">
            <div className="flex items-end justify-between mb-1.5">
              <span className="text-2xl font-black text-stone-900">{formatCurrency(goal.savedAmount)}</span>
              <span className="text-sm text-stone-400 font-semibold">of {formatCurrency(goal.targetAmount)}</span>
            </div>
            <div className="h-3 bg-stone-100 rounded-full overflow-hidden">
              <div
                className={`h-full rounded-full transition-all duration-500 ${isComplete ? 'bg-emerald-500' : 'bg-indigo-500'}`}
                style={{ width: `${progress}%` }}
              />
            </div>
            <div className="flex justify-between mt-1">
              <span className={`text-xs font-bold ${isComplete ? 'text-emerald-600' : 'text-indigo-600'}`}>
                {Math.round(progress)}%
              </span>
              {!isComplete && (
                <span className="text-xs text-stone-400 font-medium">
                  {formatCurrency(goal.targetAmount - goal.savedAmount)} to go
                </span>
              )}
            </div>
          </div>

          {/* Actions */}
          {showActions && (
            <div className="flex gap-2 mt-4">
              {!isComplete && (
                <button
                  onClick={() => openAddFunds(goal.id)}
                  className="flex-1 flex items-center justify-center gap-1.5 py-2.5 bg-indigo-600 text-white rounded-2xl font-bold text-sm hover:bg-indigo-700 transition-colors shadow-sm"
                >
                  <Plus size={15} />
                  Add Money
                </button>
              )}
              <button
                onClick={() => openGoalModal(goal)}
                className="p-2.5 bg-stone-100 text-stone-500 rounded-2xl hover:bg-stone-200 transition-colors"
              >
                <Edit3 size={15} />
              </button>
              <button
                onClick={() => deleteGoal(goal.id)}
                className="p-2.5 bg-stone-100 text-stone-400 rounded-2xl hover:bg-red-50 hover:text-red-500 transition-colors"
              >
                <Trash2 size={15} />
              </button>
            </div>
          )}
        </div>
      </div>
    );
  };

  // ---------------------------------------------------------------------------
  // Reusable: Goal Modal
  // ---------------------------------------------------------------------------
  const GoalModal = () => {
    if (!isGoalModalOpen) return null;
    return (
      <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
        <div className="bg-white rounded-3xl max-w-md w-full max-h-[90vh] overflow-y-auto p-6 shadow-2xl">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-xl font-bold text-stone-800">
              {editingGoal ? 'Edit Savings Goal' : 'New Savings Goal'}
            </h2>
            <button onClick={() => setIsGoalModalOpen(false)} className="p-2 hover:bg-stone-100 rounded-xl transition-colors">
              <X size={20} className="text-stone-400" />
            </button>
          </div>

          <div className="space-y-5">
            {/* Who is this goal for? (parent only, when adding) */}
            {!isKid && !editingGoal && familyKids.length > 0 && (
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">For</label>
                <div className="flex gap-2 flex-wrap">
                  {familyKids.map(kid => (
                    <button
                      key={kid.id}
                      onClick={() => setGoalOwnerId(kid.id)}
                      className={`flex items-center gap-2 px-4 py-2 rounded-2xl text-sm font-bold transition-all ${
                        goalOwnerId === kid.id
                          ? 'bg-indigo-600 text-white shadow-sm'
                          : 'bg-stone-100 text-stone-600 hover:bg-stone-200'
                      }`}
                    >
                      <span className="w-6 h-6 rounded-full bg-white/30 flex items-center justify-center text-xs font-black">
                        {kid.name[0]}
                      </span>
                      {kid.name.split(' ')[0]}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {/* Icon */}
            <div>
              <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">Icon</label>
              <div className="grid grid-cols-8 gap-1.5">
                {GOAL_ICONS.map(ic => (
                  <button
                    key={ic}
                    onClick={() => setGIcon(ic)}
                    className={`w-9 h-9 rounded-xl flex items-center justify-center text-lg transition-all ${
                      gIcon === ic ? 'bg-indigo-100 ring-2 ring-indigo-400 scale-110' : 'hover:bg-stone-100'
                    }`}
                  >
                    {ic}
                  </button>
                ))}
              </div>
            </div>

            {/* Title */}
            <div>
              <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                What are you saving for?
              </label>
              <input
                autoFocus
                type="text"
                placeholder="e.g., Nintendo Switch, New Bike"
                value={gTitle}
                onChange={e => setGTitle(e.target.value)}
                className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
              />
            </div>

            {/* Picture URL */}
            <div>
              <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                <span className="flex items-center gap-1.5">
                  <ImagePlus size={13} />
                  Picture URL (optional)
                </span>
              </label>
              <input
                type="url"
                placeholder="Paste a link to a picture..."
                value={gImageUrl}
                onChange={e => { setGImageUrl(e.target.value); setImgError(false); }}
                className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm text-stone-900 placeholder:text-stone-400"
              />
              {gImageUrl.trim() && !imgError && (
                <div className="mt-2 rounded-xl overflow-hidden border border-stone-200 h-28 bg-stone-50">
                  <img
                    src={gImageUrl}
                    alt="Preview"
                    className="w-full h-full object-cover"
                    onError={() => setImgError(true)}
                  />
                </div>
              )}
              {imgError && (
                <p className="text-xs text-red-500 mt-1 font-medium">Couldn't load image. Check the URL.</p>
              )}
            </div>

            {/* Target amount */}
            <div>
              <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                Target Price ({currencySymbol})
              </label>
              <div className="relative">
                <span className="absolute left-4 top-1/2 -translate-y-1/2 text-stone-400 font-bold text-sm">{currencySymbol}</span>
                <input
                  type="number"
                  step="1"
                  min="1"
                  value={gTargetAmount}
                  onChange={e => setGTargetAmount(parseFloat(e.target.value) || 1)}
                  className="w-full pl-8 pr-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-bold text-stone-900"
                />
              </div>
              <div className="flex gap-2 mt-2 flex-wrap">
                {[10, 25, 50, 100, 200, 500].map(v => (
                  <button
                    key={v}
                    onClick={() => setGTargetAmount(v)}
                    className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all ${
                      gTargetAmount === v
                        ? 'bg-indigo-100 text-indigo-700 ring-2 ring-indigo-400'
                        : 'bg-stone-50 text-stone-500 hover:bg-stone-100'
                    }`}
                  >
                    {formatCurrency(v)}
                  </button>
                ))}
              </div>
            </div>

            {/* Already saved */}
            <div>
              <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                Already Saved ({currencySymbol})
              </label>
              <div className="relative">
                <span className="absolute left-4 top-1/2 -translate-y-1/2 text-stone-400 font-bold text-sm">{currencySymbol}</span>
                <input
                  type="number"
                  step="0.50"
                  min="0"
                  value={gSavedAmount || ''}
                  onChange={e => setGSavedAmount(parseFloat(e.target.value) || 0)}
                  className="w-full pl-8 pr-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-bold text-stone-900"
                  placeholder="0.00"
                />
              </div>
              <p className="text-xs text-stone-400 mt-1">Include birthday money, pocket money, or anything they've already saved.</p>
            </div>

            {/* Save */}
            <button
              onClick={saveGoal}
              disabled={!gTitle.trim() || gTargetAmount <= 0}
              className="w-full bg-indigo-600 text-white py-3.5 rounded-2xl font-bold hover:bg-indigo-700 shadow-lg shadow-indigo-100 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
            >
              {editingGoal ? 'Save Changes' : 'Create Goal'}
            </button>
          </div>
        </div>
      </div>
    );
  };

  // ---------------------------------------------------------------------------
  // Add Funds Modal
  // ---------------------------------------------------------------------------
  const AddFundsModal = () => {
    if (!isAddFundsOpen) return null;
    const goal = (db.savingsGoals || []).find(g => g.id === addFundsGoalId);
    if (!goal) return null;
    const remaining = Math.max(0, goal.targetAmount - goal.savedAmount);

    return (
      <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
        <div className="bg-white rounded-3xl max-w-sm w-full p-6 shadow-2xl">
          <div className="flex items-center justify-between mb-5">
            <h2 className="text-lg font-bold text-stone-800">Add Money</h2>
            <button onClick={() => setIsAddFundsOpen(false)} className="p-2 hover:bg-stone-100 rounded-xl transition-colors">
              <X size={18} className="text-stone-400" />
            </button>
          </div>

          <div className="text-center mb-5">
            <span className="text-4xl">{goal.icon}</span>
            <p className="font-bold text-stone-800 mt-2">{goal.title}</p>
            <p className="text-sm text-stone-400">
              {formatCurrency(goal.savedAmount)} of {formatCurrency(goal.targetAmount)} saved
            </p>
            <p className="text-xs text-indigo-600 font-bold mt-1">
              {formatCurrency(remaining)} to go
            </p>
          </div>

          <div className="space-y-4">
            <div className="relative">
              <span className="absolute left-4 top-1/2 -translate-y-1/2 text-stone-400 font-bold text-sm">{currencySymbol}</span>
              <input
                autoFocus
                type="number"
                step="0.50"
                min="0.50"
                value={addFundsAmount || ''}
                onChange={e => setAddFundsAmount(parseFloat(e.target.value) || 0)}
                placeholder="0.00"
                className="w-full pl-8 pr-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-bold text-lg text-stone-900 text-center"
              />
            </div>

            <div className="flex gap-2 flex-wrap justify-center">
              {[1, 2, 5, 10, 20].map(v => (
                <button
                  key={v}
                  onClick={() => setAddFundsAmount(v)}
                  className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all ${
                    addFundsAmount === v
                      ? 'bg-emerald-100 text-emerald-700 ring-2 ring-emerald-400'
                      : 'bg-stone-50 text-stone-500 hover:bg-stone-100'
                  }`}
                >
                  +{formatCurrency(v)}
                </button>
              ))}
              {remaining > 0 && (
                <button
                  onClick={() => setAddFundsAmount(remaining)}
                  className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all ${
                    addFundsAmount === remaining
                      ? 'bg-emerald-100 text-emerald-700 ring-2 ring-emerald-400'
                      : 'bg-indigo-50 text-indigo-600 hover:bg-indigo-100'
                  }`}
                >
                  All ({formatCurrency(remaining)})
                </button>
              )}
            </div>

            <button
              onClick={handleAddFunds}
              disabled={addFundsAmount <= 0}
              className="w-full bg-emerald-600 text-white py-3 rounded-2xl font-bold hover:bg-emerald-700 transition-colors disabled:opacity-40 disabled:cursor-not-allowed shadow-sm shadow-emerald-100"
            >
              Add {addFundsAmount > 0 ? formatCurrency(addFundsAmount) : 'Money'}
            </button>
          </div>
        </div>
      </div>
    );
  };

  // ---------------------------------------------------------------------------
  // KIDS VIEW
  // ---------------------------------------------------------------------------
  if (isKid) {
    return (
      <div className="space-y-8">
        {/* Header */}
        <div>
          <h1 className="text-3xl font-black text-stone-800 tracking-tight">Reward Store</h1>
          <p className="text-stone-500 text-sm mt-1">Earn money by doing chores, then pick a reward!</p>
        </div>

        {/* Balance Hero */}
        <div className="bg-gradient-to-br from-emerald-500 to-teal-600 rounded-3xl p-7 text-white shadow-xl shadow-emerald-100">
          <p className="text-emerald-100 text-sm font-medium mb-2">Your Balance</p>
          <p className="text-6xl font-black mb-1">{formatCurrency(myBalance)}</p>
          <p className="text-emerald-200 text-xs">
            Total earned: {formatCurrency(getTotalEarned(user.id))}
          </p>
        </div>

        {/* Savings Goals */}
        <div>
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <PiggyBank size={22} className="text-pink-500" />
              <h2 className="text-xl font-bold text-stone-800">Saving For</h2>
            </div>
            <button
              onClick={() => openGoalModal()}
              className="flex items-center gap-1.5 px-4 py-2 bg-pink-100 text-pink-700 rounded-2xl font-bold text-sm hover:bg-pink-200 transition-colors"
            >
              <Plus size={15} />
              New Goal
            </button>
          </div>

          {mySavingsGoals.length > 0 ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {mySavingsGoals.map(goal => (
                <GoalCard key={goal.id} goal={goal} />
              ))}
            </div>
          ) : (
            <div className="bg-pink-50 rounded-3xl border border-pink-100 p-8 text-center">
              <p className="text-5xl mb-3">🐷</p>
              <p className="font-bold text-stone-700">No savings goals yet</p>
              <p className="text-sm text-stone-400 mt-1">Set a goal for something you want to save up for!</p>
              <button
                onClick={() => openGoalModal()}
                className="mt-4 px-5 py-2.5 bg-pink-500 text-white rounded-2xl font-bold text-sm hover:bg-pink-600 transition-colors"
              >
                Create First Goal
              </button>
            </div>
          )}
        </div>

        {/* Reward Store */}
        {activeRewards.length > 0 ? (
          <div>
            <h2 className="text-xl font-bold text-stone-800 mb-4">Available Rewards</h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {activeRewards.map(item => {
                const canAfford = myBalance >= item.cost;
                const isPending = myRedemptions.some(r => r.rewardId === item.id && r.status === 'PENDING');
                return (
                  <div
                    key={item.id}
                    className={`bg-white border-2 rounded-3xl p-5 transition-all shadow-sm ${canAfford && !isPending ? 'border-emerald-200 hover:border-emerald-400' : 'border-stone-100'}`}
                  >
                    <div className="flex items-start justify-between mb-3">
                      <span className="text-4xl">{item.icon}</span>
                      <span className="text-lg font-black text-emerald-600">{formatCurrency(item.cost)}</span>
                    </div>
                    <p className="font-bold text-stone-800 mb-1">{item.title}</p>
                    {item.description && <p className="text-xs text-stone-500 mb-3">{item.description}</p>}
                    <button
                      onClick={() => requestReward(item)}
                      disabled={!canAfford || isPending}
                      className={`w-full py-2.5 rounded-2xl font-bold text-sm transition-all mt-3 ${
                        isPending
                          ? 'bg-amber-100 text-amber-700 cursor-default'
                          : canAfford
                            ? 'bg-emerald-600 text-white hover:bg-emerald-700 shadow-sm shadow-emerald-200'
                            : 'bg-stone-100 text-stone-400 cursor-not-allowed'
                      }`}
                    >
                      {isPending
                        ? '⏳ Pending Approval'
                        : canAfford
                          ? '🎁 Request Reward'
                          : `Need ${formatCurrency(item.cost - myBalance)} more`}
                    </button>
                  </div>
                );
              })}
            </div>
          </div>
        ) : (
          <div className="bg-stone-50 rounded-3xl border border-stone-200 p-10 text-center">
            <p className="text-5xl mb-3">🏪</p>
            <p className="font-bold text-stone-700 text-lg">No rewards yet</p>
            <p className="text-sm text-stone-400 mt-1">Ask a parent to add rewards to the store!</p>
          </div>
        )}

        {/* My Requests */}
        {myRedemptions.length > 0 && (
          <div>
            <h2 className="text-xl font-bold text-stone-800 mb-4">My Requests</h2>
            <div className="space-y-3">
              {myRedemptions.slice(0, 10).map(r => (
                <div
                  key={r.id}
                  className={`flex items-center justify-between p-4 rounded-2xl border ${
                    r.status === 'APPROVED'
                      ? 'bg-emerald-50 border-emerald-100'
                      : r.status === 'DENIED'
                        ? 'bg-red-50 border-red-100'
                        : 'bg-amber-50 border-amber-100'
                  }`}
                >
                  <div>
                    <p className="font-bold text-stone-800 text-sm">{r.rewardTitle}</p>
                    <p className="text-xs text-stone-400 mt-0.5">
                      {new Date(r.requestedAt).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="font-bold text-stone-700">{formatCurrency(r.amount)}</span>
                    <span className={`text-[10px] font-black uppercase px-2 py-1 rounded-full ${
                      r.status === 'APPROVED'
                        ? 'bg-emerald-100 text-emerald-700'
                        : r.status === 'DENIED'
                          ? 'bg-red-100 text-red-700'
                          : 'bg-amber-100 text-amber-700'
                    }`}>{r.status}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {GoalModal()}
        {AddFundsModal()}
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // PARENT / ADMIN VIEW
  // ---------------------------------------------------------------------------
  const resolvedRedemptions = familyRedemptions
    .filter(r => r.status !== 'PENDING')
    .sort((a, b) => new Date(b.requestedAt).getTime() - new Date(a.requestedAt).getTime());

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-3xl font-black text-stone-800 tracking-tight">Reward Store</h1>
          <p className="text-stone-500 text-sm mt-1">Manage rewards, savings goals, and approve requests</p>
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => openGoalModal()}
            className="flex items-center space-x-2 bg-pink-500 text-white px-4 py-2.5 rounded-2xl font-bold hover:bg-pink-600 shadow-sm transition-all text-sm"
          >
            <PiggyBank size={16} />
            <span>Add Goal</span>
          </button>
          <button
            onClick={() => openModal()}
            className="flex items-center space-x-2 bg-indigo-600 text-white px-4 py-2.5 rounded-2xl font-bold hover:bg-indigo-700 shadow-lg shadow-indigo-100 transition-all text-sm"
          >
            <Plus size={16} />
            <span>Add Reward</span>
          </button>
        </div>
      </div>

      {/* Kids Balances */}
      {familyKids.length > 0 && (
        <div>
          <h2 className="text-lg font-bold text-stone-800 mb-4">Kids' Balances</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
            {familyKids.map(kid => {
              const balance = getBalance(kid.id);
              const earned = getTotalEarned(kid.id);
              const kidPendingCount = familyRedemptions.filter(r => r.userId === kid.id && r.status === 'PENDING').length;
              return (
                <div key={kid.id} className="bg-white border border-stone-200 rounded-3xl p-5 shadow-sm">
                  <div className="flex items-center gap-3 mb-4">
                    <div className="w-10 h-10 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-bold text-lg">
                      {kid.name[0]}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-bold text-stone-800 truncate">{kid.name.split(' ')[0]}</p>
                      <p className="text-xs text-stone-400">Earned: {formatCurrency(earned)}</p>
                    </div>
                    {kidPendingCount > 0 && (
                      <span className="text-[10px] font-black bg-amber-100 text-amber-700 px-2 py-1 rounded-full shrink-0">
                        {kidPendingCount} pending
                      </span>
                    )}
                  </div>
                  <p className="text-3xl font-black text-emerald-600">{formatCurrency(balance)}</p>
                  <p className="text-xs text-stone-400 mt-1">Available balance</p>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Kids' Savings Goals */}
      {allSavingsGoals.length > 0 && (
        <div>
          <div className="flex items-center gap-2 mb-4">
            <PiggyBank size={20} className="text-pink-500" />
            <h2 className="text-lg font-bold text-stone-800">Kids' Savings Goals</h2>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
            {allSavingsGoals.map(goal => (
              <GoalCard key={goal.id} goal={goal} showActions={true} showKidName={true} />
            ))}
          </div>
        </div>
      )}

      {/* Pending Approvals */}
      {pendingApprovals.length > 0 && (
        <div>
          <h2 className="text-lg font-bold text-stone-800 mb-4 flex items-center gap-2">
            Pending Approvals
            <span className="text-sm bg-amber-100 text-amber-700 px-2.5 py-0.5 rounded-full font-bold">
              {pendingApprovals.length}
            </span>
          </h2>
          <div className="space-y-3">
            {pendingApprovals.map(r => {
              const requestingUser = (db.users || []).find(u => u.id === r.userId);
              return (
                <div key={r.id} className="bg-amber-50 border border-amber-200 rounded-2xl p-4 flex items-center justify-between gap-4 flex-wrap">
                  <div>
                    <p className="font-bold text-stone-800">
                      {requestingUser?.name.split(' ')[0] || 'Kid'} wants: {r.rewardTitle}
                    </p>
                    <p className="text-sm text-emerald-700 font-bold">{formatCurrency(r.amount)}</p>
                    <p className="text-xs text-stone-400 mt-0.5">
                      {new Date(r.requestedAt).toLocaleDateString(undefined, { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
                    </p>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <button
                      onClick={() => resolveRedemption(r.id, 'APPROVED')}
                      className="flex items-center gap-1.5 px-4 py-2 bg-emerald-600 text-white rounded-xl font-bold text-sm hover:bg-emerald-700 transition-colors shadow-sm shadow-emerald-100"
                    >
                      <CheckCircle2 size={15} />
                      Approve
                    </button>
                    <button
                      onClick={() => resolveRedemption(r.id, 'DENIED')}
                      className="flex items-center gap-1.5 px-4 py-2 bg-red-100 text-red-600 rounded-xl font-bold text-sm hover:bg-red-200 transition-colors"
                    >
                      <XCircle size={15} />
                      Deny
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Reward Catalog */}
      <div>
        <h2 className="text-lg font-bold text-stone-800 mb-4">Reward Catalog</h2>
        {rewardItems.length === 0 ? (
          <div className="bg-stone-50 rounded-3xl border border-dashed border-stone-200 p-8 text-center">
            <p className="text-4xl mb-3">🎁</p>
            <p className="font-bold text-stone-700 text-lg mb-4">Set up your family reward store</p>
            <ul className="space-y-2 max-w-xs mx-auto text-left mb-6">
              {[
                'Kids earn points by completing chores',
                'Create rewards with a point cost — screen time, treats, outings',
                'Review and approve every redemption request',
                'Kids can also set savings goals for bigger items',
              ].map(tip => (
                <li key={tip} className="flex items-start gap-2 text-sm text-stone-500">
                  <span className="text-stone-300 shrink-0 mt-0.5">›</span>
                  <span>{tip}</span>
                </li>
              ))}
            </ul>
            <button
              onClick={() => openModal()}
              className="px-5 py-2.5 bg-indigo-600 text-white rounded-2xl font-bold text-sm hover:bg-indigo-700 transition-colors shadow-lg shadow-indigo-100"
            >
              Add First Reward
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
            {rewardItems.map(item => (
              <div
                key={item.id}
                className={`bg-white border rounded-3xl p-5 shadow-sm group ${item.active ? 'border-stone-200' : 'border-stone-100 opacity-60'}`}
              >
                <div className="flex items-start justify-between mb-3">
                  <span className="text-4xl">{item.icon}</span>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => openModal(item)}
                      className="p-2 hover:bg-stone-100 active:bg-stone-200 rounded-lg text-stone-400 hover:text-stone-600 active:text-stone-600 transition-colors"
                    >
                      <Edit3 size={16} />
                    </button>
                    <button
                      onClick={() => deleteReward(item.id)}
                      className="p-2 hover:bg-red-50 active:bg-red-100 rounded-lg text-stone-400 hover:text-red-500 active:text-red-500 transition-colors"
                    >
                      <Trash2 size={16} />
                    </button>
                  </div>
                </div>
                <p className="font-bold text-stone-800">{item.title}</p>
                {item.description && <p className="text-xs text-stone-500 mt-1">{item.description}</p>}
                <p className="text-xl font-black text-emerald-600 mt-2">{formatCurrency(item.cost)}</p>
                {!item.active && (
                  <span className="text-[10px] font-bold text-stone-400 bg-stone-100 px-2 py-0.5 rounded-full mt-1 inline-block">
                    Inactive
                  </span>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Recent History */}
      {resolvedRedemptions.length > 0 && (
        <div>
          <h2 className="text-lg font-bold text-stone-800 mb-4">Recent History</h2>
          <div className="bg-white rounded-3xl border border-stone-200 divide-y divide-stone-50">
            {resolvedRedemptions.slice(0, 15).map(r => {
              const requestingUser = (db.users || []).find(u => u.id === r.userId);
              return (
                <div key={r.id} className="flex items-center justify-between px-5 py-4">
                  <div>
                    <p className="text-sm font-semibold text-stone-700">
                      {requestingUser?.name.split(' ')[0]} — {r.rewardTitle}
                    </p>
                    <p className="text-xs text-stone-400 mt-0.5">
                      {new Date(r.requestedAt).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="font-bold text-stone-600 text-sm">{formatCurrency(r.amount)}</span>
                    <span className={`text-[10px] font-black uppercase px-2 py-1 rounded-full ${
                      r.status === 'APPROVED' ? 'bg-emerald-100 text-emerald-700' : 'bg-red-100 text-red-700'
                    }`}>
                      {r.status}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Reward Add/Edit Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-3xl max-w-md w-full max-h-[90vh] overflow-y-auto p-6 shadow-2xl">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold text-stone-800">
                {editingReward ? 'Edit Reward' : 'New Reward'}
              </h2>
              <button onClick={() => setIsModalOpen(false)} className="p-2 hover:bg-stone-100 rounded-xl transition-colors">
                <X size={20} className="text-stone-400" />
              </button>
            </div>

            <div className="space-y-5">
              {/* Icon */}
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">Icon</label>
                <div className="grid grid-cols-8 gap-1.5">
                  {REWARD_ICONS.map(ic => (
                    <button
                      key={ic}
                      onClick={() => setRIcon(ic)}
                      className={`w-9 h-9 rounded-xl flex items-center justify-center text-lg transition-all ${
                        rIcon === ic ? 'bg-indigo-100 ring-2 ring-indigo-400 scale-110' : 'hover:bg-stone-100'
                      }`}
                    >
                      {ic}
                    </button>
                  ))}
                </div>
              </div>

              {/* Title */}
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                  Reward Name
                </label>
                <input
                  autoFocus
                  type="text"
                  placeholder="e.g., Extra Screen Time"
                  value={rTitle}
                  onChange={e => setRTitle(e.target.value)}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-medium text-stone-900 placeholder:text-stone-400"
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
                  value={rDescription}
                  onChange={e => setRDescription(e.target.value)}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm text-stone-900 placeholder:text-stone-400"
                />
              </div>

              {/* Cost */}
              <div>
                <label className="block text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">
                  Cost ({currencySymbol})
                </label>
                <div className="relative">
                  <span className="absolute left-4 top-1/2 -translate-y-1/2 text-stone-400 font-bold text-sm">{currencySymbol}</span>
                  <input
                    type="number"
                    step="0.50"
                    min="0.50"
                    value={rCost}
                    onChange={e => setRCost(parseFloat(e.target.value) || 0.5)}
                    className="w-full pl-8 pr-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 font-bold text-stone-900"
                  />
                </div>
                <div className="flex gap-2 mt-2 flex-wrap">
                  {[1, 2, 5, 10, 20, 50].map(v => (
                    <button
                      key={v}
                      onClick={() => setRCost(v)}
                      className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all ${
                        rCost === v
                          ? 'bg-emerald-100 text-emerald-700 ring-2 ring-emerald-400'
                          : 'bg-stone-50 text-stone-500 hover:bg-stone-100'
                      }`}
                    >
                      {formatCurrency(v)}
                    </button>
                  ))}
                </div>
              </div>

              {/* Save */}
              <button
                onClick={saveReward}
                disabled={!rTitle.trim() || rCost <= 0}
                className="w-full bg-indigo-600 text-white py-3.5 rounded-2xl font-bold hover:bg-indigo-700 shadow-lg shadow-indigo-100 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {editingReward ? 'Save Changes' : 'Create Reward'}
              </button>
            </div>
          </div>
        </div>
      )}

      {GoalModal()}
      {AddFundsModal()}
    </div>
  );
};

export default Rewards;

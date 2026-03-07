
import React, { useMemo, useState, useEffect, useCallback } from 'react';
import {
  CheckCircle2,
  Calendar as CalendarIcon,
  Utensils,
  TrendingUp,
  ArrowRight,
  Plus,
  Sparkles,
  ListTodo,
  BookOpen,
  Activity,
  Wallet,
  Dumbbell,
  RefreshCw,
  CheckSquare,
  CircleDot,
  ClipboardList,
  Flame,
  Vote,
  Trophy,
  Star,
  Megaphone,
  Pencil,
  X,
  Gift,
  Brain,
  Lightbulb,
  Clock,
  ChevronDown,
  ChevronUp,
  BarChart3,
  Loader2,
  HandHeart,
} from 'lucide-react';
import { getDB, fetchLatestDB, onDBUpdate, DB, saveDB } from '../services/db';
import { isSupabaseConfigured } from '../services/supabase';
import { User, Family, ChoreCompletion, MonthlySummary, SmartSuggestion, SpecialDate } from '../types';
import { useLocale } from '../contexts/LocaleContext';
import { format, isToday, isBefore, isAfter, startOfDay, startOfMonth, endOfMonth, isSameMonth, addDays, differenceInDays, subMonths } from 'date-fns';
import { Link } from 'react-router-dom';
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts';
import { APP_CONFIG } from '../appConfig';
import { generateMonthlySummary, generateSmartSuggestions, type MonthlySummaryInput, type SmartSuggestionsInput } from '../services/gemini';
import { useFeature } from '../hooks/useFeature';

const Dashboard: React.FC<{ user: User; family: Family; onSwitchUser?: (user: User, family: Family) => void }> = ({ user, family, onSwitchUser }) => {
  const [db, setDb] = useState<DB>(getDB());
  const { fmtCurrency, fmtCurrencyCompact, weightUnit } = useLocale();

  // Refresh when realtime broadcasts update the DB
  useEffect(() => {
    return onDBUpdate(() => setDb(getDB()));
  }, []);
  const [isLoading, setIsLoading] = useState(false);
  const [editingAnnouncement, setEditingAnnouncement] = useState(false);
  const [announcementDraft, setAnnouncementDraft] = useState('');
  const today = useMemo(() => new Date(), []); // stable across renders; refreshes on remount
  const monthStart = useMemo(() => startOfMonth(today), [today]);
  const monthEnd = useMemo(() => endOfMonth(today), [today]);

  // Fetch from Supabase on mount
  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    fetchLatestDB().then(fresh => {
      if (!cancelled) {
        setDb(fresh);
        setIsLoading(false);
      }
    }).catch(() => {
      if (!cancelled) setIsLoading(false);
    });
    return () => { cancelled = true; };
  }, []);

  const handleRefresh = async () => {
    setIsLoading(true);
    try {
      const fresh = await fetchLatestDB();
      setDb(fresh);
    } catch {
      // fetchLatestDB catches most network errors internally and returns local
      // data, so this fires for unexpected runtime errors. Still show feedback
      // so the user isn't left wondering whether the tap did anything.
      alert("Couldn't sync with the cloud right now. Check your connection!");
    } finally {
      setIsLoading(false);
    }
  };

  // ---------- TASKS ----------
  const todayTasks = useMemo(() => {
    return db.tasks
      .filter(t => t.familyId === family.id && !t.completed && t.dueDate && (isToday(new Date(t.dueDate)) || isBefore(new Date(t.dueDate), startOfDay(today))))
      .sort((a, b) => {
        const prio = { HIGH: 0, MEDIUM: 1, LOW: 2 };
        return (prio[a.priority] || 2) - (prio[b.priority] || 2);
      });
  }, [db.tasks, family.id]);

  const completedTodayCount = useMemo(() => {
    return db.tasks.filter(t => t.familyId === family.id && t.completed && t.dueDate && isToday(new Date(t.dueDate))).length;
  }, [db.tasks, family.id]);

  // ---------- CALENDAR ----------
  const upcomingEvents = useMemo(() => {
    return db.events
      .filter(e => e.familyId === family.id && isAfter(new Date(e.end), startOfDay(today)))
      .sort((a, b) => new Date(a.start).getTime() - new Date(b.start).getTime())
      .slice(0, 3);
  }, [db.events, family.id]);

  // ---------- BUDGET ----------
  const budgetSummary = useMemo(() => {
    const monthTransactions = db.transactions.filter(t =>
      t.familyId === family.id && isSameMonth(new Date(t.date), today)
    );
    const totalExpenses = monthTransactions.filter(t => t.type === 'EXPENSE').reduce((a, c) => a + c.amount, 0);
    const totalIncome = monthTransactions.filter(t => t.type === 'INCOME').reduce((a, c) => a + c.amount, 0);
    const byCategory = db.budgetCategories
      .filter(c => c.familyId === family.id)
      .map(cat => ({
        name: cat.name,
        value: monthTransactions.filter(t => t.categoryId === cat.id && t.type === 'EXPENSE').reduce((a, c) => a + c.amount, 0),
        limit: cat.limit,
        color: cat.color,
      }))
      .filter(c => c.value > 0);

    return { totalExpenses, totalIncome, net: totalIncome - totalExpenses, byCategory };
  }, [db.transactions, db.budgetCategories, family.id]);

  // ---------- LISTS ----------
  const activeLists = useMemo(() => {
    return db.lists
      .filter(l => l.familyId === family.id)
      .map(l => ({
        ...l,
        checkedCount: l.items.filter(i => i.checked).length,
        totalCount: l.items.length,
      }))
      .sort((a, b) => {
        const aProgress = a.totalCount > 0 ? a.checkedCount / a.totalCount : 1;
        const bProgress = b.totalCount > 0 ? b.checkedCount / b.totalCount : 1;
        return aProgress - bProgress;
      })
      .slice(0, 4);
  }, [db.lists, family.id]);

  // ---------- MEALS ----------
  const todayMeals = useMemo(() => {
    const todayStr = format(today, 'yyyy-MM-dd');
    return db.mealPlans.filter(m =>
      m.familyId === family.id &&
      format(new Date(m.date), 'yyyy-MM-dd') === todayStr
    );
  }, [db.mealPlans, family.id]);

  const todayRecipes = useMemo(() => {
    return todayMeals.map(m => {
      const recipe = m.recipeId ? db.recipes.find(r => r.id === m.recipeId) : null;
      return { mealType: m.mealType, name: recipe?.title || m.customMeal || 'Not planned', hasRecipe: !!recipe };
    });
  }, [todayMeals, db.recipes]);

  // ---------- DEVOTIONAL ----------
  const latestDevotional = useMemo(() => {
    return db.devotionals
      .filter(d => d.familyId === family.id)
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())[0] || null;
  }, [db.devotionals, family.id]);

  // ---------- BIRTHDAYS ----------
  const upcomingBirthdays = useMemo(() => {
    // Compute midnight-today once (avoid mutating a Date inside the map)
    const nowMs = new Date().setHours(0, 0, 0, 0);
    const thisYear = new Date(nowMs).getFullYear();
    return (db.specialDates || [])
      .filter(d => d.familyId === family.id)
      .map(d => {
        let next = new Date(thisYear, d.month - 1, d.day);
        if (next.getTime() < nowMs) next = new Date(thisYear + 1, d.month - 1, d.day);
        const days = Math.round((next.getTime() - nowMs) / 86400000);
        const turningAge = d.year ? next.getFullYear() - d.year : null;
        return { ...d, days, turningAge };
      })
      .filter(d => d.days <= 7)
      .sort((a, b) => a.days - b.days);
  }, [db.specialDates, family.id]);

  // ---------- PRAYER WALL ----------
  const recentPrayers = useMemo(() => {
    return (db.prayerWall || [])
      .filter(e => e.familyId === family.id && e.visibility === 'FAMILY')
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
      .slice(0, 3);
  }, [db.prayerWall, family.id]);

  // ---------- READING PLANS ----------
  const activeReadingPlan = useMemo(() => {
    const plans = (db.readingPlans || []).filter(p => p.familyId === family.id);
    const progress = (db.readingPlanProgress || []).filter(p => p.userId === user.id && p.familyId === family.id);
    // Find a plan in progress (not 100% complete)
    for (const plan of plans) {
      const prog = progress.find(p => p.planId === plan.id);
      const completed = prog?.completedDays.length || 0;
      if (completed < plan.totalDays) {
        return { plan, completed, total: plan.totalDays, streak: prog?.currentStreak || 0 };
      }
    }
    return null;
  }, [db.readingPlans, db.readingPlanProgress, family.id, user.id]);

  // ---------- FITNESS ----------
  const recentFitness = useMemo(() => {
    return db.fitness
      .filter(f => f.userId === user.id)
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
      .slice(0, 3);
  }, [db.fitness, user.id]);

  // ---------- HABITS ----------
  const todayHabits = useMemo(() => {
    const todayStr = format(today, 'yyyy-MM-dd');
    const myHabits = db.dailyHabits.filter(h => h.userId === user.id).sort((a, b) => a.order - b.order);
    return myHabits.map(h => ({
      ...h,
      done: db.dailyHabitCompletions.some(c => c.habitId === h.id && c.date === todayStr),
    }));
  }, [db.dailyHabits, db.dailyHabitCompletions, user.id]);

  const habitsCompleted = todayHabits.filter(h => h.done).length;
  const habitsTotal = todayHabits.length;

  // ---------- CHORES ----------
  const todayChores = useMemo(() => {
    const dayOfWeek = today.getDay();
    const todayStr = format(today, 'yyyy-MM-dd');
    const chores = Array.isArray(db.chores) ? db.chores : [];
    const completions = Array.isArray(db.choreCompletions) ? db.choreCompletions : [];
    const familyChores = chores.filter(c => {
      if (c.familyId !== family.id) return false;
      if (c.frequency === 'DAILY') return true;
      const days = Array.isArray(c.daysOfWeek) ? c.daysOfWeek : [];
      return days.includes(dayOfWeek);
    });
    return familyChores.map(c => {
      const myCompletion = completions.some(
        comp => comp.choreId === c.id && comp.userId === user.id && comp.date === todayStr
      );
      return { ...c, done: myCompletion };
    });
  }, [db.chores, db.choreCompletions, family.id, user.id]);

  const myChores = useMemo(() => todayChores.filter(c => {
    const assignees = Array.isArray(c.assignees) ? c.assignees : [];
    return assignees.includes(user.id);
  }), [todayChores, user.id]);
  const myChoresDone = myChores.filter(c => c.done).length;

  // Leaderboard: all-time points per family member
  const leaderboard = useMemo(() => {
    const scores: Record<string, number> = {};
    const completionsArr = Array.isArray(db.choreCompletions) ? db.choreCompletions : [];
    completionsArr.filter(c => c.familyId === family.id).forEach(c => {
      const chore = (Array.isArray(db.chores) ? db.chores : []).find(ch => ch.id === c.choreId);
      if (chore) scores[c.userId] = (scores[c.userId] || 0) + chore.points;
    });
    return Object.entries(scores)
      .map(([userId, pts]) => {
        const member = db.users.find(u => u.id === userId);
        return { userId, name: member?.name || 'Unknown', totalPoints: pts };
      })
      .sort((a, b) => b.totalPoints - a.totalPoints)
      .slice(0, 5);
  }, [db.choreCompletions, db.chores, db.users, family.id]);

  // Streak helper (longest current streak for a chore)
  const getChoreStreak = (choreId: string): number => {
    const chore = db.chores.find(c => c.id === choreId);
    if (!chore) return 0;
    let streak = 0;
    for (let i = 0; i < 365; i++) {
      const d = new Date(today);
      d.setDate(today.getDate() - i);
      const dateStr = format(d, 'yyyy-MM-dd');
      const dayOfWeek = d.getDay();
      const isScheduled = chore.frequency === 'DAILY' || chore.daysOfWeek.includes(dayOfWeek);
      if (!isScheduled) continue;
      const done = db.choreCompletions.some(c => c.choreId === choreId && c.userId === user.id && c.date === dateStr);
      if (done) streak++;
      else if (i === 0) continue; // Grace period: don't break streak if today's chore isn't done yet
      else break;
    }
    return streak;
  };

  // ---------- POLLS ----------
  const openPolls = useMemo(() => {
    return db.polls
      .filter(p => p.familyId === family.id && p.status === 'OPEN')
      .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
      .slice(0, 3);
  }, [db.polls, family.id]);

  const myPollVotes = useMemo(() => {
    return db.pollVotes.filter(v => v.familyId === family.id && v.userId === user.id);
  }, [db.pollVotes, family.id, user.id]);

  // ---------- REWARDS BALANCE (kids) ----------
  const myKidBalance = useMemo(() => {
    const chores = Array.isArray(db.chores) ? db.chores : [];
    const completions = Array.isArray(db.choreCompletions) ? db.choreCompletions : [];
    const redemptions = Array.isArray(db.rewardRedemptions) ? db.rewardRedemptions : [];
    const earned = completions
      .filter(c => c.userId === user.id && c.familyId === family.id)
      .reduce((sum, c) => {
        const chore = chores.find(ch => ch.id === c.choreId);
        return sum + (chore?.reward || 0);
      }, 0);
    const spent = redemptions
      .filter(r => r.userId === user.id && r.familyId === family.id && (r.status === 'APPROVED' || r.status === 'PENDING'))
      .reduce((sum, r) => sum + r.amount, 0);
    return Math.max(0, earned - spent);
  }, [db.chores, db.choreCompletions, db.rewardRedemptions, family.id, user.id]);

  const MEAL_ORDER = ['BREAKFAST', 'LUNCH', 'DINNER'] as const;
  const mealDisplay = MEAL_ORDER.map(type => {
    const found = todayRecipes.find(r => r.mealType === type);
    return { type, name: found?.name || 'Not planned', planned: !!found };
  });

  const getDaysUntil = (dateStr: string): number => {
    const eventDay = startOfDay(new Date(dateStr));
    const todayStart = startOfDay(today);
    return Math.ceil((eventDay.getTime() - todayStart.getTime()) / (1000 * 60 * 60 * 24));
  };

  // -----------------------------------------------------------------------
  // Quick kid account switcher — other restricted family members on this device
  // -----------------------------------------------------------------------
  const switchableKids = useMemo(() => {
    const restrictedMembers = db.familyMembers.filter(
      m => m.familyId === family.id &&
        m.userId !== user.id &&
        m.moduleAccess && m.moduleAccess.length > 0
    );
    return restrictedMembers
      .map(m => db.users.find(u => u.id === m.userId))
      .filter(Boolean) as User[];
  }, [db.familyMembers, db.users, family.id, user.id]);

  const handleSwitchKid = (switchTo: User) => {
    const membership = db.familyMembers.find(
      m => m.userId === switchTo.id && m.familyId === family.id
    );
    const switchFamily = membership ? db.families.find(f => f.id === membership.familyId) : null;
    if (switchFamily && onSwitchUser) {
      localStorage.setItem(APP_CONFIG.activeUserKey, switchTo.id);
      onSwitchUser(switchTo, switchFamily);
    }
  };

  // -----------------------------------------------------------------------
  // Chore toggle (used by kids dashboard inline completion)
  // -----------------------------------------------------------------------
  const handleToggleChore = (choreId: string) => {
    const todayDate = format(today, 'yyyy-MM-dd');
    const existing = db.choreCompletions.find(
      c => c.choreId === choreId && c.userId === user.id && c.date === todayDate
    );
    let newCompletions: ChoreCompletion[];
    if (existing) {
      newCompletions = db.choreCompletions.filter(c => c.id !== existing.id);
    } else {
      const newCompletion: ChoreCompletion = {
        id: Math.random().toString(36).substr(2, 9),
        choreId,
        userId: user.id,
        familyId: family.id,
        date: todayDate,
        completedAt: new Date().toISOString(),
      };
      newCompletions = [...db.choreCompletions, newCompletion];
    }
    const newDb = { ...db, choreCompletions: newCompletions };
    setDb(newDb);
    saveDB(newDb, { userId: user.id, userName: user.name, action: existing ? 'unchecked a chore' : 'completed a chore', module: 'Chores', detail: '' });
  };

  // -----------------------------------------------------------------------
  // Family Announcement
  // -----------------------------------------------------------------------
  const currentFamily = db.families.find(f => f.id === family.id);
  const currentAnnouncement = currentFamily?.announcement || '';

  const handleSaveAnnouncement = () => {
    const updatedFamilies = db.families.map(f =>
      f.id === family.id
        ? { ...f, announcement: announcementDraft.trim(), announcementAuthor: user.name }
        : f
    );
    const newDb = { ...db, families: updatedFamilies };
    setDb(newDb);
    saveDB(newDb, { userId: user.id, userName: user.name, action: 'updated the announcement', module: 'Dashboard', detail: '' });
    setEditingAnnouncement(false);
  };

  const handleClearAnnouncement = () => {
    const updatedFamilies = db.families.map(f =>
      f.id === family.id ? { ...f, announcement: '', announcementAuthor: '' } : f
    );
    const newDb = { ...db, families: updatedFamilies };
    setDb(newDb);
    saveDB(newDb, { userId: user.id, userName: user.name, action: 'cleared the announcement', module: 'Dashboard', detail: '' });
    setEditingAnnouncement(false);
  };

  // -----------------------------------------------------------------------
  // Kids / restricted-access dashboard
  // -----------------------------------------------------------------------
  const userMembership = db.familyMembers.find(m => m.userId === user.id && m.familyId === family.id);
  const isRestricted = !!(userMembership?.moduleAccess && userMembership.moduleAccess.length > 0);
  const canEditAnnouncement = !isRestricted && (userMembership?.role === 'OWNER' || userMembership?.role === 'ADMIN');

  // Respect family-level module toggle (undefined or [] = all enabled)
  const isModuleEnabled = (path: string): boolean => {
    if (!family.enabledModules || family.enabledModules.length === 0) return true;
    return family.enabledModules.includes(path);
  };

  // -----------------------------------------------------------------------
  // Welcome / onboarding banner
  // -----------------------------------------------------------------------
  const trialDaysLeft = useMemo(() => {
    if (!currentFamily?.createdAt) return null;
    const created = new Date(currentFamily.createdAt);
    const daysUsed = Math.floor((today.getTime() - created.getTime()) / (1000 * 60 * 60 * 24));
    return Math.max(0, 14 - daysUsed);
  }, [currentFamily?.createdAt]);

  const MODULE_WELCOME_SUGGESTIONS = [
    { path: '/meals',      emoji: '🍽️', title: 'Plan your first week of meals',    desc: 'Use the AI Week Planner to fill your meal plan and build a categorised shopping list.' },
    { path: '/budget',     emoji: '💰', title: 'Track your family spending',        desc: 'Add expense categories and log transactions to see where your money goes.' },
    { path: '/chores',     emoji: '🧹', title: 'Set up your chore chart',           desc: 'Assign daily chores to family members with points and cash rewards.' },
    { path: '/tasks',      emoji: '✅', title: 'Create your first shared task',     desc: 'Add tasks, assign them to family members, and track progress together.' },
    { path: '/calendar',   emoji: '📅', title: 'Add your family events',            desc: 'Sync school events and appointments to your shared family calendar.' },
    { path: '/rewards',    emoji: '🎁', title: 'Set up a rewards store',            desc: 'Create rewards kids can redeem using their earned points.' },
    { path: '/fitness',    emoji: '💪', title: 'Start your fitness journey',        desc: 'Log workouts, track weight progress and build healthy daily habits.' },
    { path: '/devotional', emoji: '📖', title: 'Start your first devotional',       desc: 'Generate a personalised family devotional for today.' },
    { path: '/prayer-wall', emoji: '🙏', title: 'Share a prayer or gratitude',     desc: 'Post what you\'re thankful for or lift up a prayer request for your family.' },
    { path: '/lists',      emoji: '📋', title: 'Create a shopping list',            desc: 'Build and share grocery lists with your whole family.' },
    { path: '/polls',      emoji: '🗳️', title: 'Run a family poll',                 desc: 'Vote on dinner, holidays, movie night — anything the family decides together.' },
  ];

  const welcomeSuggestions = MODULE_WELCOME_SUGGESTIONS
    .filter(s => isModuleEnabled(s.path))
    .slice(0, 3);

  const handleDismissWelcome = () => {
    const updatedFamilies = db.families.map(f =>
      f.id === family.id ? { ...f, welcomeDismissed: true } : f
    );
    const newDb = { ...db, families: updatedFamilies };
    setDb(newDb);
    saveDB(newDb);
  };

  // -----------------------------------------------------------------------
  // AI Insights — Smart Suggestions & Monthly Summary
  // -----------------------------------------------------------------------
  const hasAIInsights = useFeature(family, 'ai_insights');

  // --- Smart Suggestions ---
  const [smartSuggestions, setSmartSuggestions] = useState<SmartSuggestion[]>([]);
  const [suggestionsLoading, setSuggestionsLoading] = useState(false);
  const [suggestionsError, setSuggestionsError] = useState('');
  const [suggestionsDismissed, setSuggestionsDismissed] = useState<Set<string>>(new Set());

  const buildSmartSuggestionsInput = useCallback((): SmartSuggestionsInput => {
    const todayStr = format(today, 'yyyy-MM-dd');
    const tomorrowStr = format(addDays(today, 1), 'yyyy-MM-dd');
    const threeDaysOut = addDays(today, 3);

    // Calendar context — next 3 days
    const upcoming3Days = db.events
      .filter(e => e.familyId === family.id && isAfter(new Date(e.start), startOfDay(today)) && isBefore(new Date(e.start), threeDaysOut))
      .map(e => ({
        title: e.title,
        start: format(new Date(e.start), 'h:mm a'),
        end: format(new Date(e.end), 'h:mm a'),
        day: format(new Date(e.start), 'EEEE'),
      }));

    const eventsToday = db.events.filter(e => e.familyId === family.id && format(new Date(e.start), 'yyyy-MM-dd') === todayStr).length;
    const eventsTomorrow = db.events.filter(e => e.familyId === family.id && format(new Date(e.start), 'yyyy-MM-dd') === tomorrowStr).length;

    // Meals context
    const todayPlanned = todayMeals.map(m => {
      const recipe = m.recipeId ? db.recipes.find(r => r.id === m.recipeId) : null;
      return { type: m.mealType, name: recipe?.title || m.customMeal || 'Unknown' };
    });
    const plannedTypes = new Set(todayPlanned.map(m => m.type));
    const allMealTypes = ['BREAKFAST', 'LUNCH', 'DINNER'] as const;
    const missingToday = allMealTypes.filter(t => !plannedTypes.has(t));

    const tomorrowMeals = db.mealPlans.filter(m => m.familyId === family.id && format(new Date(m.date), 'yyyy-MM-dd') === tomorrowStr);
    const tomorrowPlannedTypes = new Set(tomorrowMeals.map(m => m.mealType));
    const missingTomorrow = allMealTypes.filter(t => !tomorrowPlannedTypes.has(t));

    // Tasks context
    const overdueTasks = db.tasks
      .filter(t => t.familyId === family.id && !t.completed && t.dueDate && isBefore(new Date(t.dueDate), startOfDay(today)))
      .map(t => t.title).slice(0, 5);
    const dueToday = db.tasks
      .filter(t => t.familyId === family.id && !t.completed && t.dueDate && isToday(new Date(t.dueDate)))
      .map(t => t.title).slice(0, 5);

    // Devotional context
    const sortedDevotionals = db.devotionals
      .filter(d => d.familyId === family.id)
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
    const daysSinceLastDevotional = sortedDevotionals.length > 0
      ? differenceInDays(today, new Date(sortedDevotionals[0].date))
      : null;

    // Habits context
    const myHabits = db.dailyHabits.filter(h => h.userId === user.id);
    const notDone = myHabits
      .filter(h => !db.dailyHabitCompletions.some(c => c.habitId === h.id && c.date === todayStr))
      .map(h => h.label);

    // Budget context
    const overBudget = db.budgetCategories
      .filter(c => c.familyId === family.id)
      .filter(cat => {
        const spent = db.transactions
          .filter(t => t.categoryId === cat.id && t.type === 'EXPENSE' && isSameMonth(new Date(t.date), today))
          .reduce((a, c) => a + c.amount, 0);
        return spent > cat.limit && cat.limit > 0;
      })
      .map(c => c.name);

    // Prayer wall context
    const unansweredPrayers = (db.prayerWall || []).filter(e => e.familyId === family.id && e.type === 'REQUEST').length;
    const sortedPrayers = (db.prayerWall || [])
      .filter(e => e.familyId === family.id)
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
    const daysSinceLastPrayer = sortedPrayers.length > 0
      ? differenceInDays(today, new Date(sortedPrayers[0].date))
      : null;

    // Reading plan context
    const plans = (db.readingPlans || []).filter(p => p.familyId === family.id);
    const progresses = (db.readingPlanProgress || []).filter(p => p.userId === user.id && p.familyId === family.id);
    let activePlan: SmartSuggestionsInput['activeReadingPlan'] = null;
    for (const plan of plans) {
      const prog = progresses.find(p => p.planId === plan.id);
      const completed = prog?.completedDays?.length || 0;
      if (completed < plan.totalDays) {
        activePlan = { title: plan.title, currentDay: completed + 1, totalDays: plan.totalDays, streak: prog?.currentStreak || 0 };
        break;
      }
    }

    return {
      familyName: family.name,
      todayDate: format(today, 'EEEE, MMMM do yyyy'),
      upcomingEvents: upcoming3Days,
      mealsPlannedToday: todayPlanned,
      mealsMissingToday: missingToday,
      mealsMissingTomorrow: missingTomorrow,
      overdueTasks: overdueTasks,
      tasksDueToday: dueToday,
      daysSinceLastDevotional: daysSinceLastDevotional,
      habitsNotDoneToday: notDone,
      eventsToday,
      eventsTomorrow,
      overBudgetCategories: overBudget,
      unansweredPrayers,
      daysSinceLastPrayer,
      activeReadingPlan: activePlan,
    };
  }, [db, family, user, today, todayMeals]);

  const handleLoadSuggestions = useCallback(async () => {
    if (suggestionsLoading) return;
    setSuggestionsLoading(true);
    setSuggestionsError('');
    try {
      const input = buildSmartSuggestionsInput();
      const results = await generateSmartSuggestions(input);
      setSmartSuggestions(results.map((r, i) => ({ ...r, id: `sug-${i}-${Date.now()}` })));
    } catch (err: any) {
      setSuggestionsError(err.message || 'Failed to generate suggestions');
    } finally {
      setSuggestionsLoading(false);
    }
  }, [buildSmartSuggestionsInput, suggestionsLoading]);

  // Auto-load smart suggestions once on mount for AI subscribers
  useEffect(() => {
    if (hasAIInsights && !isRestricted && smartSuggestions.length === 0 && !suggestionsLoading) {
      handleLoadSuggestions();
    }
  }, [hasAIInsights, isRestricted]); // eslint-disable-line react-hooks/exhaustive-deps

  // --- Monthly Summary ---
  const [monthlySummary, setMonthlySummary] = useState<MonthlySummary | null>(null);
  const [summaryLoading, setSummaryLoading] = useState(false);
  const [summaryError, setSummaryError] = useState('');
  const [summaryExpanded, setSummaryExpanded] = useState(false);

  // Check if we should show the monthly summary (last 5 days of the month or any time user clicks)
  const dayOfMonth = today.getDate();
  const daysInMonth = endOfMonth(today).getDate();
  const isEndOfMonth = daysInMonth - dayOfMonth <= 5;

  const buildMonthlySummaryInput = useCallback((): MonthlySummaryInput => {
    const monthStr = format(today, 'MMMM yyyy');

    // Tasks this month
    const monthTasks = db.tasks.filter(t => t.familyId === family.id && t.dueDate && isSameMonth(new Date(t.dueDate), today));
    const tasksCompleted = monthTasks.filter(t => t.completed).length;
    const tasksCreated = monthTasks.length;

    // Events this month
    const eventsAttended = db.events.filter(e => e.familyId === family.id && isSameMonth(new Date(e.start), today)).length;

    // Meals this month
    const mealsPlanned = db.mealPlans.filter(m => m.familyId === family.id && isSameMonth(new Date(m.date), today)).length;

    // Devotionals this month
    const devotionalsShared = db.devotionals.filter(d => d.familyId === family.id && isSameMonth(new Date(d.date), today)).length;

    // Chores this month
    const monthCompletions = db.choreCompletions.filter(c => c.familyId === family.id && isSameMonth(new Date(c.date), today));
    const choresCompleted = monthCompletions.length;
    const totalChorePoints = monthCompletions.reduce((sum, c) => {
      const chore = db.chores.find(ch => ch.id === c.choreId);
      return sum + (chore?.points || 0);
    }, 0);

    // Top chore members
    const choreScores: Record<string, number> = {};
    monthCompletions.forEach(c => {
      choreScores[c.userId] = (choreScores[c.userId] || 0) + 1;
    });
    const topChoreMembers = Object.entries(choreScores)
      .map(([userId, completions]) => ({
        name: db.users.find(u => u.id === userId)?.name || 'Unknown',
        completions,
      }))
      .sort((a, b) => b.completions - a.completions)
      .slice(0, 5);

    // Budget
    const monthTransactions = db.transactions.filter(t => t.familyId === family.id && isSameMonth(new Date(t.date), today));
    const budgetIncome = monthTransactions.filter(t => t.type === 'INCOME').reduce((a, c) => a + c.amount, 0);
    const budgetExpenses = monthTransactions.filter(t => t.type === 'EXPENSE').reduce((a, c) => a + c.amount, 0);
    const topBudgetCategories = db.budgetCategories
      .filter(c => c.familyId === family.id)
      .map(cat => ({
        name: cat.name,
        amount: monthTransactions.filter(t => t.categoryId === cat.id && t.type === 'EXPENSE').reduce((a, c) => a + c.amount, 0),
      }))
      .filter(c => c.amount > 0)
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 5);

    // Fitness
    const workoutsLogged = db.fitness.filter(f => f.userId === user.id && f.type === 'WORKOUT' && isSameMonth(new Date(f.date), today)).length;

    // Habits completion rate
    const monthDays = dayOfMonth;
    const myHabits = db.dailyHabits.filter(h => h.userId === user.id);
    const totalHabitSlots = myHabits.length * monthDays;
    const completedHabits = db.dailyHabitCompletions.filter(c => c.userId === user.id && isSameMonth(new Date(c.date), today)).length;
    const habitsCompletionRate = totalHabitSlots > 0 ? Math.round((completedHabits / totalHabitSlots) * 100) : 0;

    // Lists completed
    const listsCompleted = db.lists.filter(l => l.familyId === family.id && l.items.length > 0 && l.items.every(i => i.checked)).length;

    // Polls voted
    const pollsVoted = new Set(db.pollVotes.filter(v => v.familyId === family.id && v.userId === user.id).map(v => v.pollId)).size;

    // Savings progress
    const savingsProgress = db.savingsGoals
      .filter(g => g.familyId === family.id && !g.completedAt)
      .map(g => ({
        title: g.title,
        percent: g.targetAmount > 0 ? Math.round((g.savedAmount / g.targetAmount) * 100) : 0,
      }));

    // Prayer wall this month
    const monthPrayers = (db.prayerWall || []).filter(e => e.familyId === family.id && isSameMonth(new Date(e.date), today));
    const prayerWallEntries = monthPrayers.length;
    const gratitudeCount = monthPrayers.filter(e => e.type === 'GRATITUDE').length;
    const answeredPrayers = monthPrayers.filter(e => e.type === 'ANSWERED').length;

    // Reading plans this month
    const readingPlansActive = (db.readingPlans || []).filter(p => p.familyId === family.id).length;
    const myProgress = (db.readingPlanProgress || []).filter(p => p.userId === user.id && p.familyId === family.id);
    const readingDaysCompleted = myProgress.reduce((sum, p) => sum + (p.completedDays?.length || 0), 0);
    const longestReadingStreak = myProgress.reduce((max, p) => Math.max(max, p.longestStreak || 0), 0);

    return {
      familyName: family.name,
      month: monthStr,
      tasksCompleted,
      tasksCreated,
      eventsAttended,
      mealsPlanned,
      devotionalsShared,
      choresCompleted,
      totalChorePoints,
      topChoreMembers,
      budgetIncome,
      budgetExpenses,
      topBudgetCategories,
      workoutsLogged,
      habitsCompletionRate,
      listsCompleted,
      pollsVoted,
      savingsProgress,
      prayerWallEntries,
      gratitudeCount,
      answeredPrayers,
      readingPlansActive,
      readingDaysCompleted,
      longestReadingStreak,
    };
  }, [db, family, user, today, dayOfMonth]);

  const handleLoadMonthlySummary = useCallback(async () => {
    if (summaryLoading) return;
    setSummaryLoading(true);
    setSummaryError('');
    try {
      const input = buildMonthlySummaryInput();
      const result = await generateMonthlySummary(input);
      setMonthlySummary({
        id: `summary-${Date.now()}`,
        familyId: family.id,
        month: format(today, 'yyyy-MM'),
        ...result,
        generatedAt: new Date().toISOString(),
      });
      setSummaryExpanded(true);
    } catch (err: any) {
      setSummaryError(err.message || 'Failed to generate summary');
    } finally {
      setSummaryLoading(false);
    }
  }, [buildMonthlySummaryInput, summaryLoading, family.id]);

  // --- Suggestion type styling ---
  const getSuggestionStyle = (type: string) => {
    switch (type) {
      case 'meal': return { bg: 'bg-amber-50', border: 'border-amber-200', icon: Utensils, iconColor: 'text-amber-500', badge: 'bg-amber-100 text-amber-700' };
      case 'devotional': return { bg: 'bg-sky-50', border: 'border-sky-200', icon: BookOpen, iconColor: 'text-sky-500', badge: 'bg-sky-100 text-sky-700' };
      case 'task': return { bg: 'bg-emerald-50', border: 'border-emerald-200', icon: CheckSquare, iconColor: 'text-emerald-500', badge: 'bg-emerald-100 text-emerald-700' };
      case 'wellness': return { bg: 'bg-green-50', border: 'border-green-200', icon: Activity, iconColor: 'text-green-500', badge: 'bg-green-100 text-green-700' };
      case 'family': return { bg: 'bg-violet-50', border: 'border-violet-200', icon: Sparkles, iconColor: 'text-violet-500', badge: 'bg-violet-100 text-violet-700' };
      case 'prayer': return { bg: 'bg-rose-50', border: 'border-rose-200', icon: HandHeart, iconColor: 'text-rose-500', badge: 'bg-rose-100 text-rose-700' };
      default: return { bg: 'bg-stone-50', border: 'border-stone-200', icon: Lightbulb, iconColor: 'text-stone-500', badge: 'bg-stone-100 text-stone-700' };
    }
  };

  if (isRestricted) {
    const firstName = user.name?.split(' ')[0] || user.name;
    return (
      <div className="space-y-8">
        {/* Family Announcement Banner */}
        {currentAnnouncement && (
          <div className="bg-amber-50 border border-amber-200 rounded-2xl px-5 py-4 flex items-start gap-3">
            <Megaphone size={18} className="text-amber-500 shrink-0 mt-0.5" />
            <p className="text-amber-900 font-semibold text-sm flex-1">{currentAnnouncement}</p>
          </div>
        )}

        {/* Welcome + Quick Switch */}
        <section className="space-y-4">
          <div className="flex flex-col sm:flex-row sm:items-end justify-between gap-4">
            <div>
              <h1 className="text-4xl font-bold text-stone-900 mb-2">Hey {firstName}!</h1>
              <p className="text-stone-500 font-medium">It's {format(today, 'EEEE, MMMM do')}. Here's your day.</p>
            </div>
            <button
              onClick={handleRefresh}
              disabled={isLoading}
              className="flex items-center space-x-2 bg-white border border-stone-200 text-stone-600 px-4 py-2 rounded-xl hover:bg-stone-50 transition-colors font-medium disabled:opacity-50 self-start sm:self-auto"
            >
              <RefreshCw size={16} className={isLoading ? 'animate-spin' : ''} />
              <span>{isLoading ? 'Syncing...' : 'Refresh'}</span>
            </button>
          </div>

          {/* Quick Account Switcher — shown when other kids are registered on this device */}
          {onSwitchUser && switchableKids.length > 0 && (
            <div className="flex items-center gap-3 flex-wrap">
              {/* Active kid chip */}
              <div className="flex items-center gap-2 bg-indigo-600 text-white px-4 py-2 rounded-2xl shadow-sm">
                <div className="w-6 h-6 rounded-full bg-white/30 flex items-center justify-center font-bold text-xs">
                  {user.name[0]}
                </div>
                <span className="font-bold text-sm">{firstName}</span>
                <div className="w-2 h-2 rounded-full bg-emerald-400" title="Active" />
              </div>

              <span className="text-stone-400 text-sm font-medium">·</span>

              {/* Other kids */}
              {switchableKids.map(kid => (
                <button
                  key={kid.id}
                  onClick={() => handleSwitchKid(kid)}
                  className="flex items-center gap-2 bg-white border border-stone-200 text-stone-700 px-4 py-2 rounded-2xl hover:bg-stone-50 hover:border-indigo-300 hover:text-indigo-700 transition-all shadow-sm font-bold text-sm"
                >
                  <div className="w-6 h-6 rounded-full bg-stone-200 text-stone-600 flex items-center justify-center font-bold text-xs">
                    {kid.name[0]}
                  </div>
                  {kid.name.split(' ')[0]}
                </button>
              ))}
            </div>
          )}
        </section>

        {/* Quick Stats */}
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
          {isModuleEnabled('/chores') && (
            <div className="bg-teal-50 rounded-2xl border border-teal-100 p-5 shadow-sm">
              <div className="flex items-center justify-between mb-2">
                <ClipboardList size={20} className="text-teal-500" />
                <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${myChores.length > 0 && myChoresDone === myChores.length ? 'bg-emerald-100 text-emerald-700' : 'bg-teal-100 text-teal-700'}`}>
                  {myChores.length > 0 ? `${Math.round((myChoresDone / myChores.length) * 100)}%` : '--'}
                </span>
              </div>
              <p className="text-3xl font-black text-stone-900">{myChoresDone}/{myChores.length}</p>
              <p className="text-sm text-teal-700 font-medium mt-1">Chores Done Today</p>
              <div className="h-1.5 bg-teal-100 rounded-full mt-3 overflow-hidden">
                <div
                  className="h-full bg-teal-500 rounded-full transition-all"
                  style={{ width: myChores.length > 0 ? `${(myChoresDone / myChores.length) * 100}%` : '0%' }}
                />
              </div>
            </div>
          )}
          {isModuleEnabled('/calendar') && (
            <div className="bg-indigo-50 rounded-2xl border border-indigo-100 p-5 shadow-sm">
              <div className="flex items-center justify-between mb-2">
                <CalendarIcon size={20} className="text-indigo-500" />
                <span className="text-[10px] font-bold text-indigo-600 bg-indigo-100 px-2 py-0.5 rounded-full">upcoming</span>
              </div>
              <p className="text-3xl font-black text-stone-900">{upcomingEvents.length}</p>
              <p className="text-sm text-indigo-700 font-medium mt-1">Upcoming Events</p>
            </div>
          )}
          {isModuleEnabled('/rewards') && (
            <div className="col-span-2 sm:col-span-1 bg-emerald-50 rounded-2xl border border-emerald-100 p-5 shadow-sm">
              <div className="flex items-center justify-between mb-2">
                <Gift size={20} className="text-emerald-500" />
                <span className="text-[10px] font-bold text-emerald-600 bg-emerald-100 px-2 py-0.5 rounded-full">balance</span>
              </div>
              <p className="text-3xl font-black text-stone-900">
                {fmtCurrency(myKidBalance)}
              </p>
              <p className="text-sm text-emerald-700 font-medium mt-1">Reward Balance</p>
            </div>
          )}
        </div>

        {/* Chores — hero card */}
        {isModuleEnabled('/chores') && <div className="bg-teal-50 rounded-3xl border border-teal-100 p-6 shadow-sm">
          <div className="flex items-center justify-between mb-5">
            <div className="flex items-center space-x-3">
              <div className="bg-teal-100 p-2 rounded-xl text-teal-600"><ClipboardList size={22} /></div>
              <h3 className="text-xl font-bold text-teal-900">My Chores Today</h3>
            </div>
            <Link to="/chores" className="text-teal-700 font-semibold text-sm hover:underline flex items-center">
              Full Chart <ArrowRight size={14} className="ml-1" />
            </Link>
          </div>
          {myChores.length > 0 ? (
            <div className="space-y-3">
              {myChores.map(chore => {
                const streak = getChoreStreak(chore.id);
                return (
                  <div
                    key={chore.id}
                    className={`flex items-center justify-between p-4 rounded-2xl transition-all ${chore.done ? 'bg-teal-100' : 'bg-white border border-teal-100'}`}
                  >
                    <div className="flex items-center space-x-4 min-w-0">
                      <span className="text-2xl shrink-0">{chore.icon}</span>
                      <div className="min-w-0">
                        <p className={`font-bold truncate ${chore.done ? 'text-teal-600 line-through' : 'text-stone-800'}`}>
                          {chore.title}
                        </p>
                        {streak > 0 && (
                          <p className="flex items-center space-x-1 text-xs text-orange-500 font-bold">
                            <Flame size={12} />
                            <span>{streak} day streak!</span>
                          </p>
                        )}
                      </div>
                    </div>
                    <div className="flex items-center space-x-3 shrink-0">
                      <span className="text-sm font-bold text-teal-600">{chore.points} pts</span>
                      <button
                        onClick={() => handleToggleChore(chore.id)}
                        className="w-8 h-8 rounded-full flex items-center justify-center transition-all active:scale-90"
                        style={chore.done ? { backgroundColor: chore.color } : undefined}
                        title={chore.done ? 'Mark incomplete' : 'Mark done'}
                      >
                        {chore.done
                          ? <CheckCircle2 size={18} className="text-white" />
                          : <div className="w-8 h-8 rounded-full border-2 border-dashed border-teal-300 hover:border-teal-500 transition-colors" />
                        }
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="text-center py-12">
              <div className="bg-teal-100 w-16 h-16 rounded-full flex items-center justify-center mx-auto mb-3 text-teal-500">
                <CheckCircle2 size={32} />
              </div>
              <p className="text-teal-700 font-bold">No chores today!</p>
              <p className="text-teal-400 text-sm mt-1">Enjoy your free time.</p>
            </div>
          )}
        </div>}

        {/* Points Leaderboard */}
        {isModuleEnabled('/chores') && leaderboard.length > 0 && (
          <div className="bg-white rounded-3xl border border-stone-200 p-6 shadow-sm">
            <div className="flex items-center space-x-3 mb-4">
              <div className="bg-amber-100 p-2 rounded-xl text-amber-500"><Trophy size={20} /></div>
              <h3 className="text-lg font-bold text-stone-800">Points Leaderboard</h3>
            </div>
            <div className="space-y-3">
              {leaderboard.map((entry, idx) => (
                <div
                  key={entry.userId}
                  className={`flex items-center justify-between p-3 rounded-2xl ${
                    idx === 0 ? 'bg-amber-50 border border-amber-200' :
                    idx === 1 ? 'bg-stone-50 border border-stone-200' :
                    'bg-stone-50/50'
                  }`}
                >
                  <div className="flex items-center space-x-3">
                    <div className={`w-8 h-8 rounded-full flex items-center justify-center font-black text-sm ${
                      idx === 0 ? 'bg-amber-400 text-white' :
                      idx === 1 ? 'bg-stone-400 text-white' :
                      idx === 2 ? 'bg-orange-400 text-white' :
                      'bg-stone-200 text-stone-600'
                    }`}>
                      {idx === 0 ? '👑' : idx + 1}
                    </div>
                    <span className="font-semibold text-stone-700 text-sm">{entry.userId === user.id ? `${entry.name} (You)` : entry.name.split(' ')[0]}</span>
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

        {/* Rewards Teaser */}
        {isModuleEnabled('/rewards') && <Link
          to="/rewards"
          className="block bg-gradient-to-r from-emerald-500 to-teal-600 rounded-3xl p-5 text-white shadow-lg shadow-emerald-100 hover:shadow-xl hover:shadow-emerald-200 transition-all"
        >
          <div className="flex items-center justify-between">
            <div>
              <div className="flex items-center gap-2 mb-1">
                <Gift size={20} />
                <span className="font-bold">Reward Store</span>
              </div>
              <p className="text-emerald-100 text-sm">
                You have <span className="font-black text-white">{fmtCurrency(myKidBalance)}</span> to spend!
              </p>
            </div>
            <ArrowRight size={22} className="text-emerald-200 shrink-0" />
          </div>
        </Link>}

        {/* Meals + Calendar grid */}
        {(isModuleEnabled('/meals') || isModuleEnabled('/calendar')) && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Today's Meals */}
            {isModuleEnabled('/meals') && (
              <div className="bg-amber-50 rounded-3xl border border-amber-100 p-6 relative overflow-hidden">
                <Utensils className="absolute -bottom-4 -right-4 w-24 h-24 text-amber-200 opacity-30" />
                <div className="flex items-center justify-between mb-4 relative z-10">
                  <h3 className="text-lg font-bold text-amber-900">Today's Meals</h3>
                  <Link to="/meals" className="text-amber-800 text-sm font-semibold hover:underline flex items-center">
                    Plan <ArrowRight size={14} className="ml-1" />
                  </Link>
                </div>
                <div className="space-y-2 relative z-10">
                  {mealDisplay.map(meal => (
                    <div key={meal.type} className="flex items-center justify-between p-3 bg-white/60 rounded-xl">
                      <div>
                        <p className="text-[10px] font-bold text-amber-600 uppercase">{meal.type}</p>
                        <p className={`text-sm font-semibold ${meal.planned ? 'text-amber-900' : 'text-stone-400 italic'}`}>{meal.name}</p>
                      </div>
                      {meal.planned && <Utensils size={14} className="text-amber-400" />}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Upcoming Events */}
            {isModuleEnabled('/calendar') && (
              <div className="bg-indigo-600 rounded-3xl p-6 text-white shadow-xl shadow-indigo-100 relative overflow-hidden">
                <Sparkles className="absolute -top-4 -right-4 w-28 h-28 text-indigo-500 opacity-20" />
                <div className="flex items-center justify-between mb-4 relative z-10">
                  <h3 className="text-lg font-bold">Upcoming Events</h3>
                  <Link to="/calendar" className="text-indigo-100 text-sm font-semibold hover:underline flex items-center">
                    Calendar <ArrowRight size={14} className="ml-1" />
                  </Link>
                </div>
                <div className="space-y-3 relative z-10">
                  {upcomingEvents.length > 0 ? upcomingEvents.map(event => (
                    <div key={event.id} className="bg-white/10 backdrop-blur-sm rounded-2xl p-3 border border-white/10">
                      <p className="text-[10px] font-bold text-indigo-200 uppercase tracking-wider mb-1">
                        {format(new Date(event.start), 'MMM d, h:mm a')}
                      </p>
                      <p className="font-bold text-sm leading-tight">{event.title}</p>
                      {event.location && <p className="text-[10px] text-indigo-100/70">{event.location}</p>}
                    </div>
                  )) : (
                    <div className="py-6 text-center text-indigo-100/50 italic text-sm">No events coming up.</div>
                  )}
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    );
  }

  // -----------------------------------------------------------------------
  // Full dashboard (parents / unrestricted users)
  // -----------------------------------------------------------------------
  return (
    <div className="space-y-8">
      {/* Welcome Header */}
      <section className="flex flex-col md:flex-row md:items-end justify-between gap-4">
        <div>
          <h1 className="text-4xl font-bold text-stone-900 mb-2">
            Hey {family.name}!
          </h1>
          <p className="text-stone-500 font-medium">It's {format(today, 'EEEE, MMMM do')}. Here's your family at a glance.</p>
        </div>
        <div className="flex items-center space-x-3">
          <button
            onClick={handleRefresh}
            disabled={isLoading}
            className="flex items-center space-x-2 bg-white border border-stone-200 text-stone-600 px-4 py-2 rounded-xl hover:bg-stone-50 transition-colors font-medium disabled:opacity-50"
            title="Refresh from cloud"
          >
            <RefreshCw size={16} className={isLoading ? 'animate-spin' : ''} />
            <span className="hidden sm:inline">{isLoading ? 'Syncing...' : 'Refresh'}</span>
          </button>
          {isModuleEnabled('/tasks') && (
            <Link to="/tasks" className="flex items-center space-x-2 bg-indigo-600 text-white px-4 py-2 rounded-xl hover:bg-indigo-700 transition-shadow shadow-lg shadow-indigo-100 font-medium">
              <Plus size={18} />
              <span>New Task</span>
            </Link>
          )}
          {isModuleEnabled('/budget') && (
            <Link to="/budget" className="flex items-center space-x-2 bg-white border border-stone-200 text-stone-700 px-4 py-2 rounded-xl hover:bg-stone-50 transition-colors font-medium">
              <TrendingUp size={18} />
              <span className="hidden sm:inline">Record Expense</span>
            </Link>
          )}
        </div>
      </section>

      {/* Family Announcement */}
      {(currentAnnouncement || canEditAnnouncement) && (
        <div className={`rounded-2xl border px-5 py-4 flex items-start gap-3 ${currentAnnouncement ? 'bg-amber-50 border-amber-200' : 'bg-stone-50 border-stone-200 border-dashed'}`}>
          <Megaphone size={18} className={`shrink-0 mt-0.5 ${currentAnnouncement ? 'text-amber-500' : 'text-stone-400'}`} />
          {editingAnnouncement ? (
            <div className="flex-1 flex items-center gap-2">
              <input
                autoFocus
                type="text"
                value={announcementDraft}
                onChange={(e) => setAnnouncementDraft(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') handleSaveAnnouncement(); if (e.key === 'Escape') setEditingAnnouncement(false); }}
                placeholder="Type a family announcement..."
                className="flex-1 bg-white border border-amber-200 rounded-xl px-3 py-2 text-sm text-stone-900 focus:outline-none focus:ring-2 focus:ring-amber-400/30"
              />
              <button onClick={handleSaveAnnouncement} className="px-3 py-2 bg-amber-500 text-white rounded-xl text-sm font-bold hover:bg-amber-600 transition-colors">Save</button>
              {currentAnnouncement && <button onClick={handleClearAnnouncement} className="px-3 py-2 bg-stone-100 text-stone-600 rounded-xl text-sm font-bold hover:bg-stone-200 transition-colors">Clear</button>}
              <button onClick={() => setEditingAnnouncement(false)} className="p-2 text-stone-400 hover:text-stone-600 rounded-xl hover:bg-stone-100 transition-colors"><X size={16} /></button>
            </div>
          ) : (
            <div className="flex-1 flex items-start justify-between gap-2">
              <p className={`text-sm font-semibold ${currentAnnouncement ? 'text-amber-900' : 'text-stone-400 italic'}`}>
                {currentAnnouncement || 'Pin a family announcement here...'}
              </p>
              {canEditAnnouncement && (
                <button
                  onClick={() => { setAnnouncementDraft(currentAnnouncement); setEditingAnnouncement(true); }}
                  className="p-1.5 text-stone-400 hover:text-amber-600 rounded-lg hover:bg-amber-50 transition-colors shrink-0"
                  title="Edit announcement"
                >
                  <Pencil size={14} />
                </button>
              )}
            </div>
          )}
        </div>
      )}

      {/* Upcoming Birthdays & Anniversaries (next 7 days) */}
      {upcomingBirthdays.length > 0 && isModuleEnabled('/birthdays') && (
        <div className="flex gap-3 overflow-x-auto pb-1 -mx-1 px-1">
          {upcomingBirthdays.map(d => (
            <Link key={d.id} to="/birthdays"
              className={`flex items-center gap-3 px-4 py-3 rounded-2xl border shrink-0 transition-all hover:shadow-md ${d.days === 0 ? 'bg-gradient-to-r from-rose-500 to-pink-500 text-white border-transparent shadow-lg shadow-rose-100' : 'bg-white border-stone-200 hover:border-pink-300'}`}>
              <span className="text-2xl">{d.emoji}</span>
              <div>
                <p className={`font-bold text-sm ${d.days === 0 ? 'text-white' : 'text-stone-800'}`}>{d.name}</p>
                <p className={`text-xs ${d.days === 0 ? 'text-white/80' : 'text-stone-500'}`}>
                  {d.days === 0 ? '🎉 Today!' : d.days === 1 ? 'Tomorrow' : `In ${d.days} days`}
                  {d.turningAge != null && ` · Turning ${d.turningAge}`}
                </p>
              </div>
            </Link>
          ))}
        </div>
      )}

      {/* Welcome / Onboarding Banner — shown until dismissed */}
      {!currentFamily?.welcomeDismissed && welcomeSuggestions.length > 0 && (
        <div className="bg-gradient-to-br from-indigo-600 to-violet-600 rounded-3xl p-6 md:p-8 text-white shadow-xl shadow-indigo-100 relative overflow-hidden">
          <Sparkles className="absolute -top-6 -right-6 w-40 h-40 opacity-10 pointer-events-none" />
          <div className="relative z-10">
            <div className="flex items-start justify-between gap-4 mb-5">
              <div>
                <p className="text-indigo-200 text-xs font-bold uppercase tracking-widest mb-1">
                  {trialDaysLeft !== null
                    ? trialDaysLeft > 0 ? `${trialDaysLeft} days left in your free trial` : 'Trial ended — upgrade to keep going'
                    : 'Welcome to your free trial'}
                </p>
                <h2 className="text-2xl font-black leading-tight">Welcome to {family.name}! 👋</h2>
                <p className="text-indigo-200 text-sm mt-1">Here's what you can do with your new hub — give these a try.</p>
              </div>
              {canEditAnnouncement && (
                <button
                  onClick={handleDismissWelcome}
                  className="p-2 text-indigo-300 hover:text-white hover:bg-white/10 rounded-xl transition-colors shrink-0"
                  title="Dismiss"
                >
                  <X size={18} />
                </button>
              )}
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              {welcomeSuggestions.map(s => (
                <Link
                  key={s.path}
                  to={s.path}
                  className="bg-white/10 hover:bg-white/20 backdrop-blur-sm rounded-2xl p-4 border border-white/10 transition-all group"
                >
                  <span className="text-2xl mb-2 block">{s.emoji}</span>
                  <p className="font-bold text-sm leading-snug mb-1">{s.title}</p>
                  <p className="text-indigo-200 text-xs leading-relaxed line-clamp-2">{s.desc}</p>
                  <div className="mt-3 flex items-center gap-1 text-indigo-200 group-hover:text-white text-xs font-bold transition-colors">
                    Get started <ArrowRight size={12} />
                  </div>
                </Link>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* AI Smart Suggestions */}
      {hasAIInsights && !isRestricted && (
        <div className="bg-gradient-to-br from-violet-50 to-indigo-50 rounded-3xl border border-violet-200/60 p-6 shadow-sm">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center space-x-3">
              <div className="bg-violet-100 p-2 rounded-xl text-violet-600"><Brain size={22} /></div>
              <div>
                <h3 className="text-lg font-bold text-violet-900">AI Suggestions</h3>
                <p className="text-xs text-violet-500 font-medium">Personalised for your day</p>
              </div>
            </div>
            <button
              onClick={handleLoadSuggestions}
              disabled={suggestionsLoading}
              className="flex items-center space-x-1.5 bg-violet-100 hover:bg-violet-200 text-violet-700 px-3 py-1.5 rounded-xl text-xs font-bold transition-colors disabled:opacity-50"
            >
              {suggestionsLoading ? <Loader2 size={14} className="animate-spin" /> : <RefreshCw size={14} />}
              <span>{suggestionsLoading ? 'Thinking...' : 'Refresh'}</span>
            </button>
          </div>
          {suggestionsError && (
            <p className="text-xs text-red-500 mb-3">{suggestionsError}</p>
          )}
          {suggestionsLoading && smartSuggestions.length === 0 ? (
            <div className="flex items-center justify-center py-8 space-x-3">
              <Loader2 size={20} className="animate-spin text-violet-400" />
              <p className="text-sm text-violet-400 font-medium">Analysing your schedule...</p>
            </div>
          ) : smartSuggestions.length > 0 ? (
            <div className="space-y-3">
              {smartSuggestions
                .filter(s => !suggestionsDismissed.has(s.id))
                .map(suggestion => {
                  const style = getSuggestionStyle(suggestion.type);
                  const SugIcon = style.icon;
                  return (
                    <div key={suggestion.id} className={`${style.bg} border ${style.border} rounded-2xl p-4 relative group`}>
                      <button
                        onClick={() => setSuggestionsDismissed(prev => new Set([...prev, suggestion.id]))}
                        className="absolute top-3 right-3 p-1 text-stone-300 hover:text-stone-500 opacity-0 group-hover:opacity-100 transition-opacity"
                      >
                        <X size={14} />
                      </button>
                      <div className="flex items-start space-x-3">
                        <SugIcon size={18} className={`${style.iconColor} mt-0.5 shrink-0`} />
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center space-x-2 mb-1">
                            <p className="font-bold text-sm text-stone-800">{suggestion.title}</p>
                            {suggestion.timeEstimate && (
                              <span className="flex items-center space-x-1 text-[10px] font-bold text-stone-400">
                                <Clock size={10} />
                                <span>{suggestion.timeEstimate}</span>
                              </span>
                            )}
                          </div>
                          <p className="text-xs text-stone-600 leading-relaxed mb-2">{suggestion.description}</p>
                          <div className="flex items-center justify-between">
                            <p className="text-[10px] text-stone-400 italic flex-1">{suggestion.reason}</p>
                            {suggestion.actionModule && (
                              <Link
                                to={suggestion.actionModule}
                                className={`${style.badge} text-[10px] font-bold px-2.5 py-1 rounded-full hover:opacity-80 transition-opacity flex items-center space-x-1`}
                              >
                                <span>Go</span>
                                <ArrowRight size={10} />
                              </Link>
                            )}
                          </div>
                        </div>
                      </div>
                    </div>
                  );
                })}
            </div>
          ) : (
            <div className="text-center py-6">
              <Lightbulb size={24} className="text-violet-300 mx-auto mb-2" />
              <p className="text-sm text-violet-400">No suggestions right now. Check back later!</p>
            </div>
          )}
        </div>
      )}

      {/* Quick Stats Bar */}
      <div className="grid grid-cols-2 sm:grid-cols-5 gap-4">
        {isModuleEnabled('/tasks') && (
          <div className="bg-white rounded-2xl border border-stone-200 p-4 shadow-sm">
            <div className="flex items-center justify-between mb-2">
              <CheckSquare size={18} className="text-emerald-500" />
              <span className="text-[10px] font-bold text-emerald-600 bg-emerald-50 px-2 py-0.5 rounded-full">{completedTodayCount} done</span>
            </div>
            <p className="text-2xl font-black text-stone-900">{todayTasks.length}</p>
            <p className="text-xs text-stone-400 font-medium">Tasks Due</p>
          </div>
        )}
        {isModuleEnabled('/chores') && (
          <div className="bg-white rounded-2xl border border-stone-200 p-4 shadow-sm">
            <div className="flex items-center justify-between mb-2">
              <ClipboardList size={18} className="text-teal-500" />
              <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${myChores.length > 0 && myChoresDone === myChores.length ? 'text-emerald-600 bg-emerald-50' : 'text-teal-600 bg-teal-50'}`}>
                {myChores.length > 0 ? `${Math.round((myChoresDone / myChores.length) * 100)}%` : '--'}
              </span>
            </div>
            <p className="text-2xl font-black text-stone-900">{myChoresDone}/{myChores.length}</p>
            <p className="text-xs text-stone-400 font-medium">Chores Today</p>
          </div>
        )}
        {isModuleEnabled('/calendar') && (
          <div className="bg-white rounded-2xl border border-stone-200 p-4 shadow-sm">
            <div className="flex items-center justify-between mb-2">
              <CalendarIcon size={18} className="text-indigo-500" />
              <span className="text-[10px] font-bold text-indigo-600 bg-indigo-50 px-2 py-0.5 rounded-full">upcoming</span>
            </div>
            <p className="text-2xl font-black text-stone-900">{db.events.filter(e => e.familyId === family.id && isSameMonth(new Date(e.start), today)).length}</p>
            <p className="text-xs text-stone-400 font-medium">Events This Month</p>
          </div>
        )}
        {isModuleEnabled('/budget') && (
          <div className="bg-white rounded-2xl border border-stone-200 p-4 shadow-sm">
            <div className="flex items-center justify-between mb-2">
              <Wallet size={18} className="text-pink-500" />
              <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${budgetSummary.net >= 0 ? 'text-emerald-600 bg-emerald-50' : 'text-red-600 bg-red-50'}`}>
                {budgetSummary.net >= 0 ? '+' : ''}{fmtCurrencyCompact(budgetSummary.net)}
              </span>
            </div>
            <p className="text-2xl font-black text-stone-900">{fmtCurrencyCompact(budgetSummary.totalExpenses)}</p>
            <p className="text-xs text-stone-400 font-medium">Spent This Month</p>
          </div>
        )}
        {isModuleEnabled('/fitness') && (
          <div className="bg-white rounded-2xl border border-stone-200 p-4 shadow-sm">
            <div className="flex items-center justify-between mb-2">
              <CircleDot size={18} className="text-violet-500" />
              <span className="text-[10px] font-bold text-violet-600 bg-violet-50 px-2 py-0.5 rounded-full">{habitsTotal > 0 ? `${Math.round((habitsCompleted / habitsTotal) * 100)}%` : '--'}</span>
            </div>
            <p className="text-2xl font-black text-stone-900">{habitsCompleted}/{habitsTotal}</p>
            <p className="text-xs text-stone-400 font-medium">Habits Today</p>
          </div>
        )}
      </div>

      {/* Countdown Cards */}
      {isModuleEnabled('/calendar') && upcomingEvents.length > 0 && (
        <div>
          <h2 className="text-xs font-bold text-stone-400 uppercase tracking-wider mb-3">Counting Down</h2>
          <div className="flex gap-3 overflow-x-auto pb-1">
            {upcomingEvents.map(event => {
              const days = getDaysUntil(event.start);
              return (
                <Link
                  key={event.id}
                  to="/calendar"
                  className="flex-shrink-0 bg-indigo-600 hover:bg-indigo-700 text-white rounded-2xl px-5 py-4 min-w-[140px] text-center shadow-md shadow-indigo-100 transition-colors"
                >
                  <p className="text-4xl font-black leading-none">
                    {days === 0 ? '🎉' : days}
                  </p>
                  {days !== 0 && (
                    <p className="text-xs text-indigo-200 font-medium mt-0.5">
                      {days === 1 ? 'day away' : 'days away'}
                    </p>
                  )}
                  <p className="text-sm font-bold mt-2 leading-tight line-clamp-2">{event.title}</p>
                </Link>
              );
            })}
          </div>
        </div>
      )}

      {/* Monthly Summary */}
      {hasAIInsights && !isRestricted && (
        <div className="bg-gradient-to-br from-indigo-600 to-violet-700 rounded-3xl p-6 text-white shadow-xl shadow-indigo-100 relative overflow-hidden">
          <BarChart3 className="absolute -top-6 -right-6 w-36 h-36 text-indigo-500 opacity-10" />
          <div className="relative z-10">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center space-x-3">
                <div className="bg-white/20 p-2 rounded-xl"><BarChart3 size={22} /></div>
                <div>
                  <h3 className="text-lg font-bold">{format(today, 'MMMM')} Family Recap</h3>
                  <p className="text-indigo-200 text-xs font-medium">
                    {isEndOfMonth ? 'Your month at a glance' : 'See how your month is going'}
                  </p>
                </div>
              </div>
              {!monthlySummary ? (
                <button
                  onClick={handleLoadMonthlySummary}
                  disabled={summaryLoading}
                  className="flex items-center space-x-1.5 bg-white/20 hover:bg-white/30 text-white px-4 py-2 rounded-xl text-sm font-bold transition-colors disabled:opacity-50"
                >
                  {summaryLoading ? <Loader2 size={14} className="animate-spin" /> : <Sparkles size={14} />}
                  <span>{summaryLoading ? 'Generating...' : 'Generate Recap'}</span>
                </button>
              ) : (
                <button
                  onClick={() => setSummaryExpanded(!summaryExpanded)}
                  className="flex items-center space-x-1 bg-white/20 hover:bg-white/30 text-white px-3 py-1.5 rounded-xl text-xs font-bold transition-colors"
                >
                  <span>{summaryExpanded ? 'Collapse' : 'Expand'}</span>
                  {summaryExpanded ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                </button>
              )}
            </div>

            {summaryError && (
              <p className="text-sm text-red-200 mb-3">{summaryError}</p>
            )}

            {summaryLoading && !monthlySummary && (
              <div className="flex items-center justify-center py-10 space-x-3">
                <Loader2 size={22} className="animate-spin text-indigo-300" />
                <p className="text-indigo-200 font-medium">Reviewing your month across all modules...</p>
              </div>
            )}

            {monthlySummary && (
              <>
                {/* Always-visible headline + top achievement */}
                <div className="mb-4">
                  <h4 className="text-xl font-black mb-2">{monthlySummary.headline}</h4>
                  <div className="flex items-center space-x-2 bg-white/10 rounded-xl px-4 py-2.5">
                    <Trophy size={16} className="text-amber-300 shrink-0" />
                    <p className="text-sm font-semibold">{monthlySummary.topAchievement}</p>
                  </div>
                </div>

                {/* Expandable details */}
                {summaryExpanded && (
                  <div className="space-y-5 animate-in fade-in duration-300">
                    {/* Highlights */}
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                      {monthlySummary.highlights.map((h, i) => (
                        <div key={i} className="bg-white/10 rounded-xl px-4 py-3 flex items-start space-x-3">
                          <span className="text-lg shrink-0">{h.icon}</span>
                          <div>
                            <p className="text-[10px] font-bold text-indigo-200 uppercase tracking-wider">{h.module}</p>
                            <p className="text-sm font-medium leading-snug">{h.text}</p>
                          </div>
                        </div>
                      ))}
                    </div>

                    {/* Encouragement */}
                    <div className="bg-white/10 rounded-2xl p-4">
                      <p className="text-sm leading-relaxed">{monthlySummary.encouragement}</p>
                    </div>

                    {/* Faith Note */}
                    <div className="bg-white/5 border border-white/10 rounded-2xl p-4">
                      <div className="flex items-center space-x-2 mb-2">
                        <BookOpen size={14} className="text-indigo-300" />
                        <span className="text-[10px] font-bold text-indigo-300 uppercase tracking-wider">Faith Note</span>
                      </div>
                      <p className="text-sm italic leading-relaxed text-indigo-100">{monthlySummary.faithNote}</p>
                    </div>

                    {/* Focus Areas */}
                    {monthlySummary.areasToFocus.length > 0 && (
                      <div>
                        <p className="text-[10px] font-bold text-indigo-300 uppercase tracking-wider mb-2">Focus for Next Month</p>
                        <div className="space-y-1.5">
                          {monthlySummary.areasToFocus.map((area, i) => (
                            <div key={i} className="flex items-center space-x-2 bg-white/10 rounded-xl px-3 py-2">
                              <Lightbulb size={12} className="text-amber-300 shrink-0" />
                              <p className="text-xs font-medium">{area}</p>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      )}

      {/* Main Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">

        {/* Column 1: Tasks + Calendar */}
        <div className="lg:col-span-2 space-y-8">

          {/* Today's Tasks */}
          {isModuleEnabled('/tasks') && <div className="bg-white rounded-3xl border border-stone-200 p-6 shadow-sm">
            <div className="flex items-center justify-between mb-5">
              <div className="flex items-center space-x-3">
                <div className="bg-emerald-100 p-2 rounded-xl text-emerald-600"><CheckCircle2 size={22} /></div>
                <h3 className="text-lg font-bold text-stone-800">Today's Focus</h3>
              </div>
              <Link to="/tasks" className="text-indigo-600 font-semibold text-sm hover:underline flex items-center">
                View all <ArrowRight size={14} className="ml-1" />
              </Link>
            </div>
            {todayTasks.length > 0 ? (
              <div className="space-y-2">
                {todayTasks.slice(0, 5).map(task => (
                  <div key={task.id} className="group flex items-center justify-between p-3 bg-stone-50 hover:bg-white border border-transparent hover:border-stone-200 rounded-2xl transition-all">
                    <div className="flex items-center space-x-3">
                      <div className={`w-2.5 h-2.5 rounded-full shrink-0 ${task.priority === 'HIGH' ? 'bg-red-500' : task.priority === 'MEDIUM' ? 'bg-amber-500' : 'bg-blue-500'}`} />
                      <div>
                        <p className="font-semibold text-stone-800 text-sm">{task.title}</p>
                        <p className="text-[10px] text-stone-400">{task.tags.join(', ')}</p>
                      </div>
                    </div>
                    <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                      task.dueDate && isBefore(new Date(task.dueDate), startOfDay(today)) ? 'bg-red-50 text-red-600' : 'bg-stone-100 text-stone-500'
                    }`}>
                      {task.dueDate && isBefore(new Date(task.dueDate), startOfDay(today)) ? 'Overdue' : 'Today'}
                    </span>
                  </div>
                ))}
                {todayTasks.length > 5 && (
                  <p className="text-xs text-stone-400 text-center pt-2">+{todayTasks.length - 5} more tasks</p>
                )}
              </div>
            ) : (
              <div className="text-center py-10">
                <div className="bg-stone-50 w-14 h-14 rounded-full flex items-center justify-center mx-auto mb-3 text-stone-300"><CheckCircle2 size={28} /></div>
                <p className="text-stone-500 text-sm">All clear! No tasks due today.</p>
              </div>
            )}
          </div>}

          {/* Upcoming Events */}
          {isModuleEnabled('/calendar') && <div className="bg-indigo-600 rounded-3xl p-6 text-white shadow-xl shadow-indigo-100 overflow-hidden relative">
            <Sparkles className="absolute -top-4 -right-4 w-32 h-32 text-indigo-500 opacity-20" />
            <div className="flex items-center justify-between mb-5 relative z-10">
              <div className="flex items-center space-x-3">
                <CalendarIcon size={22} />
                <h3 className="text-lg font-bold">Upcoming Events</h3>
              </div>
              <Link to="/calendar" className="text-indigo-100 font-semibold text-sm hover:underline">Full Schedule</Link>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3 relative z-10">
              {upcomingEvents.length > 0 ? upcomingEvents.map(event => (
                <div key={event.id} className="bg-white/10 backdrop-blur-md rounded-2xl p-4 border border-white/10">
                  <p className="text-[10px] font-bold text-indigo-200 uppercase tracking-wider mb-1">
                    {format(new Date(event.start), 'MMM d, h:mm a')}
                  </p>
                  <p className="font-bold mb-1 leading-tight">{event.title}</p>
                  {event.location && <p className="text-[10px] text-indigo-100/70">{event.location}</p>}
                </div>
              )) : (
                <div className="md:col-span-3 py-8 text-center text-indigo-100/50 italic">No events on the horizon.</div>
              )}
            </div>
          </div>}

          {/* Lists Overview */}
          {isModuleEnabled('/lists') && <div className="bg-white rounded-3xl border border-stone-200 p-6 shadow-sm">
            <div className="flex items-center justify-between mb-5">
              <div className="flex items-center space-x-3">
                <div className="bg-violet-100 p-2 rounded-xl text-violet-600"><ListTodo size={22} /></div>
                <h3 className="text-lg font-bold text-stone-800">Active Lists</h3>
              </div>
              <Link to="/lists" className="text-indigo-600 font-semibold text-sm hover:underline flex items-center">
                All lists <ArrowRight size={14} className="ml-1" />
              </Link>
            </div>
            {activeLists.length > 0 ? (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                {activeLists.map(list => {
                  const progress = list.totalCount > 0 ? Math.round((list.checkedCount / list.totalCount) * 100) : 0;
                  return (
                    <div key={list.id} className="p-4 bg-stone-50 rounded-2xl border border-stone-100 hover:border-violet-200 transition-all">
                      <div className="flex items-center justify-between mb-2">
                        <p className="font-bold text-sm text-stone-800 truncate flex-1">{list.title}</p>
                        <span className="text-[10px] font-bold text-stone-400 ml-2">{list.checkedCount}/{list.totalCount}</span>
                      </div>
                      <div className="h-1.5 w-full bg-stone-200 rounded-full overflow-hidden">
                        <div className="h-full bg-violet-500 rounded-full transition-all" style={{ width: `${progress}%` }} />
                      </div>
                    </div>
                  );
                })}
              </div>
            ) : (
              <div className="text-center py-8 text-stone-400 text-sm">No active lists. Create one from the Lists module.</div>
            )}
          </div>}
        </div>

        {/* Column 2: Budget + Meals + Devotional + Fitness */}
        <div className="space-y-8">

          {/* Budget Snapshot */}
          {isModuleEnabled('/budget') && <div className="bg-white rounded-3xl border border-stone-200 p-6 shadow-sm">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-bold text-stone-800">Budget</h3>
              <Link to="/budget" className="text-indigo-600 text-sm font-semibold hover:underline flex items-center">
                Details <ArrowRight size={14} className="ml-1" />
              </Link>
            </div>
            {budgetSummary.byCategory.length > 0 ? (
              <>
                <div className="h-48">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie data={budgetSummary.byCategory} cx="50%" cy="50%" innerRadius={50} outerRadius={70} paddingAngle={4} dataKey="value">
                        {budgetSummary.byCategory.map((entry, index) => (
                          <Cell key={`cell-${index}`} fill={entry.color} />
                        ))}
                      </Pie>
                      <Tooltip formatter={(value: number) => fmtCurrencyCompact(value)} />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                <div className="flex flex-wrap justify-center gap-3 mt-2">
                  {budgetSummary.byCategory.map((cat, i) => (
                    <div key={i} className="flex items-center space-x-1.5">
                      <div className="w-2 h-2 rounded-full" style={{ backgroundColor: cat.color }} />
                      <span className="text-[10px] text-stone-500 font-medium">{cat.name}</span>
                    </div>
                  ))}
                </div>
              </>
            ) : (
              <div className="text-center py-10 text-stone-400 text-sm">Start tracking to see insights.</div>
            )}
            <div className="mt-4 pt-4 border-t border-stone-100 grid grid-cols-2 gap-4">
              <div>
                <p className="text-[10px] text-stone-400 uppercase font-bold tracking-wider">Income</p>
                <p className="text-lg font-black text-emerald-600">{fmtCurrencyCompact(budgetSummary.totalIncome)}</p>
              </div>
              <div>
                <p className="text-[10px] text-stone-400 uppercase font-bold tracking-wider">Expenses</p>
                <p className="text-lg font-black text-stone-900">{fmtCurrencyCompact(budgetSummary.totalExpenses)}</p>
              </div>
            </div>
          </div>}

          {/* Today's Meals */}
          {isModuleEnabled('/meals') && <div className="bg-amber-50 rounded-3xl border border-amber-100 p-6 relative overflow-hidden">
            <Utensils className="absolute -bottom-4 -right-4 w-24 h-24 text-amber-200 opacity-30" />
            <div className="flex items-center justify-between mb-4 relative z-10">
              <h3 className="text-lg font-bold text-amber-900">Today's Meals</h3>
              <Link to="/meals" className="text-amber-800 text-sm font-semibold hover:underline flex items-center">
                Plan <ArrowRight size={14} className="ml-1" />
              </Link>
            </div>
            <div className="space-y-2 relative z-10">
              {mealDisplay.map(meal => (
                <div key={meal.type} className="flex items-center justify-between p-3 bg-white/60 rounded-xl">
                  <div>
                    <p className="text-[10px] font-bold text-amber-600 uppercase">{meal.type}</p>
                    <p className={`text-sm font-semibold ${meal.planned ? 'text-amber-900' : 'text-stone-400 italic'}`}>{meal.name}</p>
                  </div>
                  {meal.planned && <Utensils size={14} className="text-amber-400" />}
                </div>
              ))}
            </div>
          </div>}

          {/* Chores */}
          {isModuleEnabled('/chores') && <div className="bg-teal-50 rounded-3xl border border-teal-100 p-6 relative overflow-hidden">
            <ClipboardList className="absolute -bottom-3 -right-3 w-20 h-20 text-teal-200 opacity-30" />
            <div className="flex items-center justify-between mb-4 relative z-10">
              <h3 className="text-lg font-bold text-teal-900">Today's Chores</h3>
              <Link to="/chores" className="text-teal-700 text-sm font-semibold hover:underline flex items-center">
                Chart <ArrowRight size={14} className="ml-1" />
              </Link>
            </div>
            {myChores.length > 0 ? (
              <div className="space-y-2 relative z-10">
                {myChores.map(chore => {
                  const streak = getChoreStreak(chore.id);
                  return (
                    <div key={chore.id} className={`flex items-center justify-between p-3 rounded-xl transition-all ${chore.done ? 'bg-teal-100/60' : 'bg-white/60'}`}>
                      <div className="flex items-center space-x-3 min-w-0">
                        <span className="text-lg shrink-0">{chore.icon}</span>
                        <div className="min-w-0">
                          <p className={`text-sm font-semibold truncate ${chore.done ? 'text-teal-600 line-through' : 'text-teal-900'}`}>{chore.title}</p>
                          {streak > 0 && (
                            <p className="flex items-center space-x-1 text-[10px] text-orange-500 font-bold">
                              <Flame size={10} />
                              <span>{streak} day streak</span>
                            </p>
                          )}
                        </div>
                      </div>
                      <div className="flex items-center space-x-2 shrink-0">
                        <span className="text-[10px] font-bold text-teal-500">{chore.points} pts</span>
                        {chore.done ? (
                          <div className="w-6 h-6 rounded-full flex items-center justify-center text-white" style={{ backgroundColor: chore.color }}>
                            <CheckCircle2 size={14} />
                          </div>
                        ) : (
                          <div className="w-6 h-6 rounded-full border-2 border-dashed border-teal-300" />
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            ) : (
              <p className="text-sm text-teal-400 relative z-10">No chores assigned today. Enjoy the break!</p>
            )}
          </div>}

          {/* Devotional */}
          {isModuleEnabled('/devotional') && <div className="bg-sky-50 rounded-3xl border border-sky-100 p-6 relative overflow-hidden">
            <BookOpen className="absolute -bottom-3 -right-3 w-20 h-20 text-sky-200 opacity-30" />
            <div className="flex items-center justify-between mb-3 relative z-10">
              <h3 className="text-lg font-bold text-sky-900">Devotional</h3>
              <Link to="/devotional" className="text-sky-700 text-sm font-semibold hover:underline flex items-center">
                Open <ArrowRight size={14} className="ml-1" />
              </Link>
            </div>
            {latestDevotional ? (
              <div className="relative z-10">
                <p className="text-[10px] font-bold text-sky-500 uppercase tracking-wider mb-1">{format(new Date(latestDevotional.date), 'MMM d')}</p>
                <p className="font-bold text-sky-900 mb-1">{latestDevotional.title}</p>
                <p className="text-xs text-sky-700 italic leading-relaxed line-clamp-2">{latestDevotional.scripture}</p>
              </div>
            ) : (
              <p className="text-sm text-sky-400 relative z-10">No devotionals yet. Start your spiritual journey.</p>
            )}
          </div>}

          {/* Reading Plan Progress */}
          {isModuleEnabled('/devotional') && activeReadingPlan && <div className="bg-violet-50 rounded-3xl border border-violet-100 p-6 relative overflow-hidden">
            <Flame className="absolute -bottom-3 -right-3 w-20 h-20 text-violet-200 opacity-30" />
            <div className="flex items-center justify-between mb-3 relative z-10">
              <h3 className="text-lg font-bold text-violet-900">Reading Plan</h3>
              <Link to="/devotional" className="text-violet-700 text-sm font-semibold hover:underline flex items-center">
                Continue <ArrowRight size={14} className="ml-1" />
              </Link>
            </div>
            <div className="relative z-10">
              <p className="font-bold text-violet-900 mb-2 line-clamp-1">{activeReadingPlan.plan.title}</p>
              <div className="w-full h-2 bg-violet-100 rounded-full overflow-hidden mb-2">
                <div className="h-full bg-violet-500 rounded-full" style={{ width: `${Math.round((activeReadingPlan.completed / activeReadingPlan.total) * 100)}%` }} />
              </div>
              <div className="flex items-center justify-between">
                <span className="text-[10px] font-bold text-violet-500">{activeReadingPlan.completed}/{activeReadingPlan.total} days</span>
                {activeReadingPlan.streak > 0 && (
                  <span className="text-[10px] font-bold text-amber-600 flex items-center gap-0.5">
                    <Flame size={10} /> {activeReadingPlan.streak} day streak
                  </span>
                )}
              </div>
            </div>
          </div>}

          {/* Prayer Wall */}
          {isModuleEnabled('/prayer-wall') && <div className="bg-rose-50 rounded-3xl border border-rose-100 p-6 relative overflow-hidden">
            <HandHeart className="absolute -bottom-3 -right-3 w-20 h-20 text-rose-200 opacity-30" />
            <div className="flex items-center justify-between mb-3 relative z-10">
              <h3 className="text-lg font-bold text-rose-900">Prayer Wall</h3>
              <Link to="/prayer-wall" className="text-rose-700 text-sm font-semibold hover:underline flex items-center">
                Open <ArrowRight size={14} className="ml-1" />
              </Link>
            </div>
            {recentPrayers.length > 0 ? (
              <div className="space-y-2 relative z-10">
                {recentPrayers.map(entry => (
                  <div key={entry.id} className="p-2.5 bg-white/60 rounded-xl">
                    <div className="flex items-center gap-1.5 mb-0.5">
                      <span className="text-xs">{entry.type === 'GRATITUDE' ? '🌟' : entry.type === 'ANSWERED' ? '✨' : '🙏'}</span>
                      <span className="text-[10px] font-bold text-rose-500">
                        {(db.users.find(u => u.id === entry.creatorId)?.name || 'Unknown').split(' ')[0]}
                      </span>
                    </div>
                    <p className="text-xs text-rose-800 line-clamp-1">{entry.text}</p>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-sm text-rose-400 relative z-10">Share gratitude or lift up a prayer.</p>
            )}
          </div>}

          {/* Fitness */}
          {isModuleEnabled('/fitness') && <div className="bg-green-50 rounded-3xl border border-green-100 p-6 relative overflow-hidden">
            <Activity className="absolute -bottom-3 -right-3 w-20 h-20 text-green-200 opacity-30" />
            <div className="flex items-center justify-between mb-3 relative z-10">
              <h3 className="text-lg font-bold text-green-900">Fitness</h3>
              <Link to="/fitness" className="text-green-700 text-sm font-semibold hover:underline flex items-center">
                Log <ArrowRight size={14} className="ml-1" />
              </Link>
            </div>
            {recentFitness.length > 0 ? (
              <div className="space-y-2 relative z-10">
                {recentFitness.map(f => (
                  <div key={f.id} className="flex items-center justify-between p-2 bg-white/60 rounded-xl">
                    <div className="flex items-center gap-2">
                      <Dumbbell size={14} className="text-green-500" />
                      <div>
                        <p className="text-xs font-bold text-green-800 capitalize">{f.type.toLowerCase()}</p>
                        <p className="text-[10px] text-green-500">{format(new Date(f.date), 'MMM d')}</p>
                      </div>
                    </div>
                    <span className="text-sm font-black text-green-800">
                      {f.value}{f.type === 'WEIGHT' ? ` ${weightUnit}` : f.type === 'STEPS' ? ' steps' : ' min'}
                    </span>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-sm text-green-400 relative z-10">No fitness data logged yet.</p>
            )}
          </div>}

          {/* Polls */}
          {isModuleEnabled('/polls') && <div className="bg-fuchsia-50 rounded-3xl border border-fuchsia-100 p-6 relative overflow-hidden">
            <Vote className="absolute -bottom-3 -right-3 w-20 h-20 text-fuchsia-200 opacity-30" />
            <div className="flex items-center justify-between mb-4 relative z-10">
              <h3 className="text-lg font-bold text-fuchsia-900">Open Polls</h3>
              <Link to="/polls" className="text-fuchsia-700 text-sm font-semibold hover:underline flex items-center">
                All Polls <ArrowRight size={14} className="ml-1" />
              </Link>
            </div>
            {openPolls.length > 0 ? (
              <div className="space-y-2 relative z-10">
                {openPolls.map(poll => {
                  const voted = myPollVotes.some(v => v.pollId === poll.id);
                  const totalVotes = db.pollVotes.filter(v => v.pollId === poll.id).length;
                  const uniqueVoters = new Set(db.pollVotes.filter(v => v.pollId === poll.id).map(v => v.userId)).size;
                  return (
                    <Link key={poll.id} to="/polls" className={`block p-3 rounded-xl transition-all ${voted ? 'bg-fuchsia-100/60' : 'bg-white/60 hover:bg-white/80'}`}>
                      <p className={`text-sm font-semibold truncate ${voted ? 'text-fuchsia-600' : 'text-fuchsia-900'}`}>
                        {poll.question}
                      </p>
                      <div className="flex items-center space-x-3 mt-1 text-[10px] text-fuchsia-400">
                        <span>{poll.options.length} options</span>
                        <span>{uniqueVoters} voter{uniqueVoters !== 1 ? 's' : ''}</span>
                        {voted && <span className="text-fuchsia-600 font-bold">Voted</span>}
                        {!voted && <span className="text-fuchsia-600 font-bold">Vote now</span>}
                      </div>
                    </Link>
                  );
                })}
              </div>
            ) : (
              <p className="text-sm text-fuchsia-400 relative z-10">No open polls right now.</p>
            )}
          </div>}
        </div>
      </div>
    </div>
  );
};

export default Dashboard;

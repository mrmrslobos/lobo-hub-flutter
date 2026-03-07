
import React, { useState, useMemo, useEffect } from 'react';
import {
  BookOpen,
  Sparkles,
  Loader2,
  Heart,
  Share2,
  Bookmark,
  Search,
  Lock,
  Globe,
  HandHeart,
  Pencil,
  Check,
  X,
  ChevronDown,
  ChevronRight,
  Flame,
  Plus,
  Calendar,
  Trophy,
} from 'lucide-react';
import { DevotionalEntry, ReadingPlan, ReadingPlanProgress, Visibility, User, Family } from '../types';
import { generateDevotional, generateReadingPlan } from '../services/gemini';
import { format } from 'date-fns';
import { useRealtimeDB } from '../hooks/useRealtimeDB';

type DevotionalView = 'DEVOTIONAL' | 'PLANS';

const PLAN_DURATIONS = [
  { days: 7, label: '7 days' },
  { days: 14, label: '14 days' },
  { days: 21, label: '21 days' },
  { days: 30, label: '30 days' },
];

const PLAN_THEMES = [
  'Gratitude', 'Faith in Hard Times', 'Love & Kindness', 'Patience',
  'Courage', 'Forgiveness', 'Family Unity', 'Hope',
];

const Devotional: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const [view, setView] = useState<DevotionalView>('DEVOTIONAL');
  const [isAiLoading, setIsAiLoading] = useState(false);
  const [aiError, setAiError] = useState('');
  const [topic, setTopic] = useState('');
  const [searchTerm, setSearchTerm] = useState('');
  const [genVisibility, setGenVisibility] = useState<Visibility>('FAMILY');
  const [pastReadingsOpen, setPastReadingsOpen] = useState(false);

  // Reading plan state
  const [planTheme, setPlanTheme] = useState('');
  const [planDays, setPlanDays] = useState(7);
  const [activePlanId, setActivePlanId] = useState<string | null>(null);
  const [activePlanDay, setActivePlanDay] = useState<number | null>(null);
  const [isPlanGenerating, setIsPlanGenerating] = useState(false);
  const [planError, setPlanError] = useState('');

  const visibleDevotionals = useMemo(() => {
    return db.devotionals.filter(d =>
      (d.visibility === 'FAMILY' || d.creatorId === user.id) &&
      (d.familyId === family.id)
    );
  }, [db.devotionals, family.id, user.id]);

  const [activeEntryId, setActiveEntryId] = useState<string | null>(visibleDevotionals[0]?.id || null);

  useEffect(() => {
    if (!activeEntryId && visibleDevotionals.length > 0) {
      setActiveEntryId(visibleDevotionals[0].id);
    } else if (activeEntryId && !visibleDevotionals.some(d => d.id === activeEntryId)) {
      setActiveEntryId(visibleDevotionals[0]?.id || null);
    }
  }, [activeEntryId, visibleDevotionals]);

  const [isEditingPrayer, setIsEditingPrayer] = useState(false);
  const [prayerDraft, setPrayerDraft] = useState('');

  const activeEntry = useMemo(() => {
    return visibleDevotionals.find(d => d.id === activeEntryId);
  }, [visibleDevotionals, activeEntryId]);

  const filteredDevotionals = useMemo(() => {
    return visibleDevotionals.filter(d =>
      d.title.toLowerCase().includes(searchTerm.toLowerCase()) ||
      d.scripture.toLowerCase().includes(searchTerm.toLowerCase())
    );
  }, [visibleDevotionals, searchTerm]);

  // Reading plans data
  const familyPlans = useMemo(() => {
    return (db.readingPlans || [])
      .filter(p => p.familyId === family.id)
      .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
  }, [db.readingPlans, family.id]);

  const myProgress = useMemo(() => {
    return (db.readingPlanProgress || []).filter(p => p.userId === user.id && p.familyId === family.id);
  }, [db.readingPlanProgress, user.id, family.id]);

  const getProgressForPlan = (planId: string): ReadingPlanProgress | undefined => {
    return myProgress.find(p => p.planId === planId);
  };

  const activePlan = useMemo(() => {
    return familyPlans.find(p => p.id === activePlanId);
  }, [familyPlans, activePlanId]);

  const activePlanProgress = useMemo(() => {
    return activePlanId ? getProgressForPlan(activePlanId) : undefined;
  }, [activePlanId, myProgress]);

  // Calculate streak for a plan progress
  const calcStreak = (progress: ReadingPlanProgress | undefined): number => {
    return progress?.currentStreak || 0;
  };

  const shareEntry = (id: string) => {
    const newDevos = db.devotionals.map(d => d.id === id ? { ...d, visibility: 'FAMILY' as Visibility } : d);
    save({ ...db, devotionals: newDevos }, 'shared a devotional', 'Devotional', '');
  };

  const saveUserPrayer = () => {
    if (!activeEntryId) return;
    const newDevos = db.devotionals.map(d =>
      d.id === activeEntryId ? { ...d, userPrayer: prayerDraft.trim() } : d
    );
    save({ ...db, devotionals: newDevos }, 'updated a prayer', 'Devotional', '');
    setIsEditingPrayer(false);
  };

  const startEditingPrayer = () => {
    setPrayerDraft(activeEntry?.userPrayer || '');
    setIsEditingPrayer(true);
  };

  const handleGenerate = async () => {
    if (!topic) return;
    setIsAiLoading(true);
    setAiError('');
    try {
      const data = await generateDevotional(topic);
      const newEntry: DevotionalEntry = {
        id: Math.random().toString(36).substr(2, 9),
        familyId: family.id,
        creatorId: user.id,
        title: data.title || topic,
        scripture: data.scripture || '',
        content: data.content || '',
        reflectionPrompts: Array.isArray(data.reflectionPrompts) ? data.reflectionPrompts : [],
        prayer: data.prayer,
        tags: [topic],
        date: new Date().toISOString(),
        visibility: genVisibility
      };
      const newDb = { ...db, devotionals: [newEntry, ...db.devotionals] };
      save(newDb, 'created a devotional', 'Devotional', topic);
      setActiveEntryId(newEntry.id);
      setTopic('');
    } catch (e: any) {
      setAiError(e?.message || 'AI failed to generate devotional. Check your API key.');
    } finally {
      setIsAiLoading(false);
    }
  };

  const handleGeneratePlan = async () => {
    if (!planTheme) return;
    setIsPlanGenerating(true);
    setPlanError('');
    try {
      const data = await generateReadingPlan(planTheme, planDays);
      const plan: ReadingPlan = {
        id: Math.random().toString(36).substr(2, 9),
        familyId: family.id,
        creatorId: user.id,
        title: data.title || `${planTheme} (${planDays} days)`,
        description: data.description || '',
        totalDays: planDays,
        days: data.days || [],
        createdAt: new Date().toISOString(),
      };
      const newPlans = [plan, ...(db.readingPlans || [])];
      save({ ...db, readingPlans: newPlans }, 'created a reading plan', 'Devotional', plan.title);
      setActivePlanId(plan.id);
      setActivePlanDay(1);
      setPlanTheme('');
    } catch (e: any) {
      setPlanError(e?.message || 'AI failed to generate reading plan.');
    } finally {
      setIsPlanGenerating(false);
    }
  };

  const handleCompleteDay = (planId: string, dayNum: number) => {
    const existingProgress = getProgressForPlan(planId);
    const now = new Date().toISOString();

    if (existingProgress) {
      const alreadyDone = existingProgress.completedDays.includes(dayNum);
      if (alreadyDone) return;

      const newCompleted = [...existingProgress.completedDays, dayNum].sort((a, b) => a - b);
      // Calculate streak: count consecutive completed days ending at the latest
      let streak = 1;
      for (let i = newCompleted.length - 1; i > 0; i--) {
        if (newCompleted[i] - newCompleted[i - 1] === 1) streak++;
        else break;
      }
      const longestStreak = Math.max(existingProgress.longestStreak, streak);

      const updated = (db.readingPlanProgress || []).map(p =>
        p.id === existingProgress.id
          ? { ...p, completedDays: newCompleted, currentStreak: streak, longestStreak, lastCompletedAt: now }
          : p
      );
      save({ ...db, readingPlanProgress: updated }, 'completed a reading plan day', 'Devotional', `Day ${dayNum}`);
    } else {
      const newProgress: ReadingPlanProgress = {
        id: Math.random().toString(36).substr(2, 9),
        planId,
        userId: user.id,
        familyId: family.id,
        completedDays: [dayNum],
        currentStreak: 1,
        longestStreak: 1,
        startedAt: now,
        lastCompletedAt: now,
      };
      save(
        { ...db, readingPlanProgress: [...(db.readingPlanProgress || []), newProgress] },
        'started a reading plan',
        'Devotional',
        `Day ${dayNum}`
      );
    }
  };

  const handleDeletePlan = (planId: string) => {
    const newPlans = (db.readingPlans || []).filter(p => p.id !== planId);
    const newProgress = (db.readingPlanProgress || []).filter(p => p.planId !== planId);
    save({ ...db, readingPlans: newPlans, readingPlanProgress: newProgress }, 'deleted a reading plan', 'Devotional', '');
    if (activePlanId === planId) {
      setActivePlanId(null);
      setActivePlanDay(null);
    }
  };

  return (
    <div className="space-y-8">
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Spiritual Growth</h1>
          <p className="text-stone-500">Reflect, pray, and grow as a family.</p>
        </div>
        {/* View toggle */}
        <div className="flex bg-stone-100 rounded-xl overflow-hidden border border-stone-200">
          <button
            onClick={() => setView('DEVOTIONAL')}
            className={`flex items-center gap-2 px-4 py-2 text-sm font-bold transition-all ${view === 'DEVOTIONAL' ? 'bg-indigo-600 text-white' : 'text-stone-500 hover:text-stone-700'}`}
          >
            <BookOpen size={16} />
            Devotionals
          </button>
          <button
            onClick={() => setView('PLANS')}
            className={`flex items-center gap-2 px-4 py-2 text-sm font-bold transition-all ${view === 'PLANS' ? 'bg-indigo-600 text-white' : 'text-stone-500 hover:text-stone-700'}`}
          >
            <Calendar size={16} />
            Reading Plans
          </button>
        </div>
      </header>

      {/* ============================================================ */}
      {/* DEVOTIONALS VIEW                                              */}
      {/* ============================================================ */}
      {view === 'DEVOTIONAL' && (
        <>
          {/* AI Inspiration */}
          <div className="bg-gradient-to-r from-amber-600 to-orange-500 rounded-3xl p-6 text-white relative overflow-hidden shadow-xl shadow-orange-100">
            <BookOpen className="absolute right-[-20px] top-[-20px] w-48 h-48 opacity-10" />
            <div className="relative z-10">
              <h3 className="text-xl font-bold mb-2 flex items-center">
                <Sparkles size={20} className="mr-2" />
                AI Faith Assistant
              </h3>
              <p className="text-orange-50 text-sm mb-4">Need inspiration? Tell me a topic (e.g., Patience, Hope, Forgiveness) and I'll draft a devotional.</p>
              <div className="flex flex-col sm:flex-row gap-3">
                <input
                  type="text"
                  placeholder="Enter a topic..."
                  value={topic}
                  onChange={(e) => setTopic(e.target.value)}
                  className="flex-1 px-4 py-2 bg-white/10 backdrop-blur-md border border-white/20 rounded-xl text-white placeholder:text-white/50 focus:outline-none focus:ring-2 focus:ring-white/50"
                />
                <div className="flex bg-white/10 backdrop-blur-md rounded-xl overflow-hidden border border-white/20">
                  <button
                    onClick={() => setGenVisibility('FAMILY')}
                    className={`flex items-center gap-1 px-3 py-2 text-xs font-bold transition-all ${genVisibility === 'FAMILY' ? 'bg-white/20 text-white' : 'text-white/60'}`}
                  >
                    <Globe size={12} /> Shared
                  </button>
                  <button
                    onClick={() => setGenVisibility('PRIVATE')}
                    className={`flex items-center gap-1 px-3 py-2 text-xs font-bold transition-all ${genVisibility === 'PRIVATE' ? 'bg-white/20 text-white' : 'text-white/60'}`}
                  >
                    <Lock size={12} /> Private
                  </button>
                </div>
                <button
                  onClick={handleGenerate}
                  disabled={isAiLoading || !topic}
                  className="bg-white text-orange-600 px-6 py-2 rounded-xl font-bold hover:bg-stone-50 disabled:opacity-50 transition-colors flex items-center justify-center min-w-[140px]"
                >
                  {isAiLoading ? <Loader2 size={18} className="animate-spin" /> : 'Generate Now'}
                </button>
              </div>
              {aiError && (
                <p className="mt-3 text-sm text-red-200 bg-red-500/20 px-4 py-2 rounded-xl">{aiError}</p>
              )}
            </div>
          </div>

          {/* Active Reading */}
          {activeEntry ? (
            <article className="bg-white rounded-[2.5rem] border border-stone-200 p-8 md:p-12 shadow-sm space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500">
              <header className="space-y-4">
                <div className="flex flex-wrap gap-2 items-center">
                  {activeEntry.tags.map(tag => (
                    <span key={tag} className="text-[10px] font-black uppercase tracking-widest px-3 py-1 bg-stone-100 text-stone-500 rounded-full">{tag}</span>
                  ))}
                  {activeEntry.visibility === 'PRIVATE' && (
                    <span className="text-[10px] font-black uppercase tracking-widest px-3 py-1 bg-stone-800 text-white rounded-full flex items-center gap-1">
                      <Lock size={10} /> Private
                    </span>
                  )}
                </div>
                <h2 className="text-4xl font-black text-stone-900 leading-tight">{activeEntry.title}</h2>
                <p className="text-xl font-medium text-indigo-600 italic">"{activeEntry.scripture}"</p>
              </header>

              <div className="prose prose-stone max-w-none">
                <p className="text-lg text-stone-700 leading-relaxed whitespace-pre-wrap">
                  {activeEntry.content}
                </p>
              </div>

              <section className="bg-stone-50 rounded-3xl p-8 space-y-6">
                <h3 className="text-lg font-black text-stone-800 uppercase tracking-widest flex items-center">
                  <Heart size={18} className="mr-2 text-rose-500" />
                  Family Reflection
                </h3>
                <ul className="space-y-4">
                  {activeEntry.reflectionPrompts.map((p, i) => (
                    <li key={i} className="flex items-start space-x-3 text-stone-700 font-medium">
                      <span className="text-indigo-400 font-black">Q{i+1}.</span>
                      <span>{p}</span>
                    </li>
                  ))}
                </ul>
              </section>

              <section className="bg-amber-50 rounded-3xl p-8 space-y-5">
                <h3 className="text-lg font-black text-stone-800 uppercase tracking-widest flex items-center">
                  <HandHeart size={18} className="mr-2 text-amber-500" />
                  Prayer
                </h3>

                {activeEntry.prayer && (
                  <blockquote className="italic text-stone-600 leading-relaxed border-l-4 border-amber-300 pl-4">
                    "{activeEntry.prayer}"
                  </blockquote>
                )}

                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <p className="text-xs font-bold text-stone-500 uppercase tracking-widest">Your Prayer</p>
                    {!isEditingPrayer && (
                      <button
                        onClick={startEditingPrayer}
                        className="flex items-center gap-1 text-xs font-bold text-amber-600 hover:text-amber-700 active:text-amber-700 transition-colors"
                      >
                        <Pencil size={14} />
                        {activeEntry.userPrayer ? 'Edit' : 'Add Prayer'}
                      </button>
                    )}
                  </div>

                  {isEditingPrayer ? (
                    <div className="space-y-2">
                      <textarea
                        value={prayerDraft}
                        onChange={(e) => setPrayerDraft(e.target.value)}
                        placeholder="Write your personal prayer here..."
                        rows={4}
                        autoFocus
                        className="w-full px-4 py-3 bg-white border border-amber-200 rounded-2xl text-stone-700 placeholder:text-stone-400 focus:outline-none focus:ring-2 focus:ring-amber-300 text-sm leading-relaxed resize-none"
                      />
                      <div className="flex justify-end gap-2">
                        <button
                          onClick={() => setIsEditingPrayer(false)}
                          className="flex items-center gap-1 px-4 py-2 text-sm font-bold text-stone-500 hover:text-stone-700 transition-colors"
                        >
                          <X size={14} /> Cancel
                        </button>
                        <button
                          onClick={saveUserPrayer}
                          className="flex items-center gap-1 px-4 py-2 text-sm font-bold bg-amber-500 text-white rounded-xl hover:bg-amber-600 transition-colors"
                        >
                          <Check size={14} /> Save Prayer
                        </button>
                      </div>
                    </div>
                  ) : activeEntry.userPrayer ? (
                    <p className="text-stone-700 leading-relaxed italic whitespace-pre-wrap">
                      {activeEntry.userPrayer}
                    </p>
                  ) : (
                    <p className="text-stone-400 text-sm italic">
                      No personal prayer yet. Tap "Add Prayer" to write one.
                    </p>
                  )}
                </div>
              </section>

              <footer className="flex items-center justify-between pt-8 border-t border-stone-100">
                <div className="flex items-center space-x-4">
                  <button className="flex items-center space-x-2 text-stone-400 hover:text-indigo-600 font-bold transition-colors">
                    <Bookmark size={20} />
                    <span className="text-sm">Save to Favorites</span>
                  </button>
                </div>
                {activeEntry.visibility === 'PRIVATE' && activeEntry.creatorId === user.id ? (
                  <button
                    onClick={() => shareEntry(activeEntry.id)}
                    className="flex items-center space-x-2 text-indigo-600 hover:text-indigo-700 font-bold transition-colors"
                  >
                    <Share2 size={20} />
                    <span className="text-sm">Share with Family</span>
                  </button>
                ) : (
                  <span className="flex items-center space-x-2 text-stone-300 font-bold text-sm">
                    <Globe size={16} /> Shared
                  </span>
                )}
              </footer>
            </article>
          ) : (
            <div className="flex flex-col items-center justify-center h-[400px] bg-white border border-stone-200 border-dashed rounded-[2.5rem] text-stone-400">
              <BookOpen size={48} className="mb-4 opacity-20" />
              <p>Start your day with a reading or generate one using AI.</p>
            </div>
          )}

          {/* Collapsible Past Readings */}
          {visibleDevotionals.length > 0 && (
            <div className="bg-white rounded-3xl border border-stone-200 shadow-sm overflow-hidden">
              <button
                onClick={() => setPastReadingsOpen(!pastReadingsOpen)}
                className="w-full flex items-center justify-between px-6 py-5 hover:bg-stone-50 active:bg-stone-100 transition-colors"
              >
                <div className="flex items-center gap-3">
                  <BookOpen size={18} className="text-stone-400" />
                  <span className="font-bold text-stone-700">Past Readings</span>
                  <span className="text-[11px] font-black bg-stone-100 text-stone-500 px-2 py-0.5 rounded-full">
                    {visibleDevotionals.length}
                  </span>
                </div>
                <ChevronDown
                  size={18}
                  className={`text-stone-400 transition-transform duration-200 ${pastReadingsOpen ? 'rotate-180' : ''}`}
                />
              </button>

              {pastReadingsOpen && (
                <div className="border-t border-stone-100 p-6 space-y-5">
                  <div className="relative">
                    <Search className="absolute left-3 top-3 text-stone-400" size={18} />
                    <input
                      type="text"
                      placeholder="Search by title or scripture..."
                      value={searchTerm}
                      onChange={(e) => setSearchTerm(e.target.value)}
                      className="w-full pl-10 pr-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm"
                    />
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                    {filteredDevotionals.map(d => (
                      <button
                        key={d.id}
                        onClick={() => {
                          setActiveEntryId(d.id);
                          setIsEditingPrayer(false);
                          setPastReadingsOpen(false);
                          window.scrollTo({ top: 0, behavior: 'smooth' });
                        }}
                        className={`text-left p-4 rounded-2xl border transition-all ${
                          activeEntryId === d.id
                            ? 'bg-indigo-50 border-indigo-200 ring-1 ring-indigo-100'
                            : 'bg-stone-50 border-stone-100 hover:border-stone-200 hover:bg-white'
                        }`}
                      >
                        <div className="flex items-center gap-1.5 mb-1">
                          <p className="text-[10px] font-bold text-stone-400 uppercase">
                            {format(new Date(d.date), 'MMM d, yyyy')}
                          </p>
                          {d.visibility === 'PRIVATE' && <Lock size={10} className="text-stone-400" />}
                        </div>
                        <h4 className="font-bold text-stone-800 line-clamp-1 text-sm">{d.title}</h4>
                        <p className="text-xs text-stone-500 line-clamp-1 mt-0.5">{d.scripture}</p>
                      </button>
                    ))}
                  </div>

                  {filteredDevotionals.length === 0 && (
                    <p className="text-center text-stone-400 text-sm py-4">No results for "{searchTerm}"</p>
                  )}
                </div>
              )}
            </div>
          )}
        </>
      )}

      {/* ============================================================ */}
      {/* READING PLANS VIEW                                            */}
      {/* ============================================================ */}
      {view === 'PLANS' && (
        <>
          {/* Plan Generator */}
          <div className="bg-gradient-to-r from-indigo-600 to-violet-600 rounded-3xl p-6 text-white relative overflow-hidden shadow-xl shadow-indigo-100">
            <Calendar className="absolute right-[-20px] top-[-20px] w-48 h-48 opacity-10" />
            <div className="relative z-10">
              <h3 className="text-xl font-bold mb-2 flex items-center">
                <Sparkles size={20} className="mr-2" />
                Create a Reading Plan
              </h3>
              <p className="text-indigo-100 text-sm mb-4">Choose a theme and duration. The AI will create a day-by-day scripture journey for your family.</p>

              {/* Quick theme pills */}
              <div className="flex flex-wrap gap-2 mb-4">
                {PLAN_THEMES.map(t => (
                  <button
                    key={t}
                    onClick={() => setPlanTheme(t)}
                    className={`px-3 py-1.5 rounded-full text-xs font-bold transition-all ${
                      planTheme === t
                        ? 'bg-white text-indigo-700'
                        : 'bg-white/10 text-white/80 hover:bg-white/20'
                    }`}
                  >
                    {t}
                  </button>
                ))}
              </div>

              <div className="flex flex-col sm:flex-row gap-3">
                <input
                  type="text"
                  placeholder="Or type your own theme..."
                  value={planTheme}
                  onChange={(e) => setPlanTheme(e.target.value)}
                  className="flex-1 px-4 py-2 bg-white/10 backdrop-blur-md border border-white/20 rounded-xl text-white placeholder:text-white/50 focus:outline-none focus:ring-2 focus:ring-white/50"
                />
                <div className="flex bg-white/10 backdrop-blur-md rounded-xl overflow-hidden border border-white/20">
                  {PLAN_DURATIONS.map(d => (
                    <button
                      key={d.days}
                      onClick={() => setPlanDays(d.days)}
                      className={`px-3 py-2 text-xs font-bold transition-all ${
                        planDays === d.days ? 'bg-white/20 text-white' : 'text-white/60 hover:text-white/80'
                      }`}
                    >
                      {d.label}
                    </button>
                  ))}
                </div>
                <button
                  onClick={handleGeneratePlan}
                  disabled={isPlanGenerating || !planTheme}
                  className="bg-white text-indigo-600 px-6 py-2 rounded-xl font-bold hover:bg-stone-50 disabled:opacity-50 transition-colors flex items-center justify-center min-w-[140px]"
                >
                  {isPlanGenerating ? <Loader2 size={18} className="animate-spin" /> : 'Generate Plan'}
                </button>
              </div>
              {planError && (
                <p className="mt-3 text-sm text-red-200 bg-red-500/20 px-4 py-2 rounded-xl">{planError}</p>
              )}
            </div>
          </div>

          {/* Active Plan Detail */}
          {activePlan && activePlanDay && (
            <div className="bg-white rounded-[2.5rem] border border-stone-200 p-8 md:p-12 shadow-sm space-y-6">
              {/* Plan header */}
              <div className="flex items-start justify-between">
                <div>
                  <button
                    onClick={() => { setActivePlanId(null); setActivePlanDay(null); }}
                    className="text-xs font-bold text-indigo-600 hover:text-indigo-700 mb-2 flex items-center gap-1"
                  >
                    <ChevronDown size={12} className="rotate-90" /> Back to all plans
                  </button>
                  <h2 className="text-3xl font-black text-stone-900">{activePlan.title}</h2>
                  <p className="text-stone-500 text-sm mt-1">{activePlan.description}</p>
                </div>
                {/* Progress ring */}
                <div className="text-center shrink-0">
                  <div className="relative w-16 h-16">
                    <svg className="w-16 h-16 -rotate-90" viewBox="0 0 36 36">
                      <circle cx="18" cy="18" r="14" fill="none" stroke="#e7e5e4" strokeWidth="3" />
                      <circle
                        cx="18" cy="18" r="14" fill="none" stroke="#6366f1" strokeWidth="3"
                        strokeDasharray={`${((activePlanProgress?.completedDays.length || 0) / activePlan.totalDays) * 88} 88`}
                        strokeLinecap="round"
                      />
                    </svg>
                    <span className="absolute inset-0 flex items-center justify-center text-xs font-black text-stone-700">
                      {activePlanProgress?.completedDays.length || 0}/{activePlan.totalDays}
                    </span>
                  </div>
                  {calcStreak(activePlanProgress) > 0 && (
                    <p className="text-[10px] font-bold text-amber-600 mt-1 flex items-center justify-center gap-0.5">
                      <Flame size={10} /> {calcStreak(activePlanProgress)} day streak
                    </p>
                  )}
                </div>
              </div>

              {/* Day navigator */}
              <div className="flex gap-1.5 overflow-x-auto pb-2">
                {activePlan.days.map(d => {
                  const done = activePlanProgress?.completedDays.includes(d.day);
                  const isActive = activePlanDay === d.day;
                  return (
                    <button
                      key={d.day}
                      onClick={() => setActivePlanDay(d.day)}
                      className={`shrink-0 w-10 h-10 rounded-full text-xs font-bold transition-all flex items-center justify-center ${
                        done
                          ? isActive
                            ? 'bg-indigo-600 text-white ring-2 ring-indigo-300'
                            : 'bg-indigo-100 text-indigo-600'
                          : isActive
                            ? 'bg-stone-800 text-white ring-2 ring-stone-400'
                            : 'bg-stone-100 text-stone-500 hover:bg-stone-200'
                      }`}
                    >
                      {done ? <Check size={14} /> : d.day}
                    </button>
                  );
                })}
              </div>

              {/* Current day content */}
              {(() => {
                const dayData = activePlan.days.find(d => d.day === activePlanDay);
                if (!dayData) return null;
                const isDone = activePlanProgress?.completedDays.includes(dayData.day);

                return (
                  <div className="space-y-6">
                    <div>
                      <p className="text-[10px] font-black text-indigo-500 uppercase tracking-widest mb-1">Day {dayData.day} of {activePlan.totalDays}</p>
                      <h3 className="text-2xl font-black text-stone-900">{dayData.title}</h3>
                    </div>

                    <div className="bg-indigo-50 rounded-2xl p-5 border border-indigo-100">
                      <p className="text-[10px] font-black text-indigo-400 uppercase tracking-widest mb-1">Scripture</p>
                      <p className="text-lg font-medium text-indigo-700 italic">"{dayData.scripture}"</p>
                    </div>

                    <div>
                      <p className="text-[10px] font-black text-stone-400 uppercase tracking-widest mb-2">Reflection</p>
                      <p className="text-stone-700 leading-relaxed whitespace-pre-wrap">{dayData.reflection}</p>
                    </div>

                    <div className="bg-amber-50 rounded-2xl p-5 border border-amber-100">
                      <p className="text-[10px] font-black text-amber-500 uppercase tracking-widest mb-1">Family Discussion</p>
                      <p className="text-stone-700 font-medium">{dayData.discussionQuestion}</p>
                    </div>

                    {/* Complete / Next buttons */}
                    <div className="flex items-center gap-3 pt-4">
                      {!isDone ? (
                        <button
                          onClick={() => handleCompleteDay(activePlan.id, dayData.day)}
                          className="flex items-center gap-2 bg-indigo-600 text-white px-6 py-3 rounded-2xl font-bold hover:bg-indigo-700 transition-colors"
                        >
                          <Check size={18} />
                          Mark Day {dayData.day} Complete
                        </button>
                      ) : (
                        <span className="flex items-center gap-2 text-emerald-600 font-bold">
                          <Check size={18} className="bg-emerald-100 rounded-full p-0.5" />
                          Day {dayData.day} completed
                        </span>
                      )}
                      {dayData.day < activePlan.totalDays && (
                        <button
                          onClick={() => setActivePlanDay(dayData.day + 1)}
                          className="flex items-center gap-1 text-sm font-bold text-stone-500 hover:text-stone-700 transition-colors"
                        >
                          Next day <ChevronRight size={14} />
                        </button>
                      )}
                      {dayData.day === activePlan.totalDays && activePlanProgress?.completedDays.length === activePlan.totalDays && (
                        <span className="flex items-center gap-2 text-amber-600 font-bold">
                          <Trophy size={18} /> Plan completed!
                        </span>
                      )}
                    </div>
                  </div>
                );
              })()}
            </div>
          )}

          {/* Plans list */}
          {familyPlans.length > 0 && !activePlanDay && (
            <div className="space-y-4">
              <h3 className="text-lg font-bold text-stone-800">Your Reading Plans</h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                {familyPlans.map(plan => {
                  const progress = getProgressForPlan(plan.id);
                  const completed = progress?.completedDays.length || 0;
                  const pct = Math.round((completed / plan.totalDays) * 100);
                  const streak = calcStreak(progress);
                  const isComplete = completed === plan.totalDays;

                  return (
                    <button
                      key={plan.id}
                      onClick={() => {
                        setActivePlanId(plan.id);
                        // Open at first incomplete day or day 1
                        const nextDay = plan.days.find(d => !progress?.completedDays.includes(d.day))?.day || 1;
                        setActivePlanDay(nextDay);
                      }}
                      className={`text-left p-5 rounded-3xl border transition-all hover:shadow-md ${
                        isComplete
                          ? 'bg-emerald-50 border-emerald-200'
                          : 'bg-white border-stone-200 hover:border-indigo-200'
                      }`}
                    >
                      <div className="flex items-start justify-between mb-3">
                        <div className="flex-1 min-w-0">
                          <h4 className="font-bold text-stone-900 line-clamp-1">{plan.title}</h4>
                          <p className="text-xs text-stone-500 mt-0.5">{plan.totalDays} days · {format(new Date(plan.createdAt), 'MMM d')}</p>
                        </div>
                        {isComplete && <Trophy size={16} className="text-amber-500 shrink-0 ml-2" />}
                      </div>

                      {/* Progress bar */}
                      <div className="w-full h-2 bg-stone-100 rounded-full overflow-hidden mb-2">
                        <div
                          className={`h-full rounded-full transition-all ${isComplete ? 'bg-emerald-500' : 'bg-indigo-500'}`}
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                      <div className="flex items-center justify-between">
                        <span className="text-[10px] font-bold text-stone-400">{completed}/{plan.totalDays} days · {pct}%</span>
                        {streak > 0 && (
                          <span className="text-[10px] font-bold text-amber-600 flex items-center gap-0.5">
                            <Flame size={10} /> {streak}
                          </span>
                        )}
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          {familyPlans.length === 0 && !isPlanGenerating && (
            <div className="flex flex-col items-center justify-center h-[300px] bg-white border border-stone-200 border-dashed rounded-[2.5rem] text-stone-400">
              <Calendar size={48} className="mb-4 opacity-20" />
              <p className="font-medium">No reading plans yet.</p>
              <p className="text-sm mt-1">Generate one above to start your family's scripture journey.</p>
            </div>
          )}
        </>
      )}
    </div>
  );
};

export default Devotional;

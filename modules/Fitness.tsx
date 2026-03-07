
import React, { useState, useMemo } from 'react';
import {
  Activity,
  Plus,
  Flame,
  Target,
  TrendingUp,
  Sparkles,
  Loader2,
  Scale,
  Footprints,
  Calendar,
  CheckCircle2,
  Trash2,
  X,
  Dumbbell,
  Clock,
  ChevronDown,
  ChevronUp,
  User as UserIcon
} from 'lucide-react';
import { FitnessMetric, StoredFitnessPlan, User, Family, DailyHabit, DailyHabitCompletion } from '../types';
import { generateFitnessMotivation, generateFitnessPlan, refineFitnessPlan, type LocaleHint } from '../services/gemini';
import AiRefineInput from '../components/AiRefineInput';
import { useLocale } from '../contexts/LocaleContext';
import { format } from 'date-fns';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { useRealtimeDB } from '../hooks/useRealtimeDB';

const ICON_OPTIONS = [
  { name: 'Footprints', component: Footprints, color: 'text-blue-500', hex: '#3b82f6' },
  { name: 'Activity', component: Activity, color: 'text-cyan-500', hex: '#06b6d4' },
  { name: 'Flame', component: Flame, color: 'text-orange-500', hex: '#f97316' },
  { name: 'Target', component: Target, color: 'text-indigo-500', hex: '#6366f1' },
  { name: 'Scale', component: Scale, color: 'text-emerald-500', hex: '#10b981' },
  { name: 'Sparkles', component: Sparkles, color: 'text-pink-500', hex: '#ec4899' },
];

const Fitness: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const { weightUnit, heightUnit, settings } = useLocale();
  const localeHint: LocaleHint = { units: settings.units, country: settings.country };
  const [isAiLoading, setIsAiLoading] = useState(false);
  const [motivation, setMotivation] = useState<string | null>(null);
  const [motivationError, setMotivationError] = useState('');
  const [newVal, setNewVal] = useState('');
  const [showAddHabit, setShowAddHabit] = useState(false);
  const [newHabitLabel, setNewHabitLabel] = useState('');
  const [selectedIcon, setSelectedIcon] = useState(0);
  const [selectedColor, setSelectedColor] = useState(0);

  // AI Fitness Plan state
  const [isPlanLoading, setIsPlanLoading] = useState(false);
  const [showPlanForm, setShowPlanForm] = useState(false);
  const [planError, setPlanError] = useState('');
  const [expandedDay, setExpandedDay] = useState<number | null>(null);
  const [planProfile, setPlanProfile] = useState({
    gender: '',
    height: '',
    weight: '',
    level: '',
    daysPerWeek: '5',
    location: '',
    equipment: [] as string[],
  });

  const HOME_EQUIPMENT = [
    'Dumbbells', 'Resistance Bands', 'Barbell & Plates', 'Pull-up Bar',
    'Kettlebell', 'Bench', 'Jump Rope', 'Bodyweight Only',
  ];

  const toggleEquipment = (item: string) => {
    const eq = planProfile.equipment;
    if (item === 'Bodyweight Only') {
      // Selecting bodyweight only clears all other equipment
      setPlanProfile({ ...planProfile, equipment: eq.includes(item) ? [] : ['Bodyweight Only'] });
    } else {
      const without = eq.filter(e => e !== 'Bodyweight Only');
      setPlanProfile({
        ...planProfile,
        equipment: without.includes(item) ? without.filter(e => e !== item) : [...without, item],
      });
    }
  };

  const weightData = useMemo(() => {
    return db.fitness
      .filter((m: FitnessMetric) => m.type === 'WEIGHT')
      .sort((a: FitnessMetric, b: FitnessMetric) => new Date(a.date).getTime() - new Date(b.date).getTime())
      .map((m: FitnessMetric) => ({
        date: format(new Date(m.date), 'MMM d'),
        weight: m.value
      }));
  }, [db.fitness]);

  const activeStreakDays = useMemo(() => {
    let streak = 0;
    for (let i = 0; i < 365; i++) {
      const d = new Date();
      d.setDate(d.getDate() - i);
      const dateStr = format(d, 'yyyy-MM-dd');
      const hadCompletion = (db.dailyHabitCompletions || []).some(
        (c: DailyHabitCompletion) => c.userId === user.id && c.date === dateStr,
      );
      if (hadCompletion) {
        streak++;
      } else {
        if (i === 0) continue; // don't break streak if today not yet done
        break;
      }
    }
    return streak;
  }, [db.dailyHabitCompletions, user.id]);

  const fitnessPlan = useMemo((): StoredFitnessPlan | null => {
    const plans = (db.fitnessPlans || []).filter((p: StoredFitnessPlan) => p.userId === user.id);
    if (plans.length === 0) return null;
    return plans.sort((a: StoredFitnessPlan, b: StoredFitnessPlan) =>
      new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
    )[0];
  }, [db.fitnessPlans, user.id]);

  const addMetric = (type: 'WEIGHT' | 'STEPS') => {
    const val = parseFloat(newVal);
    if (isNaN(val)) return;

    const newMetric: FitnessMetric = {
      id: Math.random().toString(36).substr(2, 9),
      userId: user.id,
      type,
      value: val,
      date: new Date().toISOString()
    };
    const newDb = { ...db, fitness: [...db.fitness, newMetric] };
    save(newDb, 'logged a metric', 'Fitness', type);
    setNewVal('');
  };

  const handleGetMotivation = async () => {
    setIsAiLoading(true);
    setMotivationError('');
    try {
      const context = `${user.name}'s fitness journey with ${weightData.length} weight entries and ${userHabits.length} daily habits tracked.`;
      const msg = await generateFitnessMotivation(context);
      setMotivation(msg);
    } catch (e: any) {
      setMotivationError(e?.message || 'AI failed to generate motivation. Check your API key.');
    } finally {
      setIsAiLoading(false);
    }
  };

  const handleRefinePlan = async (request: string) => {
    if (!fitnessPlan) return;
    const refined = await refineFitnessPlan(
      { summary: fitnessPlan.summary, weeklyPlan: fitnessPlan.weeklyPlan, tips: fitnessPlan.tips },
      fitnessPlan.profile,
      request,
      localeHint,
    );
    const updatedPlan: StoredFitnessPlan = {
      ...fitnessPlan,
      summary: refined.summary,
      weeklyPlan: refined.weeklyPlan,
      tips: refined.tips,
    };
    const filteredPlans = (db.fitnessPlans || []).filter((p: StoredFitnessPlan) => p.userId !== user.id);
    save({ ...db, fitnessPlans: [...filteredPlans, updatedPlan] }, 'refined fitness plan', 'Fitness', request);
  };

  const handleGeneratePlan = async () => {
    if (!planProfile.gender || !planProfile.height || !planProfile.weight || !planProfile.level) {
      setPlanError('Please fill in all fields before generating.');
      return;
    }
    setIsPlanLoading(true);
    setPlanError('');
    try {
      const plan = await generateFitnessPlan(planProfile, localeHint);
      const newPlan: StoredFitnessPlan = {
        id: Math.random().toString(36).substr(2, 9),
        userId: user.id,
        summary: plan.summary,
        weeklyPlan: plan.weeklyPlan,
        tips: plan.tips,
        profile: planProfile,
        createdAt: new Date().toISOString(),
      };
      // Replace any existing plan for this user
      const filteredPlans = (db.fitnessPlans || []).filter((p: StoredFitnessPlan) => p.userId !== user.id);
      save({ ...db, fitnessPlans: [...filteredPlans, newPlan] }, 'generated a fitness plan', 'Fitness', planProfile.level);
      setShowPlanForm(false);
      setExpandedDay(0);
    } catch (e: any) {
      setPlanError(e?.message || 'Failed to generate fitness plan. Please try again.');
    } finally {
      setIsPlanLoading(false);
    }
  };

  const userHabits = useMemo(() => {
    return (db.dailyHabits || [])
      .filter((h: DailyHabit) => h.userId === user.id)
      .sort((a: DailyHabit, b: DailyHabit) => a.order - b.order);
  }, [db.dailyHabits, user.id]);

  const getTodayString = () => {
    return format(new Date(), 'yyyy-MM-dd');
  };

  const isHabitCompletedToday = (habitId: string) => {
    const today = getTodayString();
    return (db.dailyHabitCompletions || []).some(
      (c: DailyHabitCompletion) => c.habitId === habitId && c.userId === user.id && c.date === today
    );
  };

  const addHabit = () => {
    if (!newHabitLabel.trim()) return;

    const newHabit: DailyHabit = {
      id: Math.random().toString(36).substr(2, 9),
      userId: user.id,
      label: newHabitLabel.trim(),
      icon: ICON_OPTIONS[selectedIcon].name,
      color: ICON_OPTIONS[selectedColor].color,
      createdAt: new Date().toISOString(),
      order: (db.dailyHabits || []).filter((h: DailyHabit) => h.userId === user.id).length
    };

    const newDb = { ...db, dailyHabits: [...(db.dailyHabits || []), newHabit] };
    save(newDb, 'added a habit', 'Fitness', newHabitLabel.trim());
    setNewHabitLabel('');
    setShowAddHabit(false);
  };

  const toggleHabit = (habitId: string) => {
    const today = getTodayString();
    const completions = db.dailyHabitCompletions || [];
    const existingCompletion = completions.find(
      (c: DailyHabitCompletion) => c.habitId === habitId && c.userId === user.id && c.date === today
    );

    let newCompletions;
    if (existingCompletion) {
      newCompletions = completions.filter((c: DailyHabitCompletion) => c.id !== existingCompletion.id);
    } else {
      const newCompletion: DailyHabitCompletion = {
        id: Math.random().toString(36).substr(2, 9),
        habitId,
        userId: user.id,
        date: today,
        completedAt: new Date().toISOString()
      };
      newCompletions = [...completions, newCompletion];
    }

    const newDb = { ...db, dailyHabitCompletions: newCompletions };
    save(newDb, 'toggled a habit', 'Fitness', '');
  };

  const deleteHabit = (habitId: string) => {
    const newHabits = (db.dailyHabits || []).filter((h: DailyHabit) => h.id !== habitId);
    const newCompletions = (db.dailyHabitCompletions || []).filter((c: DailyHabitCompletion) => c.habitId !== habitId);
    const newDb = { ...db, dailyHabits: newHabits, dailyHabitCompletions: newCompletions };
    save(newDb, 'removed a habit', 'Fitness', '');
  };

  const currentWeight = weightData[weightData.length - 1]?.weight || 0;
  const startWeight = weightData[0]?.weight || 0;
  const progress = startWeight - currentWeight;

  return (
    <div className="space-y-8 pb-10">
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Fitness & Health</h1>
          <p className="text-stone-500">Track your vitals and stay active together.</p>
        </div>
        <div className="flex space-x-3">
          <input
            type="number"
            placeholder="Metric Value..."
            value={newVal}
            onChange={(e) => setNewVal(e.target.value)}
            className="px-4 py-2 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm w-32"
          />
          <button
            onClick={() => addMetric('WEIGHT')}
            className="bg-indigo-600 text-white px-6 py-2 rounded-xl font-bold text-sm shadow-lg shadow-indigo-100"
          >
            Log Weight
          </button>
        </div>
      </header>

      {/* AI Motivation Section */}
      <div className="bg-indigo-600 rounded-3xl p-8 text-white relative overflow-hidden shadow-xl shadow-indigo-100">
        <Activity className="absolute right-[-20px] bottom-[-20px] w-48 h-48 opacity-10" />
        <div className="relative z-10 flex flex-col md:flex-row items-center gap-8">
          <div className="flex-1 space-y-4">
            <h3 className="text-2xl font-black flex items-center">
              <Sparkles size={24} className="mr-2 text-indigo-300" />
              AI Health Coach
            </h3>
            {motivation ? (
              <p className="text-lg italic font-medium leading-relaxed">"{motivation}"</p>
            ) : (
              <p className="text-indigo-100">Click the button for a personalized motivation boost based on your recent activity.</p>
            )}
            {motivationError && (
              <p className="text-sm text-red-200 bg-red-500/20 px-4 py-2 rounded-xl">{motivationError}</p>
            )}
            <button
              onClick={handleGetMotivation}
              disabled={isAiLoading}
              className="bg-white text-indigo-600 px-6 py-3 rounded-2xl font-bold hover:bg-indigo-50 transition-colors flex items-center justify-center space-x-2"
            >
              {isAiLoading ? <Loader2 size={18} className="animate-spin" /> : <span>Get Motivation</span>}
            </button>
          </div>
          <div className="flex gap-4">
            <div className="bg-white/10 backdrop-blur-md p-6 rounded-3xl text-center border border-white/10 min-w-[120px]">
              <p className="text-xs font-bold text-indigo-200 uppercase tracking-widest mb-1">Weight Progress</p>
              <p className="text-3xl font-black">{progress > 0 ? '-' : '+'}{Math.abs(progress).toFixed(1)} <span className="text-xs">{weightUnit}</span></p>
            </div>
            <div className="bg-white/10 backdrop-blur-md p-6 rounded-3xl text-center border border-white/10 min-w-[120px]">
              <p className="text-xs font-bold text-indigo-200 uppercase tracking-widest mb-1">Active Streak</p>
              <p className="text-3xl font-black">{activeStreakDays} <span className="text-xs">days</span></p>
            </div>
          </div>
        </div>
      </div>

      {/* AI Fitness Plan Generator */}
      <div className="bg-white rounded-[2.5rem] border border-stone-200 p-8 shadow-sm">
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-xl font-bold text-stone-800 flex items-center">
            <Dumbbell size={20} className="mr-2 text-indigo-600" />
            AI Fitness Plan
          </h3>
          <button
            onClick={() => { setShowPlanForm(!showPlanForm); setPlanError(''); }}
            className="bg-indigo-600 text-white px-5 py-2 rounded-xl font-bold text-sm hover:bg-indigo-700 transition-colors flex items-center gap-2"
          >
            <Sparkles size={16} />
            {fitnessPlan ? 'New Plan' : 'Generate Plan'}
          </button>
        </div>

        {showPlanForm && (
          <div className="bg-stone-50 rounded-2xl p-6 space-y-4 mb-6">
            <p className="text-sm text-stone-600 font-medium">Tell us about yourself to generate a personalised fitness plan:</p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {/* Gender */}
              <div>
                <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Gender</label>
                <div className="flex gap-2">
                  {['Male', 'Female'].map((g) => (
                    <button
                      key={g}
                      onClick={() => setPlanProfile({ ...planProfile, gender: g })}
                      className={`flex-1 py-3 rounded-xl text-sm font-bold transition-all flex items-center justify-center gap-2 ${
                        planProfile.gender === g
                          ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-100'
                          : 'bg-white border border-stone-200 text-stone-600 hover:border-indigo-300'
                      }`}
                    >
                      <UserIcon size={16} />
                      {g}
                    </button>
                  ))}
                </div>
              </div>

              {/* Fitness Level */}
              <div>
                <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Fitness Level</label>
                <div className="flex gap-2">
                  {['Beginner', 'Intermediate', 'Advanced'].map((level) => (
                    <button
                      key={level}
                      onClick={() => setPlanProfile({ ...planProfile, level })}
                      className={`flex-1 py-3 rounded-xl text-xs font-bold transition-all ${
                        planProfile.level === level
                          ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-100'
                          : 'bg-white border border-stone-200 text-stone-600 hover:border-indigo-300'
                      }`}
                    >
                      {level}
                    </button>
                  ))}
                </div>
              </div>

              {/* Height */}
              <div>
                <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Height ({heightUnit})</label>
                <input
                  type="text"
                  placeholder={heightUnit === 'in' ? 'e.g. 69' : 'e.g. 175'}
                  value={planProfile.height}
                  onChange={(e) => setPlanProfile({ ...planProfile, height: e.target.value })}
                  className="w-full px-4 py-3 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm"
                />
              </div>

              {/* Weight */}
              <div>
                <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Weight ({weightUnit})</label>
                <input
                  type="text"
                  placeholder={weightUnit === 'lbs' ? 'e.g. 176' : 'e.g. 80'}
                  value={planProfile.weight}
                  onChange={(e) => setPlanProfile({ ...planProfile, weight: e.target.value })}
                  className="w-full px-4 py-3 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm"
                />
              </div>

              {/* Location */}
              <div className="sm:col-span-2">
                <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Where will you work out?</label>
                <div className="flex gap-3">
                  {[
                    { id: 'Gym', label: '🏋️ Gym', desc: 'Full equipment available' },
                    { id: 'Home', label: '🏠 Home', desc: 'Choose your equipment' },
                  ].map(({ id, label, desc }) => (
                    <button
                      key={id}
                      type="button"
                      onClick={() => setPlanProfile({ ...planProfile, location: id, equipment: [] })}
                      className={`flex-1 py-3 px-4 rounded-xl text-sm font-bold transition-all flex flex-col items-center gap-0.5 ${
                        planProfile.location === id
                          ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-100'
                          : 'bg-white border border-stone-200 text-stone-600 hover:border-indigo-300'
                      }`}
                    >
                      {label}
                      <span className={`text-[10px] font-medium ${planProfile.location === id ? 'text-indigo-200' : 'text-stone-400'}`}>{desc}</span>
                    </button>
                  ))}
                </div>
              </div>

              {/* Equipment (only when Home is selected) */}
              {planProfile.location === 'Home' && (
                <div className="sm:col-span-2">
                  <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Equipment you have at home</label>
                  <div className="flex flex-wrap gap-2">
                    {HOME_EQUIPMENT.map((item) => {
                      const selected = planProfile.equipment.includes(item);
                      return (
                        <button
                          key={item}
                          type="button"
                          onClick={() => toggleEquipment(item)}
                          className={`px-3 py-2 rounded-xl text-xs font-bold transition-all border ${
                            selected
                              ? 'bg-indigo-600 text-white border-indigo-600'
                              : 'bg-white text-stone-600 border-stone-200 hover:border-indigo-300'
                          }`}
                        >
                          {item}
                        </button>
                      );
                    })}
                  </div>
                  <p className="text-[10px] text-stone-400 mt-1.5">Select all equipment you have. The plan will only use what you pick.</p>
                </div>
              )}

              {/* Days Per Week */}
              <div className="sm:col-span-2">
                <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Days Available to Work Out</label>
                <div className="flex gap-2">
                  {['2', '3', '4', '5', '6', '7'].map((d) => (
                    <button
                      key={d}
                      onClick={() => setPlanProfile({ ...planProfile, daysPerWeek: d })}
                      className={`flex-1 py-3 rounded-xl text-sm font-bold transition-all ${
                        planProfile.daysPerWeek === d
                          ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-100'
                          : 'bg-white border border-stone-200 text-stone-600 hover:border-indigo-300'
                      }`}
                    >
                      {d}
                    </button>
                  ))}
                </div>
                <p className="text-[10px] text-stone-400 mt-1.5">Remaining days will be rest or active recovery</p>
              </div>
            </div>

            {planError && (
              <p className="text-sm text-red-600 bg-red-50 border border-red-200 px-4 py-2 rounded-xl">{planError}</p>
            )}
            <button
              onClick={handleGeneratePlan}
              disabled={isPlanLoading}
              className="w-full bg-indigo-600 text-white py-3 rounded-xl font-bold text-sm hover:bg-indigo-700 transition-colors flex items-center justify-center gap-2"
            >
              {isPlanLoading ? (
                <>
                  <Loader2 size={18} className="animate-spin" />
                  Generating Your Plan...
                </>
              ) : (
                <>
                  <Sparkles size={18} />
                  Generate My Fitness Plan
                </>
              )}
            </button>
          </div>
        )}

        {fitnessPlan && (
          <div className="space-y-6">
            {/* Plan Summary */}
            <div className="bg-gradient-to-r from-indigo-50 to-purple-50 rounded-2xl p-6 border border-indigo-100">
              <p className="text-sm text-indigo-900 font-medium leading-relaxed">{fitnessPlan.summary}</p>
              {(fitnessPlan.profile.location || (fitnessPlan.profile.equipment && fitnessPlan.profile.equipment.length > 0)) && (
                <div className="flex flex-wrap gap-1.5 mt-3">
                  {fitnessPlan.profile.location && (
                    <span className="bg-indigo-100 text-indigo-700 text-[11px] font-bold px-2.5 py-1 rounded-lg">
                      {fitnessPlan.profile.location === 'Gym' ? '🏋️ Gym' : '🏠 Home'}
                    </span>
                  )}
                  {fitnessPlan.profile.equipment?.map(e => (
                    <span key={e} className="bg-white border border-indigo-200 text-indigo-600 text-[11px] font-semibold px-2.5 py-1 rounded-lg">
                      {e}
                    </span>
                  ))}
                </div>
              )}
            </div>

            {/* Weekly Plan */}
            <div className="space-y-3">
              {fitnessPlan.weeklyPlan.map((day, i) => (
                <div key={i} className="border border-stone-200 rounded-2xl overflow-hidden">
                  <button
                    onClick={() => setExpandedDay(expandedDay === i ? null : i)}
                    className={`w-full flex items-center justify-between p-4 transition-colors ${
                      expandedDay === i ? 'bg-indigo-50' : 'hover:bg-stone-50'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <div className={`w-10 h-10 rounded-xl flex items-center justify-center font-bold text-sm ${
                        day.focus.toLowerCase().includes('rest')
                          ? 'bg-green-100 text-green-600'
                          : 'bg-indigo-100 text-indigo-600'
                      }`}>
                        {day.day.slice(0, 3)}
                      </div>
                      <div className="text-left">
                        <p className="font-bold text-sm text-stone-800">{day.focus}</p>
                        <p className="text-xs text-stone-400 flex items-center gap-1">
                          <Clock size={12} /> {day.duration}
                        </p>
                      </div>
                    </div>
                    {expandedDay === i ? <ChevronUp size={18} className="text-stone-400" /> : <ChevronDown size={18} className="text-stone-400" />}
                  </button>

                  {expandedDay === i && day.exercises.length > 0 && (
                    <div className="px-4 pb-4 space-y-2">
                      {day.exercises.map((ex, j) => (
                        <div key={j} className="flex items-center gap-3 p-3 bg-stone-50 rounded-xl">
                          <div className="w-8 h-8 rounded-lg bg-indigo-100 text-indigo-600 flex items-center justify-center text-xs font-bold">
                            {j + 1}
                          </div>
                          <div className="flex-1">
                            <p className="text-sm font-bold text-stone-700">{ex.name}</p>
                            <p className="text-xs text-stone-400">{ex.detail}</p>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              ))}
            </div>

            {/* Tips */}
            {fitnessPlan.tips && fitnessPlan.tips.length > 0 && (
              <div className="bg-amber-50 rounded-2xl p-6 border border-amber-100">
                <h4 className="font-bold text-sm text-amber-800 mb-3 flex items-center gap-2">
                  <Sparkles size={16} className="text-amber-500" />
                  Pro Tips
                </h4>
                <ul className="space-y-2">
                  {fitnessPlan.tips.map((tip, i) => (
                    <li key={i} className="text-sm text-amber-900 flex items-start gap-2">
                      <span className="text-amber-500 mt-0.5">-</span>
                      {tip}
                    </li>
                  ))}
                </ul>
              </div>
            )}

            <AiRefineInput
              onRefine={handleRefinePlan}
              label="Refine your plan"
              placeholder='e.g. "Move rest days to Saturday and Sunday" or "Replace running with cycling"'
            />
          </div>
        )}

        {!showPlanForm && !fitnessPlan && (
          <p className="text-center text-stone-400 py-6 text-sm">Click "Generate Plan" to get a personalised AI fitness plan based on your profile.</p>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Weight Tracker Chart */}
        <div className="lg:col-span-2 bg-white rounded-[2.5rem] border border-stone-200 p-8 shadow-sm">
          <div className="flex items-center justify-between mb-8">
            <h3 className="text-xl font-bold text-stone-800 flex items-center">
              <Scale size={20} className="mr-2 text-stone-400" />
              Weight Trends ({weightUnit})
            </h3>
            <div className="flex bg-stone-50 p-1 rounded-xl">
              <button className="px-4 py-1 text-xs font-bold text-stone-500 hover:text-indigo-600">30D</button>
              <button className="px-4 py-1 text-xs font-bold bg-white text-indigo-600 shadow-sm rounded-lg">90D</button>
            </div>
          </div>
          <div className="h-80 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={weightData}>
                <defs>
                  <linearGradient id="colorWeight" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#4f46e5" stopOpacity={0.1}/>
                    <stop offset="95%" stopColor="#4f46e5" stopOpacity={0}/>
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#f1f1f1" />
                <XAxis dataKey="date" axisLine={false} tickLine={false} tick={{fontSize: 10, fill: '#a1a1aa'}} />
                <YAxis axisLine={false} tickLine={false} tick={{fontSize: 10, fill: '#a1a1aa'}} domain={['dataMin - 5', 'dataMax + 5']} />
                <Tooltip
                  contentStyle={{ borderRadius: '16px', border: 'none', boxShadow: '0 10px 15px -3px rgba(0,0,0,0.1)' }}
                  itemStyle={{ fontWeight: 'bold' }}
                />
                <Area type="monotone" dataKey="weight" stroke="#4f46e5" strokeWidth={3} fillOpacity={1} fill="url(#colorWeight)" />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Habit Tracker */}
        <div className="bg-white rounded-[2.5rem] border border-stone-200 p-8 shadow-sm space-y-6">
          <div className="flex items-center justify-between">
            <h3 className="text-xl font-bold text-stone-800 flex items-center">
              <Flame size={20} className="mr-2 text-orange-500" />
              Daily Habits
            </h3>
            <button
              onClick={() => setShowAddHabit(!showAddHabit)}
              className="p-2 rounded-full bg-indigo-600 text-white hover:bg-indigo-700 transition-colors"
            >
              {showAddHabit ? <X size={20} /> : <Plus size={20} />}
            </button>
          </div>

          {showAddHabit && (
            <div className="bg-stone-50 p-4 rounded-2xl space-y-3">
              <input
                type="text"
                placeholder="Habit name (e.g., 8k Steps)"
                value={newHabitLabel}
                onChange={(e) => setNewHabitLabel(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && addHabit()}
                className="w-full px-4 py-2 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-sm"
              />
              <div className="flex gap-2">
                <div className="flex-1">
                  <p className="text-xs font-bold text-stone-500 mb-2">Icon</p>
                  <div className="flex gap-2 flex-wrap">
                    {ICON_OPTIONS.map((opt, i) => {
                      const IconComp = opt.component;
                      return (
                        <button
                          key={i}
                          onClick={() => setSelectedIcon(i)}
                          className={`p-2 rounded-lg ${selectedIcon === i ? 'bg-indigo-100 ring-2 ring-indigo-600' : 'bg-white hover:bg-stone-100'}`}
                        >
                          <IconComp size={18} className={opt.color} />
                        </button>
                      );
                    })}
                  </div>
                </div>
                <div className="flex-1">
                  <p className="text-xs font-bold text-stone-500 mb-2">Color</p>
                  <div className="flex gap-2 flex-wrap">
                    {ICON_OPTIONS.map((opt, i) => (
                      <button
                        key={i}
                        onClick={() => setSelectedColor(i)}
                        className={`w-8 h-8 rounded-lg ${selectedColor === i ? 'ring-2 ring-offset-2 ring-indigo-600' : ''}`}
                        style={{ backgroundColor: opt.hex }}
                      />
                    ))}
                  </div>
                </div>
              </div>
              <button
                onClick={addHabit}
                className="w-full bg-indigo-600 text-white py-2 rounded-xl font-bold text-sm hover:bg-indigo-700 transition-colors"
              >
                Add Habit
              </button>
            </div>
          )}

          <div className="space-y-3">
            {userHabits.length === 0 ? (
              <p className="text-center text-stone-400 py-8 text-sm">No habits yet. Click + to add one!</p>
            ) : (
              userHabits.map((habit: DailyHabit) => {
                const done = isHabitCompletedToday(habit.id);
                const IconOption = ICON_OPTIONS.find(o => o.name === habit.icon);
                const IconComp = IconOption?.component || Activity;

                return (
                  <div
                    key={habit.id}
                    className={`flex items-center justify-between p-4 rounded-2xl border transition-all ${
                      done ? 'bg-indigo-50 border-indigo-100' : 'bg-stone-50 border-transparent hover:border-stone-200'
                    }`}
                  >
                    <div className="flex items-center space-x-3 flex-1">
                      <div className={`p-2 rounded-xl bg-white shadow-sm ${habit.color}`}>
                        <IconComp size={18} />
                      </div>
                      <span className={`font-bold text-sm ${done ? 'text-indigo-900' : 'text-stone-600'}`}>
                        {habit.label}
                      </span>
                    </div>
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => toggleHabit(habit.id)}
                        className={`p-2 rounded-full transition-colors ${
                          done ? 'text-indigo-600' : 'text-stone-300 hover:text-indigo-600'
                        }`}
                      >
                        <CheckCircle2 size={24} />
                      </button>
                      <button
                        onClick={() => deleteHabit(habit.id)}
                        className="p-2 rounded-full text-stone-300 hover:text-red-600 transition-colors"
                      >
                        <Trash2 size={18} />
                      </button>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default Fitness;

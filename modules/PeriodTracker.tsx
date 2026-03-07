
import React, { useState, useMemo, useRef } from 'react';
import {
  ChevronLeft, ChevronRight, Droplets, SmilePlus,
  Trash2, X, Activity, TrendingUp, Bell, BookOpen,
  AlertCircle, Upload, Sparkles, Loader2, Heart,
} from 'lucide-react';
import {
  format, addMonths, subMonths, startOfMonth, endOfMonth,
  eachDayOfInterval, isSameDay, parseISO,
  differenceInDays, addDays, isBefore,
} from 'date-fns';
import { useRealtimeDB } from '../hooks/useRealtimeDB';
import { createId } from '../services/id';
import { generateWithModelFallback } from '../services/gemini';
import {
  User, Family, PeriodCycle, PeriodSymptomLog, IntimateLog,
  FlowLevel, CycleMood, PERIOD_SYMPTOM_OPTIONS, SYMPTOM_LABELS,
} from '../types';
import ModuleHint from '../components/ModuleHint';

// ── Constants ──────────────────────────────────────────────────────────────────

const FLOW_COLORS: Record<FlowLevel, string> = {
  LIGHT: 'bg-pink-200 text-pink-700',
  MEDIUM: 'bg-rose-400 text-white',
  HEAVY: 'bg-red-600 text-white',
};
const FLOW_LABELS: Record<FlowLevel, string> = { LIGHT: 'Light', MEDIUM: 'Medium', HEAVY: 'Heavy' };
const MOOD_EMOJI: Record<CycleMood, string> = { GREAT: '😄', GOOD: '🙂', OKAY: '😐', LOW: '😞', ROUGH: '😢' };
const MOOD_LABELS: Record<CycleMood, string> = { GREAT: 'Great', GOOD: 'Good', OKAY: 'Okay', LOW: 'Low', ROUGH: 'Rough' };

function dateStr(d: Date): string { return format(d, 'yyyy-MM-dd'); }
function avg(nums: number[]): number {
  if (!nums.length) return 0;
  return Math.round(nums.reduce((a, b) => a + b, 0) / nums.length);
}

// ── Prediction types ───────────────────────────────────────────────────────────

interface CyclePrediction {
  /** First day of period (actual for i=0, predicted for i>0) */
  periodStart: Date;
  /** Last day of period (estimated) */
  periodEnd: Date;
  /** Estimated ovulation day */
  ovulation: Date;
  /** Fertile window start (ovulation - 5) */
  fertileStart: Date;
  /** Fertile window end (ovulation + 1) */
  fertileEnd: Date;
  /** PMS window start (7 days before next period) */
  pmsStart: Date;
  /** PMS window end (1 day before next period) */
  pmsEnd: Date;
  /** true for the cycle derived from the last logged period */
  isCurrentCycle: boolean;
}

function buildPredictions(
  lastStart: Date,
  avgCycleLength: number,
  avgPeriodLength: number,
  count = 4,
): CyclePrediction[] {
  const preds: CyclePrediction[] = [];
  for (let i = 0; i < count; i++) {
    const periodStart = i === 0 ? lastStart : addDays(lastStart, avgCycleLength * i);
    const periodEnd = addDays(periodStart, avgPeriodLength - 1);
    // Ovulation: cycle length - 14 days after period start (luteal phase = 14d)
    const ovulation = addDays(periodStart, avgCycleLength - 14);
    const fertileStart = addDays(ovulation, -5);
    const fertileEnd = addDays(ovulation, 1);
    // PMS: 7 days before the *next* period
    const nextStart = addDays(periodStart, avgCycleLength);
    const pmsStart = addDays(nextStart, -7);
    const pmsEnd = addDays(nextStart, -1);
    preds.push({ periodStart, periodEnd, ovulation, fertileStart, fertileEnd, pmsStart, pmsEnd, isCurrentCycle: i === 0 });
  }
  return preds;
}

// Priority ordering for calendar display (highest priority first)
type DayPhase =
  | 'period'
  | 'ovulation'
  | 'fertile'
  | 'pms'
  | 'predicted_period'
  | 'predicted_ovulation'
  | 'predicted_fertile'
  | 'predicted_pms'
  | 'none';

const PHASE_PRIORITY: DayPhase[] = [
  'period', 'ovulation', 'fertile', 'pms',
  'predicted_period', 'predicted_ovulation', 'predicted_fertile', 'predicted_pms',
  'none',
];

interface DayInfo {
  phases: Set<DayPhase>;
  hasSymptom: boolean;
}

// ── Component ──────────────────────────────────────────────────────────────────

interface PeriodTrackerProps { user: User; family: Family; }

const PeriodTracker: React.FC<PeriodTrackerProps> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [currentMonth, setCurrentMonth] = useState(new Date());
  const [selectedDay, setSelectedDay] = useState<Date | null>(null);
  const [isDayPopup, setIsDayPopup] = useState(false);
  const [isLogModal, setIsLogModal] = useState(false);
  const [isNewCycleModal, setIsNewCycleModal] = useState(false);
  const [isImportModal, setIsImportModal] = useState(false);
  const [activeTab, setActiveTab] = useState<'calendar' | 'history' | 'insights'>('calendar');

  // New cycle form
  const [cycleStartDate, setCycleStartDate] = useState(dateStr(new Date()));
  const [cycleEndDate, setCycleEndDate] = useState('');
  const [cycleFlow, setCycleFlow] = useState<FlowLevel>('MEDIUM');
  const [cycleNotes, setCycleNotes] = useState('');

  // Symptom log form
  const [logDate, setLogDate] = useState(dateStr(new Date()));
  const [logSymptoms, setLogSymptoms] = useState<Set<string>>(new Set());
  const [logMood, setLogMood] = useState<CycleMood | ''>('');
  const [logPain, setLogPain] = useState(0);
  const [logNotes, setLogNotes] = useState('');

  // AI import state
  const [importText, setImportText] = useState('');
  const [importLoading, setImportLoading] = useState(false);
  const [importPreview, setImportPreview] = useState<PeriodCycle[] | null>(null);
  const [importError, setImportError] = useState('');

  // ── Data ────────────────────────────────────────────────────────────────────

  const myCycles = useMemo(() =>
    (db.periodCycles || [])
      .filter(c => c.userId === user.id && c.familyId === family.id)
      .sort((a, b) => b.startDate.localeCompare(a.startDate)),
    [db.periodCycles, user.id, family.id]);

  const mySymptoms = useMemo(() =>
    (db.periodSymptoms || [])
      .filter(s => s.userId === user.id && s.familyId === family.id),
    [db.periodSymptoms, user.id, family.id]);

  const myIntimateLogs = useMemo(() =>
    (db.intimateLogs || [])
      .filter(l => l.userId === user.id && l.familyId === family.id),
    [db.intimateLogs, user.id, family.id]);

  const intimateDatesSet = useMemo(() =>
    new Set(myIntimateLogs.map(l => l.date)),
    [myIntimateLogs]);

  // ── Statistics ───────────────────────────────────────────────────────────────

  const stats = useMemo(() => {
    const recent = myCycles.slice(0, 12);
    if (recent.length < 1) return null;

    const lengths: number[] = [];
    const periodLengths: number[] = [];

    for (let i = 0; i < recent.length - 1; i++) {
      const len = Math.abs(differenceInDays(parseISO(recent[i].startDate), parseISO(recent[i + 1].startDate)));
      if (len >= 15 && len <= 60) lengths.push(len);
    }
    for (const c of recent) {
      if (c.endDate) {
        const len = differenceInDays(parseISO(c.endDate), parseISO(c.startDate)) + 1;
        if (len >= 1 && len <= 10) periodLengths.push(len);
      }
    }

    const avgCycleLength = avg(lengths) || 28;
    const avgPeriodLength = avg(periodLengths) || 5;
    const minCycle = lengths.length ? Math.min(...lengths) : avgCycleLength;
    const maxCycle = lengths.length ? Math.max(...lengths) : avgCycleLength;
    const isIrregular = lengths.length >= 3 && (maxCycle - minCycle) >= 8;
    // true when cycle length is estimated (< 2 cycles logged — no start-to-start interval yet)
    const isEstimated = lengths.length === 0;

    return { avgCycleLength, avgPeriodLength, totalCycles: myCycles.length, minCycle, maxCycle, isIrregular, isEstimated };
  }, [myCycles]);

  // ── Predictions ──────────────────────────────────────────────────────────────

  const predictions = useMemo((): CyclePrediction[] => {
    if (!stats || !myCycles.length) return [];
    return buildPredictions(
      parseISO(myCycles[0].startDate),
      stats.avgCycleLength,
      stats.avgPeriodLength,
      4, // current cycle + 3 future cycles
    );
  }, [stats, myCycles]);

  // ── Day info map (used for calendar rendering) ────────────────────────────────

  const dayInfoMap = useMemo(() => {
    const map = new Map<string, DayInfo>();
    const get = (ds: string): DayInfo => {
      if (!map.has(ds)) map.set(ds, { phases: new Set(), hasSymptom: false });
      return map.get(ds)!;
    };

    // Actual logged period days
    for (const cycle of myCycles) {
      const start = parseISO(cycle.startDate);
      const end = cycle.endDate
        ? parseISO(cycle.endDate)
        : addDays(start, (stats?.avgPeriodLength || 5) - 1);
      eachDayOfInterval({ start, end }).forEach(d => get(dateStr(d)).phases.add('period'));
    }

    // Symptom dots
    mySymptoms.forEach(s => { get(s.date).hasSymptom = true; });

    // Windows from predictions
    const today = new Date();
    for (let i = 0; i < predictions.length; i++) {
      const pred = predictions[i];

      if (i === 0) {
        // Current cycle: show fertile / ovulation / PMS windows only for today onwards
        const futureOnly = (d: Date) => !isBefore(d, today);
        eachDayOfInterval({ start: pred.fertileStart, end: pred.fertileEnd })
          .filter(futureOnly)
          .forEach(d => get(dateStr(d)).phases.add('fertile'));
        if (futureOnly(pred.ovulation)) get(dateStr(pred.ovulation)).phases.add('ovulation');
        eachDayOfInterval({ start: pred.pmsStart, end: pred.pmsEnd })
          .filter(futureOnly)
          .forEach(d => get(dateStr(d)).phases.add('pms'));
      } else {
        // Future cycles: predicted period + fertile / ovulation / PMS
        eachDayOfInterval({ start: pred.periodStart, end: pred.periodEnd })
          .forEach(d => get(dateStr(d)).phases.add('predicted_period'));
        eachDayOfInterval({ start: pred.fertileStart, end: pred.fertileEnd })
          .forEach(d => get(dateStr(d)).phases.add('predicted_fertile'));
        get(dateStr(pred.ovulation)).phases.add('predicted_ovulation');
        eachDayOfInterval({ start: pred.pmsStart, end: pred.pmsEnd })
          .forEach(d => get(dateStr(d)).phases.add('predicted_pms'));
      }
    }

    return map;
  }, [myCycles, mySymptoms, predictions, stats]);

  const getPrimaryPhase = (ds: string): DayPhase => {
    const info = dayInfoMap.get(ds);
    if (!info) return 'none';
    for (const phase of PHASE_PRIORITY) {
      if (info.phases.has(phase)) return phase;
    }
    return 'none';
  };

  // ── Today's phase (for banner) ────────────────────────────────────────────────

  const todayInfo = useMemo(() => {
    if (!stats || !myCycles.length) return null;
    const today = new Date();
    const ds = dateStr(today);
    const phase = getPrimaryPhase(ds);

    const lastStart = parseISO(myCycles[0].startDate);
    const dayOfCycle = differenceInDays(today, lastStart) + 1; // 1-based
    const nextPeriod = predictions[1]?.periodStart ?? null;
    const daysUntilNext = nextPeriod ? differenceInDays(nextPeriod, today) : null;
    const isLate = daysUntilNext !== null && daysUntilNext < 0 && phase !== 'period';
    const daysLate = isLate && daysUntilNext !== null ? Math.abs(daysUntilNext) : 0;

    return { phase, dayOfCycle, daysUntilNext, isLate, daysLate, nextPeriod };
  }, [dayInfoMap, stats, myCycles, predictions]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Calendar helpers ──────────────────────────────────────────────────────────

  const calendarDays = useMemo(() => {
    const start = startOfMonth(currentMonth);
    const end = endOfMonth(currentMonth);
    const days: (Date | null)[] = [];
    for (let i = 0; i < start.getDay(); i++) days.push(null);
    eachDayOfInterval({ start, end }).forEach(d => days.push(d));
    return days;
  }, [currentMonth]);

  const selectedDayLog = useMemo(() =>
    selectedDay ? (mySymptoms.find(s => s.date === dateStr(selectedDay)) ?? null) : null,
    [selectedDay, mySymptoms]);

  const selectedDayCycle = useMemo(() => {
    if (!selectedDay) return null;
    const ds = dateStr(selectedDay);
    return myCycles.find(c => {
      const e = c.endDate ?? dateStr(addDays(parseISO(c.startDate), (stats?.avgPeriodLength || 5) - 1));
      return ds >= c.startDate && ds <= e;
    }) ?? null;
  }, [selectedDay, myCycles, stats]);

  function getDayClasses(ds: string, isToday: boolean, isSelected: boolean): string {
    const phase = getPrimaryPhase(ds);
    const phaseMap: Record<DayPhase, string> = {
      'period':            'bg-rose-500 text-white hover:opacity-90',
      'ovulation':         'bg-teal-500 text-white ring-2 ring-teal-300 hover:opacity-90',
      'fertile':           'bg-teal-100 text-teal-700 hover:bg-teal-200',
      'pms':               'bg-violet-100 text-violet-700 hover:bg-violet-200',
      'predicted_period':  'bg-pink-100 text-pink-700 border border-dashed border-pink-400',
      'predicted_ovulation':'bg-teal-50 text-teal-600 border border-dashed border-teal-400',
      'predicted_fertile': 'bg-teal-50 text-teal-500 border border-dashed border-teal-200',
      'predicted_pms':     'bg-violet-50 text-violet-500 border border-dashed border-violet-200',
      'none':              `hover:bg-stone-50 ${isToday ? 'ring-2 ring-indigo-400 text-indigo-600 font-bold' : 'text-stone-700'}`,
    };
    const sel = isSelected ? 'ring-2 ring-offset-1 ring-stone-800' : '';
    return `relative aspect-square flex flex-col items-center justify-center rounded-xl transition-all text-sm font-semibold ${phaseMap[phase]} ${sel}`.trim();
  }

  // ── Phase banner ──────────────────────────────────────────────────────────────

  const getPhaseBanner = () => {
    if (!todayInfo) return null;
    const { phase, daysUntilNext, isLate, daysLate, nextPeriod, dayOfCycle } = todayInfo;

    if (isLate) {
      return {
        bg: 'from-amber-500 to-orange-500',
        icon: <AlertCircle size={24} />,
        title: `${daysLate} day${daysLate !== 1 ? 's' : ''} late`,
        sub: 'Your period is later than predicted. Cycle length naturally varies by 1–7 days.',
      };
    }
    if (phase === 'period') {
      return { bg: 'from-rose-500 to-pink-500', icon: <Droplets size={24} />, title: 'Period phase', sub: 'Day ' + dayOfCycle + ' of your cycle · Take care of yourself 💗' };
    }
    if (phase === 'ovulation') {
      return { bg: 'from-teal-500 to-emerald-500', icon: <span className="text-2xl">🌟</span>, title: 'Ovulation day', sub: 'Peak fertility today · Day ' + dayOfCycle + ' of your cycle' };
    }
    if (phase === 'fertile') {
      return { bg: 'from-teal-500 to-cyan-500', icon: <span className="text-2xl">🌿</span>, title: 'Fertile window', sub: 'Higher chance of conception · Day ' + dayOfCycle };
    }
    if (phase === 'pms') {
      return { bg: 'from-purple-500 to-violet-500', icon: <span className="text-2xl">🌙</span>, title: 'PMS phase', sub: daysUntilNext !== null ? `Period expected in ${daysUntilNext} day${daysUntilNext !== 1 ? 's' : ''}` : '' };
    }
    if (nextPeriod && daysUntilNext !== null && daysUntilNext > 0) {
      return {
        bg: 'from-indigo-500 to-violet-500',
        icon: <Bell size={24} />,
        title: `Next period in ${daysUntilNext} day${daysUntilNext !== 1 ? 's' : ''}`,
        sub: format(nextPeriod, 'EEEE, MMMM d') + ' · Day ' + dayOfCycle + ' of your cycle',
      };
    }
    return null;
  };

  const banner = getPhaseBanner();

  // ── Actions ───────────────────────────────────────────────────────────────────

  const openLogModal = (day?: Date) => {
    const d = day ?? selectedDay ?? new Date();
    setLogDate(dateStr(d));
    const existing = mySymptoms.find(s => s.date === dateStr(d));
    if (existing) {
      setLogSymptoms(new Set(existing.symptoms));
      setLogMood(existing.mood ?? '');
      setLogPain(existing.painLevel ?? 0);
      setLogNotes(existing.notes ?? '');
    } else {
      setLogSymptoms(new Set()); setLogMood(''); setLogPain(0); setLogNotes('');
    }
    setIsLogModal(true);
  };

  const saveSymptomLog = () => {
    const existing = mySymptoms.find(s => s.date === logDate && s.userId === user.id);
    const entry: PeriodSymptomLog = {
      id: existing?.id ?? createId(),
      userId: user.id, familyId: family.id,
      date: logDate,
      symptoms: Array.from(logSymptoms) as any,
      mood: logMood || undefined,
      painLevel: logPain || undefined,
      notes: logNotes || undefined,
      createdAt: existing?.createdAt ?? new Date().toISOString(),
    };
    const newSymptoms = existing
      ? (db.periodSymptoms || []).map(s => s.id === existing.id ? entry : s)
      : [...(db.periodSymptoms || []), entry];
    save({ ...db, periodSymptoms: newSymptoms }, 'logged symptoms', 'Period Tracker', logDate);
    setIsLogModal(false);
  };

  const saveCycle = () => {
    if (!cycleStartDate || isNaN(new Date(cycleStartDate).getTime())) return;
    if (cycleEndDate && isNaN(new Date(cycleEndDate).getTime())) return;
    const newCycle: PeriodCycle = {
      id: createId(),
      userId: user.id, familyId: family.id,
      startDate: cycleStartDate,
      endDate: cycleEndDate || undefined,
      flowLevel: cycleFlow,
      notes: cycleNotes || undefined,
      createdAt: new Date().toISOString(),
    };
    save({ ...db, periodCycles: [...(db.periodCycles || []), newCycle] }, 'logged period', 'Period Tracker', cycleStartDate);
    setIsNewCycleModal(false);
    setCycleStartDate(dateStr(new Date())); setCycleEndDate(''); setCycleNotes('');
  };

  const deleteCycle = (id: string) =>
    save({ ...db, periodCycles: (db.periodCycles || []).filter(c => c.id !== id) }, 'deleted cycle', 'Period Tracker', '');

  const deleteSymptomLog = (id: string) =>
    save({ ...db, periodSymptoms: (db.periodSymptoms || []).filter(s => s.id !== id) }, 'deleted symptom log', 'Period Tracker', '');

  // ── Quick period start/stop from day popup ────────────────────────────────────

  const quickStartPeriod = (day: Date) => {
    const ds = dateStr(day);
    // Close any open cycle that has no end date (mark it ended the day before this one)
    const openCycle = myCycles.find(c => !c.endDate);
    let cycles = db.periodCycles || [];
    if (openCycle && openCycle.startDate < ds) {
      cycles = cycles.map(c => c.id === openCycle.id ? { ...c, endDate: dateStr(addDays(day, -1)) } : c);
    }
    const newCycle: PeriodCycle = {
      id: createId(),
      userId: user.id, familyId: family.id,
      startDate: ds,
      flowLevel: 'MEDIUM',
      createdAt: new Date().toISOString(),
    };
    save({ ...db, periodCycles: [...cycles, newCycle] }, 'logged period start', 'Period Tracker', ds);
    setIsDayPopup(false);
  };

  const quickEndPeriod = (day: Date) => {
    const ds = dateStr(day);
    // Find the open cycle or the cycle containing this day
    const openCycle = myCycles.find(c => !c.endDate) ?? myCycles.find(c => c.startDate <= ds);
    if (!openCycle) return;
    save({
      ...db,
      periodCycles: (db.periodCycles || []).map(c =>
        c.id === openCycle.id ? { ...c, endDate: ds } : c
      ),
    }, 'logged period end', 'Period Tracker', ds);
    setIsDayPopup(false);
  };

  // ── Intimate log ──────────────────────────────────────────────────────────────

  const toggleIntimateLog = (day: Date) => {
    const ds = dateStr(day);
    const existing = myIntimateLogs.find(l => l.date === ds);
    if (existing) {
      save({ ...db, intimateLogs: (db.intimateLogs || []).filter(l => l.id !== existing.id) }, 'removed intimate log', 'Period Tracker', ds);
    } else {
      const entry: IntimateLog = {
        id: createId(),
        userId: user.id, familyId: family.id,
        date: ds,
        createdAt: new Date().toISOString(),
      };
      save({ ...db, intimateLogs: [...(db.intimateLogs || []), entry] }, 'logged intimate', 'Period Tracker', ds);
    }
    setIsDayPopup(false);
  };

  const toggleSymptom = (s: string) =>
    setLogSymptoms(prev => { const n = new Set(prev); n.has(s) ? n.delete(s) : n.add(s); return n; });

  // ── AI Import ─────────────────────────────────────────────────────────────────

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = ev => setImportText(ev.target?.result as string ?? '');
    reader.readAsText(file);
  };

  const parseWithAI = async () => {
    if (!importText.trim()) return;
    setImportLoading(true);
    setImportError('');
    setImportPreview(null);
    try {
      const result = await generateWithModelFallback({
        prompt: `You are parsing period/menstrual cycle export data from a health app (e.g. Clue, Flo, Apple Health, or plain text).

Extract menstrual period start dates and return ONLY a valid JSON array. Each object must have:
- "startDate": "YYYY-MM-DD" (required — the first day of the period/bleed)
- "endDate": "YYYY-MM-DD" (optional — last day of bleeding, only if clearly available)
- "flowLevel": "LIGHT" | "MEDIUM" | "HEAVY" (optional — infer from words like light/medium/heavy/spotting/normal)
- "notes": string (optional — any relevant notes)

Rules:
- Only include PERIOD START dates (days 1 of each cycle / first day of bleeding)
- Do NOT include ovulation dates, fertile window dates, or spotting-only entries
- Sort by startDate DESCENDING (newest first)
- If a date is ambiguous, skip it
- Return ONLY the JSON array with no explanation, markdown, or extra text

Data to parse:
${importText.slice(0, 8000)}`,
        feature: 'period_import',
      });

      const text = result.text ?? '';
      const jsonMatch = text.match(/\[[\s\S]*\]/);
      if (!jsonMatch) throw new Error('Could not extract JSON from AI response. Please check your data format.');

      const parsed: Array<{ startDate?: string; endDate?: string; flowLevel?: string; notes?: string }> = JSON.parse(jsonMatch[0]);
      if (!Array.isArray(parsed) || parsed.length === 0) throw new Error('No cycles were found in the data.');

      const cycles: PeriodCycle[] = parsed
        .filter(c => c.startDate && /^\d{4}-\d{2}-\d{2}$/.test(c.startDate))
        .map(c => ({
          id: createId(),
          userId: user.id,
          familyId: family.id,
          startDate: c.startDate!,
          endDate: c.endDate && /^\d{4}-\d{2}-\d{2}$/.test(c.endDate) ? c.endDate : undefined,
          flowLevel: (['LIGHT', 'MEDIUM', 'HEAVY'].includes(c.flowLevel ?? '') ? c.flowLevel : undefined) as FlowLevel | undefined,
          notes: c.notes || undefined,
          createdAt: new Date().toISOString(),
        }));

      if (cycles.length === 0) throw new Error('No valid dates found. Make sure the data contains period start dates in YYYY-MM-DD format.');
      setImportPreview(cycles);
    } catch (err: any) {
      setImportError(err.message || 'Failed to parse data. Please try again or check the format.');
    } finally {
      setImportLoading(false);
    }
  };

  const confirmImport = () => {
    if (!importPreview) return;
    const existingDates = new Set(myCycles.map(c => c.startDate));
    const toAdd = importPreview.filter(c => !existingDates.has(c.startDate));
    save({ ...db, periodCycles: [...(db.periodCycles || []), ...toAdd] }, 'imported cycles', 'Period Tracker', '');
    setIsImportModal(false);
    setImportText(''); setImportPreview(null);
  };

  // ── Render ─────────────────────────────────────────────────────────────────────

  return (
    <div className="space-y-6">

      {/* Header */}
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Period Tracker</h1>
          <p className="text-stone-500">Track your cycle, symptoms & fertility.</p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <button
            onClick={() => { setImportText(''); setImportPreview(null); setImportError(''); setIsImportModal(true); }}
            className="flex items-center gap-2 px-4 py-2 bg-stone-50 text-stone-600 border border-stone-200 rounded-2xl font-bold hover:bg-stone-100 transition-colors"
          >
            <Upload size={16} />Import
          </button>
          <button
            onClick={() => openLogModal()}
            className="flex items-center gap-2 px-4 py-2 bg-pink-50 text-pink-700 border border-pink-200 rounded-2xl font-bold hover:bg-pink-100 transition-colors"
          >
            <SmilePlus size={18} />Log Symptoms
          </button>
          <button
            onClick={() => { setCycleStartDate(dateStr(new Date())); setCycleEndDate(''); setCycleFlow('MEDIUM'); setCycleNotes(''); setIsNewCycleModal(true); }}
            className="flex items-center gap-2 px-4 py-2 bg-rose-600 text-white rounded-2xl font-bold hover:bg-rose-700 transition-colors shadow-lg shadow-rose-100"
          >
            <Droplets size={18} />Log Period
          </button>
        </div>
      </header>

      {/* Phase banner */}
      {banner && (
        <div className={`bg-gradient-to-r ${banner.bg} rounded-3xl p-5 text-white flex items-center gap-4`}>
          <div className="w-12 h-12 bg-white/20 rounded-2xl flex items-center justify-center shrink-0">
            {banner.icon}
          </div>
          <div>
            <p className="font-bold text-lg leading-tight">{banner.title}</p>
            <p className="text-white/80 text-sm mt-0.5">{banner.sub}</p>
          </div>
        </div>
      )}

      {/* Stats row */}
      {stats && (
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {[
            {
              label: 'Avg Cycle', icon: <TrendingUp size={16} className="text-indigo-500" />,
              value: `${stats.avgCycleLength}d${stats.isEstimated ? '*' : ''}`,
              note: stats.isEstimated
                ? <span className="text-stone-400">*Estimated avg</span>
                : stats.isIrregular
                  ? <span className="text-amber-500">Irregular ({stats.minCycle}–{stats.maxCycle}d)</span>
                  : <span className="text-emerald-600">Regular ✓</span>,
            },
            {
              label: 'Avg Period', icon: <Droplets size={16} className="text-rose-500" />,
              value: `${stats.avgPeriodLength}d`,
              note: <span className="text-stone-400">Typical 3–7d</span>,
            },
            {
              label: 'Fertile Window', icon: <span className="text-base">🌿</span>,
              value: `Day ${stats.avgCycleLength - 19}–${stats.avgCycleLength - 13}`,
              note: <span className="text-stone-400">Ovulation day {stats.avgCycleLength - 14}</span>,
            },
            {
              label: 'Cycles Logged', icon: <Activity size={16} className="text-emerald-500" />,
              value: String(stats.totalCycles),
              note: <span className="text-stone-400">&nbsp;</span>,
            },
          ].map(s => (
            <div key={s.label} className="bg-white rounded-2xl p-4 border border-stone-100 space-y-1">
              <div className="flex items-center gap-1.5">{s.icon}<p className="text-xs text-stone-400 font-semibold">{s.label}</p></div>
              <p className="text-xl font-black text-stone-800">{s.value}</p>
              <p className="text-[10px] font-semibold">{s.note}</p>
            </div>
          ))}
        </div>
      )}

      {/* Tabs */}
      <div className="flex bg-stone-100 p-1 rounded-2xl gap-1">
        {(['calendar', 'history', 'insights'] as const).map(tab => (
          <button key={tab} onClick={() => setActiveTab(tab)}
            className={`flex-1 py-2 rounded-xl text-sm font-bold transition-all capitalize ${activeTab === tab ? 'bg-white text-stone-800 shadow-sm' : 'text-stone-500'}`}>
            {tab}
          </button>
        ))}
      </div>

      {/* ── Calendar Tab ── */}
      {activeTab === 'calendar' && (
        <div className="bg-white rounded-3xl border border-stone-100 p-6 shadow-sm">
          {/* Month nav */}
          <div className="flex items-center justify-between mb-6">
            <button onClick={() => setCurrentMonth(subMonths(currentMonth, 1))} className="p-2 hover:bg-stone-100 rounded-xl"><ChevronLeft size={20} /></button>
            <h2 className="font-bold text-stone-800">{format(currentMonth, 'MMMM yyyy')}</h2>
            <button onClick={() => setCurrentMonth(addMonths(currentMonth, 1))} className="p-2 hover:bg-stone-100 rounded-xl"><ChevronRight size={20} /></button>
          </div>

          {/* Day headers */}
          <div className="grid grid-cols-7 mb-2">
            {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map(d => (
              <div key={d} className="text-center text-[10px] font-black text-stone-400 uppercase py-1">{d}</div>
            ))}
          </div>

          {/* Calendar grid */}
          <div className="grid grid-cols-7 gap-1">
            {calendarDays.map((day, i) => {
              if (!day) return <div key={`e-${i}`} />;
              const ds = dateStr(day);
              const info = dayInfoMap.get(ds);
              const isToday = isSameDay(day, new Date());
              const isSelected = !!selectedDay && isSameDay(day, selectedDay);
              const isOvulationDay = info?.phases.has('ovulation') || info?.phases.has('predicted_ovulation');
              const hasIntimate = intimateDatesSet.has(ds);
              return (
                <button
                  key={ds}
                  onClick={() => { setSelectedDay(day); setIsDayPopup(true); }}
                  className={getDayClasses(ds, isToday, isSelected)}
                >
                  {format(day, 'd')}
                  {(info?.hasSymptom || hasIntimate) && (
                    <span className="absolute bottom-0.5 flex gap-0.5">
                      {info?.hasSymptom && (
                        <span className={`w-1.5 h-1.5 rounded-full ${info.phases.has('period') ? 'bg-white/70' : 'bg-indigo-400'}`} />
                      )}
                      {hasIntimate && (
                        <span className={`w-1.5 h-1.5 rounded-full ${info?.phases.has('period') ? 'bg-pink-200' : 'bg-rose-400'}`} />
                      )}
                    </span>
                  )}
                  {isOvulationDay && (
                    <span className="absolute top-0.5 right-0.5 text-[8px]">★</span>
                  )}
                </button>
              );
            })}
          </div>

          {/* Legend */}
          <div className="flex flex-wrap gap-x-4 gap-y-2 mt-4 pt-4 border-t border-stone-100">
            {[
              { cls: 'bg-rose-500', label: 'Period' },
              { cls: 'bg-teal-500', label: 'Ovulation ★' },
              { cls: 'bg-teal-100 border border-teal-300', label: 'Fertile' },
              { cls: 'bg-violet-100 border border-violet-300', label: 'PMS' },
              { cls: 'bg-pink-100 border border-dashed border-pink-400', label: 'Predicted' },
              { cls: 'bg-indigo-400', label: 'Symptom log', dot: true },
              { cls: 'bg-rose-400', label: 'Intimate', dot: true },
            ].map(l => (
              <div key={l.label} className="flex items-center gap-1.5 text-xs text-stone-500">
                {l.dot
                  ? <span className={`w-2 h-2 rounded-full shrink-0 ${l.cls}`} />
                  : <span className={`w-3 h-3 rounded-full shrink-0 ${l.cls}`} />
                }
                {l.label}
              </div>
            ))}
          </div>
          <p className="text-[10px] text-stone-400 mt-2 text-center">Tap any day to log period, symptoms, or intimate activity</p>

          {myCycles.length === 0 && (
            <ModuleHint
              emoji="🌸"
              title="Track your cycle with ease"
              tips={[
                'Tap any day and choose "Log Period Start" to begin',
                'Log symptoms & mood daily for better insights',
                'After 2+ cycles the app predicts your next period',
                'All data is private to you — partners cannot see it',
              ]}
              className="mt-4"
            />
          )}
        </div>
      )}

      {/* ── History Tab ── */}
      {activeTab === 'history' && (
        <div className="space-y-4">
          <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest">Cycle History</h3>
          {myCycles.length === 0 ? (
            <ModuleHint
              emoji="📅"
              title="Your cycle history will appear here"
              tips={[
                'Switch to the Calendar tab and tap a day to log your first period',
                'Each logged cycle shows start date, duration, and length',
                'Delete individual cycles if you made a mistake',
              ]}
            />
          ) : (
            <div className="space-y-3">
              {myCycles.map(cycle => {
                const duration = cycle.endDate
                  ? differenceInDays(parseISO(cycle.endDate), parseISO(cycle.startDate)) + 1
                  : null;
                return (
                  <div key={cycle.id} className="bg-white rounded-2xl border border-stone-100 p-4 flex items-center gap-4">
                    <div className="w-12 h-12 bg-rose-100 rounded-2xl flex items-center justify-center shrink-0">
                      <Droplets size={22} className="text-rose-500" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-bold text-stone-800">
                        {format(parseISO(cycle.startDate), 'MMM d, yyyy')}
                        {cycle.endDate && <> → {format(parseISO(cycle.endDate), 'MMM d')}</>}
                      </p>
                      <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                        {duration && <span className="text-xs text-stone-400">{duration} days</span>}
                        {cycle.flowLevel && (
                          <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${FLOW_COLORS[cycle.flowLevel]}`}>{FLOW_LABELS[cycle.flowLevel]}</span>
                        )}
                        {cycle.notes && <span className="text-xs text-stone-400 truncate">{cycle.notes}</span>}
                      </div>
                    </div>
                    <button onClick={() => deleteCycle(cycle.id)} className="p-2 text-stone-300 hover:text-red-500 transition-colors rounded-lg">
                      <Trash2 size={16} />
                    </button>
                  </div>
                );
              })}
            </div>
          )}

          <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest mt-6">Symptom Logs</h3>
          {mySymptoms.length === 0 ? (
            <div className="bg-white rounded-3xl border border-stone-100 p-8 text-center text-stone-400">
              <SmilePlus size={32} className="mx-auto mb-3 text-stone-200" />
              <p className="font-medium text-sm">No symptom logs yet.</p>
            </div>
          ) : (
            <div className="space-y-3">
              {[...mySymptoms].sort((a, b) => b.date.localeCompare(a.date)).map(log => (
                <div key={log.id} className="bg-white rounded-2xl border border-stone-100 p-4 flex items-start gap-3">
                  <div className="w-10 h-10 bg-pink-50 rounded-xl flex items-center justify-center shrink-0 text-lg">
                    {log.mood ? MOOD_EMOJI[log.mood] : '📋'}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-bold text-stone-700 text-sm">{format(parseISO(log.date), 'EEE, MMM d, yyyy')}</p>
                    <div className="flex flex-wrap gap-1 mt-1.5">
                      {log.symptoms.map(s => (
                        <span key={s} className="text-[10px] px-2 py-0.5 bg-pink-100 text-pink-700 rounded-full font-semibold">{SYMPTOM_LABELS[s as any] || s}</span>
                      ))}
                    </div>
                    {(log.painLevel ?? 0) > 0 && <p className="text-xs text-stone-400 mt-1">Pain: {log.painLevel}/10</p>}
                    {log.notes && <p className="text-xs text-stone-400 mt-1 truncate">{log.notes}</p>}
                  </div>
                  <button onClick={() => deleteSymptomLog(log.id)} className="p-2 text-stone-300 hover:text-red-500 transition-colors rounded-lg shrink-0">
                    <Trash2 size={14} />
                  </button>
                </div>
              ))}
            </div>
          )}

          {/* Intimate Logs */}
          {myIntimateLogs.length > 0 && (
            <>
              <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest mt-6">Intimate Activity</h3>
              <div className="space-y-2">
                {[...myIntimateLogs].sort((a, b) => b.date.localeCompare(a.date)).map(log => (
                  <div key={log.id} className="bg-white rounded-2xl border border-stone-100 p-4 flex items-center gap-3">
                    <div className="w-10 h-10 bg-rose-50 rounded-xl flex items-center justify-center shrink-0">
                      <Heart size={18} className="text-rose-400" fill="currentColor" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-bold text-stone-700 text-sm">{format(parseISO(log.date), 'EEE, MMM d, yyyy')}</p>
                      {log.notes && <p className="text-xs text-stone-400 mt-0.5 truncate">{log.notes}</p>}
                    </div>
                    <button
                      onClick={() => save({ ...db, intimateLogs: (db.intimateLogs || []).filter(l => l.id !== log.id) }, 'removed intimate log', 'Period Tracker', '')}
                      className="p-2 text-stone-300 hover:text-red-500 transition-colors rounded-lg shrink-0"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
      )}

      {/* ── Insights Tab ── */}
      {activeTab === 'insights' && (
        <div className="space-y-4">
          {!stats ? (
            <div className="bg-white rounded-3xl border border-stone-100 p-12 text-center text-stone-400">
              <BookOpen size={40} className="mx-auto mb-4 text-stone-200" />
              <p className="font-medium">Log your first period to see insights.</p>
              <p className="text-sm mt-1">Predictions improve as you log more cycles.</p>
            </div>
          ) : (
            <>
              {/* Estimated data notice */}
              {stats.isEstimated && (
                <div className="flex items-start gap-3 px-4 py-3 bg-amber-50 border border-amber-200 rounded-2xl text-sm text-amber-700">
                  <AlertCircle size={16} className="shrink-0 mt-0.5" />
                  <span>Predictions are estimated using a 28-day average. Log a second period for personalised insights.</span>
                </div>
              )}

              {/* Cycle analysis */}
              <div className="bg-gradient-to-br from-rose-50 to-pink-50 rounded-3xl p-6 border border-rose-100 space-y-4">
                <h3 className="font-bold text-rose-700 flex items-center gap-2"><TrendingUp size={18} />Cycle Analysis</h3>
                <div className="grid grid-cols-2 gap-3">
                  <div className="bg-white rounded-2xl p-4">
                    <p className="text-2xl font-black text-rose-600">{stats.avgCycleLength}<span className="text-sm font-normal text-stone-400">d</span></p>
                    <p className="text-xs text-stone-500 mt-1">Avg cycle length</p>
                    <p className="text-[10px] mt-0.5 font-semibold">
                      {stats.isIrregular
                        ? <span className="text-amber-500">Irregular ({stats.minCycle}–{stats.maxCycle}d range)</span>
                        : <span className="text-emerald-600">Regular cycle ✓</span>}
                    </p>
                  </div>
                  <div className="bg-white rounded-2xl p-4">
                    <p className="text-2xl font-black text-pink-600">{stats.avgPeriodLength}<span className="text-sm font-normal text-stone-400">d</span></p>
                    <p className="text-xs text-stone-500 mt-1">Avg period length</p>
                    <p className="text-[10px] text-stone-400 mt-0.5">Typical is 3–7 days</p>
                  </div>
                </div>
              </div>

              {/* Fertility window */}
              <div className="bg-gradient-to-br from-teal-50 to-emerald-50 rounded-3xl p-6 border border-teal-100 space-y-4">
                <h3 className="font-bold text-teal-700 flex items-center gap-2">🌿 Fertility Window</h3>
                <div className="grid grid-cols-2 gap-3">
                  <div className="bg-white rounded-2xl p-4">
                    <p className="text-lg font-black text-teal-600">Day {stats.avgCycleLength - 19}–{stats.avgCycleLength - 13}</p>
                    <p className="text-xs text-stone-500 mt-1">Fertile window</p>
                    <p className="text-[10px] text-stone-400 mt-0.5">6 days total</p>
                  </div>
                  <div className="bg-white rounded-2xl p-4">
                    <p className="text-lg font-black text-teal-600">Day {stats.avgCycleLength - 14}</p>
                    <p className="text-xs text-stone-500 mt-1">Est. ovulation</p>
                    <p className="text-[10px] text-stone-400 mt-0.5">Calendar method</p>
                  </div>
                </div>

                {/* Upcoming windows */}
                {predictions.length > 1 && (
                  <div className="bg-white rounded-2xl p-4 space-y-2">
                    <p className="text-sm font-bold text-stone-700">Upcoming windows</p>
                    {predictions.slice(1, 4).map((pred, i) => (
                      <div key={i} className="text-xs text-stone-600 flex flex-col gap-0.5 py-2 border-t border-stone-100 first:border-t-0 first:pt-0">
                        <div className="flex items-center gap-2">
                          <span>🩸</span>
                          <span><b>Period:</b> {format(pred.periodStart, 'MMM d')} (predicted)</span>
                        </div>
                        <div className="flex items-center gap-2">
                          <span>🌿</span>
                          <span><b>Fertile:</b> {format(pred.fertileStart, 'MMM d')} – {format(pred.fertileEnd, 'MMM d')}</span>
                        </div>
                        <div className="flex items-center gap-2">
                          <span>🌟</span>
                          <span><b>Ovulation:</b> {format(pred.ovulation, 'MMM d')}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              {/* Top symptoms */}
              {mySymptoms.length > 0 && (() => {
                const counts: Record<string, number> = {};
                mySymptoms.forEach(log => log.symptoms.forEach(s => { counts[s] = (counts[s] || 0) + 1; }));
                const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 6);
                return (
                  <div className="bg-white rounded-3xl border border-stone-100 p-6">
                    <h3 className="font-bold text-stone-700 mb-4 flex items-center gap-2">
                      <Activity size={18} className="text-pink-500" />Most Common Symptoms
                    </h3>
                    <div className="space-y-2.5">
                      {sorted.map(([sym, count]) => (
                        <div key={sym} className="flex items-center gap-3">
                          <span className="text-sm text-stone-600 w-36 shrink-0">{SYMPTOM_LABELS[sym as any] || sym}</span>
                          <div className="flex-1 h-2 bg-stone-100 rounded-full overflow-hidden">
                            <div className="h-full bg-pink-400 rounded-full" style={{ width: `${(count / mySymptoms.length) * 100}%` }} />
                          </div>
                          <span className="text-xs text-stone-400 shrink-0">{count}×</span>
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })()}

              <div className="flex items-start gap-3 p-4 bg-amber-50 rounded-2xl border border-amber-100">
                <AlertCircle size={16} className="text-amber-500 shrink-0 mt-0.5" />
                <p className="text-xs text-amber-700">
                  Predictions use the standard calendar method (ovulation = cycle length − 14 days). This is an estimate only. For conception planning or medical concerns, consult a healthcare professional.
                </p>
              </div>
            </>
          )}
        </div>
      )}

      {/* ── Day Quick-Log Popup ── */}
      {isDayPopup && selectedDay && (() => {
        const ds = dateStr(selectedDay);
        const phase = getPrimaryPhase(ds);
        const phaseLabels: Partial<Record<DayPhase, string>> = {
          'period': '🔴 Period', 'ovulation': '🌟 Ovulation', 'fertile': '🌿 Fertile window',
          'pms': '🌙 PMS phase', 'predicted_period': '🩷 Predicted period',
          'predicted_ovulation': '🌟 Predicted ovulation', 'predicted_fertile': '🌿 Predicted fertile',
          'predicted_pms': '🌙 Predicted PMS',
        };
        const hasIntimate = intimateDatesSet.has(ds);
        const isOnPeriod = !!selectedDayCycle;
        const openCycle = myCycles.find(c => !c.endDate);
        const canStartPeriod = !isOnPeriod;
        const canEndPeriod = isOnPeriod && !selectedDayCycle?.endDate;
        return (
          <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm"
            onClick={() => setIsDayPopup(false)}>
            <div className="bg-white w-full max-w-sm rounded-3xl p-6 shadow-2xl space-y-4" onClick={e => e.stopPropagation()}>
              {/* Header */}
              <div className="flex items-center justify-between">
                <div>
                  <h2 className="text-lg font-bold text-stone-900">{format(selectedDay, 'EEEE, MMMM d')}</h2>
                  {phaseLabels[phase] && (
                    <span className="text-xs font-semibold text-stone-500 bg-stone-100 px-2 py-0.5 rounded-full">{phaseLabels[phase]}</span>
                  )}
                </div>
                <button onClick={() => setIsDayPopup(false)} className="p-2 text-stone-400 hover:bg-stone-100 rounded-xl"><X size={18} /></button>
              </div>

              {/* Existing logs summary */}
              {(selectedDayCycle || selectedDayLog || hasIntimate) && (
                <div className="space-y-2">
                  {selectedDayCycle && (
                    <div className="flex items-center gap-2 px-3 py-2 bg-rose-50 rounded-xl text-sm text-rose-700">
                      <Droplets size={14} />
                      <span className="font-semibold">Period day</span>
                      {selectedDayCycle.flowLevel && <span className="text-rose-400">· {FLOW_LABELS[selectedDayCycle.flowLevel]} flow</span>}
                    </div>
                  )}
                  {selectedDayLog && (
                    <div className="flex flex-wrap gap-1 px-3 py-2 bg-stone-50 rounded-xl">
                      {selectedDayLog.mood && <span className="text-sm">{MOOD_EMOJI[selectedDayLog.mood]}</span>}
                      {selectedDayLog.symptoms.slice(0, 3).map(s => (
                        <span key={s} className="text-[10px] px-1.5 py-0.5 bg-pink-100 text-pink-700 rounded-full font-semibold">{SYMPTOM_LABELS[s as any] || s}</span>
                      ))}
                      {selectedDayLog.symptoms.length > 3 && (
                        <span className="text-[10px] text-stone-400">+{selectedDayLog.symptoms.length - 3} more</span>
                      )}
                    </div>
                  )}
                  {hasIntimate && (
                    <div className="flex items-center gap-2 px-3 py-2 bg-rose-50/50 rounded-xl text-sm text-rose-600">
                      <Heart size={13} fill="currentColor" /><span className="font-semibold">Intimate logged</span>
                    </div>
                  )}
                </div>
              )}

              {/* Action buttons */}
              <div className="space-y-2">
                {/* Period start/stop */}
                {canStartPeriod && (
                  <button
                    onClick={() => quickStartPeriod(selectedDay)}
                    className="w-full py-3 bg-rose-600 text-white rounded-2xl font-bold text-sm hover:bg-rose-700 transition-colors flex items-center justify-center gap-2"
                  >
                    <Droplets size={16} />Period Started
                  </button>
                )}
                {canEndPeriod && (
                  <button
                    onClick={() => quickEndPeriod(selectedDay)}
                    className="w-full py-3 bg-rose-100 text-rose-700 rounded-2xl font-bold text-sm hover:bg-rose-200 transition-colors flex items-center justify-center gap-2"
                  >
                    <Droplets size={16} />Period Ended
                  </button>
                )}

                {/* Symptoms */}
                <button
                  onClick={() => { setIsDayPopup(false); openLogModal(selectedDay); }}
                  className="w-full py-3 bg-pink-50 text-pink-700 rounded-2xl font-bold text-sm hover:bg-pink-100 transition-colors flex items-center justify-center gap-2"
                >
                  <SmilePlus size={16} />{selectedDayLog ? 'Edit Symptoms' : 'Log Symptoms'}
                </button>

                {/* Intimate */}
                <button
                  onClick={() => toggleIntimateLog(selectedDay)}
                  className={`w-full py-3 rounded-2xl font-bold text-sm transition-colors flex items-center justify-center gap-2 ${
                    hasIntimate
                      ? 'bg-rose-100 text-rose-700 hover:bg-rose-200'
                      : 'bg-stone-50 text-stone-600 hover:bg-stone-100 border border-stone-200'
                  }`}
                >
                  <Heart size={15} fill={hasIntimate ? 'currentColor' : 'none'} />
                  {hasIntimate ? 'Remove Intimate Log' : 'Log Intimate'}
                </button>
              </div>
            </div>
          </div>
        );
      })()}

      {/* ── New Cycle Modal ── */}
      {isNewCycleModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-sm rounded-3xl p-7 shadow-2xl">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold text-stone-900 flex items-center gap-2"><Droplets size={20} className="text-rose-500" />Log Period</h2>
              <button onClick={() => setIsNewCycleModal(false)} className="p-2 text-stone-400 hover:bg-stone-100 rounded-xl"><X size={18} /></button>
            </div>
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-bold text-stone-600 mb-1.5">Start Date</label>
                  <input type="date" value={cycleStartDate} onChange={e => setCycleStartDate(e.target.value)}
                    className="w-full px-3 py-2.5 bg-stone-50 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-rose-500/20" />
                </div>
                <div>
                  <label className="block text-xs font-bold text-stone-600 mb-1.5">End Date <span className="font-normal text-stone-400">(opt.)</span></label>
                  <input type="date" value={cycleEndDate} min={cycleStartDate} onChange={e => setCycleEndDate(e.target.value)}
                    className="w-full px-3 py-2.5 bg-stone-50 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-rose-500/20" />
                </div>
              </div>
              <div>
                <label className="block text-xs font-bold text-stone-600 mb-2">Flow Level</label>
                <div className="flex gap-2">
                  {(['LIGHT', 'MEDIUM', 'HEAVY'] as FlowLevel[]).map(f => (
                    <button key={f} onClick={() => setCycleFlow(f)}
                      className={`flex-1 py-2 rounded-xl text-xs font-bold border transition-all ${cycleFlow === f ? FLOW_COLORS[f] + ' border-transparent' : 'border-stone-200 text-stone-500 hover:border-stone-300'}`}>
                      {FLOW_LABELS[f]}
                    </button>
                  ))}
                </div>
              </div>
              <div>
                <label className="block text-xs font-bold text-stone-600 mb-1.5">Notes <span className="font-normal text-stone-400">(optional)</span></label>
                <input type="text" value={cycleNotes} onChange={e => setCycleNotes(e.target.value)} placeholder="Any notes…"
                  className="w-full px-3 py-2.5 bg-stone-50 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-rose-500/20" />
              </div>
              <div className="flex gap-3 pt-2">
                <button onClick={() => setIsNewCycleModal(false)} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold hover:bg-stone-200">Cancel</button>
                <button onClick={saveCycle} disabled={!cycleStartDate}
                  className="flex-1 py-3 bg-rose-600 text-white rounded-xl font-bold hover:bg-rose-700 shadow-lg shadow-rose-100 disabled:opacity-50">Save</button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Symptom Log Modal ── */}
      {isLogModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-sm rounded-3xl p-7 shadow-2xl max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold text-stone-900 flex items-center gap-2"><SmilePlus size={20} className="text-pink-500" />Symptom Log</h2>
              <button onClick={() => setIsLogModal(false)} className="p-2 text-stone-400 hover:bg-stone-100 rounded-xl"><X size={18} /></button>
            </div>
            <div className="space-y-5">
              <div>
                <label className="block text-xs font-bold text-stone-600 mb-1.5">Date</label>
                <input type="date" value={logDate} onChange={e => setLogDate(e.target.value)}
                  className="w-full px-3 py-2.5 bg-stone-50 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-pink-500/20" />
              </div>
              <div>
                <label className="block text-xs font-bold text-stone-600 mb-2">Mood</label>
                <div className="flex gap-2">
                  {(Object.keys(MOOD_EMOJI) as CycleMood[]).map(m => (
                    <button key={m} onClick={() => setLogMood(logMood === m ? '' : m)} title={MOOD_LABELS[m]}
                      className={`flex-1 py-2 rounded-xl text-lg border-2 transition-all ${logMood === m ? 'border-pink-500 bg-pink-50' : 'border-stone-200 hover:border-stone-300'}`}>
                      {MOOD_EMOJI[m]}
                    </button>
                  ))}
                </div>
              </div>
              <div>
                <label className="block text-xs font-bold text-stone-600 mb-2">Pain Level: {logPain}/10</label>
                <input type="range" min={0} max={10} value={logPain} onChange={e => setLogPain(Number(e.target.value))}
                  className="w-full accent-pink-500" />
                <div className="flex justify-between text-[10px] text-stone-400 mt-1">
                  <span>None</span><span>Mild</span><span>Moderate</span><span>Severe</span>
                </div>
              </div>
              <div>
                <label className="block text-xs font-bold text-stone-600 mb-2">Symptoms</label>
                <div className="flex flex-wrap gap-2">
                  {PERIOD_SYMPTOM_OPTIONS.map(s => {
                    const active = logSymptoms.has(s);
                    return (
                      <button key={s} onClick={() => toggleSymptom(s)}
                        className={`px-3 py-1.5 rounded-full text-xs font-bold border transition-all ${active ? 'bg-pink-500 text-white border-pink-500' : 'border-stone-200 text-stone-600 hover:border-pink-300 hover:text-pink-600'}`}>
                        {SYMPTOM_LABELS[s]}
                      </button>
                    );
                  })}
                </div>
              </div>
              <div>
                <label className="block text-xs font-bold text-stone-600 mb-1.5">Notes <span className="font-normal text-stone-400">(optional)</span></label>
                <textarea value={logNotes} onChange={e => setLogNotes(e.target.value)} rows={2}
                  placeholder="How are you feeling today?"
                  className="w-full px-3 py-2.5 bg-stone-50 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-pink-500/20 resize-none" />
              </div>
              <div className="flex gap-3 pt-1">
                <button onClick={() => setIsLogModal(false)} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold hover:bg-stone-200">Cancel</button>
                <button onClick={saveSymptomLog} className="flex-1 py-3 bg-pink-600 text-white rounded-xl font-bold hover:bg-pink-700 shadow-lg shadow-pink-100">Save Log</button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── AI Import Modal ── */}
      {isImportModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-lg rounded-3xl shadow-2xl max-h-[90vh] flex flex-col overflow-hidden">
            <div className="p-6 border-b border-stone-100 flex items-center justify-between shrink-0">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-indigo-100 rounded-xl"><Sparkles size={20} className="text-indigo-600" /></div>
                <div>
                  <h2 className="text-xl font-bold text-stone-900">AI Import</h2>
                  <p className="text-xs text-stone-500">Import from Clue, Flo, Apple Health, or any format</p>
                </div>
              </div>
              <button onClick={() => setIsImportModal(false)} className="p-2 text-stone-400 hover:bg-stone-100 rounded-xl"><X size={18} /></button>
            </div>

            <div className="flex-1 overflow-y-auto p-6 space-y-4">
              {!importPreview ? (
                <>
                  {/* File upload */}
                  <button
                    onClick={() => fileInputRef.current?.click()}
                    className="w-full flex items-center gap-3 p-4 bg-stone-50 rounded-2xl border border-stone-200 hover:bg-stone-100 transition-colors text-left"
                  >
                    <Upload size={18} className="text-stone-400 shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-stone-700">Upload a file</p>
                      <p className="text-xs text-stone-400">CSV, TXT, XML (Clue export, Apple Health, etc.)</p>
                    </div>
                    <span className="px-3 py-1.5 bg-stone-200 text-stone-600 rounded-lg text-xs font-bold">Browse</span>
                  </button>
                  <input ref={fileInputRef} type="file" accept=".csv,.txt,.xml,.json" className="hidden" onChange={handleFileUpload} />

                  <p className="text-xs text-center text-stone-400">— or paste below —</p>

                  <textarea
                    value={importText}
                    onChange={e => setImportText(e.target.value)}
                    rows={9}
                    placeholder={`Paste data in any format, e.g.:\n\nDate,Period,Flow\n2024-01-15,Yes,Heavy\n2024-02-12,Yes,Medium\n\nOr just a list of dates:\n2024-01-15\n2024-02-12\n2024-03-10\n\nWorks with Clue CSV, Apple Health XML, or plain text.`}
                    className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-2xl text-sm font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 resize-none"
                  />

                  {importError && (
                    <div className="flex items-start gap-2 p-3 bg-red-50 rounded-xl border border-red-200">
                      <AlertCircle size={16} className="text-red-500 shrink-0 mt-0.5" />
                      <p className="text-xs text-red-700">{importError}</p>
                    </div>
                  )}
                </>
              ) : (
                <div className="space-y-3">
                  {(() => {
                    const newCount = importPreview.filter(c => !myCycles.some(e => e.startDate === c.startDate)).length;
                    const dupCount = importPreview.length - newCount;
                    return (
                      <div className="p-3 bg-emerald-50 rounded-xl border border-emerald-200">
                        <p className="text-sm font-bold text-emerald-700">Found {importPreview.length} cycles</p>
                        <p className="text-xs text-emerald-600">{newCount} new · {dupCount} duplicates (will be skipped)</p>
                      </div>
                    );
                  })()}
                  <div className="space-y-2 max-h-64 overflow-y-auto">
                    {importPreview.map((cycle, i) => {
                      const isDup = myCycles.some(e => e.startDate === cycle.startDate);
                      return (
                        <div key={i} className={`flex items-center gap-3 p-3 rounded-xl border ${isDup ? 'border-stone-200 bg-stone-50 opacity-50' : 'border-stone-200 bg-white'}`}>
                          <Droplets size={16} className={isDup ? 'text-stone-300' : 'text-rose-500'} />
                          <span className="text-sm font-semibold text-stone-700 flex-1">
                            {format(parseISO(cycle.startDate), 'MMM d, yyyy')}
                            {cycle.endDate && ` → ${format(parseISO(cycle.endDate), 'MMM d')}`}
                          </span>
                          {cycle.flowLevel && (
                            <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${FLOW_COLORS[cycle.flowLevel]}`}>{FLOW_LABELS[cycle.flowLevel]}</span>
                          )}
                          {isDup && <span className="text-[10px] text-stone-400">duplicate</span>}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>

            <div className="p-4 border-t border-stone-100 shrink-0 flex gap-3">
              {!importPreview ? (
                <>
                  <button onClick={() => setIsImportModal(false)} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-2xl font-bold hover:bg-stone-200">Cancel</button>
                  <button
                    onClick={parseWithAI}
                    disabled={!importText.trim() || importLoading}
                    className="flex-1 py-3 bg-indigo-600 text-white rounded-2xl font-bold hover:bg-indigo-700 transition-colors flex items-center justify-center gap-2 disabled:opacity-50"
                  >
                    {importLoading
                      ? <><Loader2 size={18} className="animate-spin" />Parsing…</>
                      : <><Sparkles size={18} />Parse with AI</>}
                  </button>
                </>
              ) : (
                <>
                  <button onClick={() => setImportPreview(null)} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-2xl font-bold hover:bg-stone-200">Back</button>
                  <button
                    onClick={confirmImport}
                    disabled={importPreview.filter(c => !myCycles.some(e => e.startDate === c.startDate)).length === 0}
                    className="flex-1 py-3 bg-rose-600 text-white rounded-2xl font-bold hover:bg-rose-700 flex items-center justify-center gap-2 disabled:opacity-50"
                  >
                    <Droplets size={18} />
                    Import {importPreview.filter(c => !myCycles.some(e => e.startDate === c.startDate)).length} Cycles
                  </button>
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default PeriodTracker;

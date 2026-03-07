import React, { useState, useMemo, useEffect } from 'react';
import {
  Cake, Gift, Heart, Star, Plus, Trash2, Edit3, Bell, X,
  ChevronDown, ChevronUp, Calendar,
} from 'lucide-react';
import { differenceInDays, startOfDay } from 'date-fns';
import { useRealtimeDB } from '../hooks/useRealtimeDB';
import { createId } from '../services/id';
import { User, Family, SpecialDate, SpecialDateType, Visibility } from '../types';

// ── Helpers ───────────────────────────────────────────────────────────────────

const TYPE_META: Record<SpecialDateType, { label: string; emoji: string; color: string }> = {
  BIRTHDAY:    { label: 'Birthday',    emoji: '🎂', color: 'bg-pink-100 text-pink-700 border-pink-200' },
  ANNIVERSARY: { label: 'Anniversary', emoji: '💍', color: 'bg-violet-100 text-violet-700 border-violet-200' },
  MEMORIAL:    { label: 'Memorial',    emoji: '🌹', color: 'bg-stone-100 text-stone-700 border-stone-200' },
  OTHER:       { label: 'Other',       emoji: '⭐', color: 'bg-amber-100 text-amber-700 border-amber-200' },
};

const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const QUICK_EMOJIS = ['🎂', '🎉', '💍', '🌹', '⭐', '🎈', '👶', '💕', '🌸', '🐾', '🏆', '🌟'];

/** Days until the next occurrence of a month/day date from today. */
function daysUntil(month: number, day: number): number {
  const today = startOfDay(new Date());
  const thisYear = today.getFullYear();
  let next = startOfDay(new Date(thisYear, month - 1, day));
  if (next < today) next = startOfDay(new Date(thisYear + 1, month - 1, day));
  return differenceInDays(next, today);
}

function ageThisYear(year: number): number {
  return new Date().getFullYear() - year;
}

function urgencyColor(days: number): string {
  if (days === 0) return 'text-rose-600 font-black';
  if (days <= 3) return 'text-orange-600 font-bold';
  if (days <= 7) return 'text-amber-600 font-semibold';
  if (days <= 30) return 'text-indigo-600 font-medium';
  return 'text-stone-500';
}

function countdownLabel(days: number): string {
  if (days === 0) return '🎉 Today!';
  if (days === 1) return 'Tomorrow';
  if (days <= 7) return `In ${days} days`;
  if (days <= 30) return `In ${days} days`;
  const months = Math.floor(days / 30);
  if (months === 1) return 'In 1 month';
  if (months < 12) return `In ${months} months`;
  return `In ${Math.floor(days / 365)} year${Math.floor(days / 365) !== 1 ? 's' : ''}`;
}

// ── Props ────────────────────────────────────────────────────────────────────

interface BirthdaysProps { user: User; family: Family; }

// ── Component ─────────────────────────────────────────────────────────────────

const Birthdays: React.FC<BirthdaysProps> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);

  const [showModal, setShowModal] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'upcoming' | 'all'>('upcoming');
  const [expandedId, setExpandedId] = useState<string | null>(null);

  // Form state
  const [name, setName] = useState('');
  const [type, setType] = useState<SpecialDateType>('BIRTHDAY');
  const [month, setMonth] = useState(new Date().getMonth() + 1);
  const [day, setDay] = useState(new Date().getDate());
  const [year, setYear] = useState<string>('');
  const [emoji, setEmoji] = useState('🎂');
  const [notes, setNotes] = useState('');
  const [reminderDays, setReminderDays] = useState<number[]>([7, 1]);
  const [visibility, setVisibility] = useState<Visibility>('FAMILY');

  const familySpecialDates = useMemo(() =>
    (db.specialDates || []).filter(d => d.familyId === family.id),
    [db.specialDates, family.id]);

  const sorted = useMemo(() => {
    return [...familySpecialDates].sort((a, b) => daysUntil(a.month, a.day) - daysUntil(b.month, b.day));
  }, [familySpecialDates]);

  const upcoming = useMemo(() => sorted.filter(d => daysUntil(d.month, d.day) <= 60), [sorted]);
  const byMonth = useMemo(() => {
    const map = new Map<number, SpecialDate[]>();
    for (const d of sorted) {
      const prev = map.get(d.month) ?? [];
      map.set(d.month, [...prev, d]);
    }
    return map;
  }, [sorted]);

  const openCreate = () => {
    setEditId(null);
    setName(''); setType('BIRTHDAY'); setMonth(new Date().getMonth() + 1);
    setDay(new Date().getDate()); setYear(''); setEmoji('🎂');
    setNotes(''); setReminderDays([7, 1]); setVisibility('FAMILY');
    setShowModal(true);
  };

  const openEdit = (d: SpecialDate) => {
    setEditId(d.id);
    setName(d.name); setType(d.type); setMonth(d.month); setDay(d.day);
    setYear(d.year ? String(d.year) : ''); setEmoji(d.emoji);
    setNotes(d.notes ?? ''); setReminderDays(d.reminderDays); setVisibility(d.visibility);
    setShowModal(true);
  };

  const handleSave = () => {
    if (!name.trim()) return;
    const entry: SpecialDate = {
      id: editId ?? createId(),
      familyId: family.id,
      creatorId: user.id,
      name: name.trim(),
      type,
      month,
      day,
      year: year ? parseInt(year, 10) : undefined,
      emoji,
      notes: notes.trim() || undefined,
      reminderDays,
      visibility,
      createdAt: editId
        ? ((db.specialDates || []).find(d => d.id === editId)?.createdAt ?? new Date().toISOString())
        : new Date().toISOString(),
    };
    const updated = editId
      ? (db.specialDates || []).map(d => d.id === editId ? entry : d)
      : [...(db.specialDates || []), entry];
    save({ ...db, specialDates: updated }, editId ? 'updated special date' : 'added special date', 'Occasions', entry.name);
    setShowModal(false);
  };

  const handleDelete = (id: string) => {
    save({ ...db, specialDates: (db.specialDates || []).filter(d => d.id !== id) }, 'deleted special date', 'Occasions', '');
  };

  const toggleReminder = (days: number) => {
    setReminderDays(prev => prev.includes(days) ? prev.filter(d => d !== days) : [...prev, days]);
  };

  // Days in selected month — use entered year if available to handle leap years correctly
  const effectiveYear = year ? parseInt(year, 10) : new Date().getFullYear();
  const daysInMonth = new Date(effectiveYear, month, 0).getDate();

  // Clamp day when month or year changes so invalid dates (e.g. Feb 31) can't be saved
  useEffect(() => {
    setDay(prev => Math.min(prev, daysInMonth));
  }, [daysInMonth]);

  return (
    <div className="space-y-6">
      {/* Header */}
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Occasions</h1>
          <p className="text-stone-500">Birthdays, anniversaries & special dates — never miss one.</p>
        </div>
        <button
          onClick={openCreate}
          className="flex items-center gap-2 px-5 py-2.5 bg-pink-600 text-white rounded-2xl font-bold hover:bg-pink-700 transition-colors shadow-lg shadow-pink-100"
        >
          <Plus size={18} />Add Date
        </button>
      </header>

      {/* Upcoming strip (next 60 days) */}
      {upcoming.length > 0 && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {upcoming.slice(0, 6).map(d => {
            const days = daysUntil(d.month, d.day);
            const meta = TYPE_META[d.type];
            const turningAge = d.year ? ageThisYear(d.year) : null;
            return (
              <div key={d.id}
                className={`bg-white rounded-2xl border ${days === 0 ? 'border-rose-300 ring-2 ring-rose-200' : 'border-stone-100'} p-4 flex items-center gap-4 shadow-sm`}>
                <div className={`w-12 h-12 rounded-2xl flex items-center justify-center text-2xl shrink-0 border ${meta.color}`}>
                  {d.emoji}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-bold text-stone-800 truncate">{d.name}</p>
                  <p className="text-xs text-stone-400">{MONTH_NAMES[d.month - 1]} {d.day}{turningAge !== null && ` · Turning ${turningAge}`}</p>
                  <p className={`text-sm mt-0.5 ${urgencyColor(days)}`}>{countdownLabel(days)}</p>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Tabs */}
      <div className="flex bg-stone-100 p-1 rounded-2xl gap-1">
        {(['upcoming', 'all'] as const).map(tab => (
          <button key={tab} onClick={() => setActiveTab(tab)}
            className={`flex-1 py-2 rounded-xl text-sm font-bold transition-all capitalize ${activeTab === tab ? 'bg-white text-stone-800 shadow-sm' : 'text-stone-500'}`}>
            {tab === 'upcoming' ? `Upcoming (${upcoming.length})` : `All (${familySpecialDates.length})`}
          </button>
        ))}
      </div>

      {/* Upcoming tab */}
      {activeTab === 'upcoming' && (
        <div className="space-y-3">
          {upcoming.length === 0 ? (
            <div className="bg-white rounded-3xl border border-stone-100 p-12 text-center text-stone-400">
              <Cake size={40} className="mx-auto mb-4 text-stone-200" />
              <p className="font-medium">No dates in the next 60 days.</p>
              <p className="text-sm mt-1">Add a birthday or anniversary to get started.</p>
            </div>
          ) : (
            upcoming.map(d => <DateRow key={d.id} d={d} onEdit={openEdit} onDelete={handleDelete} expanded={expandedId === d.id} onToggle={() => setExpandedId(expandedId === d.id ? null : d.id)} />)
          )}
        </div>
      )}

      {/* All tab — grouped by month */}
      {activeTab === 'all' && (
        <div className="space-y-6">
          {familySpecialDates.length === 0 ? (
            <div className="bg-white rounded-3xl border border-stone-100 p-12 text-center text-stone-400">
              <Gift size={40} className="mx-auto mb-4 text-stone-200" />
              <p className="font-medium">No special dates added yet.</p>
            </div>
          ) : (
            Array.from(byMonth.entries()).map(([m, dates]) => (
              <div key={m}>
                <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest mb-3 flex items-center gap-2">
                  <Calendar size={14} />{MONTH_NAMES[m - 1]}
                </h3>
                <div className="space-y-2">
                  {dates.map(d => <DateRow key={d.id} d={d} onEdit={openEdit} onDelete={handleDelete} expanded={expandedId === d.id} onToggle={() => setExpandedId(expandedId === d.id ? null : d.id)} />)}
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {/* Add / Edit Modal */}
      {showModal && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 p-4">
          <div className="bg-white rounded-3xl w-full max-w-md p-6 space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="text-xl font-bold text-stone-800">{editId ? 'Edit Date' : 'Add Special Date'}</h2>
              <button onClick={() => setShowModal(false)} className="p-2 hover:bg-stone-100 rounded-xl"><X size={20} /></button>
            </div>

            {/* Emoji picker */}
            <div>
              <label className="block text-sm font-bold text-stone-700 mb-2">Icon</label>
              <div className="flex flex-wrap gap-2">
                {QUICK_EMOJIS.map(e => (
                  <button key={e} type="button" onClick={() => setEmoji(e)}
                    className={`w-10 h-10 text-xl rounded-xl border-2 transition-all ${emoji === e ? 'border-indigo-500 bg-indigo-50' : 'border-stone-200 hover:border-stone-300'}`}>
                    {e}
                  </button>
                ))}
              </div>
            </div>

            {/* Type */}
            <div>
              <label className="block text-sm font-bold text-stone-700 mb-2">Type</label>
              <div className="grid grid-cols-2 gap-2">
                {(Object.keys(TYPE_META) as SpecialDateType[]).map(t => (
                  <button key={t} type="button" onClick={() => { setType(t); if (t === 'BIRTHDAY') setEmoji('🎂'); else if (t === 'ANNIVERSARY') setEmoji('💍'); else if (t === 'MEMORIAL') setEmoji('🌹'); }}
                    className={`flex items-center gap-2 px-3 py-2 rounded-xl border-2 text-sm font-bold transition-all ${type === t ? 'border-indigo-500 bg-indigo-50 text-indigo-700' : 'border-stone-200 text-stone-600 hover:border-stone-300'}`}>
                    <span>{TYPE_META[t].emoji}</span>{TYPE_META[t].label}
                  </button>
                ))}
              </div>
            </div>

            {/* Name */}
            <div>
              <label className="block text-sm font-bold text-stone-700 mb-2">Name / Label</label>
              <input value={name} onChange={e => setName(e.target.value)} placeholder={type === 'BIRTHDAY' ? "e.g. Dad, Grandma, Baby Lily" : type === 'ANNIVERSARY' ? "e.g. Our Wedding" : "e.g. Uncle Bob"}
                className="w-full px-4 py-2.5 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
            </div>

            {/* Date */}
            <div className="grid grid-cols-3 gap-3">
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Month</label>
                <select value={month} onChange={e => setMonth(Number(e.target.value))}
                  className="w-full px-3 py-2.5 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300">
                  {MONTH_NAMES.map((m, i) => <option key={i + 1} value={i + 1}>{m}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Day</label>
                <select value={day} onChange={e => setDay(Number(e.target.value))}
                  className="w-full px-3 py-2.5 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300">
                  {Array.from({ length: daysInMonth }, (_, i) => i + 1).map(d => <option key={d} value={d}>{d}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Year <span className="font-normal text-stone-400">(opt)</span></label>
                <input type="number" value={year} onChange={e => setYear(e.target.value)} placeholder="1985"
                  min="1900" max={new Date().getFullYear()}
                  className="w-full px-3 py-2.5 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
              </div>
            </div>
            {year && <p className="text-xs text-stone-400 -mt-2">Age this year: {ageThisYear(parseInt(year, 10))}</p>}

            {/* Reminders */}
            <div>
              <label className="block text-sm font-bold text-stone-700 mb-2 flex items-center gap-1"><Bell size={14} />Remind me</label>
              <div className="flex flex-wrap gap-2">
                {[1, 3, 7, 14, 30].map(d => (
                  <button key={d} type="button" onClick={() => toggleReminder(d)}
                    className={`px-3 py-1.5 rounded-xl border-2 text-xs font-bold transition-all ${reminderDays.includes(d) ? 'border-indigo-500 bg-indigo-50 text-indigo-700' : 'border-stone-200 text-stone-500 hover:border-stone-300'}`}>
                    {d === 1 ? '1 day before' : `${d} days before`}
                  </button>
                ))}
              </div>
            </div>

            {/* Notes */}
            <div>
              <label className="block text-sm font-bold text-stone-700 mb-2">Notes <span className="font-normal text-stone-400">(optional)</span></label>
              <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} placeholder="Gift ideas, preferences..."
                className="w-full px-4 py-2.5 border border-stone-200 rounded-xl text-sm resize-none focus:outline-none focus:ring-2 focus:ring-indigo-300" />
            </div>

            {/* Actions */}
            <div className="flex gap-3 pt-2">
              <button onClick={() => setShowModal(false)}
                className="flex-1 py-3 bg-stone-100 text-stone-700 rounded-xl font-bold hover:bg-stone-200 transition-colors">
                Cancel
              </button>
              <button onClick={handleSave} disabled={!name.trim()}
                className="flex-1 py-3 bg-pink-600 text-white rounded-xl font-bold hover:bg-pink-700 transition-colors disabled:opacity-40">
                {editId ? 'Save Changes' : 'Add Date'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

// ── Date Row ─────────────────────────────────────────────────────────────────

interface DateRowProps {
  d: SpecialDate;
  onEdit: (d: SpecialDate) => void;
  onDelete: (id: string) => void;
  expanded: boolean;
  onToggle: () => void;
}

const DateRow: React.FC<DateRowProps> = ({ d, onEdit, onDelete, expanded, onToggle }) => {
  const days = daysUntil(d.month, d.day);
  const meta = TYPE_META[d.type];
  const turningAge = d.year ? ageThisYear(d.year) : null;
  const isToday = days === 0;

  return (
    <div className={`bg-white rounded-2xl border ${isToday ? 'border-rose-300 ring-2 ring-rose-100' : 'border-stone-100'} shadow-sm overflow-hidden`}>
      <button className="w-full flex items-center gap-4 p-4 text-left" onClick={onToggle}>
        <div className={`w-12 h-12 rounded-2xl flex items-center justify-center text-2xl shrink-0 border ${meta.color}`}>
          {d.emoji}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <p className="font-bold text-stone-800">{d.name}</p>
            <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${meta.color}`}>{meta.label}</span>
          </div>
          <p className="text-xs text-stone-400 mt-0.5">
            {MONTH_NAMES[d.month - 1]} {d.day}{d.year ? `, ${d.year}` : ''}
            {turningAge !== null && ` · Turning ${turningAge}`}
          </p>
        </div>
        <div className="text-right shrink-0">
          <p className={`text-sm ${urgencyColor(days)}`}>{countdownLabel(days)}</p>
          {expanded ? <ChevronUp size={16} className="text-stone-400 ml-auto mt-1" /> : <ChevronDown size={16} className="text-stone-400 ml-auto mt-1" />}
        </div>
      </button>
      {expanded && (
        <div className="px-4 pb-4 pt-0 border-t border-stone-100 flex items-start justify-between gap-4">
          <div className="space-y-1.5 flex-1">
            {d.notes && <p className="text-sm text-stone-600 italic">"{d.notes}"</p>}
            {d.reminderDays.length > 0 && (
              <p className="text-xs text-stone-400 flex items-center gap-1">
                <Bell size={12} />Reminders: {[...d.reminderDays].sort((a, b) => b - a).map(r => r === 1 ? '1 day' : `${r} days`).join(', ')} before
              </p>
            )}
          </div>
          <div className="flex gap-2">
            <button onClick={() => onEdit(d)} className="p-2 text-stone-400 hover:text-indigo-600 hover:bg-indigo-50 rounded-xl transition-colors"><Edit3 size={16} /></button>
            <button onClick={() => onDelete(d.id)} className="p-2 text-stone-400 hover:text-red-500 hover:bg-red-50 rounded-xl transition-colors"><Trash2 size={16} /></button>
          </div>
        </div>
      )}
    </div>
  );
};

export default Birthdays;

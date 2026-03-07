
import React, { useState, useMemo, useRef } from 'react';
import {
  Plus,
  Calendar as CalendarIcon,
  ChevronLeft,
  ChevronRight,
  Clock,
  MapPin,
  Download,
  Pencil,
  Trash2,
  Sparkles,
  Loader2,
  CheckCircle2,
  PartyPopper,
  Utensils,
  Gamepad2,
  TreePine,
  Baby,
  GraduationCap,
  Heart,
  Users,
  X,
  ListChecks,
  ShoppingCart,
  CheckSquare,
  Link,
  Upload,
  RefreshCw,
  Eye,
  EyeOff,
  Globe,
  AlertCircle,
} from 'lucide-react';
import { CalendarEvent, ExternalCalendar, Task, List, Visibility, Recurrence, User, Family } from '../types';
import { generateEventItinerary, planFullEvent, type LocaleHint } from '../services/gemini';
import { useLocale } from '../contexts/LocaleContext';
import { parseICSFile, fetchAndParseICS, detectCalendarType } from '../services/icsParser';
import { format, addMonths, subMonths, startOfMonth, endOfMonth, startOfWeek, endOfWeek, eachDayOfInterval, isSameMonth, isSameDay, addDays, addWeeks, subDays, isBefore, isAfter, startOfDay } from 'date-fns';
import { useRealtimeDB } from '../hooks/useRealtimeDB';

const EVENT_TEMPLATES = [
  { id: 'birthday', label: 'Birthday Party', icon: PartyPopper, color: 'bg-pink-100 text-pink-600' },
  { id: 'bbq', label: 'BBQ / Cookout', icon: Utensils, color: 'bg-orange-100 text-orange-600' },
  { id: 'game-night', label: 'Game Night', icon: Gamepad2, color: 'bg-purple-100 text-purple-600' },
  { id: 'holiday', label: 'Holiday Gathering', icon: TreePine, color: 'bg-green-100 text-green-600' },
  { id: 'baby-shower', label: 'Baby Shower', icon: Baby, color: 'bg-sky-100 text-sky-600' },
  { id: 'graduation', label: 'Graduation', icon: GraduationCap, color: 'bg-amber-100 text-amber-600' },
  { id: 'anniversary', label: 'Anniversary', icon: Heart, color: 'bg-red-100 text-red-600' },
  { id: 'other', label: 'Other Event', icon: Users, color: 'bg-stone-100 text-stone-600' },
];

const CALENDAR_COLORS = [
  '#6366f1', '#8b5cf6', '#ec4899', '#f97316',
  '#14b8a6', '#10b981', '#3b82f6', '#f59e0b',
];

interface PlanResult {
  description: string;
  location_suggestion?: string;
  tasks: { title: string; priority: string; daysBefore: number }[];
  lists: { title: string; category: string; items: { text: string; quantity?: string }[] }[];
  tips: string[];
  createdTaskCount: number;
  createdListCount: number;
}

const Calendar: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const { fmtTime, fmtDateTime, settings } = useLocale();
  const localeHint: LocaleHint = { units: settings.units, country: settings.country };
  const [currentDate, setCurrentDate] = useState(new Date());
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isAiLoading, setIsAiLoading] = useState(false);
  const [aiInput, setAiInput] = useState('');
  const [aiError, setAiError] = useState('');

  // External calendar state
  const [isImportOpen, setIsImportOpen] = useState(false);
  const [importMode, setImportMode] = useState<'file' | 'url' | 'google' | 'manage'>('file');
  const [importUrl, setImportUrl] = useState('');
  const [importCalendarName, setImportCalendarName] = useState('');
  const [importColor, setImportColor] = useState(CALENDAR_COLORS[0]);
  const [isImporting, setIsImporting] = useState(false);
  const [importError, setImportError] = useState('');
  const [importSuccess, setImportSuccess] = useState('');
  const [urlCorsBlocked, setUrlCorsBlocked] = useState(false);
  const [syncingId, setSyncingId] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Google Calendar OAuth state
  const [gcalConnecting, setGcalConnecting] = useState(false);
  const [gcalError, setGcalError] = useState('');
  const [gcalCalendars, setGcalCalendars] = useState<{ id: string; summary: string; backgroundColor: string; primary?: boolean }[]>([]);
  const [gcalSelectedIds, setGcalSelectedIds] = useState<Set<string>>(new Set());
  const [gcalImporting, setGcalImporting] = useState(false);

  const GCAL_TOKEN_KEY = `gcal_token_${user.id}`;
  const GCAL_EXPIRY_KEY = `gcal_expiry_${user.id}`;

  const getGcalClientId = (): string => {
    const env = (globalThis as any)?.process?.env;
    return env?.VITE_GOOGLE_CLIENT_ID ?? (import.meta as any)?.env?.VITE_GOOGLE_CLIENT_ID ?? '';
  };

  const getStoredGcalToken = (): string | null => {
    const token = localStorage.getItem(GCAL_TOKEN_KEY);
    const expiry = Number(localStorage.getItem(GCAL_EXPIRY_KEY) || 0);
    if (token && Date.now() < expiry - 60_000) return token;
    return null;
  };

  const loadGisScript = (): Promise<void> =>
    new Promise((resolve, reject) => {
      if ((window as any).google?.accounts?.oauth2) { resolve(); return; }
      const existing = document.querySelector('script[src*="accounts.google.com/gsi/client"]');
      if (existing) { existing.addEventListener('load', () => resolve()); return; }
      const s = document.createElement('script');
      s.src = 'https://accounts.google.com/gsi/client';
      s.async = true;
      s.onload = () => resolve();
      s.onerror = () => reject(new Error('Failed to load Google Identity Services'));
      document.head.appendChild(s);
    });

  const fetchGcalCalendars = async (accessToken: string) => {
    const res = await fetch('https://www.googleapis.com/calendar/v3/users/me/calendarList', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!res.ok) throw new Error('Failed to fetch Google Calendars');
    const data = await res.json();
    return (data.items || []) as { id: string; summary: string; backgroundColor: string; primary?: boolean }[];
  };

  const connectGoogleCalendar = async () => {
    const clientId = getGcalClientId();
    if (!clientId) {
      setGcalError('VITE_GOOGLE_CLIENT_ID is not configured. See setup instructions below.');
      return;
    }
    setGcalConnecting(true);
    setGcalError('');
    try {
      await loadGisScript();
      const existingToken = getStoredGcalToken();
      if (existingToken) {
        const cals = await fetchGcalCalendars(existingToken);
        setGcalCalendars(cals);
        setGcalConnecting(false);
        return;
      }
      const tokenClient = (window as any).google.accounts.oauth2.initTokenClient({
        client_id: clientId,
        scope: 'https://www.googleapis.com/auth/calendar.readonly',
        callback: async (resp: any) => {
          if (resp.error) {
            setGcalError(resp.error_description || resp.error);
            setGcalConnecting(false);
            return;
          }
          localStorage.setItem(GCAL_TOKEN_KEY, resp.access_token);
          localStorage.setItem(GCAL_EXPIRY_KEY, String(Date.now() + resp.expires_in * 1000));
          try {
            const cals = await fetchGcalCalendars(resp.access_token);
            setGcalCalendars(cals);
          } catch (e: any) {
            setGcalError(e.message);
          }
          setGcalConnecting(false);
        },
      });
      tokenClient.requestAccessToken({ prompt: '' });
    } catch (e: any) {
      setGcalError(e.message);
      setGcalConnecting(false);
    }
  };

  const importGoogleCalendars = async () => {
    const accessToken = getStoredGcalToken();
    if (!accessToken) { setGcalError('Session expired. Please reconnect.'); return; }
    if (gcalSelectedIds.size === 0) return;
    setGcalImporting(true);
    setGcalError('');
    const now = new Date();
    const timeMin = new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString();
    const timeMax = new Date(now.getFullYear(), now.getMonth() + 6, 1).toISOString();
    let newCals: ExternalCalendar[] = [];
    let newEvents: CalendarEvent[] = [];
    for (const calId of Array.from(gcalSelectedIds)) {
      const calMeta = gcalCalendars.find(c => c.id === calId);
      if (!calMeta) continue;
      // Skip if already connected
      const alreadyConnected = externalCalendars.some(c => c.googleCalendarId === calId);
      if (alreadyConnected) continue;
      const calDbId = Math.random().toString(36).substr(2, 9);
      try {
        const res = await fetch(
          `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calId)}/events?` +
          new URLSearchParams({ timeMin, timeMax, singleEvents: 'true', maxResults: '250' }),
          { headers: { Authorization: `Bearer ${accessToken}` } }
        );
        if (!res.ok) continue;
        const data = await res.json();
        const items: any[] = data.items || [];
        const importedEvents: CalendarEvent[] = items.map((ev: any) => ({
          id: `${calDbId}-${ev.id}`,
          familyId: family.id,
          creatorId: user.id,
          title: ev.summary || '(No title)',
          location: ev.location,
          start: ev.start?.dateTime ?? `${ev.start?.date}T00:00`,
          end: ev.end?.dateTime ?? `${ev.end?.date}T00:00`,
          description: ev.description,
          visibility: 'FAMILY' as const,
          checklist: [],
          recurrence: 'NONE' as const,
          externalCalendarId: calDbId,
        }));
        newCals.push({
          id: calDbId,
          familyId: family.id,
          creatorId: user.id,
          name: calMeta.summary,
          googleCalendarId: calId,
          color: calMeta.backgroundColor || CALENDAR_COLORS[newCals.length % CALENDAR_COLORS.length],
          type: 'GOOGLE',
          enabled: true,
          lastSynced: new Date().toISOString(),
          createdAt: new Date().toISOString(),
        });
        newEvents = [...newEvents, ...importedEvents];
      } catch {
        // skip failed calendars
      }
    }
    if (newCals.length > 0) {
      save({
        ...db,
        externalCalendars: [...(Array.isArray(db.externalCalendars) ? db.externalCalendars : []), ...newCals],
        events: [...(Array.isArray(db.events) ? db.events : []), ...newEvents],
      }, 'connected Google Calendars', 'Calendar');
      setGcalSelectedIds(new Set());
      setGcalCalendars([]);
      setImportMode('manage');
    }
    setGcalImporting(false);
  };

  const syncGoogleCalendar = async (cal: ExternalCalendar) => {
    const accessToken = getStoredGcalToken();
    if (!accessToken) {
      // Need to re-auth
      setIsImportOpen(true);
      setImportMode('google');
      setGcalError('Session expired. Reconnect to sync.');
      return;
    }
    setSyncingId(cal.id);
    const now = new Date();
    const timeMin = new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString();
    const timeMax = new Date(now.getFullYear(), now.getMonth() + 6, 1).toISOString();
    try {
      const res = await fetch(
        `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(cal.googleCalendarId!)}/events?` +
        new URLSearchParams({ timeMin, timeMax, singleEvents: 'true', maxResults: '250' }),
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );
      if (!res.ok) throw new Error('Failed to fetch events');
      const data = await res.json();
      const items: any[] = data.items || [];
      const refreshedEvents: CalendarEvent[] = items.map((ev: any) => ({
        id: `${cal.id}-${ev.id}`,
        familyId: family.id,
        creatorId: user.id,
        title: ev.summary || '(No title)',
        location: ev.location,
        start: ev.start?.dateTime ?? `${ev.start?.date}T00:00`,
        end: ev.end?.dateTime ?? `${ev.end?.date}T00:00`,
        description: ev.description,
        visibility: 'FAMILY' as const,
        checklist: [],
        recurrence: 'NONE' as const,
        externalCalendarId: cal.id,
      }));
      const updatedCal = { ...cal, lastSynced: new Date().toISOString() };
      const otherEvents = (Array.isArray(db.events) ? db.events : []).filter(e => e.externalCalendarId !== cal.id);
      const updatedCals = (Array.isArray(db.externalCalendars) ? db.externalCalendars : []).map(c => c.id === cal.id ? updatedCal : c);
      save({ ...db, externalCalendars: updatedCals, events: [...otherEvents, ...refreshedEvents] }, 'synced Google Calendar', 'Calendar', cal.name);
    } catch (e: any) {
      setImportError(`Sync failed for "${cal.name}": ${e.message}`);
    } finally {
      setSyncingId(null);
    }
  };

  // Event Planner Wizard State
  const [isWizardOpen, setIsWizardOpen] = useState(false);
  const [wizardStep, setWizardStep] = useState(0);
  const [selectedTemplate, setSelectedTemplate] = useState('');
  const [wizardForm, setWizardForm] = useState({
    eventName: '',
    date: format(addDays(new Date(), 7), 'yyyy-MM-dd'),
    guestCount: '',
    budget: '',
    notes: '',
  });
  const [isPlanLoading, setIsPlanLoading] = useState(false);
  const [planResult, setPlanResult] = useState<PlanResult | null>(null);
  const [planError, setPlanError] = useState('');

  // Day Detail Popover State
  const [selectedDay, setSelectedDay] = useState<Date | null>(null);

  // Form State
  const [title, setTitle] = useState('');
  const [location, setLocation] = useState('');
  const [start, setStart] = useState(format(new Date(), "yyyy-MM-dd'T'HH:mm"));
  const [end, setEnd] = useState(format(addDays(new Date(), 1), "yyyy-MM-dd'T'HH:mm"));
  const [eventRecurrence, setEventRecurrence] = useState<Recurrence>('NONE');

  // Edit Event State
  const [editingEvent, setEditingEvent] = useState<CalendarEvent | null>(null);
  const [editTitle, setEditTitle] = useState('');
  const [editLocation, setEditLocation] = useState('');
  const [editStart, setEditStart] = useState('');
  const [editEnd, setEditEnd] = useState('');
  const [editDescription, setEditDescription] = useState('');
  const [editRecurrence, setEditRecurrence] = useState<Recurrence>('NONE');

  const monthStart = startOfMonth(currentDate);
  const monthEnd = endOfMonth(monthStart);
  const startDate = startOfWeek(monthStart);
  const endDate = endOfWeek(monthEnd);
  const days = eachDayOfInterval({ start: startDate, end: endDate });

  const externalCalendars = useMemo(() => {
    const cals = Array.isArray(db.externalCalendars) ? db.externalCalendars : [];
    return cals.filter(c => c.familyId === family.id);
  }, [db.externalCalendars, family.id]);

  const enabledExternalIds = useMemo(() =>
    new Set(externalCalendars.filter(c => c.enabled).map(c => c.id)),
    [externalCalendars]
  );

  const externalColorMap = useMemo(() => {
    const map: Record<string, string> = {};
    for (const cal of externalCalendars) {
      map[cal.id] = cal.color;
    }
    return map;
  }, [externalCalendars]);

  // Generate virtual recurring instances within a date range
  const generateRecurringInstances = (events: CalendarEvent[], rangeStart: Date, rangeEnd: Date): CalendarEvent[] => {
    const result: CalendarEvent[] = [];
    for (const event of events) {
      if (event.familyId !== family.id) continue;
      if (event.externalCalendarId && !enabledExternalIds.has(event.externalCalendarId)) continue;

      const eventStart = new Date(event.start);
      const eventEnd = new Date(event.end);
      const duration = eventEnd.getTime() - eventStart.getTime();

      if (!event.recurrence || event.recurrence === 'NONE') {
        // Non-recurring: include if it falls in range
        if (!isAfter(eventStart, rangeEnd) && !isBefore(eventEnd, rangeStart)) {
          result.push(event);
        }
        continue;
      }

      // Generate occurrences for recurring events
      let cursor = new Date(eventStart);
      let maxIterations = 366; // safety limit
      while (!isAfter(cursor, rangeEnd) && maxIterations-- > 0) {
        const occEnd = new Date(cursor.getTime() + duration);
        if (!isBefore(occEnd, rangeStart)) {
          const isOriginal = cursor.getTime() === eventStart.getTime();
          result.push({
            ...event,
            id: isOriginal ? event.id : `${event.id}_${format(cursor, 'yyyyMMdd')}`,
            start: cursor.toISOString(),
            end: occEnd.toISOString(),
          });
        }
        // Advance cursor
        switch (event.recurrence) {
          case 'DAILY': cursor = addDays(cursor, 1); break;
          case 'WEEKLY': cursor = addWeeks(cursor, 1); break;
          case 'MONTHLY': cursor = addMonths(cursor, 1); break;
        }
      }
    }
    return result;
  };

  const eventsInMonth = useMemo(() => {
    const allEvents = Array.isArray(db.events) ? db.events : [];
    return generateRecurringInstances(allEvents, startDate, endDate);
  }, [db.events, currentDate, family.id, enabledExternalIds, startDate, endDate]);

  // Upcoming events: from today forward, sorted by start, rolling 90-day window
  const upcomingEvents = useMemo(() => {
    const allEvents = Array.isArray(db.events) ? db.events : [];
    const today = startOfDay(new Date());
    const futureLimit = addDays(today, 90);
    const instances = generateRecurringInstances(allEvents, today, futureLimit);
    return instances
      .filter(e => !isBefore(new Date(e.start), today))
      .sort((a, b) => new Date(a.start).getTime() - new Date(b.start).getTime());
  }, [db.events, family.id, enabledExternalIds]);

  const getEventColor = (event: CalendarEvent) => {
    if (event.externalCalendarId && externalColorMap[event.externalCalendarId]) {
      return null; // signals use inline style
    }
    return 'bg-indigo-50 text-indigo-700 border-indigo-100';
  };

  const getEventStyle = (event: CalendarEvent) => {
    if (event.externalCalendarId && externalColorMap[event.externalCalendarId]) {
      const hex = externalColorMap[event.externalCalendarId];
      return {
        backgroundColor: hex + '22',
        color: hex,
        borderColor: hex + '44',
      };
    }
    return {};
  };

  // --- Import helpers ---

  const importParsedEvents = (
    parsed: { uid: string; summary: string; description?: string; location?: string; dtstart: string; dtend: string }[],
    calendarId: string
  ) => {
    const existingUids = new Set(
      (Array.isArray(db.events) ? db.events : [])
        .filter(e => e.externalCalendarId === calendarId && e.externalUid)
        .map(e => e.externalUid!)
    );

    const newEvents: CalendarEvent[] = parsed
      .filter(p => !existingUids.has(p.uid))
      .map(p => ({
        id: Math.random().toString(36).substr(2, 9),
        familyId: family.id,
        creatorId: user.id,
        title: p.summary,
        description: p.description,
        location: p.location,
        start: p.dtstart,
        end: p.dtend,
        visibility: 'FAMILY' as Visibility,
        checklist: [],
        externalCalendarId: calendarId,
        externalUid: p.uid,
      }));

    return newEvents;
  };

  const handleFileImport = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (!importCalendarName.trim()) {
      setImportError('Please enter a calendar name first.');
      if (fileInputRef.current) fileInputRef.current.value = '';
      return;
    }
    setIsImporting(true);
    setImportError('');
    setImportSuccess('');
    try {
      const parsed = await parseICSFile(file);
      const calId = Math.random().toString(36).substr(2, 9);
      const newCal: ExternalCalendar = {
        id: calId,
        familyId: family.id,
        creatorId: user.id,
        name: importCalendarName.trim() || file.name.replace('.ics', ''),
        color: importColor,
        type: 'OTHER',
        enabled: true,
        lastSynced: new Date().toISOString(),
        createdAt: new Date().toISOString(),
      };
      const newEvents = importParsedEvents(parsed, calId);
      const newDb = {
        ...db,
        externalCalendars: [...(Array.isArray(db.externalCalendars) ? db.externalCalendars : []), newCal],
        events: [...(Array.isArray(db.events) ? db.events : []), ...newEvents],
      };
      save(newDb, 'imported a calendar', 'Calendar', newCal.name);
      setImportSuccess(`Imported "${newCal.name}" with ${newEvents.length} events.`);
      setImportCalendarName('');
      setImportColor(CALENDAR_COLORS[0]);
      if (fileInputRef.current) fileInputRef.current.value = '';
    } catch (err: any) {
      setImportError(err.message || 'Failed to parse ICS file.');
    } finally {
      setIsImporting(false);
    }
  };

  const handleUrlSubscribe = async () => {
    if (!importUrl.trim()) return;
    if (!importCalendarName.trim()) {
      setImportError('Please enter a calendar name.');
      return;
    }
    setIsImporting(true);
    setImportError('');
    setImportSuccess('');
    setUrlCorsBlocked(false);
    try {
      const parsed = await fetchAndParseICS(importUrl.trim());
      const calType = detectCalendarType(importUrl.trim());
      const calId = Math.random().toString(36).substr(2, 9);
      const newCal: ExternalCalendar = {
        id: calId,
        familyId: family.id,
        creatorId: user.id,
        name: importCalendarName.trim(),
        url: importUrl.trim(),
        color: importColor,
        type: calType,
        enabled: true,
        lastSynced: new Date().toISOString(),
        createdAt: new Date().toISOString(),
      };
      const newEvents = importParsedEvents(parsed, calId);
      const newDb = {
        ...db,
        externalCalendars: [...(Array.isArray(db.externalCalendars) ? db.externalCalendars : []), newCal],
        events: [...(Array.isArray(db.events) ? db.events : []), ...newEvents],
      };
      save(newDb, 'subscribed to a calendar', 'Calendar', newCal.name);
      setImportSuccess(`Subscribed to "${newCal.name}" with ${newEvents.length} events.`);
      setImportUrl('');
      setImportCalendarName('');
    } catch (err: any) {
      if (err.message === 'CORS_BLOCKED') {
        setUrlCorsBlocked(true);
        setImportError('The calendar provider blocked the request. Use one of the options below instead:');
      } else {
        setImportError(err.message || 'Failed to fetch calendar.');
      }
    } finally {
      setIsImporting(false);
    }
  };

  const handleSyncCalendar = async (cal: ExternalCalendar) => {
    if (cal.googleCalendarId) { await syncGoogleCalendar(cal); return; }
    if (!cal.url) return;
    setSyncingId(cal.id);
    setImportError('');
    try {
      const parsed = await fetchAndParseICS(cal.url);
      const newEvents = importParsedEvents(parsed, cal.id);
      const updatedCal = { ...cal, lastSynced: new Date().toISOString() };
      const updatedCals = (Array.isArray(db.externalCalendars) ? db.externalCalendars : [])
        .map(c => c.id === cal.id ? updatedCal : c);
      // Remove old events for this calendar before appending fresh ones (matches Google sync behavior)
      const withoutOld = (Array.isArray(db.events) ? db.events : []).filter(e => e.externalCalendarId !== cal.id);
      const newDb = {
        ...db,
        externalCalendars: updatedCals,
        events: [...withoutOld, ...newEvents],
      };
      save(newDb, 'synced a calendar', 'Calendar', cal.name);
    } catch (err: any) {
      setImportError(`Sync failed for "${cal.name}": ${err.message}`);
    } finally {
      setSyncingId(null);
    }
  };

  const toggleCalendar = (cal: ExternalCalendar) => {
    const updatedCals = (Array.isArray(db.externalCalendars) ? db.externalCalendars : [])
      .map(c => c.id === cal.id ? { ...c, enabled: !c.enabled } : c);
    save({ ...db, externalCalendars: updatedCals }, 'toggled a calendar', 'Calendar', cal.name);
  };

  const removeCalendar = (cal: ExternalCalendar) => {
    const updatedCals = (Array.isArray(db.externalCalendars) ? db.externalCalendars : [])
      .filter(c => c.id !== cal.id);
    const updatedEvents = (Array.isArray(db.events) ? db.events : [])
      .filter(e => e.externalCalendarId !== cal.id);
    save({ ...db, externalCalendars: updatedCals, events: updatedEvents }, 'removed a calendar', 'Calendar', cal.name);
  };

  const addEvent = () => {
    if (start >= end) { alert('Event end time must be after start time.'); return; }
    const newEvent: CalendarEvent = {
      id: Math.random().toString(36).substr(2, 9),
      familyId: family.id,
      creatorId: user.id,
      title,
      location,
      start,
      end,
      visibility: 'FAMILY',
      checklist: [],
      recurrence: eventRecurrence,
    };
    const newDb = { ...db, events: [...(Array.isArray(db.events) ? db.events : []), newEvent] };
    save(newDb, 'added an event', 'Calendar', title);
    setIsModalOpen(false);
    resetForm();
  };

  const resetForm = () => {
    setTitle('');
    setLocation('');
    setStart(format(new Date(), "yyyy-MM-dd'T'HH:mm"));
    setEnd(format(addDays(new Date(), 1), "yyyy-MM-dd'T'HH:mm"));
    setEventRecurrence('NONE');
  };

  /** Extract the base event ID from a possibly-generated recurring occurrence ID (e.g. "abc123_20260301" → "abc123"). */
  const baseEventId = (id: string) => id.replace(/_\d{8}$/, '');

  const deleteEvent = (id: string) => {
    const realId = baseEventId(id);
    const newDb = { ...db, events: (Array.isArray(db.events) ? db.events : []).filter(e => e.id !== realId) };
    save(newDb, 'deleted an event', 'Calendar', '');
  };

  const openEditEvent = (event: CalendarEvent) => {
    // For recurring occurrences, load the base event's original dates so we
    // don't accidentally overwrite them with a shifted occurrence's dates.
    const realId = baseEventId(event.id);
    const baseEvent = (Array.isArray(db.events) ? db.events : []).find(e => e.id === realId);
    const eventToEdit = baseEvent || event;
    setEditingEvent(eventToEdit);
    setEditTitle(eventToEdit.title);
    setEditLocation(eventToEdit.location || '');
    setEditDescription(eventToEdit.description || '');
    setEditRecurrence(eventToEdit.recurrence || 'NONE');
    try {
      setEditStart(format(new Date(eventToEdit.start), "yyyy-MM-dd'T'HH:mm"));
      setEditEnd(format(new Date(eventToEdit.end), "yyyy-MM-dd'T'HH:mm"));
    } catch {
      setEditStart(eventToEdit.start.slice(0, 16));
      setEditEnd(eventToEdit.end.slice(0, 16));
    }
  };

  const updateEvent = () => {
    if (!editingEvent || !editTitle) return;
    if (editStart >= editEnd) { alert('Event end time must be after start time.'); return; }
    const updatedEvents = (Array.isArray(db.events) ? db.events : []).map(e =>
      e.id === editingEvent.id
        ? { ...e, title: editTitle, location: editLocation, description: editDescription, start: editStart, end: editEnd, recurrence: editRecurrence }
        : e
    );
    save({ ...db, events: updatedEvents }, 'updated an event', 'Calendar', editTitle);
    setEditingEvent(null);
  };

  const handleAiItinerary = async () => {
    if (!aiInput) return;
    setIsAiLoading(true);
    setAiError('');
    try {
      const result = await generateEventItinerary(aiInput);
      const newEvent: CalendarEvent = {
        id: Math.random().toString(36).substr(2, 9),
        familyId: family.id,
        creatorId: user.id,
        title: aiInput,
        description: result.itinerary,
        start: new Date().toISOString(),
        end: addDays(new Date(), 1).toISOString(),
        visibility: 'FAMILY',
        checklist: result.checklist.map((text: string) => ({ id: Math.random().toString(), text, done: false })),
      };
      const newDb = { ...db, events: [...(Array.isArray(db.events) ? db.events : []), newEvent] };
      save(newDb, 'created an AI itinerary', 'Calendar', aiInput);
      setAiInput('');
    } catch (e: any) {
      setAiError(e?.message || 'AI failed to create itinerary. Check your API key.');
    } finally {
      setIsAiLoading(false);
    }
  };

  const openWizard = () => {
    setIsWizardOpen(true);
    setWizardStep(0);
    setSelectedTemplate('');
    setWizardForm({
      eventName: '',
      date: format(addDays(new Date(), 7), 'yyyy-MM-dd'),
      guestCount: '',
      budget: '',
      notes: '',
    });
    setPlanResult(null);
  };

  const handleSelectTemplate = (templateId: string) => {
    setSelectedTemplate(templateId);
    const tmpl = EVENT_TEMPLATES.find(t => t.id === templateId);
    if (tmpl && templateId !== 'other') {
      setWizardForm(prev => ({ ...prev, eventName: prev.eventName || tmpl.label }));
    }
    setWizardStep(1);
  };

  const handleGenerateEventPlan = async () => {
    if (!wizardForm.eventName || !wizardForm.date) return;
    setIsPlanLoading(true);
    try {
      const result = await planFullEvent({ template: selectedTemplate, ...wizardForm }, localeHint);
      const eventDate = new Date(wizardForm.date + 'T12:00:00');

      const newEvent: CalendarEvent = {
        id: Math.random().toString(36).substr(2, 9),
        familyId: family.id,
        creatorId: user.id,
        title: wizardForm.eventName,
        description: result.description,
        location: result.location_suggestion || '',
        start: eventDate.toISOString(),
        end: new Date(eventDate.getTime() + 4 * 60 * 60 * 1000).toISOString(),
        visibility: 'FAMILY',
        checklist: [],
      };

      const eventTag = wizardForm.eventName;
      const newTasks: Task[] = result.tasks.map((t: any) => ({
        id: Math.random().toString(36).substr(2, 9),
        familyId: family.id,
        creatorId: user.id,
        title: t.title,
        dueDate: subDays(eventDate, Math.max(0, t.daysBefore)).toISOString(),
        priority: (['HIGH', 'MEDIUM', 'LOW'].includes(t.priority) ? t.priority : 'MEDIUM') as 'HIGH' | 'MEDIUM' | 'LOW',
        completed: false,
        visibility: 'FAMILY' as Visibility,
        assignees: [user.id],
        tags: [eventTag, 'Event'],
      }));

      const categoryMap: Record<string, 'GROCERY' | 'HARDWARE' | 'PACKING' | 'OTHER'> = {
        GROCERY: 'GROCERY', FOOD: 'GROCERY', HARDWARE: 'HARDWARE', PACKING: 'PACKING',
      };
      const newLists: List[] = result.lists.map((l: any) => ({
        id: Math.random().toString(36).substr(2, 9),
        familyId: family.id,
        creatorId: user.id,
        title: `${wizardForm.eventName}: ${l.title}`,
        category: categoryMap[l.category.toUpperCase()] || 'OTHER',
        visibility: 'FAMILY' as Visibility,
        items: l.items.map((item: any) => ({
          id: Math.random().toString(36).substr(2, 9),
          text: item.text,
          quantity: item.quantity,
          checked: false,
        })),
      }));

      const newDb = {
        ...db,
        events: [...(Array.isArray(db.events) ? db.events : []), newEvent],
        tasks: [...(Array.isArray(db.tasks) ? db.tasks : []), ...newTasks],
        lists: [...(Array.isArray(db.lists) ? db.lists : []), ...newLists],
      };
      save(newDb, 'planned a full event', 'Calendar', wizardForm.eventName);
      setPlanResult({ ...result, createdTaskCount: newTasks.length, createdListCount: newLists.length });
      setWizardStep(2);
    } catch (e: any) {
      setPlanError(e?.message || 'AI event planning failed. Please try again.');
    } finally {
      setIsPlanLoading(false);
    }
  };

  /** Escape ICS text values per RFC 5545: backslash, semicolon, comma, newlines. */
  const escapeICS = (text: string) =>
    text.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');

  const exportToICS = (event: CalendarEvent) => {
    // toISOString() correctly converts the stored time to UTC before formatting.
    // date-fns format() uses local time — appending a literal 'Z' would falsely
    // claim UTC and shift the event by the user's UTC offset in every calendar app.
    const startStr = new Date(event.start).toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z';
    const endStr   = new Date(event.end).toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z';
    const icsContent = `BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nSUMMARY:${escapeICS(event.title)}\r\nLOCATION:${escapeICS(event.location || '')}\r\nDTSTART:${startStr}\r\nDTEND:${endStr}\r\nDESCRIPTION:${escapeICS(event.description || '')}\r\nEND:VEVENT\r\nEND:VCALENDAR`;
    const blob = new Blob([icsContent], { type: 'text/calendar' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${event.title}.ics`;
    link.click();
  };

  const openImport = (mode: 'file' | 'url' | 'google' | 'manage') => {
    setImportMode(mode);
    setImportError('');
    setImportSuccess('');
    setUrlCorsBlocked(false);
    setIsImportOpen(true);
  };

  const calendarTypeIcon = (type: string) => {
    switch (type) {
      case 'GOOGLE': return '🗓️';
      case 'OUTLOOK': return '📅';
      case 'APPLE': return '🍎';
      default: return '📆';
    }
  };

  return (
    <div className="space-y-8">
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Family Calendar</h1>
          <p className="text-stone-500">Coordinate schedules and plan life together.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => openImport('manage')}
            className="bg-stone-100 text-stone-700 px-4 py-3 rounded-2xl font-bold flex items-center gap-2 hover:bg-stone-200 transition-colors"
          >
            <Globe size={18} />
            <span>
              My Calendars
              {externalCalendars.length > 0 && (
                <span className="ml-1 bg-indigo-100 text-indigo-700 text-xs px-1.5 py-0.5 rounded-full">
                  {externalCalendars.length}
                </span>
              )}
            </span>
          </button>
          <button
            onClick={openWizard}
            className="bg-gradient-to-r from-violet-600 to-fuchsia-600 text-white px-5 py-3 rounded-2xl font-bold flex items-center gap-2 shadow-xl shadow-fuchsia-100"
          >
            <Sparkles size={18} />
            <span>Plan Event</span>
          </button>
          <button
            onClick={() => setIsModalOpen(true)}
            className="bg-indigo-600 text-white px-5 py-3 rounded-2xl font-bold flex items-center gap-2 shadow-xl shadow-indigo-100"
          >
            <Plus size={18} />
            <span>Add Event</span>
          </button>
        </div>
      </header>

      {/* External Calendar Quick Bar */}
      {externalCalendars.length > 0 && (
        <div className="flex flex-wrap items-center gap-3 p-4 bg-white rounded-2xl border border-stone-200 shadow-sm">
          <span className="text-xs font-bold text-stone-400 uppercase tracking-wider">Calendars:</span>
          {externalCalendars.map(cal => (
            <button
              key={cal.id}
              onClick={() => toggleCalendar(cal)}
              className={`flex items-center gap-2 px-3 py-1.5 rounded-xl text-sm font-bold border transition-all ${
                cal.enabled ? 'border-transparent text-white' : 'border-stone-200 text-stone-400 bg-stone-50'
              }`}
              style={cal.enabled ? { backgroundColor: cal.color } : {}}
            >
              <span className="text-base leading-none">{calendarTypeIcon(cal.type)}</span>
              {cal.name}
              {!cal.enabled && <EyeOff size={12} />}
            </button>
          ))}
          <button
            onClick={() => openImport('file')}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold border border-dashed border-stone-300 text-stone-400 hover:border-indigo-400 hover:text-indigo-600 transition-colors"
          >
            <Plus size={14} />
            Add Calendar
          </button>
        </div>
      )}

      {/* AI Quick Planner Banner */}
      <div className="bg-gradient-to-r from-violet-600 to-fuchsia-600 rounded-3xl p-6 text-white relative overflow-hidden shadow-xl shadow-fuchsia-100">
        <Sparkles className="absolute right-[-20px] top-[-20px] w-48 h-48 opacity-10" />
        <div className="relative z-10">
          <h3 className="text-xl font-bold mb-2 flex items-center">
            <Sparkles size={20} className="mr-2" />
            AI Event Strategist
          </h3>
          <p className="text-fuchsia-50 text-sm mb-4">
            Quick event: describe it and get an itinerary. Or use{' '}
            <button onClick={openWizard} className="underline font-bold hover:text-white">Plan Event</button>{' '}
            for the full wizard with tasks and shopping lists.
          </p>
          <div className="flex flex-col sm:flex-row gap-3">
            <input
              type="text"
              placeholder="e.g., Birthday party for Alpha next Saturday..."
              value={aiInput}
              onChange={(e) => setAiInput(e.target.value)}
              className="flex-1 px-4 py-2 bg-white/10 backdrop-blur-md border border-white/20 rounded-xl text-white placeholder:text-white/50 focus:outline-none focus:ring-2 focus:ring-white/50"
            />
            <button
              onClick={handleAiItinerary}
              disabled={isAiLoading || !aiInput}
              className="bg-white text-violet-600 px-6 py-2 rounded-xl font-bold hover:bg-stone-50 disabled:opacity-50 transition-colors flex items-center justify-center min-w-[120px]"
            >
              {isAiLoading ? <Loader2 size={18} className="animate-spin" /> : 'Quick Plan'}
            </button>
          </div>
          {aiError && (
            <p className="mt-3 text-sm text-red-200 bg-red-500/20 px-4 py-2 rounded-xl">{aiError}</p>
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-8">
        {/* Calendar Grid */}
        <div className="lg:col-span-3 bg-white rounded-3xl border border-stone-200 p-6 shadow-sm">
          <div className="flex items-center justify-between mb-8">
            <h2 className="text-2xl font-black text-stone-800">{format(currentDate, 'MMMM yyyy')}</h2>
            <div className="flex space-x-2">
              <button onClick={() => setCurrentDate(subMonths(currentDate, 1))} className="p-2 hover:bg-stone-50 rounded-lg text-stone-400 hover:text-stone-800"><ChevronLeft size={20} /></button>
              <button onClick={() => setCurrentDate(new Date())} className="px-4 py-2 text-sm font-bold text-stone-500 hover:bg-stone-50 rounded-lg">Today</button>
              <button onClick={() => setCurrentDate(addMonths(currentDate, 1))} className="p-2 hover:bg-stone-50 rounded-lg text-stone-400 hover:text-stone-800"><ChevronRight size={20} /></button>
            </div>
          </div>

          <div className="grid grid-cols-7 gap-px bg-stone-100 border border-stone-200 rounded-2xl overflow-hidden">
            {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map(day => (
              <div key={day} className="bg-stone-50 p-3 text-center text-xs font-bold text-stone-400 uppercase tracking-widest">{day}</div>
            ))}
            {days.map((day, idx) => {
              const dayEvents = eventsInMonth.filter(e => isSameDay(new Date(e.start), day));
              const isSelected = selectedDay && isSameDay(day, selectedDay);
              return (
                <div
                  key={idx}
                  onClick={() => setSelectedDay(day)}
                  className={`bg-white min-h-[120px] p-2 ${!isSameMonth(day, currentDate) ? 'opacity-30' : ''} hover:bg-indigo-50/50 transition-colors cursor-pointer relative ${isSelected ? 'ring-2 ring-indigo-500 ring-inset bg-indigo-50/30' : ''}`}
                >
                  <div className="flex justify-between items-start mb-2">
                    <span className={`text-sm font-bold flex items-center justify-center w-7 h-7 rounded-full ${isSameDay(day, new Date()) ? 'bg-indigo-600 text-white' : 'text-stone-700'}`}>
                      {format(day, 'd')}
                    </span>
                    {dayEvents.length > 0 && (
                      <span className="text-[9px] font-black text-indigo-400 bg-indigo-50 px-1.5 py-0.5 rounded-full">
                        {dayEvents.length}
                      </span>
                    )}
                  </div>
                  <div className="space-y-1 overflow-y-auto max-h-[80px]">
                    {dayEvents.map(event => {
                      const tailwindClass = getEventColor(event);
                      const inlineStyle = getEventStyle(event);
                      return (
                        <div
                          key={event.id}
                          className={`text-[10px] p-1 font-bold rounded border truncate flex items-center gap-0.5 ${tailwindClass || 'border'}`}
                          style={tailwindClass ? {} : inlineStyle}
                        >
                          {event.recurrence && event.recurrence !== 'NONE' && <RefreshCw size={8} className="shrink-0" />}
                          <span className="truncate">{event.title}</span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Day Detail Panel */}
        {selectedDay && (
          <div className="lg:col-span-1 bg-white rounded-3xl border border-stone-200 shadow-sm overflow-hidden">
            <div className="bg-gradient-to-r from-indigo-600 to-violet-600 px-6 py-4 text-white flex items-center justify-between">
              <div>
                <h3 className="text-lg font-bold">{format(selectedDay, 'EEEE, MMMM d')}</h3>
                <p className="text-indigo-200 text-xs font-medium">
                  {eventsInMonth.filter(e => isSameDay(new Date(e.start), selectedDay)).length} event{eventsInMonth.filter(e => isSameDay(new Date(e.start), selectedDay)).length !== 1 ? 's' : ''}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => {
                    setTitle('');
                    setLocation('');
                    setStart(format(selectedDay, "yyyy-MM-dd") + 'T09:00');
                    setEnd(format(selectedDay, "yyyy-MM-dd") + 'T10:00');
                    setEventRecurrence('NONE');
                    setIsModalOpen(true);
                  }}
                  className="flex items-center gap-1.5 bg-white/20 hover:bg-white/30 text-white px-3 py-1.5 rounded-xl text-sm font-bold transition-colors"
                >
                  <Plus size={16} />
                  <span>Add Event</span>
                </button>
                <button
                  onClick={() => setSelectedDay(null)}
                  className="p-2 hover:bg-white/10 rounded-xl transition-colors"
                >
                  <X size={18} />
                </button>
              </div>
            </div>
            <div className="p-6">
              {(() => {
                const dayEvents = eventsInMonth
                  .filter(e => isSameDay(new Date(e.start), selectedDay))
                  .sort((a, b) => new Date(a.start).getTime() - new Date(b.start).getTime());

                if (dayEvents.length === 0) {
                  return (
                    <div className="text-center py-12">
                      <CalendarIcon size={32} className="text-stone-200 mx-auto mb-3" />
                      <p className="text-stone-400 font-medium">No events on this day</p>
                      <button
                        onClick={() => {
                          setTitle('');
                          setLocation('');
                          setStart(format(selectedDay, "yyyy-MM-dd") + 'T09:00');
                          setEnd(format(selectedDay, "yyyy-MM-dd") + 'T10:00');
                          setEventRecurrence('NONE');
                          setIsModalOpen(true);
                        }}
                        className="mt-3 inline-flex items-center gap-1.5 bg-indigo-600 text-white px-4 py-2 rounded-xl text-sm font-bold hover:bg-indigo-700 transition-colors"
                      >
                        <Plus size={16} />
                        Create an event
                      </button>
                    </div>
                  );
                }

                return (
                  <div className="space-y-3">
                    {dayEvents.map(event => {
                      const exCal = event.externalCalendarId
                        ? externalCalendars.find(c => c.id === event.externalCalendarId)
                        : null;
                      return (
                        <div key={event.id} className="flex items-start gap-4 p-4 bg-stone-50 rounded-2xl border border-stone-100 hover:border-indigo-200 transition-all group">
                          {/* Time column */}
                          <div className="shrink-0 w-16 text-center pt-0.5">
                            <p className="text-sm font-black text-indigo-600">{fmtTime(new Date(event.start))}</p>
                            <p className="text-[10px] text-stone-400">{fmtTime(new Date(event.end))}</p>
                          </div>
                          {/* Divider */}
                          <div className="w-0.5 self-stretch bg-indigo-200 rounded-full shrink-0" />
                          {/* Content */}
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 mb-1">
                              <h4 className="font-bold text-stone-800 truncate">{event.title}</h4>
                              {event.recurrence && event.recurrence !== 'NONE' && (
                                <span className="flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full bg-violet-100 text-violet-600">
                                  <RefreshCw size={10} />
                                  {event.recurrence === 'DAILY' ? 'Daily' : event.recurrence === 'WEEKLY' ? 'Weekly' : 'Monthly'}
                                </span>
                              )}
                              {exCal && (
                                <span
                                  className="text-[10px] font-bold px-2 py-0.5 rounded-full"
                                  style={{ backgroundColor: exCal.color + '22', color: exCal.color }}
                                >
                                  {exCal.name}
                                </span>
                              )}
                            </div>
                            {event.location && (
                              <p className="flex items-center gap-1 text-xs text-stone-500 mb-1">
                                <MapPin size={12} className="shrink-0" />
                                {event.location}
                              </p>
                            )}
                            {event.description && (
                              <p className="text-xs text-stone-400 line-clamp-2 leading-relaxed">{event.description}</p>
                            )}
                            {event.checklist && event.checklist.length > 0 && (
                              <div className="mt-2 flex items-center gap-2">
                                <div className="h-1.5 flex-1 bg-stone-200 rounded-full overflow-hidden">
                                  <div
                                    className="h-full bg-indigo-500 rounded-full"
                                    style={{ width: `${(event.checklist.filter(c => c.done).length / event.checklist.length) * 100}%` }}
                                  />
                                </div>
                                <span className="text-[10px] font-bold text-stone-400">
                                  {event.checklist.filter(c => c.done).length}/{event.checklist.length}
                                </span>
                              </div>
                            )}
                          </div>
                          {/* Actions */}
                          <div className="flex items-center gap-1 shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
                            {!event.externalCalendarId && (
                              <>
                                <button
                                  onClick={(e) => { e.stopPropagation(); openEditEvent(event); }}
                                  className="p-2 text-stone-400 hover:text-indigo-600 rounded-lg hover:bg-indigo-50 transition-colors"
                                  title="Edit"
                                >
                                  <Pencil size={16} />
                                </button>
                                <button
                                  onClick={(e) => { e.stopPropagation(); exportToICS(event); }}
                                  className="p-2 text-stone-400 hover:text-indigo-600 rounded-lg hover:bg-indigo-50 transition-colors"
                                  title="Export"
                                >
                                  <Download size={16} />
                                </button>
                              </>
                            )}
                            <button
                              onClick={(e) => { e.stopPropagation(); deleteEvent(event.id); }}
                              className="p-2 text-stone-400 hover:text-red-600 rounded-lg hover:bg-red-50 transition-colors"
                              title="Delete"
                            >
                              <Trash2 size={16} />
                            </button>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                );
              })()}
            </div>
          </div>
        )}

        {/* Sidebar */}
        <div className="space-y-6">
          {/* Import shortcuts */}
          <div className="bg-white rounded-2xl border border-stone-200 p-4 shadow-sm">
            <h3 className="text-sm font-bold text-stone-700 mb-3">Import External Calendar</h3>
            <div className="space-y-2">
              <button
                onClick={() => openImport('file')}
                className="w-full flex items-center gap-3 p-3 rounded-xl bg-stone-50 hover:bg-indigo-50 border border-stone-100 hover:border-indigo-200 transition-all text-left"
              >
                <div className="p-2 bg-indigo-100 rounded-lg">
                  <Upload size={16} className="text-indigo-600" />
                </div>
                <div>
                  <p className="text-sm font-bold text-stone-800">Upload .ics File</p>
                  <p className="text-[10px] text-stone-400">From Google, Apple, Outlook…</p>
                </div>
              </button>
              <button
                onClick={() => openImport('url')}
                className="w-full flex items-center gap-3 p-3 rounded-xl bg-stone-50 hover:bg-teal-50 border border-stone-100 hover:border-teal-200 transition-all text-left"
              >
                <div className="p-2 bg-teal-100 rounded-lg">
                  <Link size={16} className="text-teal-600" />
                </div>
                <div>
                  <p className="text-sm font-bold text-stone-800">Subscribe via URL</p>
                  <p className="text-[10px] text-stone-400">Paste a public iCal feed URL</p>
                </div>
              </button>
            </div>
          </div>

          {/* Coming Up */}
          <h3 className="text-xl font-bold text-stone-800">Coming Up</h3>
          <div className="space-y-4">
            {upcomingEvents.length > 0 ? upcomingEvents.map(event => {
              const tailwindClass = getEventColor(event);
              const inlineStyle = getEventStyle(event);
              const exCal = event.externalCalendarId
                ? externalCalendars.find(c => c.id === event.externalCalendarId)
                : null;
              return (
                <div key={event.id} className="bg-white rounded-2xl border border-stone-200 p-4 shadow-sm hover:border-indigo-200 transition-all group">
                  <div className="flex justify-between items-start mb-2">
                    <div className="flex items-center gap-2">
                      <p className="text-xs font-bold text-indigo-600 uppercase">{format(new Date(event.start), 'MMM d')}</p>
                      {exCal && (
                        <span
                          className="text-[10px] font-bold px-2 py-0.5 rounded-full"
                          style={{ backgroundColor: exCal.color + '22', color: exCal.color }}
                        >
                          {calendarTypeIcon(exCal.type)} {exCal.name}
                        </span>
                      )}
                    </div>
                    <div className="flex space-x-1">
                      {!event.externalCalendarId && (
                        <>
                          <button onClick={() => openEditEvent(event)} className="p-2 text-stone-400 hover:text-indigo-600 active:text-indigo-600 rounded-lg transition-colors" title="Edit">
                            <Pencil size={16} />
                          </button>
                          <button onClick={() => exportToICS(event)} className="p-2 text-stone-400 hover:text-indigo-600 active:text-indigo-600 rounded-lg transition-colors" title="Export to ICS">
                            <Download size={16} />
                          </button>
                        </>
                      )}
                      <button onClick={() => deleteEvent(event.id)} className="p-2 text-stone-400 hover:text-red-600 active:text-red-600 rounded-lg transition-colors">
                        <Trash2 size={16} />
                      </button>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 mb-2">
                    <h4 className="font-bold text-stone-800">{event.title}</h4>
                    {event.recurrence && event.recurrence !== 'NONE' && (
                      <span className="flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full bg-violet-100 text-violet-600">
                        <RefreshCw size={10} />
                        {event.recurrence === 'DAILY' ? 'Daily' : event.recurrence === 'WEEKLY' ? 'Weekly' : 'Monthly'}
                      </span>
                    )}
                  </div>
                  <div className="space-y-1">
                    <div className="flex items-center text-[10px] text-stone-500">
                      <Clock size={12} className="mr-1" />
                      {fmtTime(new Date(event.start))} – {fmtTime(new Date(event.end))}
                    </div>
                    {event.location && (
                      <div className="flex items-center text-[10px] text-stone-500">
                        <MapPin size={12} className="mr-1" />
                        {event.location}
                      </div>
                    )}
                  </div>
                  {event.checklist && event.checklist.length > 0 && (
                    <div className="mt-3 pt-3 border-t border-stone-50">
                      <div className="flex items-center justify-between text-[10px] text-stone-400 mb-1">
                        <span>Checklist</span>
                        <span>{event.checklist.filter(c => c.done).length}/{event.checklist.length}</span>
                      </div>
                      <div className="h-1 w-full bg-stone-100 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-indigo-500 rounded-full"
                          style={{ width: `${(event.checklist.filter(c => c.done).length / event.checklist.length) * 100}%` }}
                        />
                      </div>
                    </div>
                  )}
                </div>
              );
            }) : (
              <div className="text-center py-12 text-stone-400 border border-dashed border-stone-200 rounded-3xl">No upcoming events in the next 90 days.</div>
            )}
          </div>
        </div>
      </div>

      {/* Add Event Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-md rounded-3xl p-8 shadow-2xl">
            <h2 className="text-2xl font-bold mb-6">Create New Event</h2>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Event Title</label>
                <input type="text" value={title} onChange={(e) => setTitle(e.target.value)}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900"
                  placeholder="What's happening?" />
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Location</label>
                <input type="text" value={location} onChange={(e) => setLocation(e.target.value)}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900"
                  placeholder="Where?" />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-bold text-stone-700 mb-2">Start</label>
                  <input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)}
                    className="w-full px-3 py-3 bg-stone-50 border border-stone-200 rounded-xl text-sm text-stone-900" />
                </div>
                <div>
                  <label className="block text-sm font-bold text-stone-700 mb-2">End</label>
                  <input type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)}
                    className="w-full px-3 py-3 bg-stone-50 border border-stone-200 rounded-xl text-sm text-stone-900" />
                </div>
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Repeat</label>
                <div className="flex gap-2">
                  {(['NONE', 'DAILY', 'WEEKLY', 'MONTHLY'] as const).map(r => (
                    <button
                      key={r}
                      type="button"
                      onClick={() => setEventRecurrence(r)}
                      className={`flex-1 py-2 rounded-xl text-xs font-bold border transition-all flex items-center justify-center gap-1 ${eventRecurrence === r ? 'bg-violet-600 border-violet-600 text-white' : 'bg-white border-stone-200 text-stone-500 hover:border-stone-400'}`}
                    >
                      {r !== 'NONE' && <RefreshCw size={10} />}
                      {r === 'NONE' ? 'None' : r === 'DAILY' ? 'Daily' : r === 'WEEKLY' ? 'Weekly' : 'Monthly'}
                    </button>
                  ))}
                </div>
              </div>
              <div className="pt-4 flex gap-3">
                <button onClick={() => { setIsModalOpen(false); resetForm(); }} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold">Cancel</button>
                <button onClick={addEvent} disabled={!title} className="flex-1 py-3 bg-indigo-600 text-white rounded-xl font-bold shadow-lg shadow-indigo-100 disabled:opacity-50">Create</button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Edit Event Modal */}
      {editingEvent && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-md rounded-3xl p-8 shadow-2xl">
            <h2 className="text-2xl font-bold mb-6">Edit Event</h2>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Event Title</label>
                <input type="text" value={editTitle} onChange={(e) => setEditTitle(e.target.value)}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900"
                  placeholder="What's happening?" />
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Location</label>
                <input type="text" value={editLocation} onChange={(e) => setEditLocation(e.target.value)}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900"
                  placeholder="Where?" />
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Description</label>
                <textarea value={editDescription} onChange={(e) => setEditDescription(e.target.value)}
                  rows={3}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900 resize-none"
                  placeholder="Event details..." />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-bold text-stone-700 mb-2">Start</label>
                  <input type="datetime-local" value={editStart} onChange={(e) => setEditStart(e.target.value)}
                    className="w-full px-3 py-3 bg-stone-50 border border-stone-200 rounded-xl text-sm text-stone-900" />
                </div>
                <div>
                  <label className="block text-sm font-bold text-stone-700 mb-2">End</label>
                  <input type="datetime-local" value={editEnd} onChange={(e) => setEditEnd(e.target.value)}
                    className="w-full px-3 py-3 bg-stone-50 border border-stone-200 rounded-xl text-sm text-stone-900" />
                </div>
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Repeat</label>
                <div className="flex gap-2">
                  {(['NONE', 'DAILY', 'WEEKLY', 'MONTHLY'] as const).map(r => (
                    <button
                      key={r}
                      type="button"
                      onClick={() => setEditRecurrence(r)}
                      className={`flex-1 py-2 rounded-xl text-xs font-bold border transition-all flex items-center justify-center gap-1 ${editRecurrence === r ? 'bg-violet-600 border-violet-600 text-white' : 'bg-white border-stone-200 text-stone-500 hover:border-stone-400'}`}
                    >
                      {r !== 'NONE' && <RefreshCw size={10} />}
                      {r === 'NONE' ? 'None' : r === 'DAILY' ? 'Daily' : r === 'WEEKLY' ? 'Weekly' : 'Monthly'}
                    </button>
                  ))}
                </div>
              </div>
              <div className="pt-4 flex gap-3">
                <button onClick={() => setEditingEvent(null)} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold">Cancel</button>
                <button onClick={updateEvent} disabled={!editTitle} className="flex-1 py-3 bg-indigo-600 text-white rounded-xl font-bold shadow-lg shadow-indigo-100 disabled:opacity-50">Save</button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Import / Manage Modal */}
      {isImportOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-lg rounded-3xl shadow-2xl overflow-hidden max-h-[90vh] flex flex-col">
            {/* Header */}
            <div className="bg-gradient-to-r from-indigo-600 to-teal-500 p-6 text-white flex items-center justify-between shrink-0">
              <div>
                <h2 className="text-xl font-bold flex items-center gap-2">
                  <Globe size={22} />
                  External Calendars
                </h2>
                <p className="text-indigo-100 text-sm mt-0.5">Import from Google, Apple, Outlook and more</p>
              </div>
              <button onClick={() => setIsImportOpen(false)} className="p-2 hover:bg-white/10 rounded-xl transition-colors">
                <X size={20} />
              </button>
            </div>

            {/* Tabs */}
            <div className="flex border-b border-stone-100 shrink-0">
              {(['file', 'url', 'google', 'manage'] as const).map(tab => (
                <button
                  key={tab}
                  onClick={() => { setImportMode(tab); setImportError(''); setImportSuccess(''); setUrlCorsBlocked(false); setGcalError(''); if (tab === 'google' && gcalCalendars.length === 0) connectGoogleCalendar(); }}
                  className={`flex-1 py-3 text-xs font-bold transition-colors ${
                    importMode === tab
                      ? 'text-indigo-600 border-b-2 border-indigo-600'
                      : 'text-stone-400 hover:text-stone-600'
                  }`}
                >
                  {tab === 'file' ? '📁 File' : tab === 'url' ? '🔗 URL' : tab === 'google' ? '🗓️ Google' : `📆 Mine (${externalCalendars.length})`}
                </button>
              ))}
            </div>

            <div className="flex-1 overflow-y-auto p-6">
              {/* Error / Success */}
              {importError && (
                <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-xl flex items-start gap-2">
                  <AlertCircle size={16} className="text-red-500 shrink-0 mt-0.5" />
                  <p className="text-sm text-red-700">{importError}</p>
                </div>
              )}
              {importSuccess && (
                <div className="mb-4 p-3 bg-emerald-50 border border-emerald-200 rounded-xl flex items-start gap-2">
                  <CheckCircle2 size={16} className="text-emerald-500 shrink-0 mt-0.5" />
                  <p className="text-sm text-emerald-700">{importSuccess}</p>
                </div>
              )}

              {/* File Upload */}
              {importMode === 'file' && (
                <div className="space-y-4">
                  <p className="text-sm text-stone-500">
                    Export a calendar as <strong>.ics</strong> from Google Calendar, Apple Calendar, or Outlook, then upload it here.
                  </p>
                  <div>
                    <label className="block text-sm font-bold text-stone-700 mb-2">Calendar Name</label>
                    <input
                      type="text"
                      placeholder="e.g., Mom's Google Calendar"
                      value={importCalendarName}
                      onChange={(e) => setImportCalendarName(e.target.value)}
                      className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-bold text-stone-700 mb-2">Calendar Color</label>
                    <div className="flex gap-2 flex-wrap">
                      {CALENDAR_COLORS.map(c => (
                        <button key={c} onClick={() => setImportColor(c)}
                          className={`w-8 h-8 rounded-full border-4 transition-all ${importColor === c ? 'border-stone-400 scale-110' : 'border-transparent'}`}
                          style={{ backgroundColor: c }} />
                      ))}
                    </div>
                  </div>
                  <div>
                    <label className="block text-sm font-bold text-stone-700 mb-2">ICS File</label>
                    <label className="flex flex-col items-center justify-center w-full h-32 border-2 border-dashed border-stone-300 rounded-2xl cursor-pointer hover:border-indigo-400 hover:bg-indigo-50 transition-all">
                      <Upload size={24} className="text-stone-400 mb-2" />
                      <span className="text-sm font-bold text-stone-500">Click to choose .ics file</span>
                      <span className="text-xs text-stone-400 mt-1">or drag and drop</span>
                      <input
                        ref={fileInputRef}
                        type="file"
                        accept=".ics,.ical,.ifb,.icalendar,text/calendar,application/ics"
                        className="hidden"
                        onChange={handleFileImport}
                        disabled={isImporting}
                      />
                    </label>
                  </div>
                  {isImporting && (
                    <div className="flex items-center gap-2 text-indigo-600">
                      <Loader2 size={16} className="animate-spin" />
                      <span className="text-sm font-bold">Importing events…</span>
                    </div>
                  )}
                  <div className="bg-stone-50 rounded-xl p-4 text-xs text-stone-500 space-y-1.5 border border-stone-100">
                    <p className="font-bold text-stone-600 mb-2">How to export from:</p>
                    <p><strong>Google Calendar:</strong> Settings → select calendar → Export</p>
                    <p><strong>Apple Calendar:</strong> File → Export → Export…</p>
                    <p><strong>Outlook:</strong> File → Open & Export → Import/Export → Export to file → iCalendar</p>
                  </div>
                </div>
              )}

              {/* URL Subscribe */}
              {importMode === 'url' && (
                <div className="space-y-4">
                  <p className="text-sm text-stone-500">
                    Paste a public iCal feed URL. Google Calendar "public" share links and most CalDAV URLs work. Private calendar URLs may be blocked by CORS — use file import in that case.
                  </p>
                  <div>
                    <label className="block text-sm font-bold text-stone-700 mb-2">Calendar Name</label>
                    <input
                      type="text"
                      placeholder="e.g., Family Holidays"
                      value={importCalendarName}
                      onChange={(e) => setImportCalendarName(e.target.value)}
                      className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-bold text-stone-700 mb-2">iCal URL</label>
                    <input
                      type="url"
                      placeholder="https://calendar.google.com/calendar/ical/…/basic.ics"
                      value={importUrl}
                      onChange={(e) => setImportUrl(e.target.value)}
                      className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-bold text-stone-700 mb-2">Calendar Color</label>
                    <div className="flex gap-2 flex-wrap">
                      {CALENDAR_COLORS.map(c => (
                        <button key={c} onClick={() => setImportColor(c)}
                          className={`w-8 h-8 rounded-full border-4 transition-all ${importColor === c ? 'border-stone-400 scale-110' : 'border-transparent'}`}
                          style={{ backgroundColor: c }} />
                      ))}
                    </div>
                  </div>
                  <button
                    onClick={handleUrlSubscribe}
                    disabled={isImporting || !importUrl.trim() || !importCalendarName.trim()}
                    className="w-full py-3 bg-teal-600 text-white rounded-xl font-bold hover:bg-teal-700 disabled:opacity-50 flex items-center justify-center gap-2 transition-colors"
                  >
                    {isImporting ? <><Loader2 size={18} className="animate-spin" /> Fetching…</> : <><Link size={18} /> Subscribe & Import</>}
                  </button>

                  {/* CORS fallback helpers */}
                  {urlCorsBlocked && importUrl.trim() && (
                    <div className="bg-amber-50 border border-amber-200 rounded-2xl p-4 space-y-3">
                      <p className="text-sm font-bold text-amber-800">Quick fix options:</p>
                      <button
                        onClick={() => {
                          window.open(importUrl.trim(), '_blank');
                        }}
                        className="w-full py-2.5 bg-amber-600 text-white rounded-xl font-bold text-sm flex items-center justify-center gap-2 hover:bg-amber-700 transition-colors"
                      >
                        <Download size={16} />
                        Open URL in new tab to download .ics
                      </button>
                      <button
                        onClick={() => {
                          setImportMode('file');
                          setImportError('');
                          setUrlCorsBlocked(false);
                        }}
                        className="w-full py-2.5 bg-white text-amber-800 border border-amber-300 rounded-xl font-bold text-sm flex items-center justify-center gap-2 hover:bg-amber-50 transition-colors"
                      >
                        <Upload size={16} />
                        Switch to File Upload
                      </button>
                      <p className="text-xs text-amber-600">
                        Open the URL above, save the page as a .ics file, then upload it using File Import. The calendar name and color you picked will carry over.
                      </p>
                    </div>
                  )}

                  <div className="bg-stone-50 rounded-xl p-4 text-xs text-stone-500 border border-stone-100">
                    <p className="font-bold text-stone-600 mb-2">How to get your iCal URL from Google:</p>
                    <p>1. Open Google Calendar settings</p>
                    <p>2. Click a calendar → "Integrate calendar"</p>
                    <p>3. Copy the "Public address in iCal format" link</p>
                  </div>
                </div>
              )}

              {/* Google Calendar OAuth */}
              {importMode === 'google' && (
                <div className="space-y-4">
                  {gcalConnecting && (
                    <div className="flex flex-col items-center justify-center py-10 gap-3">
                      <Loader2 size={32} className="animate-spin text-indigo-500" />
                      <p className="text-sm text-stone-500 font-bold">Connecting to Google Calendar…</p>
                    </div>
                  )}
                  {!gcalConnecting && gcalError && (
                    <div className="space-y-3">
                      <div className="flex items-start gap-2 p-3 bg-red-50 border border-red-100 rounded-xl">
                        <AlertCircle size={16} className="text-red-500 mt-0.5 shrink-0" />
                        <p className="text-sm text-red-700">{gcalError}</p>
                      </div>
                      {gcalError.includes('VITE_GOOGLE_CLIENT_ID') && (
                        <div className="bg-stone-50 rounded-xl p-4 text-xs text-stone-600 space-y-2 border border-stone-100">
                          <p className="font-bold text-stone-800">Setup: Google Calendar API</p>
                          <ol className="list-decimal list-inside space-y-1">
                            <li>Go to <span className="font-mono bg-stone-100 px-1 rounded">console.cloud.google.com</span></li>
                            <li>Create a project → Enable <strong>Google Calendar API</strong></li>
                            <li>Credentials → Create OAuth 2.0 Client ID (Web Application)</li>
                            <li>Add your app origin to <strong>Authorised JavaScript origins</strong></li>
                            <li>Copy the Client ID and set <span className="font-mono bg-stone-100 px-1 rounded">VITE_GOOGLE_CLIENT_ID=&lt;id&gt;</span> in your <span className="font-mono bg-stone-100 px-1 rounded">.env</span> file</li>
                          </ol>
                        </div>
                      )}
                      <button
                        onClick={() => { setGcalError(''); connectGoogleCalendar(); }}
                        className="w-full py-2.5 bg-indigo-600 text-white rounded-xl font-bold text-sm hover:bg-indigo-700 flex items-center justify-center gap-2"
                      >
                        <RefreshCw size={15} /> Try Again
                      </button>
                    </div>
                  )}
                  {!gcalConnecting && !gcalError && gcalCalendars.length === 0 && (
                    <div className="text-center py-8">
                      <p className="text-stone-400 text-sm mb-4">Click below to connect your Google account and choose which calendars to sync.</p>
                      <button
                        onClick={connectGoogleCalendar}
                        className="mx-auto flex items-center gap-2 px-6 py-3 bg-white border-2 border-stone-200 rounded-2xl font-bold text-stone-700 hover:border-indigo-400 hover:text-indigo-600 transition-all shadow-sm"
                      >
                        <span className="text-xl">🗓️</span> Connect Google Calendar
                      </button>
                    </div>
                  )}
                  {!gcalConnecting && gcalCalendars.length > 0 && (
                    <div className="space-y-3">
                      <p className="text-sm text-stone-500">Select calendars to add to your family calendar:</p>
                      <div className="space-y-2 max-h-52 overflow-y-auto custom-scrollbar">
                        {gcalCalendars.map(cal => {
                          const alreadyAdded = externalCalendars.some(c => c.googleCalendarId === cal.id);
                          return (
                            <label
                              key={cal.id}
                              className={`flex items-center gap-3 p-3 rounded-xl border cursor-pointer transition-all ${
                                alreadyAdded ? 'border-stone-100 bg-stone-50 opacity-60 cursor-not-allowed' :
                                gcalSelectedIds.has(cal.id) ? 'border-indigo-300 bg-indigo-50' : 'border-stone-200 bg-white hover:border-indigo-200'
                              }`}
                            >
                              <input
                                type="checkbox"
                                checked={alreadyAdded || gcalSelectedIds.has(cal.id)}
                                disabled={alreadyAdded}
                                onChange={() => {
                                  if (alreadyAdded) return;
                                  setGcalSelectedIds(prev => {
                                    const next = new Set(prev);
                                    next.has(cal.id) ? next.delete(cal.id) : next.add(cal.id);
                                    return next;
                                  });
                                }}
                                className="rounded"
                              />
                              <span className="w-3 h-3 rounded-full shrink-0" style={{ backgroundColor: cal.backgroundColor }} />
                              <span className="text-sm font-bold text-stone-800 flex-1 truncate">{cal.summary}</span>
                              {cal.primary && <span className="text-[10px] bg-indigo-100 text-indigo-600 px-1.5 py-0.5 rounded-full font-bold shrink-0">Primary</span>}
                              {alreadyAdded && <span className="text-[10px] bg-green-100 text-green-600 px-1.5 py-0.5 rounded-full font-bold shrink-0">Added</span>}
                            </label>
                          );
                        })}
                      </div>
                      <button
                        onClick={importGoogleCalendars}
                        disabled={gcalSelectedIds.size === 0 || gcalImporting}
                        className="w-full py-2.5 bg-indigo-600 text-white rounded-xl font-bold text-sm hover:bg-indigo-700 disabled:opacity-50 flex items-center justify-center gap-2 transition-colors"
                      >
                        {gcalImporting ? <Loader2 size={15} className="animate-spin" /> : <Plus size={15} />}
                        {gcalImporting ? 'Importing…' : `Add ${gcalSelectedIds.size > 0 ? gcalSelectedIds.size : ''} Calendar${gcalSelectedIds.size !== 1 ? 's' : ''}`}
                      </button>
                    </div>
                  )}
                </div>
              )}

              {/* Manage */}
              {importMode === 'manage' && (
                <div className="space-y-3">
                  {externalCalendars.length === 0 ? (
                    <div className="text-center py-12 text-stone-400">
                      <Globe size={40} className="mx-auto mb-3 opacity-30" />
                      <p className="font-bold">No external calendars yet</p>
                      <p className="text-sm mt-1">Upload a file or subscribe via URL to get started.</p>
                    </div>
                  ) : (
                    externalCalendars.map(cal => (
                      <div key={cal.id} className="flex items-start gap-3 p-4 bg-stone-50 rounded-2xl border border-stone-100">
                        <div className="w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0"
                          style={{ backgroundColor: cal.color + '22' }}>
                          {calendarTypeIcon(cal.type)}
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            <h4 className="font-bold text-stone-800 truncate">{cal.name}</h4>
                            <span
                              className="text-[10px] font-black px-2 py-0.5 rounded-full shrink-0"
                              style={{ backgroundColor: cal.color + '22', color: cal.color }}
                            >
                              {cal.type}
                            </span>
                          </div>
                          {cal.url && (
                            <p className="text-xs text-stone-400 truncate mb-1">{cal.url}</p>
                          )}
                          <p className="text-[10px] text-stone-400">
                            {cal.lastSynced
                              ? `Last synced: ${fmtDateTime(new Date(cal.lastSynced))}`
                              : 'Never synced'}
                          </p>
                          <p className="text-[10px] text-stone-400 mt-0.5">
                            {(Array.isArray(db.events) ? db.events : []).filter(e => e.externalCalendarId === cal.id).length} events imported
                          </p>
                        </div>
                        <div className="flex flex-col gap-1 shrink-0">
                          <button
                            onClick={() => toggleCalendar(cal)}
                            className={`p-2 rounded-lg transition-colors ${cal.enabled ? 'text-indigo-600 bg-indigo-50 hover:bg-indigo-100' : 'text-stone-400 bg-stone-100 hover:bg-stone-200'}`}
                            title={cal.enabled ? 'Hide calendar' : 'Show calendar'}
                          >
                            {cal.enabled ? <Eye size={16} /> : <EyeOff size={16} />}
                          </button>
                          {(cal.url || cal.googleCalendarId) && (
                            <button
                              onClick={() => handleSyncCalendar(cal)}
                              disabled={syncingId === cal.id}
                              className="p-2 rounded-lg text-teal-600 bg-teal-50 hover:bg-teal-100 transition-colors disabled:opacity-50"
                              title="Sync now"
                            >
                              {syncingId === cal.id
                                ? <Loader2 size={16} className="animate-spin" />
                                : <RefreshCw size={16} />}
                            </button>
                          )}
                          <button
                            onClick={() => removeCalendar(cal)}
                            className="p-2 rounded-lg text-red-400 bg-red-50 hover:bg-red-100 transition-colors"
                            title="Remove calendar"
                          >
                            <Trash2 size={16} />
                          </button>
                        </div>
                      </div>
                    ))
                  )}
                  <div className="flex gap-2 pt-2">
                    <button
                      onClick={() => setImportMode('file')}
                      className="flex-1 py-2.5 bg-stone-100 text-stone-700 rounded-xl font-bold text-sm hover:bg-stone-200 flex items-center justify-center gap-2 transition-colors"
                    >
                      <Upload size={15} /> File
                    </button>
                    <button
                      onClick={() => setImportMode('url')}
                      className="flex-1 py-2.5 bg-stone-100 text-stone-700 rounded-xl font-bold text-sm hover:bg-stone-200 flex items-center justify-center gap-2 transition-colors"
                    >
                      <Link size={15} /> URL
                    </button>
                    <button
                      onClick={() => { setImportMode('google'); setGcalError(''); if (gcalCalendars.length === 0) connectGoogleCalendar(); }}
                      className="flex-1 py-2.5 bg-stone-100 text-stone-700 rounded-xl font-bold text-sm hover:bg-stone-200 flex items-center justify-center gap-2 transition-colors"
                    >
                      <span>🗓️</span> Google
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Event Planner Wizard Modal */}
      {isWizardOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-2xl rounded-3xl shadow-2xl overflow-hidden max-h-[90vh] flex flex-col">
            <div className="bg-gradient-to-r from-violet-600 to-fuchsia-600 p-6 text-white flex items-center justify-between shrink-0">
              <div>
                <h2 className="text-2xl font-bold flex items-center gap-2">
                  <Sparkles size={24} />
                  AI Event Planner
                </h2>
                <p className="text-fuchsia-100 text-sm mt-1">
                  {wizardStep === 0 && 'Choose an event type to get started'}
                  {wizardStep === 1 && 'Tell us about your event'}
                  {wizardStep === 2 && 'Your event plan is ready!'}
                </p>
              </div>
              <button onClick={() => setIsWizardOpen(false)} className="p-2 hover:bg-white/10 rounded-xl transition-colors">
                <X size={20} />
              </button>
            </div>

            <div className="flex-1 overflow-y-auto p-6">
              {wizardStep === 0 && (
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                  {EVENT_TEMPLATES.map(tmpl => {
                    const IconComp = tmpl.icon;
                    return (
                      <button key={tmpl.id} onClick={() => handleSelectTemplate(tmpl.id)}
                        className="flex flex-col items-center gap-3 p-5 rounded-2xl border-2 border-stone-100 hover:border-violet-300 hover:bg-violet-50 transition-all">
                        <div className={`p-3 rounded-2xl ${tmpl.color}`}><IconComp size={28} /></div>
                        <span className="text-sm font-bold text-stone-700">{tmpl.label}</span>
                      </button>
                    );
                  })}
                </div>
              )}

              {wizardStep === 1 && (
                <div className="space-y-4">
                  <div>
                    <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Event Name</label>
                    <input type="text" placeholder="e.g., Alpha's 8th Birthday Party" value={wizardForm.eventName}
                      onChange={(e) => setWizardForm({ ...wizardForm, eventName: e.target.value })}
                      className="w-full px-4 py-3 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-600/20 text-sm" />
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <div>
                      <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Date</label>
                      <input type="date" value={wizardForm.date} onChange={(e) => setWizardForm({ ...wizardForm, date: e.target.value })}
                        className="w-full px-4 py-3 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-600/20 text-sm" />
                    </div>
                    <div>
                      <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Guests</label>
                      <input type="text" placeholder="e.g., 20" value={wizardForm.guestCount}
                        onChange={(e) => setWizardForm({ ...wizardForm, guestCount: e.target.value })}
                        className="w-full px-4 py-3 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-600/20 text-sm" />
                    </div>
                    <div>
                      <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Budget</label>
                      <input type="text" placeholder="e.g., $200" value={wizardForm.budget}
                        onChange={(e) => setWizardForm({ ...wizardForm, budget: e.target.value })}
                        className="w-full px-4 py-3 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-600/20 text-sm" />
                    </div>
                  </div>
                  <div>
                    <label className="block text-xs font-bold text-stone-500 mb-2 uppercase tracking-wider">Extra Details (optional)</label>
                    <textarea placeholder="e.g., Theme is dinosaurs, outdoor venue preferred…" value={wizardForm.notes}
                      onChange={(e) => setWizardForm({ ...wizardForm, notes: e.target.value })}
                      rows={3} className="w-full px-4 py-3 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-600/20 text-sm resize-none" />
                  </div>
                  {planError && (
                    <p className="text-sm text-red-600 bg-red-50 border border-red-200 px-4 py-2 rounded-xl">{planError}</p>
                  )}
                  <div className="flex gap-3 pt-2">
                    <button onClick={() => { setWizardStep(0); setSelectedTemplate(''); setPlanError(''); }}
                      className="px-6 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold hover:bg-stone-200 transition-colors">Back</button>
                    <button onClick={handleGenerateEventPlan} disabled={isPlanLoading || !wizardForm.eventName || !wizardForm.date}
                      className="flex-1 py-3 bg-gradient-to-r from-violet-600 to-fuchsia-600 text-white rounded-xl font-bold shadow-lg shadow-fuchsia-100 disabled:opacity-50 flex items-center justify-center gap-2 transition-colors">
                      {isPlanLoading ? <><Loader2 size={18} className="animate-spin" /> Planning…</> : <><Sparkles size={18} /> Generate Full Plan</>}
                    </button>
                  </div>
                </div>
              )}

              {wizardStep === 2 && planResult && (
                <div className="space-y-6">
                  <div className="bg-gradient-to-r from-emerald-50 to-teal-50 border border-emerald-200 rounded-2xl p-5">
                    <h3 className="font-bold text-emerald-800 flex items-center gap-2 mb-3">
                      <CheckCircle2 size={20} className="text-emerald-500" /> Event Plan Created!
                    </h3>
                    <div className="grid grid-cols-3 gap-3">
                      <div className="bg-white rounded-xl p-3 text-center border border-emerald-100">
                        <CalendarIcon size={18} className="mx-auto text-violet-500 mb-1" />
                        <p className="text-lg font-black text-stone-800">1</p>
                        <p className="text-[10px] font-bold text-stone-400 uppercase">Calendar Event</p>
                      </div>
                      <div className="bg-white rounded-xl p-3 text-center border border-emerald-100">
                        <ListChecks size={18} className="mx-auto text-indigo-500 mb-1" />
                        <p className="text-lg font-black text-stone-800">{planResult.createdTaskCount}</p>
                        <p className="text-[10px] font-bold text-stone-400 uppercase">Tasks Created</p>
                      </div>
                      <div className="bg-white rounded-xl p-3 text-center border border-emerald-100">
                        <ShoppingCart size={18} className="mx-auto text-pink-500 mb-1" />
                        <p className="text-lg font-black text-stone-800">{planResult.createdListCount}</p>
                        <p className="text-[10px] font-bold text-stone-400 uppercase">Lists Created</p>
                      </div>
                    </div>
                  </div>
                  <div className="bg-stone-50 rounded-2xl p-5">
                    <h4 className="font-bold text-sm text-stone-700 mb-2">Event Overview</h4>
                    <p className="text-sm text-stone-600 leading-relaxed">{planResult.description}</p>
                  </div>
                  <div>
                    <h4 className="font-bold text-sm text-stone-700 mb-3 flex items-center gap-2">
                      <CheckSquare size={16} className="text-indigo-500" /> Tasks (in Tasks module)
                    </h4>
                    <div className="space-y-1 max-h-[200px] overflow-y-auto">
                      {planResult.tasks.map((t, i) => (
                        <div key={i} className="flex items-center gap-2 p-2 bg-stone-50 rounded-xl">
                          <span className={`text-[10px] font-black px-2 py-0.5 rounded-full ${
                            t.priority === 'HIGH' ? 'bg-red-100 text-red-600' : t.priority === 'MEDIUM' ? 'bg-amber-100 text-amber-600' : 'bg-blue-100 text-blue-600'
                          }`}>{t.priority}</span>
                          <span className="text-sm text-stone-700 flex-1">{t.title}</span>
                          <span className="text-[10px] text-stone-400">{t.daysBefore}d before</span>
                        </div>
                      ))}
                    </div>
                  </div>
                  <div>
                    <h4 className="font-bold text-sm text-stone-700 mb-3 flex items-center gap-2">
                      <ShoppingCart size={16} className="text-pink-500" /> Shopping Lists (in Lists module)
                    </h4>
                    <div className="space-y-2">
                      {planResult.lists.map((l, i) => (
                        <div key={i} className="bg-stone-50 rounded-xl p-3">
                          <p className="font-bold text-sm text-stone-700 mb-1">{l.title}</p>
                          <p className="text-xs text-stone-400">{l.items.length} items</p>
                        </div>
                      ))}
                    </div>
                  </div>
                  {planResult.tips && planResult.tips.length > 0 && (
                    <div className="bg-amber-50 rounded-2xl p-5 border border-amber-100">
                      <h4 className="font-bold text-sm text-amber-800 mb-2 flex items-center gap-2">
                        <Sparkles size={16} className="text-amber-500" /> Pro Tips
                      </h4>
                      <ul className="space-y-1">
                        {planResult.tips.map((tip, i) => (
                          <li key={i} className="text-sm text-amber-900 flex items-start gap-2">
                            <span className="text-amber-400 mt-0.5">-</span>{tip}
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
              )}
            </div>

            {wizardStep === 2 && (
              <div className="p-6 border-t border-stone-100 shrink-0">
                <button onClick={() => setIsWizardOpen(false)}
                  className="w-full py-3 bg-gradient-to-r from-violet-600 to-fuchsia-600 text-white rounded-xl font-bold shadow-lg shadow-fuchsia-100">
                  Done - View Calendar
                </button>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default Calendar;

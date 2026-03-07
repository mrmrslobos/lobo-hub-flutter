/**
 * ICS (iCalendar) parser for importing external calendar events.
 * Handles .ics files from Google Calendar, Apple Calendar, Outlook, etc.
 */

export interface ParsedEvent {
  uid: string;
  summary: string;
  description?: string;
  location?: string;
  dtstart: string; // ISO string
  dtend: string;   // ISO string
}

/**
 * Parse an ICS date string into an ISO date string.
 * Handles formats: 20260217T120000Z, 20260217T120000, 20260217
 */
function parseICSDate(raw: string, tzid?: string): string {
  // Use a permissive regex to strip any property prefix before the colon
  const cleaned = raw.replace(/^[^:]*:/, '').trim();

  // All-day event: YYYYMMDD
  if (/^\d{8}$/.test(cleaned)) {
    const y = cleaned.slice(0, 4);
    const m = cleaned.slice(4, 6);
    const d = cleaned.slice(6, 8);
    return `${y}-${m}-${d}T00:00:00`;
  }

  // Date with time: YYYYMMDDTHHMMSS or YYYYMMDDTHHMMSSZ
  const match = cleaned.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$/);
  if (match) {
    const [, y, mo, d, h, mi, s, z] = match;
    const iso = `${y}-${mo}-${d}T${h}:${mi}:${s}`;
    if (z) {
      // UTC time — convert to local via Date
      return new Date(iso + 'Z').toISOString();
    }
    if (tzid) {
      // Convert from the specified timezone to UTC
      try {
        const guessUtcMs = Date.UTC(+y, +mo - 1, +d, +h, +mi, +s);
        const guessUtc = new Date(guessUtcMs);
        const parts = new Intl.DateTimeFormat('en-US', {
          timeZone: tzid,
          year: 'numeric', month: '2-digit', day: '2-digit',
          hour: '2-digit', minute: '2-digit', second: '2-digit',
          hour12: false,
        }).formatToParts(guessUtc);
        const get = (type: string) => parts.find(p => p.type === type)?.value || '0';
        const hr = get('hour') === '24' ? '0' : get('hour');
        const shownMs = Date.UTC(+get('year'), +get('month') - 1, +get('day'), +hr, +get('minute'), +get('second'));
        const offsetMs = shownMs - guessUtcMs;
        return new Date(guessUtcMs - offsetMs).toISOString();
      } catch {
        return iso;
      }
    }
    return iso;
  }

  // Fallback: try native Date parsing
  const fallback = new Date(cleaned);
  return isNaN(fallback.getTime()) ? new Date().toISOString() : fallback.toISOString();
}

/**
 * Unfold ICS content lines (lines starting with a space/tab are continuations).
 */
function unfold(text: string): string {
  return text.replace(/\r\n[ \t]/g, '').replace(/\n[ \t]/g, '');
}

/**
 * Unescape ICS text values.
 */
function unescapeICS(text: string): string {
  // Process backslash-backslash first so that \\n becomes \n (literal) not a newline
  return text
    .replace(/\\\\/g, '\x00')
    .replace(/\\n/gi, '\n')
    .replace(/\\,/g, ',')
    .replace(/\\;/g, ';')
    .replace(/\x00/g, '\\');
}

/**
 * Parse ICS content string into an array of calendar events.
 */
export function parseICS(icsContent: string): ParsedEvent[] {
  const unfolded = unfold(icsContent);
  const lines = unfolded.split(/\r?\n/);
  const events: ParsedEvent[] = [];
  let inEvent = false;
  let current: Partial<ParsedEvent> = {};

  for (const line of lines) {
    if (line === 'BEGIN:VEVENT') {
      inEvent = true;
      current = {};
      continue;
    }

    if (line === 'END:VEVENT') {
      inEvent = false;
      if (current.summary && current.dtstart) {
        events.push({
          uid: current.uid || (typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2, 14)),
          summary: current.summary,
          description: current.description,
          location: current.location,
          dtstart: current.dtstart,
          dtend: current.dtend || current.dtstart,
        });
      }
      continue;
    }

    if (!inEvent) continue;

    // Extract property name and value (handle parameters like DTSTART;VALUE=DATE:20260217)
    const colonIdx = line.indexOf(':');
    if (colonIdx < 0) continue;

    const propPart = line.slice(0, colonIdx);
    const value = line.slice(colonIdx + 1).trim();
    const propName = propPart.split(';')[0].toUpperCase();

    switch (propName) {
      case 'UID':
        current.uid = value;
        break;
      case 'SUMMARY':
        current.summary = unescapeICS(value);
        break;
      case 'DESCRIPTION':
        current.description = unescapeICS(value);
        break;
      case 'LOCATION':
        current.location = unescapeICS(value);
        break;
      case 'DTSTART': {
        const tzidMatch = propPart.match(/TZID=([^;:]+)/i);
        current.dtstart = parseICSDate(value, tzidMatch?.[1]);
        break;
      }
      case 'DTEND': {
        const tzidMatch = propPart.match(/TZID=([^;:]+)/i);
        current.dtend = parseICSDate(value, tzidMatch?.[1]);
        break;
      }
    }
  }

  return events;
}

/**
 * Read an ICS file from a File input and parse it.
 */
export function parseICSFile(file: File): Promise<ParsedEvent[]> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const content = reader.result as string;
        resolve(parseICS(content));
      } catch (err) {
        reject(err);
      }
    };
    reader.onerror = () => reject(reader.error || new Error('Failed to read file'));
    reader.readAsText(file);
  });
}

/**
 * CORS proxy services to try when direct fetch is blocked.
 * Tried in order; first successful response wins.
 */
const CORS_PROXIES = [
  (url: string) => `https://corsproxy.io/?${encodeURIComponent(url)}`,
  (url: string) => `https://api.allorigins.win/raw?url=${encodeURIComponent(url)}`,
  (url: string) => `https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(url)}`,
];

/**
 * Fetch with a timeout via AbortController.
 */
async function fetchWithTimeout(url: string, timeoutMs = 10000): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { signal: controller.signal });
    return response;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Try fetching ICS content from a single URL; returns parsed events or null.
 */
async function tryFetchICS(fetchUrl: string): Promise<ParsedEvent[] | null> {
  try {
    const response = await fetchWithTimeout(fetchUrl);
    if (!response.ok) return null;
    const content = await response.text();
    if (!content.includes('BEGIN:VCALENDAR')) return null;
    const events = parseICS(content);
    return events.length > 0 ? events : null;
  } catch {
    return null;
  }
}

/**
 * Fetch and parse an ICS calendar from a URL.
 * Tries direct fetch first, then falls back through CORS proxies.
 */
export async function fetchAndParseICS(url: string): Promise<ParsedEvent[]> {
  // 1. Try direct fetch
  const direct = await tryFetchICS(url);
  if (direct) return direct;

  // 2. Try CORS proxies — use Promise.any for first successful result
  try {
    const result = await Promise.any(
      CORS_PROXIES.map(async makeProxyUrl => {
        const events = await tryFetchICS(makeProxyUrl(url));
        if (!events) throw new Error('proxy returned no events');
        return events;
      })
    );
    return result;
  } catch {
    // All proxies failed — fall through to error
  }

  throw new Error('CORS_BLOCKED');
}

/**
 * Detect calendar provider from URL.
 */
export function detectCalendarType(url: string): 'GOOGLE' | 'OUTLOOK' | 'APPLE' | 'OTHER' {
  const lower = url.toLowerCase();
  if (lower.includes('google.com') || lower.includes('googleapis.com')) return 'GOOGLE';
  if (lower.includes('outlook.') || lower.includes('office365.') || lower.includes('live.com')) return 'OUTLOOK';
  if (lower.includes('icloud.com') || lower.includes('apple.com')) return 'APPLE';
  return 'OTHER';
}

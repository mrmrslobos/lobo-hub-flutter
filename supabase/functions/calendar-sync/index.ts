/**
 * calendar-sync — Supabase Edge Function
 *
 * Fetches events from Google Calendar or Microsoft Outlook using an OAuth
 * access token obtained via Supabase Auth (provider_token).
 *
 * POST /functions/v1/calendar-sync
 * Body: {
 *   provider:    'google' | 'microsoft'
 *   accessToken: string          // session.provider_token from Supabase Auth
 *   calendarId:  string          // 'primary' for Google, 'me' for Microsoft
 *   familyId:    string
 *   timeMin?:    string          // ISO — defaults to 3 months ago
 *   timeMax?:    string          // ISO — defaults to 12 months ahead
 * }
 * Response: { events: NormalizedEvent[] } | { error: string }
 *
 * ── Setup instructions ────────────────────────────────────────────────────
 * Google:
 *   1. Enable "Google" provider in Supabase Auth → Providers
 *   2. Add OAuth Client ID + Secret from Google Cloud Console
 *   3. Enable the Google Calendar API in Google Cloud Console
 *   4. Add "https://www.googleapis.com/auth/calendar.readonly" to the
 *      OAuth consent screen scopes
 *   5. In AuthFlow.tsx, pass scopes: 'email profile openid https://www.googleapis.com/auth/calendar.readonly'
 *      when calling signInWithProvider('google')
 *
 * Microsoft:
 *   1. Enable "Azure" provider in Supabase Auth → Providers
 *   2. Register an app in Azure Portal → App registrations
 *   3. Add "Calendars.Read" Microsoft Graph permission
 *   4. In AuthFlow.tsx, pass scopes: 'email profile openid offline_access Calendars.Read'
 *      when calling signInWithProvider('azure')
 *
 * Apple Calendar:
 *   - Apple does not offer a public CalDAV OAuth API for third-party apps.
 *   - On iOS/Android use the Capacitor device calendar plugin to read local
 *     calendar events without OAuth.
 *   - On web, guide the user to export an ICS URL from iCloud settings.
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface NormalizedEvent {
  externalUid: string;
  title: string;
  description?: string;
  location?: string;
  start: string;    // ISO datetime
  end: string;      // ISO datetime
  allDay: boolean;
}

// ── Google Calendar ──────────────────────────────────────────────────────────

async function fetchGoogleEvents(
  accessToken: string,
  calendarId: string,
  timeMin: string,
  timeMax: string,
): Promise<NormalizedEvent[]> {
  const params = new URLSearchParams({
    timeMin,
    timeMax,
    singleEvents: 'true',
    orderBy: 'startTime',
    maxResults: '500',
  });

  const res = await fetch(
    `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events?${params}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Google Calendar API error ${res.status}: ${text}`);
  }

  const data = await res.json();
  return (data.items ?? []).map((item: any): NormalizedEvent => {
    const allDay = Boolean(item.start?.date);
    return {
      externalUid: item.id,
      title: item.summary ?? '(No title)',
      description: item.description,
      location: item.location,
      start: allDay ? `${item.start.date}T00:00:00` : item.start.dateTime,
      end: allDay ? `${item.end.date}T00:00:00` : item.end.dateTime,
      allDay,
    };
  });
}

// ── Microsoft Graph Calendar ─────────────────────────────────────────────────

async function fetchMicrosoftEvents(
  accessToken: string,
  _calendarId: string,
  timeMin: string,
  timeMax: string,
): Promise<NormalizedEvent[]> {
  // Microsoft Graph uses OData filters
  const filter = `start/dateTime ge '${timeMin}' and end/dateTime le '${timeMax}'`;
  const params = new URLSearchParams({
    $filter: filter,
    $top: '500',
    $select: 'id,subject,bodyPreview,location,start,end,isAllDay',
    $orderby: 'start/dateTime',
  });

  const res = await fetch(
    `https://graph.microsoft.com/v1.0/me/events?${params}`,
    { headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' } },
  );

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Microsoft Graph API error ${res.status}: ${text}`);
  }

  const data = await res.json();
  return (data.value ?? []).map((item: any): NormalizedEvent => ({
    externalUid: item.id,
    title: item.subject ?? '(No title)',
    description: item.bodyPreview,
    location: item.location?.displayName,
    start: item.start?.dateTime
      ? `${item.start.dateTime.replace(/(\.\d+)?$/, '')}Z`
      : `${item.start?.dateTime ?? ''}`,
    end: item.end?.dateTime
      ? `${item.end.dateTime.replace(/(\.\d+)?$/, '')}Z`
      : `${item.end?.dateTime ?? ''}`,
    allDay: item.isAllDay ?? false,
  }));
}

// ── Handler ──────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS });
  }

  try {
    const { provider, accessToken, calendarId, timeMin, timeMax } = await req.json();

    if (!provider || !accessToken || !calendarId) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: provider, accessToken, calendarId' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } },
      );
    }

    // Default time range: 3 months ago → 12 months ahead
    const defaultMin = new Date();
    defaultMin.setMonth(defaultMin.getMonth() - 3);
    const defaultMax = new Date();
    defaultMax.setMonth(defaultMax.getMonth() + 12);

    const resolvedMin = timeMin ?? defaultMin.toISOString();
    const resolvedMax = timeMax ?? defaultMax.toISOString();

    let events: NormalizedEvent[];

    if (provider === 'google') {
      events = await fetchGoogleEvents(accessToken, calendarId, resolvedMin, resolvedMax);
    } else if (provider === 'microsoft') {
      events = await fetchMicrosoftEvents(accessToken, calendarId, resolvedMin, resolvedMax);
    } else {
      return new Response(
        JSON.stringify({ error: `Unsupported provider: ${provider}. Use 'google' or 'microsoft'.` }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } },
      );
    }

    return new Response(
      JSON.stringify({ events, count: events.length }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: err.message ?? 'Internal server error' }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  }
});

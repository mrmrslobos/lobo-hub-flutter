/**
 * weekly-digest Edge Function
 *
 * Invoked by a Supabase Cron job every hour (0 * * * *).
 * On each invocation it selects families whose scheduled UTC day and hour
 * match the current UTC time, then for each of those families it:
 *   - Counts chore completions from the past 7 days and finds the top contributor
 *   - Counts FAMILY-visible events starting in the next 7 days
 *   - Counts incomplete FAMILY-visible tasks due in the next 7 days
 *   - Sends a single FCM push notification summarising those stats to every
 *     family member who has a registered device token
 *
 * Families with zero activity AND no upcoming events/tasks are silently skipped.
 *
 * Required Supabase secrets (set with `supabase secrets set`):
 *   FIREBASE_SERVICE_ACCOUNT  — JSON string of the Firebase service account key
 *   SUPABASE_SERVICE_ROLE_KEY — injected automatically by Supabase runtime
 *   SUPABASE_URL              — injected automatically by Supabase runtime
 *   WEEKLY_DIGEST_CRON_SECRET — optional; when set, pg_cron must send header
 *     `x-weekly-digest-secret` with the same value. Signed-in users may instead
 *     call with `{"test":true,"family_id":"<id>"}` (no cron header) to dry-run
 *     one family they belong to (bypasses UTC schedule for that family only).
 *
 * Scheduling — run the SQL in supabase/migrations/weekly_digest_cron.sql once
 * in your Supabase project's SQL editor to register the pg_cron job (hourly).
 * Families with no weeklyDigestDay/weeklyDigestHour set receive the digest on
 * Sunday at 08:00 UTC (the defaults).
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ---------------------------------------------------------------------------
// FCM access token cache
// Edge Function workers stay warm between invocations so module-level
// variables persist. Caching avoids a Google OAuth round-trip on every call.
// ---------------------------------------------------------------------------
let cachedAccessToken: string | null = null;
let tokenExpirationTime = 0; // ms since epoch

// ---------------------------------------------------------------------------
// CORS headers
// ---------------------------------------------------------------------------
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ---------------------------------------------------------------------------
// JWT signing helpers for FCM HTTP v1 (service account RS256)
// Identical to the helpers in notify-family/index.ts.
// ---------------------------------------------------------------------------

function base64url(bytes: Uint8Array): string {
  const b64 = btoa(String.fromCharCode(...bytes));
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function encodeJwtPart(obj: object): string {
  const json = JSON.stringify(obj);
  const bytes = new TextEncoder().encode(json);
  return base64url(bytes);
}

async function getFcmAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  if (cachedAccessToken && Date.now() < tokenExpirationTime) {
    return cachedAccessToken;
  }

  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + 3600;

  const header = encodeJwtPart({ alg: 'RS256', typ: 'JWT' });
  const payload = encodeJwtPart({
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat,
    exp,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  });

  const signingInput = `${header}.${payload}`;

  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '');
  const derBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    derBytes.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput)),
  );

  const jwt = `${signingInput}.${base64url(signature)}`;

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    throw new Error(`FCM token exchange failed: ${err}`);
  }

  const { access_token } = await tokenRes.json();
  cachedAccessToken = access_token as string;
  tokenExpirationTime = exp * 1000 - 5 * 60 * 1000; // 5-min safety buffer
  return cachedAccessToken;
}

// ---------------------------------------------------------------------------
// FCM send helper — returns true when token is permanently unregistered
// ---------------------------------------------------------------------------

interface FcmMessage {
  token: string;
  title: string;
  body: string;
  path: string;
}

async function sendFcmMessage(
  projectId: string,
  accessToken: string,
  msg: FcmMessage,
): Promise<boolean> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token: msg.token,
        notification: { title: msg.title, body: msg.body },
        data: { path: msg.path },
        apns: { payload: { aps: { badge: 1, sound: 'default' } } },
        android: { notification: { sound: 'default', channel_id: 'default' } },
      },
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    console.error('[weekly-digest] FCM send error for token', msg.token.slice(-8), ':', errText);
    if (res.status === 404 || errText.includes('UNREGISTERED')) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Digest body builder
// ---------------------------------------------------------------------------

interface DigestStats {
  totalChores: number;
  topContributorName: string | null;
  topContributorCount: number;
  upcomingEvents: number;
  dueTasks: number;
}

function buildDigestBody(stats: DigestStats): string {
  const parts: string[] = [];

  if (stats.totalChores > 0) {
    if (stats.topContributorName && stats.topContributorCount > 0) {
      const n = stats.topContributorCount;
      parts.push(`${stats.topContributorName} led with ${n} chore${n !== 1 ? 's' : ''} 🏆`);
    } else {
      const n = stats.totalChores;
      parts.push(`${n} chore${n !== 1 ? 's' : ''} completed this week`);
    }
  }

  if (stats.upcomingEvents > 0) {
    const n = stats.upcomingEvents;
    parts.push(`${n} event${n !== 1 ? 's' : ''} coming up 📅`);
  }

  if (stats.dueTasks > 0) {
    const n = stats.dueTasks;
    parts.push(`${n} task${n !== 1 ? 's' : ''} due this week 📋`);
  }

  return parts.length > 0 ? parts.join(' · ') : 'Hope the family had a great week! 🌟';
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS });
  }

  try {
    let parsedBody: Record<string, unknown> | null = null;
    try {
      const raw = await req.text();
      if (raw.trim()) parsedBody = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      parsedBody = null;
    }

    const testFromUrl = new URL(req.url).searchParams.get('test') === 'true';
    const isTestStyleInvoke = testFromUrl || parsedBody?.test === true;

    /** When set, caller used user JWT + test body (not cron secret); digest only for this family. */
    let authenticatedTestUserId: string | null = null;

    const cronSecret = Deno.env.get('WEEKLY_DIGEST_CRON_SECRET');
    if (cronSecret) {
      const suppliedSecret = req.headers.get('x-weekly-digest-secret') ?? '';
      if (suppliedSecret !== cronSecret) {
        if (!isTestStyleInvoke) {
          return new Response(JSON.stringify({ error: 'unauthorized' }), {
            status: 401,
            headers: { ...CORS, 'Content-Type': 'application/json' },
          });
        }
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
        const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
        const authHeader = req.headers.get('Authorization') ?? '';
        if (!anonKey || !authHeader.startsWith('Bearer ')) {
          return new Response(JSON.stringify({ error: 'unauthorized' }), {
            status: 401,
            headers: { ...CORS, 'Content-Type': 'application/json' },
          });
        }
        const userClient = createClient(supabaseUrl, anonKey, {
          global: { headers: { Authorization: authHeader } },
          auth: { persistSession: false },
        });
        const { data: userData, error: userErr } = await userClient.auth.getUser();
        if (userErr || !userData?.user) {
          return new Response(JSON.stringify({ error: 'unauthorized' }), {
            status: 401,
            headers: { ...CORS, 'Content-Type': 'application/json' },
          });
        }
        const fid = typeof parsedBody?.family_id === 'string' ? parsedBody.family_id : null;
        if (!fid) {
          return new Response(
            JSON.stringify({
              error: 'family_id required',
              detail: 'Test invokes without x-weekly-digest-secret must include family_id in the JSON body.',
            }),
            { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } },
          );
        }
        authenticatedTestUserId = userData.user.id;
      }
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false } },
    );

    if (authenticatedTestUserId) {
      const fid = parsedBody?.family_id as string;
      const { data: mem, error: memErr } = await supabase
        .from('family_members')
        .select('family_id')
        .eq('family_id', fid)
        .eq('user_id', authenticatedTestUserId)
        .maybeSingle();
      if (memErr || !mem) {
        return new Response(JSON.stringify({ error: 'forbidden', detail: 'Not a member of this family.' }), {
          status: 403,
          headers: { ...CORS, 'Content-Type': 'application/json' },
        });
      }
    }

    const serviceAccountRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    if (!serviceAccountRaw) throw new Error('FIREBASE_SERVICE_ACCOUNT secret not configured');
    const serviceAccount = JSON.parse(serviceAccountRaw) as Record<string, string>;
    const projectId = serviceAccount.project_id;
    const accessToken = await getFcmAccessToken(serviceAccount);

    // -----------------------------------------------------------------------
    // Determine which families should receive the digest right now.
    // The cron fires every hour; we compare each family's stored UTC day +
    // hour against the current UTC time.  Families that haven't set a
    // schedule default to Sunday (0) at 08:00 UTC.
    // Families with weeklyDigest === false are always excluded.
    // -----------------------------------------------------------------------
    const now = new Date();
    const currentUtcDay = now.getUTCDay();   // 0=Sun … 6=Sat
    const currentUtcHour = now.getUTCHours(); // 0–23

    const { data: allFamilies, error: familiesErr } = await supabase
      .from('families')
      .select('id, name, weekly_digest, weekly_digest_day, weekly_digest_hour');

    if (familiesErr) throw new Error(`families query failed: ${familiesErr.message}`);

    type FamilyRow = {
      id: string;
      name: string;
      weekly_digest: boolean | null;
      weekly_digest_day: number | null;
      weekly_digest_hour: number | null;
    };

    const manualTestFamilyId =
      authenticatedTestUserId && typeof parsedBody?.family_id === 'string'
        ? (parsedBody.family_id as string)
        : null;

    let families: FamilyRow[];
    if (manualTestFamilyId) {
      const fam = ((allFamilies ?? []) as FamilyRow[]).find((f) => f.id === manualTestFamilyId);
      if (!fam) {
        return new Response(JSON.stringify({ error: 'family not found', families: 0, sent: 0, pruned: 0 }), {
          status: 404,
          headers: { ...CORS, 'Content-Type': 'application/json' },
        });
      }
      if (fam.weekly_digest === false) {
        return new Response(
          JSON.stringify({ error: 'weekly digest disabled for this family', families: 0, sent: 0, pruned: 0 }),
          { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } },
        );
      }
      families = [fam];
    } else {
      families = ((allFamilies ?? []) as FamilyRow[]).filter((f) => {
        if (f.weekly_digest === false) return false;
        const schedDay = f.weekly_digest_day ?? 0; // default: Sunday
        const schedHour = f.weekly_digest_hour ?? 8; // default: 08:00 UTC
        return schedDay === currentUtcDay && schedHour === currentUtcHour;
      });
    }

    const maxFamilies = Number(Deno.env.get('WEEKLY_DIGEST_MAX_FAMILIES_PER_RUN') ?? '40');
    const famCap = Number.isFinite(maxFamilies) && maxFamilies > 0 ? Math.floor(maxFamilies) : 40;
    if (families.length > famCap) {
      console.warn(
        `[weekly-digest] ${families.length} families match this hour; processing first ${famCap}. Raise WEEKLY_DIGEST_MAX_FAMILIES_PER_RUN or stagger schedules.`,
      );
      families = families.slice(0, famCap);
    }

    // -----------------------------------------------------------------------
    // Date window strings (text comparisons work for ISO / YYYY-MM-DD fields)
    // -----------------------------------------------------------------------
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const sevenDaysAhead = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

    const todayStr = now.toISOString().slice(0, 10);               // YYYY-MM-DD
    const sevenDaysAgoStr = sevenDaysAgo.toISOString().slice(0, 10);
    const sevenDaysAheadStr = sevenDaysAhead.toISOString().slice(0, 10);
    const nowIso = now.toISOString();
    const sevenDaysAheadIso = sevenDaysAhead.toISOString();

    let totalSent = 0;
    let totalPruned = 0;
    let familiesNotified = 0;

    for (const family of families) {
      // ---------------------------------------------------------------------
      // 1. Chore completions in the past 7 days
      // ---------------------------------------------------------------------
      const { data: completions } = await supabase
        .from('chore_completions')
        .select('user_id')
        .eq('family_id', family.id)
        .gte('date', sevenDaysAgoStr);

      const userCounts: Record<string, number> = {};
      for (const cc of completions ?? []) {
        const uid = (cc as any).user_id as string;
        userCounts[uid] = (userCounts[uid] || 0) + 1;
      }

      const totalChores = (completions ?? []).length;
      let topContributorName: string | null = null;
      let topContributorCount = 0;

      if (totalChores > 0) {
        const topEntry = Object.entries(userCounts).sort(([, a], [, b]) => b - a)[0];
        if (topEntry) {
          topContributorCount = topEntry[1];
          const { data: topUser } = await supabase
            .from('users')
            .select('name')
            .eq('id', topEntry[0])
            .maybeSingle();
          topContributorName = (topUser as any)?.name ?? null;
        }
      }

      // ---------------------------------------------------------------------
      // 2. FAMILY-visible events starting in the next 7 days
      // ---------------------------------------------------------------------
      const { data: upcomingEventsRows } = await supabase
        .from('events')
        .select('id')
        .eq('family_id', family.id)
        .eq('visibility', 'FAMILY')
        .gte('start', nowIso)
        .lte('start', sevenDaysAheadIso);

      const upcomingEvents = (upcomingEventsRows ?? []).length;

      // ---------------------------------------------------------------------
      // 3. Incomplete FAMILY-visible tasks due this week
      // ---------------------------------------------------------------------
      const { data: dueTasksRows } = await supabase
        .from('tasks')
        .select('id')
        .eq('family_id', family.id)
        .eq('visibility', 'FAMILY')
        .eq('completed', false)
        .gte('due_date', todayStr)
        .lte('due_date', sevenDaysAheadStr);

      const dueTasks = (dueTasksRows ?? []).length;

      const stats: DigestStats = { totalChores, topContributorName, topContributorCount, upcomingEvents, dueTasks };
      const notifTitle = `📊 ${family.name} — Weekly Digest`;
      const notifBody =
        totalChores === 0 && upcomingEvents === 0 && dueTasks === 0
          ? 'Quiet week ahead — no tasks due or events in the next 7 days. Open the app to plan together.'
          : buildDigestBody(stats);

      // ---------------------------------------------------------------------
      // Fetch all device tokens for this family and send
      // ---------------------------------------------------------------------
      const { data: tokens } = await supabase
        .from('device_tokens')
        .select('token, user_id')
        .eq('family_id', family.id);

      if (!tokens || tokens.length === 0) continue;

      const tokenRows = tokens as Array<{ token: string; user_id: string }>;
      const results = await Promise.all(
        tokenRows.map((row) =>
          sendFcmMessage(projectId, accessToken, {
            token: row.token,
            title: notifTitle,
            body: notifBody,
            path: '/',
          })
        ),
      );

      // Prune stale/unregistered tokens
      const staleTokens = tokenRows.filter((_, i) => results[i]).map((r) => r.token);
      if (staleTokens.length > 0) {
        await supabase.from('device_tokens').delete().in('token', staleTokens);
        totalPruned += staleTokens.length;
      }

      totalSent += results.filter((unregistered) => !unregistered).length;
      familiesNotified++;
    }

    console.info(`[weekly-digest] Done. families=${familiesNotified} sent=${totalSent} pruned=${totalPruned}`);
    return new Response(
      JSON.stringify({ families: familiesNotified, sent: totalSent, pruned: totalPruned }),
      { headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('[weekly-digest] Unhandled error:', err);
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  }
});

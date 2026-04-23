/**
 * daily-devotional Edge Function
 *
 * Invoked by a Supabase Cron job every 15 minutes (0,15,30,45 * * * *).
 * For each family member whose daily devotional is enabled (see below) and
 * whose scheduled UTC hour+minute falls in the current 15-minute window:
 *   - Generates an adult-oriented AI devotional via the Gemini API
 *   - Inserts one row into `devotionals` with creator_id = that user
 *   - visibility PRIVATE if users.settings.daily_devotional_private_default,
 *     else FAMILY (legacy shared behavior)
 *   - Sends FCM + Web Push only to that user with their devotional id
 *
 * Per-user schedule (Flutter `User.settings` JSON), keys:
 *   daily_devotional_enabled (bool), daily_devotional_hour (0–23 UTC),
 *   daily_devotional_minute (0–59), daily_devotional_private_default (bool)
 * If `daily_devotional_enabled` is absent, falls back to families.daily_devotional_enabled.
 * If hour/minute absent, falls back to families.daily_devotional_*.
 *
 * Required Supabase secrets:
 *   GEMINI_API_KEY            — Gemini API key for AI generation
 *   FIREBASE_SERVICE_ACCOUNT  — JSON string of the Firebase service account key
 *   VAPID_PUBLIC_KEY          — base64url P-256 uncompressed public key (65 bytes)
 *   VAPID_PRIVATE_KEY         — base64url P-256 raw private scalar (32 bytes)
 *   SUPABASE_SERVICE_ROLE_KEY — injected automatically by Supabase runtime
 *   SUPABASE_URL              — injected automatically by Supabase runtime
 *
 * Scheduling — run supabase/migrations/daily_devotional_cron.sql once in
 * your Supabase project's SQL editor to register the pg_cron job.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ---------------------------------------------------------------------------
// CORS headers
// ---------------------------------------------------------------------------
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ---------------------------------------------------------------------------
// FCM access token cache (persists across warm invocations)
// ---------------------------------------------------------------------------
let cachedAccessToken: string | null = null;
let tokenExpirationTime = 0;

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
  tokenExpirationTime = exp * 1000 - 5 * 60 * 1000;
  return cachedAccessToken;
}

// ---------------------------------------------------------------------------
// FCM send helper
// ---------------------------------------------------------------------------

interface FcmMessage {
  token: string;
  title: string;
  body: string;
  path: string;
  devotionalId: string;
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
        data: {
          path: msg.path,
          devotionalId: msg.devotionalId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        apns: { payload: { aps: { badge: 1, sound: 'default' } } },
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channel_id: 'default',
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
      },
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    console.error('[daily-devotional] FCM send error for token', msg.token.slice(-8), ':', errText);
    if (res.status === 404 || errText.includes('UNREGISTERED')) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Web Push helpers (RFC 8291 aes128gcm content encryption)
// ---------------------------------------------------------------------------

function concatBytes(...arrays: Uint8Array[]): Uint8Array {
  const total = arrays.reduce((n, a) => n + a.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const a of arrays) { out.set(a, offset); offset += a.length; }
  return out;
}

function bytesToBase64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64urlToBytes(str: string): Uint8Array {
  const padding = '='.repeat((4 - (str.length % 4)) % 4);
  const b64 = (str + padding).replace(/-/g, '+').replace(/_/g, '/');
  return new Uint8Array([...atob(b64)].map(c => c.charCodeAt(0)));
}

async function hkdfExtract(salt: Uint8Array, ikm: Uint8Array): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', salt, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, ikm));
}

async function hkdfExpand(prk: Uint8Array, info: Uint8Array, length: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', prk, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const blocks: Uint8Array[] = [];
  let prev = new Uint8Array(0);
  for (let i = 1; blocks.reduce((n, b) => n + b.length, 0) < length; i++) {
    prev = new Uint8Array(await crypto.subtle.sign('HMAC', key, concatBytes(prev, info, new Uint8Array([i]))));
    blocks.push(prev);
  }
  return concatBytes(...blocks).slice(0, length);
}

async function encryptWebPushPayload(
  recipientP256dhB64: string,
  authSecretB64: string,
  plaintext: string,
): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const recipientPublicKeyRaw = base64urlToBytes(recipientP256dhB64);
  const authSecret = base64urlToBytes(authSecretB64);

  const senderKeyPair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const senderPublicKeyRaw = new Uint8Array(await crypto.subtle.exportKey('raw', senderKeyPair.publicKey));

  const recipientPublicKey = await crypto.subtle.importKey('raw', recipientPublicKeyRaw, { name: 'ECDH', namedCurve: 'P-256' }, false, []);

  const sharedSecret = new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'ECDH', public: recipientPublicKey }, senderKeyPair.privateKey, 256)
  );

  const salt = crypto.getRandomValues(new Uint8Array(16));

  const prkKey = await hkdfExtract(authSecret, sharedSecret);
  const info = concatBytes(enc.encode('WebPush: info\x00'), recipientPublicKeyRaw, senderPublicKeyRaw);
  const ikm = await hkdfExpand(prkKey, info, 32);

  const prk = await hkdfExtract(salt, ikm);
  const cek = await hkdfExpand(prk, enc.encode('Content-Encoding: aes128gcm\x00'), 16);
  const nonce = await hkdfExpand(prk, enc.encode('Content-Encoding: nonce\x00'), 12);

  const aesKey = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  const paddedPlaintext = concatBytes(enc.encode(plaintext), new Uint8Array([2]));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aesKey, paddedPlaintext)
  );

  const rs = new Uint8Array(4);
  new DataView(rs.buffer).setUint32(0, 4096, false);
  return concatBytes(salt, rs, new Uint8Array([senderPublicKeyRaw.length]), senderPublicKeyRaw, ciphertext);
}

async function createVapidJwt(
  endpoint: string,
  vapidPrivateKeyB64: string,
  vapidPublicKeyB64: string,
): Promise<string> {
  const audience = new URL(endpoint).origin;
  const exp = Math.floor(Date.now() / 1000) + 43200;

  const enc = new TextEncoder();
  const headerB64 = bytesToBase64url(enc.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const payloadB64 = bytesToBase64url(enc.encode(JSON.stringify({ aud: audience, exp, sub: 'mailto:push@huddleapp.com.au' })));
  const signingInput = `${headerB64}.${payloadB64}`;

  const pubBytes = base64urlToBytes(vapidPublicKeyB64);
  const jwk = {
    kty: 'EC', crv: 'P-256',
    d: vapidPrivateKeyB64,
    x: bytesToBase64url(pubBytes.slice(1, 33)),
    y: bytesToBase64url(pubBytes.slice(33, 65)),
  };
  const cryptoKey = await crypto.subtle.importKey('jwk', jwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, cryptoKey, enc.encode(signingInput)));

  return `${signingInput}.${bytesToBase64url(sig)}`;
}

async function sendWebPushNotification(
  subscription: { endpoint: string; p256dh: string; auth: string },
  payload: { title: string; body: string; path: string; tag: string },
  vapidPrivateKey: string,
  vapidPublicKey: string,
): Promise<boolean> {
  try {
    const encryptedBody = await encryptWebPushPayload(
      subscription.p256dh, subscription.auth, JSON.stringify(payload)
    );
    const jwt = await createVapidJwt(subscription.endpoint, vapidPrivateKey, vapidPublicKey);

    const res = await fetch(subscription.endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Encoding': 'aes128gcm',
        'Authorization': `vapid t=${jwt},k=${vapidPublicKey}`,
        'TTL': '86400',
      },
      body: encryptedBody,
    });

    if (res.status === 410 || res.status === 404) return true;
    if (!res.ok) console.warn('[daily-devotional] WebPush failed:', res.status, await res.text());
    return false;
  } catch (err) {
    console.warn('[daily-devotional] WebPush send error:', err);
    return false;
  }
}

// ---------------------------------------------------------------------------
// Gemini AI call (same logic as ai-proxy)
// ---------------------------------------------------------------------------

/** Stable 32-bit hash for rotating prompts by family + calendar day. */
function simpleHash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = Math.imul(31, h) + s.charCodeAt(i) | 0;
  return h === 0 ? 1 : h;
}

/**
 * Pull a scripture reference from the stored `scripture` field (verse text + "— Ref"
 * or common dash variants). Returns null if we cannot infer one.
 */
function extractScriptureRefFromStored(scripture: string | null | undefined): string | null {
  if (!scripture || typeof scripture !== 'string') return null;
  const lines = scripture
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0);
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i];
    const dashRef = line.match(/^[\u2014\u2013\-]\s*(.+)$/);
    if (dashRef) return dashRef[1].trim();
    if (line.length > 0 && line.length <= 120 && /\d+\s*:\s*\d+/.test(line) && /[A-Za-z\u00C0-\u024F]/.test(line)) {
      return line;
    }
  }
  const em = scripture.lastIndexOf('\u2014');
  if (em >= 0) return scripture.slice(em + 1).trim();
  const en = scripture.lastIndexOf('\u2013');
  if (en >= 0) return scripture.slice(en + 1).trim();
  return null;
}

const SCRIPTURE_BUCKETS = [
  'Old Testament narrative or Torah (not used in your avoid-list)',
  'Wisdom literature — Job, Psalms, Proverbs, or Ecclesiastes',
  'Major or minor prophets',
  'The Gospels — life or teaching of Jesus',
  'Acts and the early church',
  'Pauline epistles (Romans through Philemon)',
  'Hebrews, general epistles, or Revelation',
] as const;

interface GenerateDevotionalOptions {
  familyId: string;
  userId?: string;
  recentRefs: string[];
  recentTitles: string[];
}

async function generateDevotional(
  apiKey: string,
  opts: GenerateDevotionalOptions,
): Promise<{ title: string; scripture: string; scriptureRef: string; content: string; reflectionPrompts: string[]; prayer: string } | null> {
  const today = new Date();
  const dateStr = today.toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
  const todayKey = today.toISOString().slice(0, 10);
  const entropy = new Uint32Array(2);
  crypto.getRandomValues(entropy);
  const nonce = crypto.randomUUID();
  const varietyKey = `${opts.familyId}:${opts.userId ?? 'shared'}:${todayKey}`;
  const bucket = SCRIPTURE_BUCKETS[Math.abs(simpleHash(varietyKey)) % SCRIPTURE_BUCKETS.length];

  const avoidParts: string[] = [];
  if (opts.recentRefs.length > 0) {
    avoidParts.push(
      `Do NOT use these recently featured passages or the same primary chapter (choose a different book or chapter): ${opts.recentRefs.join('; ')}.`,
    );
  }
  if (opts.recentTitles.length > 0) {
    avoidParts.push(
      `Do NOT reuse or lightly rephrase these recent devotional titles: ${opts.recentTitles.join('; ')}.`,
    );
  }
  const avoidClause = avoidParts.length > 0 ? `\n${avoidParts.join('\n')}` : '';

  const prompt = `Write an adult-oriented daily devotional for ${dateStr}.
Audience: mature adults navigating real life—work stress, relationships, parenting fatigue, grief, temptation, doubt, health, money worries, and ordinary discouragement. Speak with honesty and compassion; do not talk down, use childish language, or rely on simplistic moral tales.

Today's Scripture focus (still pick exactly ONE tight verse or passage within this region): ${bucket}.
Avoid overused "default" choices (e.g. John 3:16, Psalm 23, Philippians 4:6-7, Jeremiah 29:11) unless they truly fit and are not excluded below.${avoidClause}

Requirements:
- Be direct where it helps: name common adult struggles without being graphic or sensational.
- Anchor hope in God's character and in specific promises from Scripture (quote or paraphrase faithfully).
- Close the main message on an uplifting, faith-filled note—realistic, not trite.
- Aim for roughly 250–400 words in "content" when possible.
- Vary tone, metaphors, and structure from one day to the next; do not repeat boilerplate openings.

Return JSON with these exact fields: title, scripture, scriptureRef, content, reflectionPrompts (array of 3 personal reflection or journaling prompts for an adult), prayer.
For "scripture", write out the FULL verse text (e.g. "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.").
For "scriptureRef", provide only the reference (e.g. "John 3:16").
For "prayer", write a sincere, adult-voiced prayer that names real tension and rests on God's promises.

Internal uniqueness (do not echo in output): nonce=${nonce} entropy=${entropy[0]}-${entropy[1]}`;

  const MODEL_CANDIDATES = ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-1.5-flash'];
  let lastError: unknown;

  for (const model of MODEL_CANDIDATES) {
    const body: Record<string, unknown> = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: 'application/json',
        temperature: 1.14,
        topP: 0.92,
      },
    };

    // Gemini 2.5+ models return "thinking" parts by default which breaks
    // JSON extraction from parts[0]. Disable thinking to get clean output.
    // thinkingConfig is a top-level field, NOT inside generationConfig.
    const geminiBody: Record<string, unknown> = { ...body };
    if (model.includes('2.5')) {
      geminiBody.thinkingConfig = { thinkingBudget: 0 };
    }

    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(geminiBody) },
    );

    if (res.ok) {
      const data = await res.json();
      // Find the first text part that isn't a "thinking" part — Gemini 2.5+
      // models may prepend thought parts before the actual response.
      const parts = data?.candidates?.[0]?.content?.parts ?? [];
      const textPart = parts.filter((p: Record<string, unknown>) => 'text' in p && !p.thought);
      const text = textPart.length > 0 ? (textPart[textPart.length - 1].text as string) : '';
      try {
        return JSON.parse(text);
      } catch {
        console.warn('[daily-devotional] Failed to parse Gemini JSON, raw:', text.slice(0, 200));
        // Don't return null — try next model
        continue;
      }
    }

    const errText = await res.text();
    lastError = new Error(`Gemini ${model} failed: ${errText}`);
    console.warn('[daily-devotional]', lastError);
  }

  console.error('[daily-devotional] All Gemini model attempts failed');
  return null;
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS });
  }

  try {
    const cronSecret = Deno.env.get('DAILY_DEVOTIONAL_CRON_SECRET');
    if (cronSecret) {
      const suppliedSecret = req.headers.get('x-daily-devotional-secret') ?? '';
      if (suppliedSecret !== cronSecret) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: { ...CORS, 'Content-Type': 'application/json' },
        });
      }
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false } },
    );

    const apiKey = Deno.env.get('GEMINI_API_KEY');
    if (!apiKey) throw new Error('GEMINI_API_KEY secret not configured');

    // -----------------------------------------------------------------------
    // Determine which families should receive their daily devotional now.
    // The cron fires every 15 minutes. Family stores dailyDevotionalHour (0-23)
    // and dailyDevotionalMinute (0-59) in UTC. We match families whose
    // scheduled hour matches AND whose minute falls in the current 15-min window.
    //
    // Pass ?test=true or { "test": true } to bypass the time-window check
    // and generate for all enabled families (useful for debugging).
    // Pass { "family_id": "..." } to target a single family.
    // -----------------------------------------------------------------------
    const now = new Date();
    const currentUtcHour = now.getUTCHours();
    const currentUtcMinute = now.getUTCMinutes();
    // Round down to the 15-minute window start
    const windowStart = currentUtcMinute - (currentUtcMinute % 15);
    const windowEnd = windowStart + 14;

    // Check for test/debug mode
    let testMode = new URL(req.url).searchParams.get('test') === 'true';
    let targetFamilyId: string | null = null;
    try {
      const body = await req.clone().json();
      if (body?.test) testMode = true;
      if (body?.family_id) targetFamilyId = body.family_id;
    } catch { /* empty body is fine */ }

    if (testMode) {
      console.info(`[daily-devotional] TEST MODE — bypassing time window (current UTC: ${currentUtcHour}:${String(currentUtcMinute).padStart(2, '0')})`);
    }

    const USER_DAILY_ENABLED = 'daily_devotional_enabled';
    const USER_DAILY_HOUR = 'daily_devotional_hour';
    const USER_DAILY_MINUTE = 'daily_devotional_minute';
    const USER_DAILY_PRIVATE = 'daily_devotional_private_default';

    type FamilyRow = {
      id: string;
      name: string;
      daily_devotional_enabled: boolean | null;
      daily_devotional_hour: number | null;
      daily_devotional_minute: number | null;
    };

    type MemberRow = { family_id: string; user_id: string; families: FamilyRow | FamilyRow[] | null };

    const { data: memberRows, error: membersErr } = await supabase
      .from('family_members')
      .select('family_id, user_id, families ( id, name, daily_devotional_enabled, daily_devotional_hour, daily_devotional_minute )');

    if (membersErr) throw new Error(`family_members query failed: ${membersErr.message}`);

    const userIds = [...new Set((memberRows ?? []).map((r: MemberRow) => r.user_id).filter(Boolean))];
    const { data: userRows } = userIds.length > 0
      ? await supabase.from('users').select('id, settings').in('id', userIds)
      : { data: [] as Array<{ id: string; settings: unknown }> };

    const settingsByUser = new Map<string, Record<string, unknown>>();
    for (const u of userRows ?? []) {
      const s = u.settings;
      settingsByUser.set(
        u.id,
        s && typeof s === 'object' && !Array.isArray(s) ? (s as Record<string, unknown>) : {},
      );
    }

    type Candidate = {
      familyId: string;
      familyName: string;
      userId: string;
      schedHour: number;
      schedMinute: number;
      privateDefault: boolean;
    };

    const candidates: Candidate[] = [];

    for (const row of (memberRows ?? []) as MemberRow[]) {
      const famRel = row.families;
      const fam = Array.isArray(famRel) ? famRel[0] : famRel;
      if (!fam) continue;
      if (targetFamilyId && fam.id !== targetFamilyId) continue;

      const st = settingsByUser.get(row.user_id) ?? {};

      const userExplicitEnabled = st[USER_DAILY_ENABLED];
      const enabled =
        typeof userExplicitEnabled === 'boolean'
          ? userExplicitEnabled
          : !!fam.daily_devotional_enabled;
      if (!enabled) continue;

      const hasUserTime =
        typeof st[USER_DAILY_HOUR] === 'number' && typeof st[USER_DAILY_MINUTE] === 'number';
      const schedHour = hasUserTime
        ? (st[USER_DAILY_HOUR] as number)
        : (fam.daily_devotional_hour ?? 7);
      const schedMinute = hasUserTime
        ? (st[USER_DAILY_MINUTE] as number)
        : (fam.daily_devotional_minute ?? 0);

      if (!testMode) {
        const matches =
          schedHour === currentUtcHour && schedMinute >= windowStart && schedMinute <= windowEnd;
        if (!matches) continue;
      }

      const privateDefault = st[USER_DAILY_PRIVATE] === true;

      candidates.push({
        familyId: fam.id,
        familyName: fam.name,
        userId: row.user_id,
        schedHour,
        schedMinute,
        privateDefault,
      });
    }

    console.info(
      `[daily-devotional] Members considered: ${candidates.length} (from ${(memberRows ?? []).length} memberships). UTC: ${currentUtcHour}:${String(currentUtcMinute).padStart(2, '0')}, window: ${windowStart}-${windowEnd}, testMode=${testMode}`,
    );

    if (candidates.length === 0) {
      return new Response(
        JSON.stringify({ families: 0, generated: 0, sent: 0 }),
        { headers: { ...CORS, 'Content-Type': 'application/json' } },
      );
    }

    // Cap work per cron tick so the function stays under CPU/time limits when
    // many families share the same UTC window.
    const maxPerRun = Number(Deno.env.get('DAILY_DEVOTIONAL_MAX_PER_RUN') ?? '10');
    const cap = Number.isFinite(maxPerRun) && maxPerRun > 0 ? Math.floor(maxPerRun) : 10;
    let runCandidates = candidates;
    let truncated = 0;
    if (candidates.length > cap) {
      truncated = candidates.length - cap;
      runCandidates = candidates.slice(0, cap);
      console.warn(
        `[daily-devotional] Truncating ${truncated} candidate(s); max per run=${cap}. Raise DAILY_DEVOTIONAL_MAX_PER_RUN or narrow the cron window if needed.`,
      );
    }

    // -----------------------------------------------------------------------
    // Check for today's date to avoid duplicate generation
    // -----------------------------------------------------------------------
    const todayStr = now.toISOString().slice(0, 10); // YYYY-MM-DD

    // Load FCM + VAPID credentials
    const serviceAccountRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    const serviceAccount = serviceAccountRaw ? JSON.parse(serviceAccountRaw) as Record<string, string> : null;
    const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY');
    const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY');

    let totalGenerated = 0;
    let totalSent = 0;
    let totalPruned = 0;

    const uniqueFamilyIds = [...new Set(runCandidates.map((c) => c.familyId))];

    for (const cand of runCandidates) {
      const { data: existingRows } = await supabase
        .from('devotionals')
        .select('id, tags, creator_id')
        .eq('family_id', cand.familyId)
        .eq('creator_id', cand.userId)
        .gte('date', `${todayStr}T00:00:00.000Z`)
        .lte('date', `${todayStr}T23:59:59.999Z`);

      const hasAutoToday = (existingRows ?? []).some((row: { tags?: unknown }) => {
        const t = row.tags;
        if (!Array.isArray(t)) return false;
        const tags = t as string[];
        return tags.includes('daily-auto') || tags.includes('daily-auto-dismissed');
      });
      if (hasAutoToday) {
        console.info(
          `[daily-devotional] User ${cand.userId} in ${cand.familyName} already has today's auto devotional, skipping.`,
        );
        continue;
      }

      const recentRefs: string[] = [];
      const recentTitles: string[] = [];
      try {
        const { data: recentRows } = await supabase
          .from('devotionals')
          .select('scripture, title')
          .eq('family_id', cand.familyId)
          .eq('creator_id', cand.userId)
          .order('date', { ascending: false })
          .limit(40);
        const seenRefs = new Set<string>();
        const seenTitles = new Set<string>();
        for (const row of (recentRows ?? [])) {
          const ref = extractScriptureRefFromStored(row.scripture as string | null);
          if (ref && !seenRefs.has(ref) && seenRefs.size < 16) {
            seenRefs.add(ref);
            recentRefs.push(ref);
          }
          const t = (row.title as string | null)?.trim();
          if (t && t.length > 0 && t !== 'Daily Devotional' && !seenTitles.has(t) && seenTitles.size < 10) {
            seenTitles.add(t);
            recentTitles.push(t);
          }
        }
      } catch { /* non-critical */ }

      const devotional = await generateDevotional(apiKey, {
        familyId: cand.familyId,
        userId: cand.userId,
        recentRefs,
        recentTitles,
      });
      if (!devotional) {
        console.error(`[daily-devotional] Failed to generate for user ${cand.userId} family ${cand.familyName}`);
        continue;
      }

      const scriptureText = devotional.scripture || null;
      const scriptureRef = devotional.scriptureRef || null;
      const scripture = scriptureText && scriptureRef
        ? `${scriptureText}\n\u2014 ${scriptureRef}`
        : scriptureText ?? scriptureRef;

      const entryId = crypto.randomUUID();
      const visibility = cand.privateDefault ? 'PRIVATE' : 'FAMILY';
      const { error: insertErr } = await supabase
        .from('devotionals')
        .insert({
          id: entryId,
          family_id: cand.familyId,
          creator_id: cand.userId,
          title: devotional.title || 'Daily Devotional',
          scripture: scripture ?? '',
          content: devotional.content ?? '',
          reflection_prompts: devotional.reflectionPrompts || [],
          prayer: devotional.prayer || null,
          tags: ['daily-auto'],
          date: now.toISOString(),
          visibility,
        });

      if (insertErr) {
        console.error(
          `[daily-devotional] Insert failed for user ${cand.userId} family ${cand.familyName}:`,
          insertErr.message,
        );
        continue;
      }

      totalGenerated++;

      const notifTitle = 'Daily devotional';
      const notifBody = cand.privateDefault
        ? `"${devotional.title}" is ready for you.`
        : `"${devotional.title}" — your family's devotional for today.`;
      const notifPath = `/devotional?id=${entryId}`;

      if (serviceAccount) {
        const projectId = serviceAccount.project_id;
        const accessToken = await getFcmAccessToken(serviceAccount);

        const { data: tokens } = await supabase
          .from('device_tokens')
          .select('token, user_id')
          .eq('family_id', cand.familyId)
          .eq('user_id', cand.userId);

        if (tokens && tokens.length > 0) {
          const tokenRows = tokens as Array<{ token: string; user_id: string }>;
          const results = await Promise.all(
            tokenRows.map((row) =>
              sendFcmMessage(projectId, accessToken, {
                token: row.token,
                title: notifTitle,
                body: notifBody,
                path: notifPath,
                devotionalId: entryId,
              })
            ),
          );

          const staleTokens = tokenRows.filter((_, i) => results[i]).map((r) => r.token);
          if (staleTokens.length > 0) {
            await supabase.from('device_tokens').delete().in('token', staleTokens);
            totalPruned += staleTokens.length;
          }
          totalSent += results.filter((s) => !s).length;
        }
      }

      if (vapidPublicKey && vapidPrivateKey) {
        const { data: webSubs } = await supabase
          .from('web_push_subscriptions')
          .select('endpoint, p256dh, auth, user_id')
          .eq('family_id', cand.familyId)
          .eq('user_id', cand.userId);

        if (webSubs && webSubs.length > 0) {
          const subRows = webSubs as Array<{ endpoint: string; p256dh: string; auth: string }>;
          const tag = 'lobohub-devotional';
          const results = await Promise.all(
            subRows.map((sub) =>
              sendWebPushNotification(sub, {
                title: notifTitle,
                body: notifBody,
                path: notifPath,
                tag,
              }, vapidPrivateKey, vapidPublicKey)
            ),
          );
          const staleEndpoints = subRows.filter((_, i) => results[i]).map((r) => r.endpoint);
          if (staleEndpoints.length > 0) {
            await supabase.from('web_push_subscriptions').delete().in('endpoint', staleEndpoints);
            totalPruned += staleEndpoints.length;
          }
          totalSent += results.filter((s) => !s).length;
        }
      }
    }

    console.info(`[daily-devotional] Done. generated=${totalGenerated} sent=${totalSent} pruned=${totalPruned}`);
    return new Response(
      JSON.stringify({
        families: uniqueFamilyIds.length,
        members: runCandidates.length,
        candidatesTotal: candidates.length,
        truncated,
        generated: totalGenerated,
        sent: totalSent,
        pruned: totalPruned,
      }),
      { headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('[daily-devotional] Unhandled error:', err);
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  }
});

/**
 * daily-devotional Edge Function
 *
 * Invoked by a Supabase Cron job every 15 minutes (0,15,30,45 * * * *).
 * On each invocation it selects families whose daily devotional is enabled
 * and whose scheduled local time (stored as UTC hour + minute) matches the
 * current 15-minute window. For each matching family it:
 *   - Generates an adult-oriented AI devotional via the Gemini API
 *   - Inserts the devotional into the devotional_entries table
 *   - Sends FCM + Web Push notifications to every family member
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
  const payloadB64 = bytesToBase64url(enc.encode(JSON.stringify({ aud: audience, exp, sub: 'mailto:push@familyhub.app' })));
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

async function generateDevotional(apiKey: string, recentRefs: string[] = []): Promise<{ title: string; scripture: string; scriptureRef: string; content: string; reflectionPrompts: string[]; prayer: string } | null> {
  const today = new Date();
  const dateStr = today.toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
  const seed = Math.floor(Math.random() * 100000);
  const avoidClause = recentRefs.length > 0
    ? `\nIMPORTANT: Do NOT use any of these recently-used verses: ${recentRefs.join(', ')}. Pick a completely different passage.`
    : '';

  const prompt = `Write an adult-oriented daily devotional for ${dateStr}. (seed: ${seed})
Audience: mature adults navigating real life—work stress, relationships, parenting fatigue, grief, temptation, doubt, health, money worries, and ordinary discouragement. Speak with honesty and compassion; do not talk down, use childish language, or rely on simplistic moral tales.

Pick one Bible verse or short passage and build a focused devotional around it.${avoidClause}

Requirements:
- Be direct where it helps: name common adult struggles without being graphic or sensational.
- Anchor hope in God's character and in specific promises from Scripture (quote or paraphrase faithfully).
- Close the main message on an uplifting, faith-filled note—realistic, not trite.
- Aim for roughly 250–400 words in "content" when possible.

Return JSON with these exact fields: title, scripture, scriptureRef, content, reflectionPrompts (array of 3 personal reflection or journaling prompts for an adult), prayer.
For "scripture", write out the FULL verse text (e.g. "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.").
For "scriptureRef", provide only the reference (e.g. "John 3:16").
For "prayer", write a sincere, adult-voiced prayer that names real tension and rests on God's promises.`;

  const MODEL_CANDIDATES = ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-1.5-flash'];
  let lastError: unknown;

  for (const model of MODEL_CANDIDATES) {
    const body: Record<string, unknown> = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: 'application/json',
        temperature: 1.0,
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

    const { data: allFamilies, error: familiesErr } = await supabase
      .from('families')
      .select('id, name, daily_devotional_enabled, daily_devotional_hour, daily_devotional_minute');

    if (familiesErr) throw new Error(`families query failed: ${familiesErr.message}`);

    type FamilyRow = {
      id: string;
      name: string;
      daily_devotional_enabled: boolean | null;
      daily_devotional_hour: number | null;
      daily_devotional_minute: number | null;
    };

    console.info(`[daily-devotional] Found ${(allFamilies ?? []).length} total families. Current UTC: ${currentUtcHour}:${String(currentUtcMinute).padStart(2, '0')}, window: ${windowStart}-${windowEnd}`);

    const families = ((allFamilies ?? []) as FamilyRow[]).filter((f) => {
      if (targetFamilyId && f.id !== targetFamilyId) return false;
      if (!f.daily_devotional_enabled) {
        if (testMode || targetFamilyId === f.id) {
          console.info(`[daily-devotional] Family "${f.name}" has daily_devotional_enabled=${f.daily_devotional_enabled} — skipping`);
        }
        return false;
      }
      if (testMode) return true; // bypass time check in test mode
      const schedHour = f.daily_devotional_hour ?? 7;
      const schedMinute = f.daily_devotional_minute ?? 0;
      const matches = schedHour === currentUtcHour && schedMinute >= windowStart && schedMinute <= windowEnd;
      if (!matches) {
        console.info(`[daily-devotional] Family "${f.name}" scheduled at ${schedHour}:${String(schedMinute).padStart(2, '0')} UTC — not in current window`);
      }
      return matches;
    });

    if (families.length === 0) {
      return new Response(
        JSON.stringify({ families: 0, generated: 0, sent: 0 }),
        { headers: { ...CORS, 'Content-Type': 'application/json' } },
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

    for (const family of families) {
      const { data: existingRows } = await supabase
        .from('devotionals')
        .select('id, tags')
        .eq('family_id', family.id)
        .gte('date', `${todayStr}T00:00:00.000Z`)
        .lte('date', `${todayStr}T23:59:59.999Z`);

      const hasAutoToday = (existingRows ?? []).some((row: { tags?: unknown }) => {
        const t = row.tags;
        if (!Array.isArray(t)) return false;
        const tags = t as string[];
        return tags.includes('daily-auto') || tags.includes('daily-auto-dismissed');
      });
      if (hasAutoToday) {
        console.info(`[daily-devotional] Family ${family.name} already has today's auto devotional (or dismissed), skipping.`);
        continue;
      }

      // Fetch recent scripture references to avoid repetition
      const recentRefs: string[] = [];
      try {
        const { data: recentRows } = await supabase
          .from('devotionals')
          .select('scripture')
          .eq('family_id', family.id)
          .order('date', { ascending: false })
          .limit(14);
        for (const row of (recentRows ?? [])) {
          const s = row.scripture as string | null;
          if (!s) continue;
          const refMatch = s.match(/—\s*(.+)$/m);
          if (refMatch) recentRefs.push(refMatch[1].trim());
        }
      } catch { /* non-critical */ }

      // Generate the devotional via Gemini
      const devotional = await generateDevotional(apiKey, recentRefs);
      if (!devotional) {
        console.error(`[daily-devotional] Failed to generate for family ${family.name}`);
        continue;
      }

      // Combine full verse text with reference
      const scriptureText = devotional.scripture || null;
      const scriptureRef = devotional.scriptureRef || null;
      const scripture = scriptureText && scriptureRef
        ? `${scriptureText}\n\u2014 ${scriptureRef}`
        : scriptureText ?? scriptureRef;

      // Insert into devotionals table
      const entryId = crypto.randomUUID();
      const { error: insertErr } = await supabase
        .from('devotionals')
        .insert({
          id: entryId,
          family_id: family.id,
          creator_id: '00000000-0000-0000-0000-000000000000', // system-generated
          title: devotional.title || 'Daily Devotional',
          scripture: scripture,
          content: devotional.content || null,
          reflection_prompts: devotional.reflectionPrompts || [],
          prayer: devotional.prayer || null,
          tags: ['daily-auto'],
          date: now.toISOString(),
          visibility: 'FAMILY',
        });

      if (insertErr) {
        console.error(`[daily-devotional] Insert failed for family ${family.name}:`, insertErr.message);
        continue;
      }

      totalGenerated++;

      const notifTitle = 'Daily Devotional Ready \u2728';
      const notifBody = `"${devotional.title}" \u2014 Your family\u2019s devotional for today is here. Open to read and reflect together.`;
      const notifPath = `/devotional?id=${entryId}`;

      // -------------------------------------------------------------------
      // Channel 1: FCM (native iOS/Android)
      // -------------------------------------------------------------------
      if (serviceAccount) {
        const projectId = serviceAccount.project_id;
        const accessToken = await getFcmAccessToken(serviceAccount);

        const { data: tokens } = await supabase
          .from('device_tokens')
          .select('token, user_id')
          .eq('family_id', family.id);

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

      // -------------------------------------------------------------------
      // Channel 2: Web Push / VAPID (PWA browsers)
      // -------------------------------------------------------------------
      if (vapidPublicKey && vapidPrivateKey) {
        const { data: webSubs } = await supabase
          .from('web_push_subscriptions')
          .select('endpoint, p256dh, auth, user_id')
          .eq('family_id', family.id);

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
      JSON.stringify({ families: families.length, generated: totalGenerated, sent: totalSent, pruned: totalPruned }),
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

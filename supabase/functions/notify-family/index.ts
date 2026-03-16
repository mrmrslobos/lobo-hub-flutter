/**
 * notify-family Edge Function
 *
 * Called by Supabase Database Webhooks when rows are inserted/updated in key
 * tables (tasks, events, chores, chore_completions, lists, polls).
 *
 * Delivers notifications via TWO channels:
 *   1. FCM (native iOS/Android) — requires FIREBASE_SERVICE_ACCOUNT secret
 *   2. Web Push / VAPID (PWA browsers) — requires VAPID_PUBLIC_KEY + VAPID_PRIVATE_KEY secrets
 *
 * Required Supabase secrets (set with `supabase secrets set`):
 *   FIREBASE_SERVICE_ACCOUNT  — JSON string of the Firebase service account key
 *   VAPID_PUBLIC_KEY          — base64url P-256 uncompressed public key (65 bytes)
 *   VAPID_PRIVATE_KEY         — base64url P-256 raw private scalar (32 bytes)
 *   SUPABASE_SERVICE_ROLE_KEY — injected automatically by Supabase runtime
 *   SUPABASE_URL              — injected automatically by Supabase runtime
 *
 * Generate VAPID keys: npx web-push generate-vapid-keys
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ---------------------------------------------------------------------------
// FCM access token cache
// Edge Function workers stay warm between invocations, so module-level
// variables persist. Caching the token avoids a Google OAuth round-trip
// (~200-500 ms) on every notification and prevents hitting rate limits.
// ---------------------------------------------------------------------------
let cachedAccessToken: string | null = null;
let tokenExpirationTime = 0; // ms since epoch

// ---------------------------------------------------------------------------
// Parse a JSON secret that may have been double-quoted by Supabase's secret
// store.  e.g. the env var may arrive as:
//   '"{\"type\":\"service_account\",...}"'   (string-wrapped JSON)
// or with literal escaped quotes.  This helper peels away one layer of quoting
// if present and then parses the result.
// ---------------------------------------------------------------------------
function parseJsonSecret(raw: string): Record<string, string> {
  let cleaned = raw.trim();
  // Peel away layers of quoting — Supabase may double- or triple-encode
  while (cleaned.startsWith('"') && cleaned.endsWith('"')) {
    cleaned = JSON.parse(cleaned) as string;
    if (typeof cleaned !== 'string') break;
  }
  return typeof cleaned === 'string' ? JSON.parse(cleaned) : cleaned as unknown as Record<string, string>;
}

// ---------------------------------------------------------------------------
// CORS headers
// ---------------------------------------------------------------------------
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ---------------------------------------------------------------------------
// JWT signing helpers for FCM HTTP v1 (service account RS256)
// ---------------------------------------------------------------------------

/** Base64URL-encode a Uint8Array. */
function base64url(bytes: Uint8Array): string {
  const b64 = btoa(String.fromCharCode(...bytes));
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** Encode a plain object as a base64url JSON segment. */
function encodeJwtPart(obj: object): string {
  const json = JSON.stringify(obj);
  const bytes = new TextEncoder().encode(json);
  return base64url(bytes);
}

/**
 * Create a short-lived OAuth2 access token for the FCM HTTP v1 API by signing
 * a JWT with the Firebase service account private key (RS256).
 *
 * @param serviceAccount  Parsed Firebase service account JSON object.
 */
async function getFcmAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  // Return the cached token if it is still valid (with a 5-minute safety buffer).
  if (cachedAccessToken && Date.now() < tokenExpirationTime) {
    return cachedAccessToken;
  }

  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + 3600; // 1-hour token

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

  // Import the RSA private key from PEM
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
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      cryptoKey,
      new TextEncoder().encode(signingInput),
    ),
  );

  const jwt = `${signingInput}.${base64url(signature)}`;

  // Exchange the signed JWT for an access token
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

  // Cache for the token's lifetime minus a 5-minute buffer so we never
  // present a near-expiry token to FCM.
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
}

/**
 * Returns true if the token is confirmed unregistered (app uninstalled /
 * token rotated) so the caller can prune it from device_tokens.
 */
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
        notification: {
          title: msg.title,
          body: msg.body,
        },
        data: {
          path: msg.path,
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: 'default',
            },
          },
        },
        android: {
          notification: {
            sound: 'default',
            // No click_action — Capacitor registers no Flutter intent filter.
            // Omitting it lets Android use the default launcher intent so the
            // app opens correctly when the notification is tapped.
            channel_id: 'default',
          },
        },
      },
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    // Log but don't throw — a single bad token shouldn't block other sends
    console.error('[notify-family] FCM send error for token', msg.token.slice(-8), ':', errText);
    // 404 UNREGISTERED means the token is permanently invalid (app uninstalled
    // or token rotated). Signal to the caller to delete it from device_tokens.
    if (res.status === 404 || errText.includes('UNREGISTERED')) {
      return true; // unregistered
    }
  }
  return false; // ok (or a transient error — keep the token)
}

// ---------------------------------------------------------------------------
// Web Push (VAPID + RFC 8291 aes128gcm content encryption)
// Implemented with crypto.subtle — no external dependencies needed.
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

/** HKDF-Extract: PRK = HMAC-SHA256(salt, IKM) */
async function hkdfExtract(salt: Uint8Array, ikm: Uint8Array): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', salt, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, ikm));
}

/** HKDF-Expand: output = T(1) || T(2) || ... truncated to `length` bytes */
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

/**
 * Encrypt a web push payload using RFC 8291 (aes128gcm content encoding).
 * Returns the encrypted body ready to POST to the push service endpoint.
 */
async function encryptWebPushPayload(
  recipientP256dhB64: string,
  authSecretB64: string,
  plaintext: string,
): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const recipientPublicKeyRaw = base64urlToBytes(recipientP256dhB64);
  const authSecret = base64urlToBytes(authSecretB64);

  // Generate ephemeral ECDH key pair
  const senderKeyPair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const senderPublicKeyRaw = new Uint8Array(await crypto.subtle.exportKey('raw', senderKeyPair.publicKey));

  // Import recipient public key
  const recipientPublicKey = await crypto.subtle.importKey('raw', recipientPublicKeyRaw, { name: 'ECDH', namedCurve: 'P-256' }, false, []);

  // ECDH shared secret
  const sharedSecret = new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'ECDH', public: recipientPublicKey }, senderKeyPair.privateKey, 256)
  );

  const salt = crypto.getRandomValues(new Uint8Array(16));

  // RFC 8291 §3.3: PRK → IKM
  const prkKey = await hkdfExtract(authSecret, sharedSecret);
  const info = concatBytes(enc.encode('WebPush: info\x00'), recipientPublicKeyRaw, senderPublicKeyRaw);
  const ikm = await hkdfExpand(prkKey, info, 32);

  // RFC 8188: derive CEK and nonce from salt + IKM
  const prk = await hkdfExtract(salt, ikm);
  const cek = await hkdfExpand(prk, enc.encode('Content-Encoding: aes128gcm\x00'), 16);
  const nonce = await hkdfExpand(prk, enc.encode('Content-Encoding: nonce\x00'), 12);

  const aesKey = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  const paddedPlaintext = concatBytes(enc.encode(plaintext), new Uint8Array([2])); // RFC 8291 padding
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aesKey, paddedPlaintext)
  );

  // RFC 8188 binary header: salt(16) || record_size(4, big-endian) || keyid_len(1) || keyid(65)
  const rs = new Uint8Array(4);
  new DataView(rs.buffer).setUint32(0, 4096, false);
  return concatBytes(salt, rs, new Uint8Array([senderPublicKeyRaw.length]), senderPublicKeyRaw, ciphertext);
}

/**
 * Create a VAPID JWT (ES256) for authenticating the web push request.
 * vapidPrivateKeyB64: raw 32-byte P-256 scalar in base64url
 * vapidPublicKeyB64:  raw 65-byte P-256 uncompressed point in base64url
 */
async function createVapidJwt(
  endpoint: string,
  vapidPrivateKeyB64: string,
  vapidPublicKeyB64: string,
): Promise<string> {
  const audience = new URL(endpoint).origin;
  const exp = Math.floor(Date.now() / 1000) + 43200; // 12 hours

  const enc = new TextEncoder();
  const headerB64 = bytesToBase64url(enc.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const payloadB64 = bytesToBase64url(enc.encode(JSON.stringify({ aud: audience, exp, sub: 'mailto:push@familyhub.app' })));
  const signingInput = `${headerB64}.${payloadB64}`;

  // Reconstruct JWK from raw keys (crypto.subtle cannot import raw EC private key directly)
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

/**
 * Send a web push notification to a single browser subscription.
 * Returns true if the endpoint is stale (410/404) and should be deleted.
 */
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

    if (res.status === 410 || res.status === 404) return true; // stale
    if (!res.ok) console.warn('[WebPush] Push failed:', res.status, await res.text());
    return false;
  } catch (err) {
    console.warn('[WebPush] Send error:', err);
    return false;
  }
}

// ---------------------------------------------------------------------------
// Webhook payload → notification content mapping
// ---------------------------------------------------------------------------

interface WebhookPayload {
  type: 'INSERT' | 'UPDATE' | 'DELETE';
  table: string;
  record: Record<string, unknown>;
  old_record?: Record<string, unknown>;
  schema: string;
}

interface NotificationContent {
  familyId: string;
  actorId: string;         // userId who triggered the change (excluded from recipients)
  title: string;
  body: string;
  path: string;            // hash-router path, e.g. /tasks
  /** When set, only these users receive the notification (still excludes actorId). */
  targetUserIds?: string[];
}

async function buildNotification(
  payload: WebhookPayload,
  supabaseClient: ReturnType<typeof createClient>,
): Promise<NotificationContent | null> {
  const { table, type, record } = payload;

  // Resolve actor name from users table
  const getActorName = async (userId: string): Promise<string> => {
    const { data } = await supabaseClient
      .from('users')
      .select('name')
      .eq('id', userId)
      .maybeSingle();
    return (data as any)?.name ?? 'Someone';
  };

  if (table === 'tasks' && type === 'INSERT') {
    const actorId = record.creatorId as string;
    const actorName = await getActorName(actorId);
    const assignees = Array.isArray(record.assignees) ? (record.assignees as string[]) : [];
    // If the task is assigned to specific people (other than just the creator), notify only them.
    const nonCreatorAssignees = assignees.filter((id: string) => id !== actorId);
    if (nonCreatorAssignees.length > 0) {
      return {
        familyId: record.familyId as string,
        actorId,
        title: '📋 Task assigned to you',
        body: `${actorName} assigned you: ${record.title}`,
        path: '/tasks',
        targetUserIds: nonCreatorAssignees,
      };
    }
    return {
      familyId: record.familyId as string,
      actorId,
      title: 'New task added',
      body: `${actorName} added: ${record.title}`,
      path: '/tasks',
    };
  }

  if (table === 'tasks' && type === 'UPDATE') {
    // Handle task completion
    if (record.completed === true && payload.old_record?.completed !== true) {
      const actorId = (record.completedBy ?? record.updatedBy ?? record.creatorId) as string;
      const actorName = await getActorName(actorId);
      return {
        familyId: record.familyId as string,
        actorId,
        title: 'Task completed ✅',
        body: `${actorName} completed: ${record.title}`,
        path: '/tasks',
      };
    }

    // Handle new assignees being added
    const oldAssignees = Array.isArray(payload.old_record?.assignees) ? (payload.old_record.assignees as string[]) : [];
    const newAssignees = Array.isArray(record.assignees) ? (record.assignees as string[]) : [];
    const addedAssignees = newAssignees.filter((id: string) => !oldAssignees.includes(id));
    if (addedAssignees.length > 0) {
      const actorId = (record.updatedBy ?? record.creatorId) as string;
      const actorName = await getActorName(actorId);
      const nonActorNewAssignees = addedAssignees.filter((id: string) => id !== actorId);
      if (nonActorNewAssignees.length > 0) {
        return {
          familyId: record.familyId as string,
          actorId,
          title: '📋 Task assigned to you',
          body: `${actorName} assigned you: ${record.title}`,
          path: '/tasks',
          targetUserIds: nonActorNewAssignees,
        };
      }
    }

    return null;
  }

  if (table === 'events' && type === 'INSERT') {
    const actorId = record.creatorId as string;
    const actorName = await getActorName(actorId);
    return {
      familyId: record.familyId as string,
      actorId,
      title: 'New event added 📅',
      body: `${actorName} added: ${record.title}`,
      path: '/calendar',
    };
  }

  if (table === 'chores' && type === 'INSERT') {
    const actorId = record.creatorId as string;
    const actorName = await getActorName(actorId);
    return {
      familyId: record.familyId as string,
      actorId,
      title: 'New chore assigned 🧹',
      body: `${actorName} added: ${record.title}`,
      path: '/chores',
    };
  }

  if (table === 'chore_completions' && type === 'INSERT') {
    const actorId = record.userId as string;
    const actorName = await getActorName(actorId);

    // Get chore title for the body
    const { data: chore } = await supabaseClient
      .from('chores')
      .select('title, familyId')
      .eq('id', record.choreId)
      .maybeSingle();

    return {
      familyId: (chore as any)?.familyId ?? (record.familyId as string),
      actorId,
      title: 'Chore done! 🎉',
      body: `${actorName} completed: ${(chore as any)?.title ?? 'a chore'}`,
      path: '/chores',
    };
  }

  // List INSERT and UPDATE notifications are handled by the Flutter app via
  // NotificationService.notifyFamilyActivity with proper excludeUserId.
  // Webhook-based list notifications were removed because:
  //  1. The app already sends them with proper actor exclusion.
  //  2. The webhook had no way to identify the actor (used nil UUID),
  //     causing the actor to receive their own notifications.
  //  3. Both firing caused duplicate notifications for other family members.
  if (table === 'lists') return null;

  if (table === 'polls' && type === 'INSERT') {
    const actorId = record.creatorId as string;
    const actorName = await getActorName(actorId);
    return {
      familyId: record.familyId as string,
      actorId,
      title: 'New poll 🗳️',
      body: `${actorName} started: ${record.question}`,
      path: '/polls',
    };
  }

  // Unrecognised event — skip
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
    const body = await req.json();

    // Service-role Supabase client for reading device_tokens + users
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false } },
    );

    // ── Device token registration ───────────────────────────────────────
    if (body.action === 'register' && body.token && body.familyId && body.userId) {
      const platform = body.platform || 'android';
      const { error } = await supabaseClient
        .from('device_tokens')
        .upsert(
          {
            userId: body.userId,
            familyId: body.familyId,
            token: body.token,
            platform,
            updatedAt: new Date().toISOString(),
          },
          { onConflict: 'userId,platform' },
        );
      if (error) {
        console.error('[notify-family] Token registration failed:', error.message);
        return new Response(JSON.stringify({ registered: false, error: error.message }), {
          status: 400,
          headers: { ...CORS, 'Content-Type': 'application/json' },
        });
      }
      return new Response(JSON.stringify({ registered: true }), {
        headers: { ...CORS, 'Content-Type': 'application/json' },
      });
    }

    // ── Direct notification from the app ──────────────────────────────
    if (body.action === 'notify' && body.familyId && body.title && body.body) {
      const notification: NotificationContent = {
        familyId: body.familyId,
        actorId: body.excludeUserId ?? '',
        title: body.title,
        body: body.body,
        path: body.path ?? '/',
      };

      let fcmSent = 0;
      let fcmPruned = 0;
      const serviceAccountRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
      if (serviceAccountRaw) {
        const serviceAccount = parseJsonSecret(serviceAccountRaw);
        const projectId = serviceAccount.project_id;
        const accessToken = await getFcmAccessToken(serviceAccount);

        const tokenQuery = supabaseClient
          .from('device_tokens')
          .select('token, userId')
          .eq('familyId', notification.familyId)
          .neq('userId', notification.actorId);
        const { data: tokens } = await tokenQuery;

        if (tokens && tokens.length > 0) {
          const tokenRows = tokens as Array<{ token: string; userId: string }>;
          const results = await Promise.all(
            tokenRows.map((row) =>
              sendFcmMessage(projectId, accessToken, {
                token: row.token,
                title: notification.title,
                body: notification.body,
                path: notification.path,
              })
            ),
          );
          const staleTokens = tokenRows.filter((_, i) => results[i]).map((r) => r.token);
          if (staleTokens.length > 0) {
            await supabaseClient.from('device_tokens').delete().in('token', staleTokens);
          }
          fcmSent = results.filter((s) => !s).length;
          fcmPruned = staleTokens.length;
        }
      }

      let webPushSent = 0;
      let webPushPruned = 0;
      const vpubKey = Deno.env.get('VAPID_PUBLIC_KEY');
      const vprivKey = Deno.env.get('VAPID_PRIVATE_KEY');
      if (vpubKey && vprivKey) {
        const webSubQuery = supabaseClient
          .from('web_push_subscriptions')
          .select('endpoint, p256dh, auth, userId')
          .eq('familyId', notification.familyId)
          .neq('userId', notification.actorId);
        const { data: webSubs } = await webSubQuery;

        if (webSubs && webSubs.length > 0) {
          const subRows = webSubs as Array<{ endpoint: string; p256dh: string; auth: string }>;
          const tag = `lobohub-${notification.path.replace('/', '') || 'general'}`;
          const results = await Promise.all(
            subRows.map((sub) =>
              sendWebPushNotification(sub, {
                title: notification.title,
                body: notification.body,
                path: notification.path,
                tag,
              }, vprivKey, vpubKey)
            ),
          );
          const staleEndpoints = subRows.filter((_, i) => results[i]).map((r) => r.endpoint);
          if (staleEndpoints.length > 0) {
            await supabaseClient.from('web_push_subscriptions').delete().in('endpoint', staleEndpoints);
          }
          webPushSent = results.filter((s) => !s).length;
          webPushPruned = staleEndpoints.length;
        }
      }

      return new Response(
        JSON.stringify({ fcmSent, fcmPruned, webPushSent, webPushPruned }),
        { headers: { ...CORS, 'Content-Type': 'application/json' } },
      );
    }

    // ── Webhook notification flow ───────────────────────────────────────
    const payload: WebhookPayload = body;

    // Build notification content from webhook payload
    const notification = await buildNotification(payload, supabaseClient);
    if (!notification) {
      return new Response(JSON.stringify({ skipped: true }), {
        headers: { ...CORS, 'Content-Type': 'application/json' },
      });
    }

    // ---------------------------------------------------------------------------
    // Channel 1: FCM (native iOS/Android)
    // ---------------------------------------------------------------------------
    let fcmSent = 0;
    let fcmPruned = 0;

    const serviceAccountRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    if (serviceAccountRaw) {
      const serviceAccount = parseJsonSecret(serviceAccountRaw);
      const projectId = serviceAccount.project_id;
      const accessToken = await getFcmAccessToken(serviceAccount);

      let tokenQuery = supabaseClient
        .from('device_tokens')
        .select('token, userId')
        .eq('familyId', notification.familyId)
        .neq('userId', notification.actorId);
      if (notification.targetUserIds && notification.targetUserIds.length > 0) {
        tokenQuery = tokenQuery.in('userId', notification.targetUserIds);
      }
      const { data: tokens } = await tokenQuery;

      if (tokens && tokens.length > 0) {
        const tokenRows = tokens as Array<{ token: string; userId: string }>;
        const results = await Promise.all(
          tokenRows.map((row) =>
            sendFcmMessage(projectId, accessToken, {
              token: row.token,
              title: notification.title,
              body: notification.body,
              path: notification.path,
            })
          ),
        );
        const staleTokens = tokenRows.filter((_, i) => results[i]).map((r) => r.token);
        if (staleTokens.length > 0) {
          await supabaseClient.from('device_tokens').delete().in('token', staleTokens);
        }
        fcmSent = results.filter((s) => !s).length;
        fcmPruned = staleTokens.length;
      }
    } else {
      console.info('[notify-family] FIREBASE_SERVICE_ACCOUNT not set — skipping FCM.');
    }

    // ---------------------------------------------------------------------------
    // Channel 2: Web Push / VAPID (PWA browsers)
    // ---------------------------------------------------------------------------
    let webPushSent = 0;
    let webPushPruned = 0;

    const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY');
    const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY');

    if (vapidPublicKey && vapidPrivateKey) {
      let webSubQuery = supabaseClient
        .from('web_push_subscriptions')
        .select('endpoint, p256dh, auth, userId')
        .eq('familyId', notification.familyId)
        .neq('userId', notification.actorId);
      if (notification.targetUserIds && notification.targetUserIds.length > 0) {
        webSubQuery = webSubQuery.in('userId', notification.targetUserIds);
      }
      const { data: webSubs } = await webSubQuery;

      if (webSubs && webSubs.length > 0) {
        const subRows = webSubs as Array<{ endpoint: string; p256dh: string; auth: string }>;
        const tag = `lobohub-${notification.path.replace('/', '') || 'general'}`;
        const results = await Promise.all(
          subRows.map((sub) =>
            sendWebPushNotification(sub, {
              title: notification.title,
              body: notification.body,
              path: notification.path,
              tag,
            }, vapidPrivateKey, vapidPublicKey)
          ),
        );
        const staleEndpoints = subRows.filter((_, i) => results[i]).map((r) => r.endpoint);
        if (staleEndpoints.length > 0) {
          await supabaseClient.from('web_push_subscriptions').delete().in('endpoint', staleEndpoints);
        }
        webPushSent = results.filter((s) => !s).length;
        webPushPruned = staleEndpoints.length;
      }
    } else {
      console.info('[notify-family] VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY not set — skipping web push.');
    }

    const totalSent = fcmSent + webPushSent;
    if (totalSent === 0 && fcmPruned === 0 && webPushPruned === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: 'no subscriptions' }), {
        headers: { ...CORS, 'Content-Type': 'application/json' },
      });
    }

    return new Response(
      JSON.stringify({ fcmSent, fcmPruned, webPushSent, webPushPruned }),
      { headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('[notify-family] Unhandled error:', err);
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } },
    );
  }
});

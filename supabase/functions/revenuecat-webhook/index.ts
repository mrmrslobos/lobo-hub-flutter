/**
 * revenuecat-webhook — Supabase Edge Function
 *
 * Receives RevenueCat webhook POSTs and syncs `families.subscription_tier`
 * for families owned by the purchasing Supabase user.
 *
 * POST /functions/v1/revenuecat-webhook
 *
 * Required secrets (`supabase secrets set`):
 *   REVENUECAT_WEBHOOK_AUTHORIZATION — exact Authorization header value configured
 *                                      in RevenueCat → Integrations → Webhooks
 *   SUPABASE_SERVICE_ROLE_KEY          — injected automatically
 *   SUPABASE_URL                       — injected automatically
 *
 * RevenueCat dashboard:
 *   URL: https://<project-ref>.supabase.co/functions/v1/revenuecat-webhook
 *   Authorization: same string as REVENUECAT_WEBHOOK_AUTHORIZATION
 *   Events: INITIAL_PURCHASE, RENEWAL, PRODUCT_CHANGE, UNCANCELLATION,
 *           EXPIRATION, CANCELLATION (ignored for tier; access until expiry)
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

type RcEvent = {
  id?: string;
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  entitlement_ids?: string[];
  environment?: string;
};

type RcWebhookBody = {
  api_version?: string;
  event?: RcEvent;
};

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function tierFromEntitlementIds(ids: string[] | undefined): string {
  const set = new Set((ids ?? []).map((id) => id.toLowerCase()));
  if (set.has('ai_family') || set.has('ai_family_annual')) return 'ai_family';
  if (set.has('ai')) return 'ai';
  if (set.has('base')) return 'base';
  return 'trial';
}

function resolveSupabaseUserIds(event: RcEvent): string[] {
  const raw = [
    event.app_user_id,
    event.original_app_user_id,
    ...(event.aliases ?? []),
  ].filter((v): v is string => typeof v === 'string' && v.length > 0);

  const uuids = raw.filter((id) => UUID_RE.test(id));
  return [...new Set(uuids)];
}

async function familyIdsForUser(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<string[]> {
  const { data: owned, error: ownedErr } = await supabase
    .from('families')
    .select('id')
    .eq('owner_id', userId);
  if (ownedErr) throw ownedErr;
  if (owned && owned.length > 0) {
    return owned.map((r) => r.id as string);
  }

  const { data: member, error: memberErr } = await supabase
    .from('family_members')
    .select('family_id')
    .eq('user_id', userId);
  if (memberErr) throw memberErr;
  return (member ?? []).map((r) => r.family_id as string);
}

function authorize(req: Request): boolean {
  const expected = Deno.env.get('REVENUECAT_WEBHOOK_AUTHORIZATION')?.trim();
  if (!expected) {
    console.error('[revenuecat-webhook] REVENUECAT_WEBHOOK_AUTHORIZATION not set');
    return false;
  }
  const auth = req.headers.get('authorization')?.trim() ?? '';
  return auth === expected || auth === `Bearer ${expected}`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  if (!authorize(req)) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  let body: RcWebhookBody;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'invalid json' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const event = body.event;
  if (!event?.type) {
    return new Response(JSON.stringify({ error: 'missing event' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const eventType = event.type.toUpperCase();
  const grantTypes = new Set([
    'INITIAL_PURCHASE',
    'RENEWAL',
    'PRODUCT_CHANGE',
    'UNCANCELLATION',
    'TEMPORARY_ENTITLEMENT_GRANT',
  ]);
  const revokeTypes = new Set(['EXPIRATION']);

  if (!grantTypes.has(eventType) && !revokeTypes.has(eventType)) {
    // CANCELLATION: user opted out but keeps access until expiration_at_ms.
    return new Response(JSON.stringify({ ok: true, skipped: eventType }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const tier = revokeTypes.has(eventType)
    ? 'trial'
    : tierFromEntitlementIds(event.entitlement_ids);

  const userIds = resolveSupabaseUserIds(event);
  if (userIds.length === 0) {
    console.warn(
      `[revenuecat-webhook] no Supabase user id in event ${event.id ?? eventType} ` +
        `(app_user_id=${event.app_user_id})`,
    );
    return new Response(JSON.stringify({ ok: true, updated: 0, reason: 'anonymous_user' }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceKey) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const familyIds = new Set<string>();
  for (const userId of userIds) {
    const ids = await familyIdsForUser(supabase, userId);
    ids.forEach((id) => familyIds.add(id));
  }

  let updated = 0;
  for (const familyId of familyIds) {
    const { error } = await supabase.rpc('sync_family_subscription_tier_system', {
      p_family_id: familyId,
      p_tier: tier,
    });
    if (error) {
      console.error(
        `[revenuecat-webhook] sync failed family=${familyId} tier=${tier}: ${error.message}`,
      );
      continue;
    }
    updated += 1;
  }

  console.log(
    `[revenuecat-webhook] ${eventType} event=${event.id ?? '?'} tier=${tier} updated=${updated}`,
  );

  return new Response(
    JSON.stringify({
      ok: true,
      event_type: eventType,
      tier,
      families_updated: updated,
    }),
    {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    },
  );
});

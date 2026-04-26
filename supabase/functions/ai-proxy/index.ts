/**
 * ai-proxy — Supabase Edge Function
 *
 * Centralises the Gemini API key so it never ships to the browser.
 * Also enforces subscription tier before allowing AI calls.
 *
 * POST /functions/v1/ai-proxy
 * Body: {
 *   familyId: string
 *   feature:  string        // must match a key in FEATURE_TIER_MAP
 *   prompt:   string
 *   responseMimeType?: 'application/json'
 *   responseSchema?: object
 * }
 *
 * Required Supabase secrets (set via `supabase secrets set`):
 *   GEMINI_API_KEY
 *   SUPABASE_ANON_KEY         — validates JWT + family_members / families under RLS
 *   SUPABASE_URL
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Which tier each feature requires
const FEATURE_TIER_MAP: Record<string, 'core' | 'ai'> = {
  budget:       'core',
  rewards:      'core',
  meals_manual: 'core',
  fitness_manual: 'core',
  ai_recipes:   'ai',
  ai_fitness:   'ai',
  ai_lists:     'ai',
  ai_devotional:'ai',
  ai_budget:    'ai',
  ai_tasks:     'ai',
  ai_events:    'ai',
  ai_motivation:'ai',
  ai_copilot:   'ai',
  ai_events_vision: 'ai',
};

const TIER_RANK: Record<string, number> = { free: 0, core: 1, ai: 2 };

const TRIAL_MS = 14 * 24 * 60 * 60 * 1000;

/** Reject absurdly large prompts to protect Gemini quota and function wall time. */
const MAX_PROMPT_CHARS = 180_000;
/** Max base64 image payload (~6 MB raw) */
const MAX_IMAGE_BASE64_CHARS = 8_000_000;

const COPILOT_ACTION_TYPES = new Set([
  'create_task',
  'create_event',
  'create_shopping_list',
  'add_list_items',
  'create_meal_plan_entry',
  'create_chore',
]);

interface CopilotAction {
  type: string;
  payload: Record<string, unknown>;
}

/** Strip to JSON-safe copilot response; drops unknown action types and oversized arrays. */
function sanitizeCopilotJson(raw: string): string {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw.trim());
  } catch {
    return JSON.stringify({
      reply: 'I could not produce a valid plan. Please try rephrasing your request.',
      actions: [],
    });
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return JSON.stringify({ reply: '', actions: [] });
  }
  const o = parsed as Record<string, unknown>;
  const reply = typeof o.reply === 'string' ? o.reply.slice(0, 8000) : '';
  const rawActions = Array.isArray(o.actions) ? o.actions : [];
  const actions: CopilotAction[] = [];
  for (const a of rawActions.slice(0, 20)) {
    if (!a || typeof a !== 'object' || Array.isArray(a)) continue;
    const rec = a as Record<string, unknown>;
    const type = typeof rec.type === 'string' ? rec.type : '';
    if (!COPILOT_ACTION_TYPES.has(type)) continue;
    const payload = rec.payload && typeof rec.payload === 'object' && !Array.isArray(rec.payload)
      ? rec.payload as Record<string, unknown>
      : {};
    actions.push({ type, payload });
  }
  return JSON.stringify({ reply, actions });
}

/** Matches Flutter [Family.hasAIAccess] / [Family.effectiveTrialStart]. */
function effectiveAiRank(
  subscriptionTier: string | undefined,
  trialStartIso: string | null | undefined,
  createdAtIso: string | null | undefined,
): number {
  const tier = (subscriptionTier ?? 'trial').toLowerCase();
  if (tier === 'ai' || tier === 'ai_family') return TIER_RANK.ai;
  if (tier === 'base') return TIER_RANK.core;
  // subscription_tier === trial (or unknown): 14-day full access then core-only
  const startRaw = trialStartIso && trialStartIso.length > 0 ? trialStartIso : createdAtIso;
  const start = startRaw ? Date.parse(startRaw) : Date.now();
  if (Number.isNaN(start)) return TIER_RANK.ai;
  const expired = Date.now() - start >= TRIAL_MS;
  return expired ? TIER_RANK.core : TIER_RANK.ai;
}

function tierAllows(
  subscriptionTier: string | undefined,
  trialStartIso: string | null | undefined,
  createdAtIso: string | null | undefined,
  requiredTier: 'core' | 'ai',
): boolean {
  const rank = effectiveAiRank(subscriptionTier, trialStartIso, createdAtIso);
  return rank >= TIER_RANK[requiredTier];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('authorization') ?? '';
    const jwt = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : '';
    if (!jwt) {
      return new Response(JSON.stringify({ error: 'Missing bearer token' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const body = await req.json();
    // Accept both snake_case (Flutter client) and camelCase field names
    const familyId = body.family_id ?? body.familyId;
    const feature = body.feature;
    const prompt = body.prompt;
    const responseMimeType = body.responseMimeType;
    const responseSchema = body.responseSchema;
    const imageBase64 = body.image_base64 ?? body.imageBase64;
    const imageMimeType = body.image_mime_type ?? body.imageMimeType ?? 'image/jpeg';

    if (!familyId || !feature) {
      return new Response(JSON.stringify({ error: 'Missing required fields: family_id, feature' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const hasImage = typeof imageBase64 === 'string' && imageBase64.length > 0;
    if ((!prompt || typeof prompt !== 'string') && !hasImage) {
      return new Response(JSON.stringify({ error: 'Provide prompt and/or image_base64' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const promptStr = typeof prompt === 'string' ? prompt : '';
    if (hasImage && typeof imageBase64 === 'string' && imageBase64.length > MAX_IMAGE_BASE64_CHARS) {
      return new Response(JSON.stringify({ error: 'image_too_large', maxChars: MAX_IMAGE_BASE64_CHARS }), {
        status: 413,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (promptStr.length > MAX_PROMPT_CHARS) {
      return new Response(
        JSON.stringify({
          error: 'prompt_too_large',
          maxChars: MAX_PROMPT_CHARS,
        }),
        {
          status: 413,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    // ── Verify session + membership + tier (RLS via anon key; no service role) ─
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    if (!anonKey) {
      return new Response(JSON.stringify({ error: 'Server misconfigured: SUPABASE_ANON_KEY missing' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const userSb = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data: authData, error: authError } = await userSb.auth.getUser();
    const userId = authData.user?.id;
    if (authError || !userId) {
      return new Response(JSON.stringify({ error: 'Invalid or expired session' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { data: membership, error: membershipError } = await userSb
      .from('family_members')
      .select('family_id')
      .eq('family_id', familyId)
      .eq('user_id', userId)
      .maybeSingle();
    if (membershipError || !membership) {
      return new Response(JSON.stringify({ error: 'Not authorized for this family' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { data: family, error: familyError } = await userSb
      .from('families')
      .select('subscription_tier, trial_start_date, created_at')
      .eq('id', familyId)
      .single();

    if (familyError && familyError.code !== 'PGRST116') {
      // PGRST116 = row not found; allow through (local-only mode)
      console.warn('[Huddle] Could not verify family tier:', familyError.message);
    }

    const requiredTier = FEATURE_TIER_MAP[feature];
    if (
      requiredTier &&
      !tierAllows(
        family?.subscription_tier as string | undefined,
        family?.trial_start_date as string | null | undefined,
        family?.created_at as string | null | undefined,
        requiredTier,
      )
    ) {
      return new Response(JSON.stringify({ error: 'subscription_required', tier: requiredTier }), {
        status: 402,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── Call Gemini ───────────────────────────────────────────────────────
    const apiKey = Deno.env.get('GEMINI_API_KEY');
    if (!apiKey) {
      return new Response(JSON.stringify({ error: 'GEMINI_API_KEY not configured on server' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const MODEL_CANDIDATES = ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-1.5-flash'];
    let lastError: unknown;
    let geminiResponse: Response | null = null;

    const textPart = promptStr.length > 0
      ? promptStr
      : (feature === 'ai_events_vision'
        ? 'Extract calendar events from this image. Return JSON only.'
        : 'Describe this image briefly.');

    const bodyParts: Record<string, unknown>[] = [{ text: textPart }];
    if (hasImage && typeof imageBase64 === 'string') {
      bodyParts.push({
        inline_data: {
          mime_type: typeof imageMimeType === 'string' ? imageMimeType : 'image/jpeg',
          data: imageBase64,
        },
      });
    }

    for (const model of MODEL_CANDIDATES) {
      const reqBody: Record<string, unknown> = {
        contents: [{ parts: bodyParts }],
      };
      const genConfig: Record<string, unknown> = {};
      if (responseMimeType) {
        genConfig.responseMimeType = responseMimeType;
        if (responseSchema) genConfig.responseSchema = responseSchema;
      }
      // Devotionals were repeating with default sampling; nudge variety for this feature only.
      if (feature === 'ai_devotional') {
        genConfig.temperature = 1.12;
        genConfig.topP = 0.92;
      }
      // Per Gemini REST API, thinkingConfig lives under generationConfig (not top-level).
      if (model.includes('2.5')) {
        genConfig.thinkingConfig = { thinkingBudget: 0 };
      }
      if (Object.keys(genConfig).length > 0) {
        reqBody.generationConfig = genConfig;
      }

      geminiResponse = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
        { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(reqBody) },
      );

      if (geminiResponse.ok) break;

      const errText = await geminiResponse.text();
      lastError = new Error(`Gemini ${model} failed: ${errText}`);
      console.warn('[Huddle]', lastError);
      geminiResponse = null;
    }

    if (!geminiResponse) {
      throw lastError ?? new Error('All Gemini model attempts failed');
    }

    const geminiData = await geminiResponse.json();
    // Find the last non-thinking text part (Gemini 2.5+ may prepend thought parts)
    const candidateParts: Record<string, unknown>[] =
      (geminiData?.candidates?.[0]?.content?.parts ?? []) as Record<string, unknown>[];
    const textParts = candidateParts.filter((p) => 'text' in p && !p.thought);
    let text = textParts.length > 0 ? (textParts[textParts.length - 1].text as string) : '';
    if (!text && candidateParts.length > 0) {
      const withText = candidateParts.filter((p) => typeof p.text === 'string' && (p.text as string).length > 0);
      if (withText.length > 0) text = withText[withText.length - 1].text as string;
    }

    if (feature === 'ai_copilot') {
      text = sanitizeCopilotJson(text);
    }

    return new Response(JSON.stringify({ text }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (err) {
    console.error('[Huddle] ai-proxy error:', err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});

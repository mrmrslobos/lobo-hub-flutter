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
};

const TIER_RANK: Record<string, number> = { free: 0, core: 1, ai: 2 };

const TRIAL_MS = 14 * 24 * 60 * 60 * 1000;

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
    const body = await req.json();
    // Accept both snake_case (Flutter client) and camelCase field names
    const familyId = body.family_id ?? body.familyId;
    const feature = body.feature;
    const prompt = body.prompt;
    const responseMimeType = body.responseMimeType;
    const responseSchema = body.responseSchema;

    if (!familyId || !feature || !prompt) {
      return new Response(JSON.stringify({ error: 'Missing required fields: family_id, feature, prompt' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── Verify subscription tier ──────────────────────────────────────────
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: family, error: familyError } = await supabase
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

    for (const model of MODEL_CANDIDATES) {
      const reqBody: Record<string, unknown> = {
        contents: [{ parts: [{ text: prompt }] }],
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
      if (Object.keys(genConfig).length > 0) {
        reqBody.generationConfig = genConfig;
      }

      // Gemini 2.5+ models return "thinking" parts by default which can
      // break JSON extraction from parts[0]. Disable thinking for clean output.
      // thinkingConfig is a top-level field, NOT inside generationConfig.
      if (model.includes('2.5')) {
        reqBody.thinkingConfig = { thinkingBudget: 0 };
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
    const parts = geminiData?.candidates?.[0]?.content?.parts ?? [];
    const textParts = parts.filter((p: Record<string, unknown>) => 'text' in p && !p.thought);
    const text = textParts.length > 0 ? (textParts[textParts.length - 1].text as string) : '';

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

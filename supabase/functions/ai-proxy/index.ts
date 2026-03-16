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

function tierAllows(familyTier: string | undefined, requiredTier: 'core' | 'ai'): boolean {
  // undefined defaults to 'ai' during beta
  const rank = TIER_RANK[familyTier ?? 'ai'] ?? 2;
  return rank >= TIER_RANK[requiredTier];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { familyId, feature, prompt, responseMimeType, responseSchema } = await req.json();

    if (!familyId || !feature || !prompt) {
      return new Response(JSON.stringify({ error: 'Missing required fields: familyId, feature, prompt' }), {
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
      .select('subscription_tier')
      .eq('id', familyId)
      .single();

    if (familyError && familyError.code !== 'PGRST116') {
      // PGRST116 = row not found; allow through (local-only mode)
      console.warn('[FamilyHub] Could not verify family tier:', familyError.message);
    }

    const requiredTier = FEATURE_TIER_MAP[feature];
    if (requiredTier && !tierAllows(family?.subscription_tier, requiredTier)) {
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
      const body: Record<string, unknown> = {
        contents: [{ parts: [{ text: prompt }] }],
      };
      if (responseMimeType) {
        body.generationConfig = {
          responseMimeType,
          ...(responseSchema ? { responseSchema } : {}),
        };
      }

      // Gemini 2.5+ models return "thinking" parts by default which can
      // break JSON extraction from parts[0]. Disable thinking for clean output.
      if (model.includes('2.5')) {
        const gc = (body.generationConfig ?? {}) as Record<string, unknown>;
        gc.thinkingConfig = { thinkingBudget: 0 };
        body.generationConfig = gc;
      }

      geminiResponse = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
        { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) },
      );

      if (geminiResponse.ok) break;

      const errText = await geminiResponse.text();
      lastError = new Error(`Gemini ${model} failed: ${errText}`);
      console.warn('[FamilyHub]', lastError);
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
    console.error('[FamilyHub] ai-proxy error:', err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});

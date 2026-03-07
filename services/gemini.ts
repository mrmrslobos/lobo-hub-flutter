import { GoogleGenAI, Type } from "@google/genai";

// Primary model preference: 2.5 Flash → 2.0 Flash fallback
const MODEL_CANDIDATES = [
  'gemini-2.5-flash',
  'gemini-2.0-flash',
] as const;

// ---------------------------------------------------------------------------
// AI Proxy — routes requests through the Supabase Edge Function so the
// Gemini API key is never exposed to the browser.
// ---------------------------------------------------------------------------

interface AiProxyContext {
  supabaseUrl: string;
  supabaseAnonKey: string;
  familyId: string;
}

let _aiProxyContext: AiProxyContext | null = null;

/** Configure the AI proxy. Call this after the user authenticates. */
export function setAiProxyContext(ctx: AiProxyContext) {
  _aiProxyContext = ctx;
}

/** Clear the proxy context (e.g. on logout). */
export function clearAiProxyContext() {
  _aiProxyContext = null;
}

async function callAiProxy(params: {
  feature: string;
  prompt: string;
  responseMimeType?: 'application/json';
  responseSchema?: object;
}): Promise<string> {
  if (!_aiProxyContext) throw new Error('AI proxy context not configured');

  const { supabaseUrl, supabaseAnonKey, familyId } = _aiProxyContext;
  const endpoint = `${supabaseUrl}/functions/v1/ai-proxy`;

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${supabaseAnonKey}`,
    },
    body: JSON.stringify({
      familyId,
      feature: params.feature,
      prompt: params.prompt,
      responseMimeType: params.responseMimeType,
      responseSchema: params.responseSchema,
    }),
  });

  if (res.status === 402) {
    const body = await res.json().catch(() => ({}));
    throw new Error(`subscription_required:${body.tier ?? 'ai'}`);
  }

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `AI proxy error ${res.status}`);
  }

  const data = await res.json();
  if (!data.text) throw new Error('AI proxy returned empty response');
  return data.text as string;
}

type JsonSchema = {
  type: Type;
  items?: unknown;
  properties?: Record<string, unknown>;
  required?: string[];
};

type EnvLike = Record<string, string | undefined>;

/** Minimal locale info passed to AI prompts so they use the right units. */
export interface LocaleHint {
  units: 'metric' | 'imperial';
  country?: string; // ISO 3166 e.g. 'AU', 'US'
}

/**
 * Build a short instruction block that tells the model which measurement
 * system, vocabulary and currency context to use.
 */
const localeBlock = (hint?: LocaleHint): string => {
  if (!hint) return '';
  const isMetric = hint.units === 'metric';
  const lines = [
    `MEASUREMENT SYSTEM: Use ${isMetric ? 'METRIC' : 'IMPERIAL'} units throughout.`,
    isMetric
      ? '- Weights: grams (g) and kilograms (kg). NEVER use oz, lb, or pounds.'
      : '- Weights: ounces (oz) and pounds (lb).',
    isMetric
      ? '- Volumes: millilitres (ml) and litres (L). NEVER use cups, fl oz, or quarts.'
      : '- Volumes: cups, tablespoons, teaspoons, fluid ounces.',
    isMetric
      ? '- Temperatures: Celsius (°C). NEVER use Fahrenheit.'
      : '- Temperatures: Fahrenheit (°F).',
    isMetric
      ? '- Distances: centimetres (cm), metres (m), kilometres (km).'
      : '- Distances: inches, feet, miles.',
    hint.country ? `- The user is in ${hint.country}. Use locally common ingredient names and brands where possible.` : '',
  ];
  return '\n' + lines.filter(Boolean).join('\n') + '\n';
};

/**
 * Read an environment variable from multiple sources.
 * Vite's `define` only replaces static `process.env.X` references at compile
 * time – computed access like `process.env[key]` is left as-is and blows up
 * in the browser.  We therefore read from `import.meta.env` first (Vite
 * exposes all VITE_-prefixed vars there as a real object), then fall back to
 * process.env for non-browser runtimes.
 */
const readEnv = (key: string, aliases: string[] = []): string => {
  const candidates = [key, ...aliases];

  const importMetaEnv: EnvLike | undefined = (() => {
    try {
      return import.meta.env as EnvLike;
    } catch {
      return undefined;
    }
  })();

  const processEnv: EnvLike | undefined = (() => {
    try {
      return (globalThis as any)?.process?.env as EnvLike | undefined;
    } catch {
      return undefined;
    }
  })();

  for (const envKey of candidates) {
    const value = importMetaEnv?.[envKey] ?? processEnv?.[envKey];
    if (value) return value;
  }

  return '';
};

const getApiKey = (): string => {
  return readEnv('VITE_GEMINI_API_KEY', [
    'GEMINI_API_KEY',
    'NEXT_PUBLIC_GEMINI_API_KEY',
  ]);
};

const getPreferredModel = (): string => {
  return readEnv('VITE_GEMINI_MODEL', ['GEMINI_MODEL']) || MODEL_CANDIDATES[0];
};

const getAI = () => {
  const apiKey = getApiKey();
  if (!apiKey) {
    throw new Error('Gemini API key missing. Set VITE_GEMINI_API_KEY (recommended) and redeploy.');
  }
  return new GoogleGenAI({ apiKey });
};

/**
 * Strip optional markdown code fences that some model versions wrap around
 * JSON responses (e.g. ```json\n{...}\n```), then parse and return.
 * Throws a descriptive error if the text is empty or not valid JSON.
 */
function parseJSON<T = unknown>(text: string | undefined): T {
  if (!text || !text.trim()) {
    throw new Error('Gemini returned an empty response. Check your API key and quota.');
  }
  const stripped = text.trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```\s*$/, '');
  try {
    return JSON.parse(stripped) as T;
  } catch {
    throw new Error(`Gemini response could not be parsed as JSON: ${stripped.slice(0, 200)}`);
  }
}

export const generateWithModelFallback = async ({
  prompt,
  responseMimeType,
  responseSchema,
  feature = 'ai_general',
}: {
  prompt: string;
  responseMimeType?: 'application/json';
  responseSchema?: JsonSchema;
  /** AI proxy feature key — used for subscription tier gating on the server. */
  feature?: string;
}): Promise<{ text: string | undefined }> => {
  // ── 1. Try the AI proxy first (hides API key, enforces subscription) ──────
  if (_aiProxyContext) {
    try {
      const text = await callAiProxy({ feature, prompt, responseMimeType, responseSchema: responseSchema as object | undefined });
      return { text };
    } catch (err) {
      const msg = String(err);
      // Surface subscription errors immediately — no point falling through.
      if (msg.includes('subscription_required')) throw err;
      console.warn('[FamilyHub] AI proxy failed, falling back to direct Gemini API.', err);
    }
  }

  // ── 2. Fall back to direct Gemini API (uses client-side API key) ──────────
  const ai = getAI();
  const preferredModel = getPreferredModel();
  const models = [preferredModel, ...MODEL_CANDIDATES.filter((m) => m !== preferredModel)];

  let lastError: unknown;

  for (const model of models) {
    try {
      const res = await ai.models.generateContent({
        model,
        contents: prompt,
        config: {
          ...(responseMimeType ? { responseMimeType } : {}),
          ...(responseSchema ? { responseSchema } : {}),
        },
      });
      return { text: res.text };
    } catch (error) {
      lastError = error;
      console.warn('[FamilyHub] Gemini model failed, trying fallback model.', { model, error });
    }
  }

  throw lastError instanceof Error
    ? lastError
    : new Error('Gemini request failed for all configured model fallbacks.');
};

export const generateTaskBreakdown = async (goal: string) => {
  const response = await generateWithModelFallback({
    prompt: `Break down this family goal into a checklist of actionable tasks: "${goal}". Provide a JSON array of objects with "title" and "priority" (HIGH, MEDIUM, LOW).`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          title: { type: Type.STRING },
          priority: { type: Type.STRING }
        },
        required: ['title', 'priority']
      }
    }
  });

  return parseJSON<{ title: string; priority: string }[]>(response.text);
};

export const generateMealSuggestions = async (preferences: string, locale?: LocaleHint) => {
  const response = await generateWithModelFallback({
    prompt: `Suggest 3 dinner recipes based on these preferences: "${preferences}". Include title, ingredients (with specific quantities), and summary for each.${localeBlock(locale)}`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          title: { type: Type.STRING },
          ingredients: { type: Type.ARRAY, items: { type: Type.STRING } },
          summary: { type: Type.STRING }
        },
        required: ['title', 'ingredients', 'summary']
      }
    }
  });

  return parseJSON<{ title: string; ingredients: string[]; summary: string }[]>(response.text);
};

export const generateWeeklyMealPlan = async (preferences: string, locale?: LocaleHint) => {
  const response = await generateWithModelFallback({
    prompt: `Create a healthy and varied 7-day family meal plan based on these preferences: "${preferences || 'balanced family meals'}".
${localeBlock(locale)}
For each day provide breakfast, lunch, and dinner. Each meal must include:
- A short, appealing recipe name
- A concise ingredients list (4-8 items with specific quantities)
- Step-by-step cooking instructions (3-6 clear steps a home cook can follow)
- Number of servings (typically 4 for a family)

Make sure meals are practical, family-friendly, and use common grocery store ingredients. Vary the proteins and cuisines throughout the week.

CRITICAL LEFTOVER RULE: If any lunch is a leftover from a dinner, it MUST be a leftover of the PREVIOUS day's dinner — never the same day's dinner. For example, Monday's leftover lunch must come from Sunday's dinner (which you should include as Day 0 or carry forward), and Tuesday's leftover lunch comes from Monday's dinner. A dinner cannot be eaten as a leftover before it has been cooked. Day 1 (Monday) should only use leftovers if you include a Day 0 (Sunday) dinner, otherwise give Day 1 a fresh lunch.`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          dayName: { type: Type.STRING },
          meals: {
            type: Type.ARRAY,
            items: {
              type: Type.OBJECT,
              properties: {
                type: { type: Type.STRING },
                name: { type: Type.STRING },
                ingredients: { type: Type.ARRAY, items: { type: Type.STRING } },
                steps: { type: Type.ARRAY, items: { type: Type.STRING } },
                servings: { type: Type.NUMBER },
              },
              required: ['type', 'name', 'ingredients', 'steps', 'servings'],
            },
          },
        },
        required: ['dayName', 'meals'],
      },
    },
  });

  return parseJSON(response.text) as {
    dayName: string;
    meals: { type: string; name: string; ingredients: string[]; steps: string[]; servings: number }[];
  }[];
};

export const generateMealSwap = async (
  dayName: string,
  mealType: string,
  currentMeal: string,
  preferences: string,
  weekContext: string[],
  locale?: LocaleHint
) => {
  const contextStr = weekContext.length > 0
    ? `Other meals already planned this week: ${weekContext.slice(0, 10).join(', ')}.`
    : '';

  const response = await generateWithModelFallback({
    prompt: `Suggest a single ${mealType.toLowerCase()} meal for ${dayName} to replace "${currentMeal}".
The user wants: "${preferences}".
${contextStr}${localeBlock(locale)}
Make it different from the existing meals, practical for a family, and use common grocery store ingredients.
Include a recipe name, ingredients list (4-8 items with specific quantities), step-by-step cooking instructions (3-6 steps), and number of servings (typically 4).`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.OBJECT,
      properties: {
        name: { type: Type.STRING },
        ingredients: { type: Type.ARRAY, items: { type: Type.STRING } },
        steps: { type: Type.ARRAY, items: { type: Type.STRING } },
        servings: { type: Type.NUMBER },
      },
      required: ['name', 'ingredients', 'steps', 'servings'],
    },
  });

  return parseJSON(response.text) as {
    name: string;
    ingredients: string[];
    steps: string[];
    servings: number;
  };
};

export const extractRecipeFromText = async (pageText: string, locale?: LocaleHint) => {
  const response = await generateWithModelFallback({
    prompt: `Extract the recipe from this web page text. Find the recipe title, all ingredients with quantities, step-by-step instructions, and number of servings.${localeBlock(locale)}
Convert all ingredient quantities and cooking temperatures to the measurement system specified above.

Page text:
"""
${pageText}
"""

Return a structured recipe object.`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.OBJECT,
      properties: {
        title: { type: Type.STRING },
        ingredients: { type: Type.ARRAY, items: { type: Type.STRING } },
        steps: { type: Type.ARRAY, items: { type: Type.STRING } },
        servings: { type: Type.NUMBER },
        prepTime: { type: Type.STRING },
        cookTime: { type: Type.STRING },
      },
      required: ['title', 'ingredients', 'steps', 'servings'],
    },
  });

  const parsed = parseJSON<{ title?: string; ingredients?: string[]; steps?: string[]; servings?: number; prepTime?: string; cookTime?: string }>(response.text);
  return {
    title: parsed.title || 'Untitled Recipe',
    ingredients: parsed.ingredients || [],
    steps: parsed.steps || [],
    servings: parsed.servings || 4,
    prepTime: parsed.prepTime,
    cookTime: parsed.cookTime,
    imageUrl: undefined,
    sourceUrl: '',
  };
};

export const generateDevotional = async (topic: string) => {
  const response = await generateWithModelFallback({
    prompt: `Create a family devotional about "${topic}". Include a title, a scripture reference, a short encouraging message, 3 reflection questions, and a prayer.`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.OBJECT,
      properties: {
        title: { type: Type.STRING },
        scripture: { type: Type.STRING },
        content: { type: Type.STRING },
        reflectionPrompts: { type: Type.ARRAY, items: { type: Type.STRING } },
        prayer: { type: Type.STRING }
      },
      required: ['title', 'scripture', 'content', 'reflectionPrompts', 'prayer']
    }
  });

  return parseJSON<{ title: string; scripture: string; content: string; reflectionPrompts: string[]; prayer: string }>(response.text);
};

export const generateReadingPlan = async (theme: string, days: number) => {
  const response = await generateWithModelFallback({
    prompt: `Create a ${days}-day family Bible reading plan on the theme of "${theme}".

For EACH day provide:
- A short, engaging title for the day's reading (e.g. "The Foundation of Trust")
- A specific scripture passage reference (book chapter:verse-verse, e.g. "Proverbs 3:5-6")
- A brief reflection paragraph (3-4 sentences) connecting the scripture to daily family life
- One family discussion question that sparks conversation at dinner or bedtime

Guidelines:
- Build a progressive journey through the theme — day 1 introduces the concept, middle days explore different facets, final day brings it together
- Use a mix of Old and New Testament passages
- Keep reflections warm, practical, and accessible to all ages
- Discussion questions should be open-ended and suitable for families with children
- Each scripture reference should be a real, existing Bible passage`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.OBJECT,
      properties: {
        title: { type: Type.STRING },
        description: { type: Type.STRING },
        days: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              day: { type: Type.NUMBER },
              title: { type: Type.STRING },
              scripture: { type: Type.STRING },
              reflection: { type: Type.STRING },
              discussionQuestion: { type: Type.STRING },
            },
            required: ['day', 'title', 'scripture', 'reflection', 'discussionQuestion'],
          },
        },
      },
      required: ['title', 'description', 'days'],
    },
  });

  return parseJSON<{
    title: string;
    description: string;
    days: { day: number; title: string; scripture: string; reflection: string; discussionQuestion: string }[];
  }>(response.text);
};

export const analyzeBudget = async (summary: string) => {
  const response = await generateWithModelFallback({
    prompt: `Analyze this household budget summary and give 3 specific tips for saving money: "${summary}".`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.ARRAY,
      items: { type: Type.STRING }
    }
  });

  return parseJSON(response.text);
};

export interface ParsedBankTransaction {
  date: string;           // ISO date e.g. "2024-01-15"
  description: string;
  amount: number;         // always positive
  type: 'INCOME' | 'EXPENSE';
  suggestedCategory: string;
  isNewCategory: boolean;
}

export interface ParsedBankResult {
  transactions: ParsedBankTransaction[];
  newCategories: { name: string; suggestedLimit: number }[];
}

/**
 * Send a bank statement (CSV text or base64-encoded PDF) to Gemini and get
 * back structured transactions with suggested budget categories.
 */
export const parseBankStatement = async (
  file: { type: 'text'; content: string } | { type: 'pdf'; base64: string },
  existingCategoryNames: string[],
): Promise<ParsedBankResult> => {
  const ai = getAI();
  const preferredModel = getPreferredModel();
  const models = [preferredModel, ...MODEL_CANDIDATES.filter(m => m !== preferredModel)];

  const existingNote = existingCategoryNames.length > 0
    ? `Assign to one of these existing categories where appropriate: ${existingCategoryNames.join(', ')}.`
    : 'No existing categories yet — create appropriate ones.';

  const prompt =
    `You are a bank statement parser for a personal finance app. ` +
    `Extract every transaction from the statement. ` +
    existingNote +
    ` For each transaction set type to INCOME for credits/deposits and EXPENSE for debits/charges. ` +
    `amount must always be a positive number. ` +
    `date must be ISO format YYYY-MM-DD. ` +
    `If you create a new category, set isNewCategory=true and include it in newCategories with a realistic monthly spending limit based on the transactions seen.`;

  const parts = file.type === 'pdf'
    ? [{ inlineData: { mimeType: 'application/pdf' as const, data: file.base64 } }, { text: prompt }]
    : [{ text: `${prompt}\n\nBank statement:\n${file.content}` }];

  const responseSchema = {
    type: Type.OBJECT,
    properties: {
      transactions: {
        type: Type.ARRAY,
        items: {
          type: Type.OBJECT,
          properties: {
            date:              { type: Type.STRING },
            description:       { type: Type.STRING },
            amount:            { type: Type.NUMBER },
            type:              { type: Type.STRING },
            suggestedCategory: { type: Type.STRING },
            isNewCategory:     { type: Type.BOOLEAN },
          },
          required: ['date', 'description', 'amount', 'type', 'suggestedCategory', 'isNewCategory'],
        },
      },
      newCategories: {
        type: Type.ARRAY,
        items: {
          type: Type.OBJECT,
          properties: {
            name:           { type: Type.STRING },
            suggestedLimit: { type: Type.NUMBER },
          },
          required: ['name', 'suggestedLimit'],
        },
      },
    },
    required: ['transactions', 'newCategories'],
  };

  let lastError: unknown;
  for (const model of models) {
    try {
      const response = await ai.models.generateContent({
        model,
        contents: [{ parts }],
        config: { responseMimeType: 'application/json', responseSchema },
      });
      const text = response.text ?? '';
      if (text) return parseJSON<ParsedBankResult>(text);
      lastError = new Error('Empty response from model');
    } catch (err) {
      lastError = err;
      console.warn('[FamilyHub] parseBankStatement model failed, trying fallback.', { model, err });
    }
  }

  throw lastError instanceof Error
    ? lastError
    : new Error('Bank statement parsing failed for all model fallbacks.');
};

export const generateFitnessMotivation = async (goal: string) => {
  const response = await generateWithModelFallback({
    prompt: `Provide a short, highly motivating message for a family trying to achieve this fitness goal: "${goal}". Keep it punchy and supportive.`,
  });

  return response.text;
};

export const generateFitnessPlan = async (profile: {
  gender: string;
  height: string;
  weight: string;
  level: string;
  daysPerWeek?: string;
  location?: string;
  equipment?: string[];
}, locale?: LocaleHint) => {
  const workoutDays = parseInt(profile.daysPerWeek || '5') || 5;
  const restDays = 7 - workoutDays;
  const locationLine = profile.location ? `- Training location: ${profile.location}` : '';
  const equipmentLine = profile.equipment && profile.equipment.length > 0
    ? `- Available equipment: ${profile.equipment.join(', ')}\n  IMPORTANT: Only prescribe exercises that use this exact equipment. Do not suggest machines, cables, or gear not listed.`
    : profile.location?.toLowerCase() === 'gym'
      ? '- Training location: Gym (full equipment available — machines, cables, free weights, etc.)'
      : '';
  const response = await generateWithModelFallback({
    prompt: `Create a detailed weekly fitness plan for someone with this profile:
- Gender: ${profile.gender}
- Height: ${profile.height}
- Weight: ${profile.weight}
- Fitness Level: ${profile.level}
- Available workout days per week: ${workoutDays} (${restDays} rest/recovery day${restDays !== 1 ? 's' : ''})
${locationLine}
${equipmentLine}
${localeBlock(locale)}
Provide a structured 7-day workout plan. The person can only train ${workoutDays} days per week — the remaining ${restDays} day${restDays !== 1 ? 's' : ''} must be rest or light active recovery (stretching, walking). Spread the workout days sensibly throughout the week with adequate recovery between muscle groups. Each workout day should have a focus area, a list of exercises with sets/reps, and an estimated duration. Tailor the intensity to their fitness level (${profile.level}). ${profile.location?.toLowerCase() === 'home' ? 'All exercises must be doable at home with only the listed equipment.' : ''}`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.OBJECT,
      properties: {
        summary: { type: Type.STRING },
        weeklyPlan: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              day: { type: Type.STRING },
              focus: { type: Type.STRING },
              duration: { type: Type.STRING },
              exercises: {
                type: Type.ARRAY,
                items: {
                  type: Type.OBJECT,
                  properties: {
                    name: { type: Type.STRING },
                    detail: { type: Type.STRING },
                  },
                  required: ['name', 'detail'],
                },
              },
            },
            required: ['day', 'focus', 'duration', 'exercises'],
          },
        },
        tips: { type: Type.ARRAY, items: { type: Type.STRING } },
      },
      required: ['summary', 'weeklyPlan', 'tips'],
    },
  });

  return parseJSON<{
    summary: string;
    weeklyPlan: { day: string; focus: string; duration: string; exercises: { name: string; detail: string }[] }[];
    tips: string[];
  }>(response.text);
};

export const refineFitnessPlan = async (
  currentPlan: {
    summary: string;
    weeklyPlan: { day: string; focus: string; duration: string; exercises: { name: string; detail: string }[] }[];
    tips: string[];
  },
  profile: { gender: string; height: string; weight: string; level: string; daysPerWeek?: string; location?: string; equipment?: string[] },
  userRequest: string,
  locale?: LocaleHint,
) => {
  const equipmentNote = profile.equipment && profile.equipment.length > 0
    ? `- Available equipment: ${profile.equipment.join(', ')} — only suggest exercises using this equipment`
    : profile.location?.toLowerCase() === 'gym'
      ? '- Training at a gym with full equipment available'
      : '';
  const response = await generateWithModelFallback({
    prompt: `You are updating an existing weekly fitness plan based on a user's refinement request.

Current plan (JSON):
${JSON.stringify(currentPlan, null, 2)}

User's profile:
- Gender: ${profile.gender}
- Height: ${profile.height}
- Weight: ${profile.weight}
- Fitness Level: ${profile.level}
${profile.location ? `- Training location: ${profile.location}` : ''}
${equipmentNote}
${localeBlock(locale)}

The user wants to make this change:
"${userRequest}"

Return the COMPLETE updated plan in the same JSON format, applying the requested change while keeping everything else sensible. Preserve the overall structure, exercise count, and fitness level. Only change what the user asked for.`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.OBJECT,
      properties: {
        summary: { type: Type.STRING },
        weeklyPlan: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              day: { type: Type.STRING },
              focus: { type: Type.STRING },
              duration: { type: Type.STRING },
              exercises: {
                type: Type.ARRAY,
                items: {
                  type: Type.OBJECT,
                  properties: {
                    name: { type: Type.STRING },
                    detail: { type: Type.STRING },
                  },
                  required: ['name', 'detail'],
                },
              },
            },
            required: ['day', 'focus', 'duration', 'exercises'],
          },
        },
        tips: { type: Type.ARRAY, items: { type: Type.STRING } },
      },
      required: ['summary', 'weeklyPlan', 'tips'],
    },
  });

  return parseJSON<{
    summary: string;
    weeklyPlan: { day: string; focus: string; duration: string; exercises: { name: string; detail: string }[] }[];
    tips: string[];
  }>(response.text);
};

export const refineWeeklyMealPlan = async (
  currentDays: {
    dayName: string;
    meals: { type: string; name: string; ingredients: string[]; steps: string[]; servings: number }[];
  }[],
  userRequest: string,
  locale?: LocaleHint,
) => {
  const response = await generateWithModelFallback({
    prompt: `You are updating an existing 7-day family meal plan based on a user's refinement request.

Current meal plan (JSON):
${JSON.stringify(currentDays, null, 2)}
${localeBlock(locale)}

The user wants to make this change:
"${userRequest}"

Return the COMPLETE updated 7-day meal plan in the same JSON format, applying the requested change while keeping everything else sensible and family-friendly. Only change what the user asked for. Keep step-by-step cooking instructions for each meal.`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          dayName: { type: Type.STRING },
          meals: {
            type: Type.ARRAY,
            items: {
              type: Type.OBJECT,
              properties: {
                type: { type: Type.STRING },
                name: { type: Type.STRING },
                ingredients: { type: Type.ARRAY, items: { type: Type.STRING } },
                steps: { type: Type.ARRAY, items: { type: Type.STRING } },
                servings: { type: Type.INTEGER },
              },
              required: ['type', 'name', 'ingredients', 'steps', 'servings'],
            },
          },
        },
        required: ['dayName', 'meals'],
      },
    },
  });

  return parseJSON<{
    dayName: string;
    meals: { type: string; name: string; ingredients: string[]; steps: string[]; servings: number }[];
  }[]>(response.text);
};

export const consolidateIngredients = async (ingredients: string[], locale?: LocaleHint) => {
  const list = ingredients.map((ing, i) => `${i + 1}. ${ing}`).join('\n');

  const isMetric = !locale || locale.units === 'metric';
  const unitExamples = isMetric
    ? `- Use grams (g), kilograms (kg), millilitres (ml), and litres (L). NEVER use oz, lb, cups, or fl oz.
- Round to clean shopper amounts: "375g" → "400g", "1.3 kg" → "1.5 kg"
- Use practical pack sizes a shopper would find in store: "500g", "1 kg", "1L", "400g can", "250ml"
- Examples: "Chicken Breast" → "1 kg", "Olive Oil" → "250 ml", "Rice" → "1 kg", "Canned Tomatoes" → "2 × 400g cans"`
    : `- Use ounces (oz), pounds (lb), cups, tablespoons, teaspoons.
- Round to clean shopper amounts: "1.75 cups" → "2 cups", "3.3 lbs" → "3½ lbs"
- Use ¼ ½ ¾ fractions, not decimals.`;

  const response = await generateWithModelFallback({
    prompt: `You are building a polished, print-ready family shopping list from a 7-day meal plan. Apply these rules strictly:
${localeBlock(locale)}
MERGING
- Combine duplicate or similar ingredients into ONE entry.
  Example: "1 red bell pepper" + "2 cups diced bell pepper" → name: "Bell Peppers", quantity: "${isMetric ? '3-4 medium' : '3-4 medium'}"
- Combine like units: "1 can diced tomatoes" + "1 can diced tomatoes" → "${isMetric ? '2 × 400g cans' : '2 cans (14 oz)'}"
- Keep genuinely different cuts/types separate: "chicken breast" ≠ "chicken thighs"

QUANTITIES — must be specific, shopper-friendly, and in the correct unit system
${unitExamples}
- NEVER write "to taste", "as needed", "a pinch", or any vague term.
- Convert vague amounts to practical ones:
    "salt to taste" → quantity: "${isMetric ? '5g' : '1 tsp'}"
    "pepper to taste" → quantity: "${isMetric ? '3g' : '1 tsp'}"
    "olive oil as needed" → quantity: "${isMetric ? '60 ml' : '¼ cup'}"
    "butter as needed" → quantity: "${isMetric ? '60g' : '4 tbsp'}"
    "garlic to taste" → quantity: "3-4 cloves"

NAMES
- Title Case, no adjectives: not "fresh chopped parsley" → "Parsley"
- Not "finely diced onion" → "Onion"
- Include the type when important: "Garlic Cloves", "Cherry Tomatoes", "Canned Chickpeas"

Raw ingredient lines from the meal plan:
${list}

Return a JSON array. Each object has "name" (clean Title Case ingredient) and "quantity" (specific, practical amount — no vague terms allowed).`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          name: { type: Type.STRING },
          quantity: { type: Type.STRING },
        },
        required: ['name', 'quantity'],
      },
    },
  });

  return parseJSON(response.text) as { name: string; quantity: string }[];
};

export const categorizeListItems = async (items: { id: string; text: string }[], listCategory: string) => {
  const itemsList = items.map(i => `- ${i.text} (id: ${i.id})`).join('\n');
  const context = listCategory === 'GROCERY'
    ? 'This is a grocery/shopping list. Group items into store sections like Produce, Dairy, Meat & Seafood, Bakery, Frozen, Snacks & Beverages, Pantry Staples, Household, Health & Beauty, etc.'
    : listCategory === 'HARDWARE'
    ? 'This is a hardware/tools list. Group items into categories like Power Tools, Hand Tools, Fasteners, Plumbing, Electrical, Paint & Supplies, Lumber, Safety, etc.'
    : listCategory === 'PACKING'
    ? 'This is a packing/travel list. Group items into categories like Clothing, Toiletries, Electronics, Documents, Accessories, First Aid, Entertainment, etc.'
    : 'Group these items into logical categories that make sense for the list content.';

  const response = await generateWithModelFallback({
    prompt: `Categorize these list items into groups.

${context}

Items:
${itemsList}

Return a JSON array where each entry maps an item ID to its category name. Keep category names short (1-3 words).`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          id: { type: Type.STRING },
          category: { type: Type.STRING },
        },
        required: ['id', 'category'],
      },
    },
  });

  return parseJSON(response.text) as { id: string; category: string }[];
};

export const textToChecklist = async (text: string) => {
  const response = await generateWithModelFallback({
    prompt: `Turn this text into a structured checklist: "${text}". Return a JSON array of objects with "text" and "quantity".`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          text: { type: Type.STRING },
          quantity: { type: Type.STRING }
        },
        required: ['text']
      }
    }
  });

  return parseJSON<{ text: string; quantity?: string }[]>(response.text);
};

export const generateEventItinerary = async (eventDescription: string) => {
  const response = await generateWithModelFallback({
    prompt: `Create an itinerary and a preparation checklist for this event: "${eventDescription}". Provide a JSON object with "itinerary" (string) and "checklist" (array of strings).`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.OBJECT,
      properties: {
        itinerary: { type: Type.STRING },
        checklist: { type: Type.ARRAY, items: { type: Type.STRING } }
      },
      required: ['itinerary', 'checklist']
    }
  });

  return parseJSON<{ itinerary: string; checklist: string[] }>(response.text);
};

// ---------------------------------------------------------------------------
// AI Insights — Monthly Summary
// ---------------------------------------------------------------------------

export interface MonthlySummaryInput {
  familyName: string;
  month: string; // e.g. "March 2026"
  tasksCompleted: number;
  tasksCreated: number;
  eventsAttended: number;
  mealsPlanned: number;
  devotionalsShared: number;
  choresCompleted: number;
  totalChorePoints: number;
  budgetIncome: number;
  budgetExpenses: number;
  topBudgetCategories: { name: string; amount: number }[];
  workoutsLogged: number;
  habitsCompletionRate: number; // 0-100
  listsCompleted: number;
  pollsVoted: number;
  topChoreMembers: { name: string; completions: number }[];
  savingsProgress: { title: string; percent: number }[];
  prayerWallEntries: number;
  gratitudeCount: number;
  answeredPrayers: number;
  readingPlansActive: number;
  readingDaysCompleted: number;
  longestReadingStreak: number;
}

export const generateMonthlySummary = async (input: MonthlySummaryInput) => {
  const response = await generateWithModelFallback({
    prompt: `You are a warm, encouraging family assistant for a Christian family app. Generate a monthly recap for the ${input.familyName} family for ${input.month}.

Here is their data for the month:
- Tasks: ${input.tasksCompleted} completed out of ${input.tasksCreated} created
- Calendar Events: ${input.eventsAttended} events
- Meals Planned: ${input.mealsPlanned} meals
- Devotionals Shared: ${input.devotionalsShared}
- Chores Completed: ${input.choresCompleted} (${input.totalChorePoints} points earned)
- Top Chore Members: ${input.topChoreMembers.map(m => `${m.name}: ${m.completions}`).join(', ') || 'None yet'}
- Budget: ${input.budgetIncome} income / ${input.budgetExpenses} expenses
- Top Spending Categories: ${input.topBudgetCategories.map(c => `${c.name}: ${c.amount}`).join(', ') || 'No spending tracked'}
- Workouts Logged: ${input.workoutsLogged}
- Daily Habits Completion Rate: ${input.habitsCompletionRate}%
- Lists Completed: ${input.listsCompleted}
- Polls Voted On: ${input.pollsVoted}
- Prayer Wall: ${input.prayerWallEntries} entries (${input.gratitudeCount} gratitude, ${input.answeredPrayers} answered prayers)
- Bible Reading Plans: ${input.readingPlansActive} active plans, ${input.readingDaysCompleted} days completed, longest streak: ${input.longestReadingStreak} days
- Savings Goals Progress: ${input.savingsProgress.map(s => `${s.title}: ${s.percent}%`).join(', ') || 'None set'}

Create an uplifting, personalized monthly summary. Include:
1. A catchy headline summarizing their month (e.g. "A Month of Growing Together!")
2. 4-6 highlight bullets covering key achievements across different modules (use relevant emoji icons)
3. An encouraging message celebrating their progress as a family
4. A short faith note — a scripture or prayer relevant to their month
5. Their single top achievement of the month
6. 2-3 gentle focus areas for next month (not criticisms — encouraging nudges)

Keep the tone warm, celebratory, and faith-centered. This is a family that's trying their best.`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.OBJECT,
      properties: {
        headline: { type: Type.STRING },
        highlights: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              module: { type: Type.STRING },
              icon: { type: Type.STRING },
              text: { type: Type.STRING },
            },
            required: ['module', 'icon', 'text'],
          },
        },
        encouragement: { type: Type.STRING },
        faithNote: { type: Type.STRING },
        topAchievement: { type: Type.STRING },
        areasToFocus: { type: Type.ARRAY, items: { type: Type.STRING } },
      },
      required: ['headline', 'highlights', 'encouragement', 'faithNote', 'topAchievement', 'areasToFocus'],
    },
  });

  return parseJSON<{
    headline: string;
    highlights: { module: string; icon: string; text: string }[];
    encouragement: string;
    faithNote: string;
    topAchievement: string;
    areasToFocus: string[];
  }>(response.text);
};

// ---------------------------------------------------------------------------
// AI Insights — Smart Suggestions (calendar-aware, cross-module)
// ---------------------------------------------------------------------------

export interface SmartSuggestionsInput {
  familyName: string;
  todayDate: string;
  /** Calendar events for the next 3 days, with start/end times */
  upcomingEvents: { title: string; start: string; end: string; day: string }[];
  /** Whether meals are planned for today/tomorrow */
  mealsPlannedToday: { type: string; name: string }[];
  mealsMissingToday: string[]; // e.g. ["DINNER"]
  mealsMissingTomorrow: string[];
  /** Tasks due soon */
  overdueTasks: string[];
  tasksDueToday: string[];
  /** Recent devotional activity */
  daysSinceLastDevotional: number | null; // null = never
  /** Habits status */
  habitsNotDoneToday: string[];
  /** Busy-ness signal: number of events today */
  eventsToday: number;
  eventsTomorrow: number;
  /** Budget alert */
  overBudgetCategories: string[];
  /** Prayer wall context */
  unansweredPrayers: number;
  daysSinceLastPrayer: number | null; // null = never
  /** Reading plan context */
  activeReadingPlan: { title: string; currentDay: number; totalDays: number; streak: number } | null;
}

export const generateSmartSuggestions = async (input: SmartSuggestionsInput) => {
  const busySignal = input.eventsToday >= 3 ? 'VERY BUSY' : input.eventsToday >= 2 ? 'BUSY' : 'MODERATE';
  const tomorrowBusy = input.eventsTomorrow >= 3 ? 'VERY BUSY' : input.eventsTomorrow >= 2 ? 'BUSY' : 'MODERATE';

  const response = await generateWithModelFallback({
    prompt: `You are a proactive, thoughtful family assistant for a Christian family hub app. Based on the family's current context, generate 3-5 smart, actionable suggestions.

Family: ${input.familyName}
Today: ${input.todayDate}
Today's busyness level: ${busySignal} (${input.eventsToday} events)
Tomorrow's busyness: ${tomorrowBusy} (${input.eventsTomorrow} events)

CALENDAR CONTEXT (next 3 days):
${input.upcomingEvents.length > 0
  ? input.upcomingEvents.map(e => `- ${e.day}: "${e.title}" (${e.start} – ${e.end})`).join('\n')
  : '- No events scheduled'}

MEALS:
- Today planned: ${input.mealsPlannedToday.map(m => `${m.type}: ${m.name}`).join(', ') || 'Nothing planned'}
- Missing today: ${input.mealsMissingToday.join(', ') || 'All planned'}
- Missing tomorrow: ${input.mealsMissingTomorrow.join(', ') || 'All planned'}

TASKS:
- Overdue: ${input.overdueTasks.length > 0 ? input.overdueTasks.join(', ') : 'None'}
- Due today: ${input.tasksDueToday.length > 0 ? input.tasksDueToday.join(', ') : 'None'}

DEVOTIONAL:
- Days since last: ${input.daysSinceLastDevotional !== null ? input.daysSinceLastDevotional : 'Never done one'}

HABITS:
- Not done today: ${input.habitsNotDoneToday.length > 0 ? input.habitsNotDoneToday.join(', ') : 'All done!'}

BUDGET ALERTS:
- Over-budget categories: ${input.overBudgetCategories.length > 0 ? input.overBudgetCategories.join(', ') : 'None'}

PRAYER WALL:
- Unanswered prayer requests: ${input.unansweredPrayers}
- Days since last prayer/gratitude post: ${input.daysSinceLastPrayer !== null ? input.daysSinceLastPrayer : 'Never posted'}

BIBLE READING PLAN:
${input.activeReadingPlan
  ? `- Active plan: "${input.activeReadingPlan.title}" (Day ${input.activeReadingPlan.currentDay} of ${input.activeReadingPlan.totalDays}, ${input.activeReadingPlan.streak}-day streak)`
  : '- No active reading plan'}

IMPORTANT RULES:
- If the day is VERY BUSY, suggest QUICK things: 5-min carpool prayers, 15-min crockpot meals, 2-min family check-ins
- If meals are missing and the day is busy, suggest specific QUICK meal ideas (not generic "plan a meal")
- If it's been 3+ days since a devotional, gently suggest a short one themed to what's happening
- Always include a time estimate so the family knows it's doable
- Make suggestions specific and contextual — reference their actual events/tasks by name when possible
- If there's an active reading plan and today's reading isn't done, gently remind them to continue their streak
- If there are unanswered prayers and it's been a few days, suggest checking in on the prayer wall
- Each suggestion must have a type: "meal", "devotional", "task", "wellness", "family", or "prayer"
- Each suggestion must have an actionModule: the route path to navigate to ("/meals", "/devotional", "/tasks", "/fitness", "/calendar", "/prayer-wall")
- Keep it warm, practical, and faith-centered`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          type: { type: Type.STRING },
          title: { type: Type.STRING },
          description: { type: Type.STRING },
          reason: { type: Type.STRING },
          timeEstimate: { type: Type.STRING },
          actionModule: { type: Type.STRING },
        },
        required: ['type', 'title', 'description', 'reason', 'timeEstimate', 'actionModule'],
      },
    },
  });

  return parseJSON<{
    type: 'meal' | 'devotional' | 'task' | 'wellness' | 'family';
    title: string;
    description: string;
    reason: string;
    timeEstimate: string;
    actionModule: string;
  }[]>(response.text);
};

// ---------------------------------------------------------------------------
// Calendar-Aware Meal Plan Generation
// ---------------------------------------------------------------------------

export const generateCalendarAwareMealPlan = async (
  preferences: string,
  calendarContext: { day: string; events: { title: string; start: string; end: string }[] }[],
  locale?: LocaleHint,
) => {
  const calendarSummary = calendarContext.map(d => {
    if (d.events.length === 0) return `${d.day}: Free day`;
    return `${d.day}: ${d.events.map(e => `"${e.title}" (${e.start}–${e.end})`).join(', ')}`;
  }).join('\n');

  const response = await generateWithModelFallback({
    prompt: `Create a healthy, varied 7-day family meal plan. You have access to the family's calendar schedule — USE IT to tailor meal complexity to their day.
${localeBlock(locale)}
FAMILY PREFERENCES: "${preferences || 'balanced family meals'}"

FAMILY CALENDAR THIS WEEK:
${calendarSummary}

RULES:
- On BUSY days (3+ events, or events during meal prep times 4-6pm), suggest QUICK meals:
  * 15-minute meals, slow-cooker/crockpot meals that can be prepped in the morning, one-pot meals, etc.
  * Include a "quickNote" explaining why you chose an easy meal (e.g. "Soccer practice runs until 5:30pm — this slow cooker meal can be prepped at breakfast")
- On FREE days, suggest more involved or fun family cooking meals
- On weekend mornings with no events, suggest special breakfasts (pancakes, french toast, etc.)

For each day provide breakfast, lunch, and dinner. Each meal must include:
- A short, appealing recipe name
- A concise ingredients list (4-8 items with quantities)
- Step-by-step cooking instructions (3-6 steps)
- Number of servings (typically 4)
- A quickNote if the meal was specifically chosen based on the calendar

CRITICAL LEFTOVER RULE: If any lunch is a leftover from a dinner, it MUST be a leftover of the PREVIOUS day's dinner — never the same day's dinner.

Make meals practical, family-friendly, and use common grocery store ingredients. Vary proteins and cuisines throughout the week.`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          dayName: { type: Type.STRING },
          meals: {
            type: Type.ARRAY,
            items: {
              type: Type.OBJECT,
              properties: {
                type: { type: Type.STRING },
                name: { type: Type.STRING },
                ingredients: { type: Type.ARRAY, items: { type: Type.STRING } },
                steps: { type: Type.ARRAY, items: { type: Type.STRING } },
                servings: { type: Type.NUMBER },
                quickNote: { type: Type.STRING },
              },
              required: ['type', 'name', 'ingredients', 'steps', 'servings'],
            },
          },
        },
        required: ['dayName', 'meals'],
      },
    },
  });

  return parseJSON(response.text) as {
    dayName: string;
    meals: { type: string; name: string; ingredients: string[]; steps: string[]; servings: number; quickNote?: string }[];
  }[];
};

export const planFullEvent = async (details: {
  template: string;
  eventName: string;
  date: string;
  guestCount: string;
  budget: string;
  notes: string;
}, locale?: LocaleHint) => {
  const response = await generateWithModelFallback({
    prompt: `You are an expert event planner. Plan a complete "${details.template}" event with these details:
- Event Name: ${details.eventName}
- Date: ${details.date}
- Expected Guests: ${details.guestCount}
- Budget: ${details.budget}
- Additional Notes: ${details.notes || 'None'}
${localeBlock(locale)}
Generate:
1. A brief event description/itinerary
2. A list of preparation tasks with priorities (HIGH, MEDIUM, LOW) and how many days before the event each should be done
3. Shopping/supply lists with items grouped by list (e.g. "Food & Drinks", "Decorations", "Supplies"). Each list should have items with optional quantities.

Be practical and thorough. Tailor everything to the budget and guest count.`,
    responseMimeType: 'application/json',
    responseSchema: {
      type: Type.OBJECT,
      properties: {
        description: { type: Type.STRING },
        location_suggestion: { type: Type.STRING },
        tasks: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              title: { type: Type.STRING },
              priority: { type: Type.STRING },
              daysBefore: { type: Type.NUMBER },
            },
            required: ['title', 'priority', 'daysBefore'],
          },
        },
        lists: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              title: { type: Type.STRING },
              category: { type: Type.STRING },
              items: {
                type: Type.ARRAY,
                items: {
                  type: Type.OBJECT,
                  properties: {
                    text: { type: Type.STRING },
                    quantity: { type: Type.STRING },
                  },
                  required: ['text'],
                },
              },
            },
            required: ['title', 'category', 'items'],
          },
        },
        tips: { type: Type.ARRAY, items: { type: Type.STRING } },
      },
      required: ['description', 'tasks', 'lists', 'tips'],
    },
  });

  return parseJSON(response.text) as {
    description: string;
    location_suggestion?: string;
    tasks: { title: string; priority: string; daysBefore: number }[];
    lists: { title: string; category: string; items: { text: string; quantity?: string }[] }[];
    tips: string[];
  };
};

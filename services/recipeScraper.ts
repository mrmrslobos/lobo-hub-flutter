/**
 * Recipe scraper – fetches a URL via CORS proxy and extracts recipe data.
 *
 * Strategy:
 *  1. Fetch HTML through a CORS proxy (allorigins)
 *  2. Try to extract JSON-LD schema.org Recipe structured data
 *  3. Fall back to Gemini AI extraction from page text
 */

import { extractRecipeFromText, type LocaleHint } from './gemini';

const CORS_PROXIES = [
  (url: string) => `https://api.allorigins.win/raw?url=${encodeURIComponent(url)}`,
  (url: string) => `https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(url)}`,
];

export interface ScrapedRecipe {
  title: string;
  ingredients: string[];
  steps: string[];
  servings: number;
  prepTime?: string;
  cookTime?: string;
  imageUrl?: string;
  sourceUrl: string;
}

/**
 * Fetch raw HTML from a URL using CORS proxy with fallback.
 */
async function fetchHTML(url: string): Promise<string> {
  for (const proxy of CORS_PROXIES) {
    try {
      const resp = await fetch(proxy(url), { signal: AbortSignal.timeout(15000) });
      if (resp.ok) {
        return await resp.text();
      }
    } catch {
      continue;
    }
  }
  throw new Error('Could not fetch the recipe page. The site may be blocking access.');
}

/**
 * Extract JSON-LD Recipe from HTML.
 * Most recipe sites embed schema.org/Recipe structured data.
 */
function extractJsonLdRecipe(html: string): ScrapedRecipe | null {
  const scriptRegex = /<script[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let match: RegExpExecArray | null;

  while ((match = scriptRegex.exec(html)) !== null) {
    try {
      let data = JSON.parse(match[1]);

      // Handle @graph arrays (common pattern)
      if (data['@graph'] && Array.isArray(data['@graph'])) {
        data = data['@graph'];
      }

      // Flatten to array
      const items = Array.isArray(data) ? data : [data];

      for (const item of items) {
        if (item['@type'] === 'Recipe' || (Array.isArray(item['@type']) && item['@type'].includes('Recipe'))) {
          return parseSchemaRecipe(item);
        }
      }
    } catch {
      continue;
    }
  }

  return null;
}

function parseSchemaRecipe(recipe: any): ScrapedRecipe {
  // Parse ingredients
  const ingredients: string[] = [];
  if (Array.isArray(recipe.recipeIngredient)) {
    recipe.recipeIngredient.forEach((i: any) => {
      if (typeof i === 'string') ingredients.push(i.trim());
    });
  }

  // Parse steps
  const steps: string[] = [];
  if (Array.isArray(recipe.recipeInstructions)) {
    recipe.recipeInstructions.forEach((s: any) => {
      if (typeof s === 'string') {
        steps.push(s.trim());
      } else if (s?.text) {
        steps.push(String(s.text).trim());
      } else if (s?.['@type'] === 'HowToSection' && Array.isArray(s.itemListElement)) {
        s.itemListElement.forEach((sub: any) => {
          if (sub?.text) steps.push(String(sub.text).trim());
        });
      }
    });
  }

  // Parse servings
  let servings = 4;
  if (recipe.recipeYield) {
    const yieldVal = Array.isArray(recipe.recipeYield) ? recipe.recipeYield[0] : recipe.recipeYield;
    const num = parseInt(String(yieldVal), 10);
    if (!isNaN(num) && num > 0) servings = num;
  }

  // Parse image
  let imageUrl: string | undefined;
  if (recipe.image) {
    if (typeof recipe.image === 'string') imageUrl = recipe.image;
    else if (Array.isArray(recipe.image)) {
      const first = recipe.image[0];
      imageUrl = typeof first === 'string' ? first : first?.url;
    }
    else if (recipe.image?.url) imageUrl = recipe.image.url;
  }

  // Parse times (ISO 8601 duration to readable)
  const parseDuration = (d: string | undefined): string | undefined => {
    if (!d) return undefined;
    const m = d.match(/P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?/);
    if (!m) return undefined;
    const days = parseInt(m[1] || '0', 10);
    const hrs = parseInt(m[2] || '0', 10) + days * 24;
    const mins = parseInt(m[3] || '0', 10);
    if (hrs > 0 && mins > 0) return `${hrs}h ${mins}m`;
    if (hrs > 0) return `${hrs}h`;
    if (mins > 0) return `${mins}m`;
    return undefined;
  };

  return {
    title: recipe.name || 'Untitled Recipe',
    ingredients,
    steps,
    servings,
    prepTime: parseDuration(recipe.prepTime),
    cookTime: parseDuration(recipe.cookTime),
    imageUrl,
    sourceUrl: '',
  };
}

/**
 * Extract visible text from HTML for AI fallback.
 */
function htmlToText(html: string): string {
  // Guard against extremely large HTML before running regexes
  const truncated = html.length > 500_000 ? html.slice(0, 500_000) : html;
  // Remove scripts, styles, nav, footer
  let clean = truncated
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<nav[\s\S]*?<\/nav>/gi, '')
    .replace(/<footer[\s\S]*?<\/footer>/gi, '')
    .replace(/<header[\s\S]*?<\/header>/gi, '');

  // Convert <br>, <p>, <li>, <h*> to newlines
  clean = clean
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/?(p|li|h[1-6]|div|tr)[^>]*>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&#\d+;/g, '')
    .replace(/\s+/g, ' ')
    .replace(/\n\s+/g, '\n')
    .trim();

  // Limit to ~4000 chars to keep AI prompt reasonable
  return clean.slice(0, 4000);
}

/**
 * Main entry point: scrape a recipe from a URL.
 */
export async function scrapeRecipe(url: string, locale?: LocaleHint): Promise<ScrapedRecipe> {
  const html = await fetchHTML(url);

  // Try JSON-LD first
  const jsonLd = extractJsonLdRecipe(html);
  if (jsonLd && jsonLd.ingredients.length > 0 && jsonLd.steps.length > 0) {
    jsonLd.sourceUrl = url;
    return jsonLd;
  }

  // Fall back to AI extraction
  const pageText = htmlToText(html);
  if (pageText.length < 50) {
    throw new Error('Could not extract meaningful content from this page.');
  }

  const aiResult = await extractRecipeFromText(pageText, locale);
  return { ...aiResult, sourceUrl: url };
}

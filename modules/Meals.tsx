
import React, { useState, useMemo } from 'react';
import {
  Plus,
  Search,
  Utensils,
  ChevronLeft,
  ChevronRight,
  Sparkles,
  Loader2,
  Trash2,
  List as ListIcon,
  ChefHat,
  Link2,
  Clock,
  Users,
  ArrowLeft,
  ExternalLink,
  Pencil,
  X,
  ShoppingCart,
  CheckCircle2,
  ArrowRight,
  RefreshCw,
  Check,
} from 'lucide-react';
import { MealPlanEntry, Recipe, User, Family, List, ListItem } from '../types';
import { generateMealSuggestions, generateWeeklyMealPlan, generateMealSwap, consolidateIngredients, categorizeListItems, refineWeeklyMealPlan, type LocaleHint } from '../services/gemini';
import AiRefineInput from '../components/AiRefineInput';
import { scrapeRecipe, type ScrapedRecipe } from '../services/recipeScraper';
import { format, addDays, startOfWeek } from 'date-fns';
import { useRealtimeDB } from '../hooks/useRealtimeDB';
import { useLocale } from '../contexts/LocaleContext';
import { Link } from 'react-router-dom';

const Meals: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const { settings } = useLocale();
  const localeHint: LocaleHint = { units: settings.units, country: settings.country };
  const [currentWeek, setCurrentWeek] = useState(startOfWeek(new Date(), { weekStartsOn: 0 }));
  const [isAiLoading, setIsAiLoading] = useState(false);
  const [isScraping, setIsScraping] = useState(false);
  const [scrapeError, setScrapeError] = useState('');
  const [aiError, setAiError] = useState('');
  const [preferences, setPreferences] = useState('');
  const [aiSuggestions, setAiSuggestions] = useState<{ title: string; ingredients: string[]; summary: string }[] | null>(null);
  const [addedSuggestions, setAddedSuggestions] = useState<Set<number>>(new Set());
  const [recipeUrl, setRecipeUrl] = useState('');
  const [view, setView] = useState<'PLAN' | 'RECIPES'>('PLAN');
  const [activeRecipeId, setActiveRecipeId] = useState<string | null>(null);
  const [imgError, setImgError] = useState(false);

  // Inline meal-add state (replaces the old blocking prompt() dialog)
  const [addingMeal, setAddingMeal] = useState<{ dayStr: string; type: string } | null>(null);
  const [addingMealText, setAddingMealText] = useState('');

  // AI Week Planner state
  const [isGeneratingPlan, setIsGeneratingPlan] = useState(false);
  const [planStep, setPlanStep] = useState(0); // 0=idle 1=generating 2=shopping 3=done
  const [weekPlanPrefs, setWeekPlanPrefs] = useState('');
  const [planCreatedListId, setPlanCreatedListId] = useState<string | null>(null);
  const [planError, setPlanError] = useState('');
  const [lastMealPlanDays, setLastMealPlanDays] = useState<{
    dayName: string;
    meals: { type: string; name: string; ingredients: string[]; steps: string[]; servings: number }[];
  }[] | null>(null);

  // Meal swap state
  const [swappingMeal, setSwappingMeal] = useState<{ entryId: string; recipeId?: string; day: Date; type: 'BREAKFAST' | 'LUNCH' | 'DINNER' } | null>(null);
  const [swapPrefs, setSwapPrefs] = useState('');
  const [isSwapping, setIsSwapping] = useState(false);

  // Inline edit state for manually-entered meals
  const [editingMealId, setEditingMealId] = useState<string | null>(null);
  const [editingMealText, setEditingMealText] = useState('');

  // Recipe edit state
  const [isEditRecipeOpen, setIsEditRecipeOpen] = useState(false);
  const [editRecipeTitle, setEditRecipeTitle] = useState('');
  const [editRecipeServings, setEditRecipeServings] = useState('4');
  const [editRecipeIngredients, setEditRecipeIngredients] = useState('');
  const [editRecipeSteps, setEditRecipeSteps] = useState('');
  const [editRecipeTags, setEditRecipeTags] = useState('');

  const weekDays = useMemo(() => {
    return Array.from({ length: 7 }, (_, i) => addDays(currentWeek, i));
  }, [currentWeek]);

  const mealPlans = useMemo(() => {
    return db.mealPlans.filter(p => {
      const pDate = new Date(p.date);
      return p.familyId === family.id && pDate >= currentWeek && pDate < addDays(currentWeek, 7);
    });
  }, [db.mealPlans, currentWeek, family.id]);

  const familyRecipes = useMemo(() => {
    return db.recipes.filter(r => r.familyId === family.id);
  }, [db.recipes, family.id]);

  const activeRecipe = useMemo(() => {
    return db.recipes.find(r => r.id === activeRecipeId);
  }, [db.recipes, activeRecipeId]);

  const addMealEntry = (date: Date, type: 'BREAKFAST' | 'LUNCH' | 'DINNER', customMeal: string) => {
    const newEntry: MealPlanEntry = {
      id: Math.random().toString(36).substr(2, 9),
      familyId: family.id,
      date: date.toISOString(),
      mealType: type,
      customMeal
    };
    const newDb = { ...db, mealPlans: [...db.mealPlans, newEntry] };
    save(newDb, 'added a meal', 'Meals', customMeal);
  };

  const deleteMealEntry = (id: string) => {
    const newDb = { ...db, mealPlans: db.mealPlans.filter(p => p.id !== id) };
    save(newDb, 'removed a meal', 'Meals', '');
  };

  const updateCustomMeal = (id: string, text: string) => {
    if (!text.trim()) return;
    const newDb = { ...db, mealPlans: db.mealPlans.map(p => p.id === id ? { ...p, customMeal: text.trim() } : p) };
    save(newDb, 'updated a meal', 'Meals', text.trim());
    setEditingMealId(null);
  };

  const handleSwapMeal = async () => {
    if (!swappingMeal || !swapPrefs.trim()) return;
    setIsSwapping(true);
    try {
      const currentEntry = db.mealPlans.find(p => p.id === swappingMeal.entryId);
      const currentMealName = currentEntry?.customMeal || db.recipes.find(r => r.id === currentEntry?.recipeId)?.title || '';

      // Gather other meals this week for variety context
      const weekContext = mealPlans
        .filter(p => p.id !== swappingMeal.entryId)
        .map(p => p.customMeal || db.recipes.find(r => r.id === p.recipeId)?.title || '')
        .filter(Boolean);

      const newMeal = await generateMealSwap(
        format(swappingMeal.day, 'EEEE'),
        swappingMeal.type,
        currentMealName,
        swapPrefs.trim(),
        weekContext,
        localeHint
      );

      const newRecipeId = Math.random().toString(36).substr(2, 9);
      const newRecipe: Recipe = {
        id: newRecipeId,
        familyId: family.id,
        title: newMeal.name,
        ingredients: newMeal.ingredients,
        steps: newMeal.steps && newMeal.steps.length > 0 ? newMeal.steps : ['Follow standard preparation for this dish.'],
        servings: newMeal.servings || 4,
        tags: ['AI Swap', swappingMeal.type.charAt(0) + swappingMeal.type.slice(1).toLowerCase()],
      };

      const updatedMealPlans = db.mealPlans.map(p =>
        p.id === swappingMeal.entryId
          ? { ...p, recipeId: newRecipeId, customMeal: undefined }
          : p
      );
      const updatedRecipes = [...db.recipes, newRecipe];

      // Rebuild shopping list from all week entries
      const weekEntries = updatedMealPlans.filter(p => {
        if (p.familyId !== family.id) return false;
        const d = new Date(p.date);
        return d >= currentWeek && d < addDays(currentWeek, 7);
      });
      const allIngredients: string[] = weekEntries.flatMap(p => {
        if (p.customMeal) return [];
        return updatedRecipes.find(r => r.id === p.recipeId)?.ingredients || [];
      });

      let updatedLists = db.lists;
      if (allIngredients.length > 0) {
        const consolidated = await consolidateIngredients(allIngredients.map(i => i.trim()).filter(Boolean), localeHint);
        const rawItems: ListItem[] = consolidated.map(({ name, quantity }) => ({
          id: Math.random().toString(36).substr(2, 9),
          text: name,
          quantity,
          checked: false,
        }));
        const categorized = await categorizeListItems(rawItems.map(i => ({ id: i.id, text: i.text })), 'GROCERY');
        const catMap = new Map(categorized.map(c => [c.id, c.category]));
        const categorizedItems: ListItem[] = rawItems.map(item => ({ ...item, aiCategory: catMap.get(item.id) || 'Other' }));
        updatedLists = db.lists.map(l =>
          l.familyId === family.id && l.title === 'Meal Plan Shopping'
            ? { ...l, items: categorizedItems }
            : l
        );
      }

      save(
        { ...db, recipes: updatedRecipes, mealPlans: updatedMealPlans, lists: updatedLists },
        'swapped a meal',
        'Meals',
        `${currentMealName} → ${newMeal.name}`
      );
      setSwappingMeal(null);
      setSwapPrefs('');
    } catch (e: any) {
      setAiError(e?.message || 'Failed to swap meal. Please try again.');
    } finally {
      setIsSwapping(false);
    }
  };

  const openEditRecipe = (recipe: Recipe) => {
    setEditRecipeTitle(recipe.title);
    setEditRecipeServings(String(recipe.servings));
    setEditRecipeIngredients(recipe.ingredients.join('\n'));
    setEditRecipeSteps(recipe.steps.join('\n\n'));
    setEditRecipeTags(recipe.tags.join(', '));
    setIsEditRecipeOpen(true);
  };

  const updateRecipe = () => {
    if (!activeRecipeId || !editRecipeTitle.trim()) return;
    const newRecipes = db.recipes.map(r =>
      r.id === activeRecipeId
        ? {
            ...r,
            title: editRecipeTitle.trim(),
            servings: parseInt(editRecipeServings) || 4,
            ingredients: editRecipeIngredients.split('\n').map(s => s.trim()).filter(Boolean),
            steps: editRecipeSteps.split('\n\n').map(s => s.trim()).filter(Boolean),
            tags: editRecipeTags.split(',').map(s => s.trim()).filter(Boolean),
          }
        : r
    );
    save({ ...db, recipes: newRecipes }, 'updated a recipe', 'Meals', editRecipeTitle.trim());
    setIsEditRecipeOpen(false);
  };

  const deleteRecipe = (id: string) => {
    const newDb = { ...db, recipes: db.recipes.filter(r => r.id !== id) };
    save(newDb, 'deleted a recipe', 'Meals', '');
    if (activeRecipeId === id) setActiveRecipeId(null);
  };

  const handleAiSuggestions = async () => {
    if (!preferences) return;
    setIsAiLoading(true);
    setAiError('');
    setAiSuggestions(null);
    setAddedSuggestions(new Set());
    try {
      const suggestions = await generateMealSuggestions(preferences, localeHint);
      setAiSuggestions(suggestions);
    } catch (e: any) {
      setAiError(e?.message || 'Failed to get suggestions. Check your API key.');
    } finally {
      setIsAiLoading(false);
    }
  };

  const addSuggestionToRecipeBox = (s: { title: string; ingredients: string[]; summary: string }, index: number) => {
    const newRecipe: Recipe = {
      id: Math.random().toString(36).substr(2, 9),
      familyId: family.id,
      title: s.title,
      ingredients: s.ingredients,
      steps: [s.summary],
      servings: 4,
      tags: ['AI Suggested'],
    };
    save({ ...db, recipes: [...db.recipes, newRecipe] }, 'added recipe from suggestion', 'Meals', s.title);
    setAddedSuggestions(prev => new Set(prev).add(index));
  };

  const clearSuggestions = () => {
    setAiSuggestions(null);
    setAddedSuggestions(new Set());
    setPreferences('');
    setAiError('');
  };

  // Shared helper: turn a days[] response into recipes+entries+shopping list and save to DB
  const applyMealPlanDays = async (
    days: { dayName?: string; meals: { type: string; name: string; ingredients: string[]; steps: string[]; servings: number }[] }[],
    stepCallback?: (step: number) => void,
  ) => {
    const newRecipes: Recipe[] = [];
    const newEntries: MealPlanEntry[] = [];
    const allIngredients: string[] = [];
    const recipeByName = new Map<string, string>();

    days.forEach((day, i) => {
      const dayDate = weekDays[i] || addDays(currentWeek, i);
      day.meals.forEach((meal) => {
        const mealType = (['BREAKFAST', 'LUNCH', 'DINNER'].includes(meal.type.toUpperCase())
          ? meal.type.toUpperCase()
          : 'DINNER') as 'BREAKFAST' | 'LUNCH' | 'DINNER';

        let recipeId = recipeByName.get(meal.name);
        if (!recipeId) {
          recipeId = Math.random().toString(36).substr(2, 9);
          recipeByName.set(meal.name, recipeId);
          newRecipes.push({
            id: recipeId,
            familyId: family.id,
            title: meal.name,
            ingredients: meal.ingredients,
            steps: meal.steps && meal.steps.length > 0 ? meal.steps : ['Follow standard preparation for this dish.'],
            servings: meal.servings || 4,
            tags: ['AI Meal Plan', mealType.charAt(0) + mealType.slice(1).toLowerCase()],
          });
        }

        newEntries.push({
          id: Math.random().toString(36).substr(2, 9),
          familyId: family.id,
          date: dayDate.toISOString(),
          mealType,
          recipeId,
        });
        allIngredients.push(...meal.ingredients);
      });
    });

    stepCallback?.(2);

    const consolidated = await consolidateIngredients(
      allIngredients.map(i => i.trim()).filter(Boolean),
      localeHint,
    );
    const rawItems: ListItem[] = consolidated.map(({ name, quantity }) => ({
      id: Math.random().toString(36).substr(2, 9),
      text: name,
      quantity,
      checked: false,
    }));
    const categorized = await categorizeListItems(
      rawItems.map(i => ({ id: i.id, text: i.text })),
      'GROCERY',
    );
    const catMap = new Map(categorized.map(c => [c.id, c.category]));
    const categorizedItems: ListItem[] = rawItems.map(item => ({
      ...item,
      aiCategory: catMap.get(item.id) || 'Other',
    }));

    const newList: List = {
      id: Math.random().toString(36).substr(2, 9),
      familyId: family.id,
      creatorId: user.id,
      title: 'Meal Plan Shopping',
      items: categorizedItems,
      category: 'GROCERY',
      visibility: 'FAMILY',
    };

    const weekStart = currentWeek;
    const weekEnd = addDays(currentWeek, 7);
    const filteredMealPlans = db.mealPlans.filter(p => {
      if (p.familyId !== family.id) return true;
      const d = new Date(p.date);
      return d < weekStart || d >= weekEnd;
    });
    const filteredLists = db.lists.filter(
      l => !(l.familyId === family.id && l.title === 'Meal Plan Shopping'),
    );

    const newDb = {
      ...db,
      recipes: [...db.recipes, ...newRecipes],
      mealPlans: [...filteredMealPlans, ...newEntries],
      lists: [...filteredLists, newList],
    };
    save(newDb, 'updated week meal plan', 'Meals', `${newRecipes.length} recipes + shopping list`);
    setPlanCreatedListId(newList.id);
    return newList.id;
  };

  const handleGenerateWeekPlan = async () => {
    setIsGeneratingPlan(true);
    setPlanStep(1);
    setPlanError('');
    setPlanCreatedListId(null);
    setLastMealPlanDays(null);
    try {
      const days = await generateWeeklyMealPlan(weekPlanPrefs, localeHint);
      // Normalize to the refine-compatible shape
      const normalizedDays = days.map(d => ({
        dayName: (d as any).dayName || '',
        meals: d.meals.map(m => ({
          type: m.type,
          name: m.name,
          ingredients: m.ingredients,
          steps: (m as any).steps || [],
          servings: (m as any).servings || 4,
        })),
      }));
      setLastMealPlanDays(normalizedDays);
      await applyMealPlanDays(days, setPlanStep);
      setPlanStep(3);
    } catch (e: any) {
      setPlanError(e?.message || 'Failed to generate plan. Check your API key.');
      setPlanStep(0);
    } finally {
      setIsGeneratingPlan(false);
    }
  };

  const handleRefineMealPlan = async (request: string) => {
    if (!lastMealPlanDays) return;
    const refined = await refineWeeklyMealPlan(lastMealPlanDays, request, localeHint);
    const normalized = refined.map(d => ({
      dayName: d.dayName,
      meals: d.meals.map(m => ({
        type: m.type,
        name: m.name,
        ingredients: m.ingredients,
        steps: m.steps || [],
        servings: m.servings || 4,
      })),
    }));
    setLastMealPlanDays(normalized);
    await applyMealPlanDays(normalized);
  };

  const handleScrapeRecipe = async () => {
    if (!recipeUrl) return;
    // Basic URL validation
    let url = recipeUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://' + url;
    }
    setIsScraping(true);
    setScrapeError('');
    try {
      const scraped = await scrapeRecipe(url, localeHint);
      const newRecipe: Recipe = {
        id: Math.random().toString(36).substr(2, 9),
        familyId: family.id,
        title: scraped.title,
        ingredients: scraped.ingredients,
        steps: scraped.steps,
        servings: scraped.servings,
        tags: ['Imported'],
        image: scraped.imageUrl,
      };
      const newDb = { ...db, recipes: [...db.recipes, newRecipe] };
      save(newDb, 'imported a recipe', 'Meals', scraped.title);
      setRecipeUrl('');
      setView('RECIPES');
      setActiveRecipeId(newRecipe.id);
      setImgError(false);
    } catch (e: any) {
      setScrapeError(e?.message || 'Failed to scrape recipe. Try a different URL.');
    } finally {
      setIsScraping(false);
    }
  };

  return (
    <div className="space-y-8">
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Meal Hub</h1>
          <p className="text-stone-500">Plan nutrition and manage family recipes.</p>
        </div>
        <div className="flex bg-white p-1 rounded-2xl border border-stone-200 shadow-sm">
          <button
            onClick={() => { setView('PLAN'); setActiveRecipeId(null); }}
            className={`px-6 py-2 rounded-xl text-sm font-bold transition-all ${view === 'PLAN' ? 'bg-indigo-600 text-white' : 'text-stone-500'}`}
          >
            Weekly Plan
          </button>
          <button
            onClick={() => { setView('RECIPES'); setActiveRecipeId(null); }}
            className={`px-6 py-2 rounded-xl text-sm font-bold transition-all ${view === 'RECIPES' ? 'bg-indigo-600 text-white' : 'text-stone-500'}`}
          >
            Recipe Box
          </button>
        </div>
      </header>

      {/* AI + Scraper Row */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* AI Meal Generator */}
        <div className="bg-gradient-to-br from-amber-500 to-orange-600 rounded-3xl p-6 text-white relative overflow-hidden shadow-xl shadow-amber-100">
          <ChefHat className="absolute right-[-10px] bottom-[-10px] w-32 h-32 opacity-10" />
          <div className="relative z-10">
            <h3 className="text-lg font-bold mb-2 flex items-center">
              <Sparkles size={18} className="mr-2" />
              AI Chef Suggestion
            </h3>
            <p className="text-amber-50 text-xs mb-3">Describe cravings, allergies, or leftover ingredients.</p>
            <div className="flex flex-col gap-2">
              <input
                type="text"
                placeholder="e.g., Quick vegetarian dinners with spinach..."
                value={preferences}
                onChange={(e) => setPreferences(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') handleAiSuggestions(); }}
                className="w-full px-4 py-2.5 bg-white/10 backdrop-blur-md border border-white/20 rounded-xl text-white placeholder:text-white/60 focus:outline-none focus:ring-2 focus:ring-white/50 text-sm"
              />
              <button
                onClick={handleAiSuggestions}
                disabled={isAiLoading || !preferences}
                className="w-full bg-white text-amber-600 px-6 py-2.5 rounded-xl font-bold hover:bg-stone-50 disabled:opacity-50 transition-colors flex items-center justify-center text-sm"
              >
                {isAiLoading ? <Loader2 size={16} className="animate-spin" /> : 'Suggest Meals'}
              </button>
              {aiError && (
                <p className="text-red-200 text-xs bg-red-500/20 px-3 py-2 rounded-lg">{aiError}</p>
              )}
            </div>
          </div>
        </div>

        {/* Recipe Scraper */}
        <div className="bg-gradient-to-br from-emerald-500 to-teal-600 rounded-3xl p-6 text-white relative overflow-hidden shadow-xl shadow-emerald-100">
          <Link2 className="absolute right-[-10px] bottom-[-10px] w-32 h-32 opacity-10" />
          <div className="relative z-10">
            <h3 className="text-lg font-bold mb-2 flex items-center">
              <Link2 size={18} className="mr-2" />
              Import from URL
            </h3>
            <p className="text-emerald-50 text-xs mb-3">Paste a link from any recipe website to import it.</p>
            <div className="flex flex-col gap-2">
              <input
                type="url"
                placeholder="https://www.allrecipes.com/recipe/..."
                value={recipeUrl}
                onChange={(e) => { setRecipeUrl(e.target.value); setScrapeError(''); }}
                onKeyDown={(e) => { if (e.key === 'Enter') handleScrapeRecipe(); }}
                className="w-full px-4 py-2.5 bg-white/10 backdrop-blur-md border border-white/20 rounded-xl text-white placeholder:text-white/60 focus:outline-none focus:ring-2 focus:ring-white/50 text-sm"
              />
              <button
                onClick={handleScrapeRecipe}
                disabled={isScraping || !recipeUrl}
                className="w-full bg-white text-emerald-600 px-6 py-2.5 rounded-xl font-bold hover:bg-stone-50 disabled:opacity-50 transition-colors flex items-center justify-center text-sm"
              >
                {isScraping ? (
                  <>
                    <Loader2 size={16} className="animate-spin mr-2" />
                    Scraping...
                  </>
                ) : 'Import Recipe'}
              </button>
              {scrapeError && (
                <p className="text-red-200 text-xs bg-red-500/20 px-3 py-2 rounded-lg">{scrapeError}</p>
              )}
            </div>
          </div>
        </div>

        {/* AI Week Planner */}
        <div className="bg-gradient-to-br from-violet-600 to-indigo-700 rounded-3xl p-6 text-white relative overflow-hidden shadow-xl shadow-violet-100">
          <ShoppingCart className="absolute right-[-10px] bottom-[-10px] w-32 h-32 opacity-10" />
          <div className="relative z-10">
            <h3 className="text-lg font-bold mb-2 flex items-center">
              <Sparkles size={18} className="mr-2" />
              AI Week Planner
            </h3>
            <p className="text-violet-200 text-xs mb-3">Plans 7 days of meals + builds a categorised shopping list in Lists.</p>

            {planStep === 3 ? (
              /* Success state */
              <div className="space-y-3">
                <div className="flex items-center gap-2 bg-white/10 rounded-xl px-3 py-2">
                  <CheckCircle2 size={16} className="text-emerald-300 shrink-0" />
                  <span className="text-sm font-bold">Week planned, recipes &amp; shopping list created!</span>
                </div>
                <button
                  onClick={() => { setView('RECIPES'); setActiveRecipeId(null); setPlanStep(0); setPlanCreatedListId(null); }}
                  className="flex items-center justify-center gap-2 w-full bg-white text-violet-700 px-4 py-2.5 rounded-xl font-bold text-sm hover:bg-stone-50 transition-colors"
                >
                  <ChefHat size={15} />
                  View Recipes
                  <ArrowRight size={14} />
                </button>
                <Link
                  to="/lists"
                  className="flex items-center justify-center gap-2 w-full bg-white/20 hover:bg-white/30 text-white px-4 py-2 rounded-xl font-bold text-sm transition-colors"
                >
                  <ShoppingCart size={15} />
                  View Shopping List
                </Link>
                <button
                  onClick={() => { setPlanStep(0); setPlanCreatedListId(null); }}
                  className="w-full text-violet-300 text-xs hover:text-white transition-colors"
                >
                  Plan another week
                </button>
              </div>
            ) : (
              <div className="flex flex-col gap-2">
                <input
                  type="text"
                  placeholder="e.g., no pork, kid-friendly, budget meals..."
                  value={weekPlanPrefs}
                  onChange={(e) => setWeekPlanPrefs(e.target.value)}
                  disabled={isGeneratingPlan}
                  className="w-full px-4 py-2.5 bg-white/10 backdrop-blur-md border border-white/20 rounded-xl text-white placeholder:text-white/60 focus:outline-none focus:ring-2 focus:ring-white/50 text-sm disabled:opacity-50"
                />

                {/* Progress steps */}
                {isGeneratingPlan && (
                  <div className="flex items-center gap-2 bg-white/10 rounded-xl px-3 py-2 text-xs">
                    <Loader2 size={14} className="animate-spin shrink-0" />
                    <span>
                      {planStep === 1 ? 'Building your 7-day meal plan...' : 'Building your smart shopping list...'}
                    </span>
                  </div>
                )}

                <button
                  onClick={handleGenerateWeekPlan}
                  disabled={isGeneratingPlan}
                  className="w-full bg-white text-violet-700 px-6 py-2.5 rounded-xl font-bold hover:bg-stone-50 disabled:opacity-50 transition-colors flex items-center justify-center text-sm"
                >
                  {isGeneratingPlan ? <Loader2 size={16} className="animate-spin" /> : 'Plan My Week + Shopping List'}
                </button>

                {planError && (
                  <p className="text-red-200 text-xs bg-red-500/20 px-3 py-2 rounded-lg">{planError}</p>
                )}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* AI Suggestions Panel */}
      {aiSuggestions && (
        <div className="bg-white border border-amber-200 rounded-3xl p-6 shadow-sm">
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-bold text-stone-800 flex items-center gap-2">
              <Sparkles size={16} className="text-amber-500" />
              Chef suggestions for "{preferences || 'your search'}"
            </h3>
            <button
              onClick={clearSuggestions}
              className="text-xs text-stone-400 hover:text-stone-600 font-semibold px-3 py-1.5 rounded-xl hover:bg-stone-100 transition-colors"
            >
              Clear
            </button>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            {aiSuggestions.map((s, i) => {
              const added = addedSuggestions.has(i);
              return (
                <div key={i} className={`rounded-2xl border p-4 flex flex-col gap-3 transition-all ${added ? 'border-emerald-200 bg-emerald-50' : 'border-stone-200 bg-stone-50'}`}>
                  <div className="flex-1">
                    <p className="font-bold text-stone-800 text-sm mb-1">{s.title}</p>
                    <p className="text-xs text-stone-500 leading-relaxed">{s.summary}</p>
                    <ul className="mt-2 space-y-0.5">
                      {s.ingredients.slice(0, 4).map((ing, j) => (
                        <li key={j} className="text-[11px] text-stone-400 flex items-start gap-1">
                          <span className="text-stone-300 shrink-0 mt-0.5">›</span>{ing}
                        </li>
                      ))}
                      {s.ingredients.length > 4 && (
                        <li className="text-[11px] text-stone-400">+{s.ingredients.length - 4} more…</li>
                      )}
                    </ul>
                  </div>
                  <button
                    onClick={() => addSuggestionToRecipeBox(s, i)}
                    disabled={added}
                    className={`w-full py-2 rounded-xl text-xs font-bold transition-colors flex items-center justify-center gap-1.5 ${
                      added
                        ? 'bg-emerald-100 text-emerald-700 cursor-default'
                        : 'bg-amber-500 text-white hover:bg-amber-600'
                    }`}
                  >
                    {added ? '✓ Added to Recipe Box' : '+ Add to Recipe Box'}
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Meal Plan Refinement */}
      {planStep === 3 && lastMealPlanDays && (
        <AiRefineInput
          onRefine={handleRefineMealPlan}
          label="Refine your meal plan"
          placeholder='e.g. "Make Mondays vegetarian" or "Swap fish for chicken throughout"'
        />
      )}

      {view === 'PLAN' ? (
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <h3 className="text-xl font-bold text-stone-800 flex items-center">
              <Utensils size={20} className="mr-2 text-stone-400" />
              Week of {format(currentWeek, 'MMM d')}
            </h3>
            <div className="flex space-x-2">
              <button
                onClick={() => setCurrentWeek(addDays(currentWeek, -7))}
                className="p-2 hover:bg-stone-100 rounded-xl text-stone-500 transition-colors"
              >
                <ChevronLeft size={20} />
              </button>
              <button
                onClick={() => setCurrentWeek(addDays(currentWeek, 7))}
                className="p-2 hover:bg-stone-100 rounded-xl text-stone-500 transition-colors"
              >
                <ChevronRight size={20} />
              </button>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {weekDays.map(day => {
              const dayMeals = mealPlans.filter(p => format(new Date(p.date), 'yyyy-MM-dd') === format(day, 'yyyy-MM-dd'));
              return (
                <div key={day.toISOString()} className="bg-white rounded-3xl border border-stone-200 p-5 shadow-sm space-y-4">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="text-xs font-bold text-stone-400 uppercase tracking-widest">{format(day, 'EEEE')}</p>
                      <p className="text-lg font-bold text-stone-800">{format(day, 'MMM d')}</p>
                    </div>
                  </div>

                  <div className="space-y-3">
                    {(['BREAKFAST', 'LUNCH', 'DINNER'] as const).map(type => {
                      const entry = dayMeals.find(m => m.mealType === type);
                      const dayStr = format(day, 'yyyy-MM-dd');
                      const isAdding = addingMeal?.dayStr === dayStr && addingMeal?.type === type;
                      return (
                        <div key={type} className="group flex flex-col p-2 bg-stone-50 hover:bg-white rounded-xl border border-transparent hover:border-stone-200 transition-all">
                          <span className="text-[10px] font-bold text-stone-400 uppercase tracking-tighter mb-1">{type}</span>
                          {entry ? (
                            swappingMeal?.entryId === entry.id ? (
                              <div className="flex items-center gap-1">
                                <input
                                  type="text"
                                  autoFocus
                                  value={swapPrefs}
                                  onChange={e => setSwapPrefs(e.target.value)}
                                  onKeyDown={e => {
                                    if (e.key === 'Enter' && swapPrefs.trim() && !isSwapping) handleSwapMeal();
                                    else if (e.key === 'Escape') { setSwappingMeal(null); setSwapPrefs(''); }
                                  }}
                                  placeholder="What would you like instead?"
                                  disabled={isSwapping}
                                  className="flex-1 min-w-0 px-2 py-1 text-xs border border-amber-300 rounded-lg focus:outline-none focus:ring-1 focus:ring-amber-400 text-stone-900 bg-white disabled:opacity-50"
                                />
                                <button
                                  onClick={handleSwapMeal}
                                  disabled={!swapPrefs.trim() || isSwapping}
                                  className="p-2 text-amber-600 hover:bg-amber-50 active:bg-amber-100 rounded-lg disabled:opacity-40 transition-colors"
                                >
                                  {isSwapping ? <Loader2 size={16} className="animate-spin" /> : <RefreshCw size={16} />}
                                </button>
                                <button
                                  onClick={() => { setSwappingMeal(null); setSwapPrefs(''); }}
                                  disabled={isSwapping}
                                  className="p-2 text-stone-400 hover:bg-stone-100 active:bg-stone-200 rounded-lg disabled:opacity-40 transition-colors"
                                >
                                  <X size={16} />
                                </button>
                              </div>
                            ) : editingMealId === entry.id ? (
                              <div className="flex items-center gap-1">
                                <input
                                  type="text"
                                  autoFocus
                                  value={editingMealText}
                                  onChange={e => setEditingMealText(e.target.value)}
                                  onKeyDown={e => {
                                    if (e.key === 'Enter') updateCustomMeal(entry.id, editingMealText);
                                    else if (e.key === 'Escape') setEditingMealId(null);
                                  }}
                                  className="flex-1 min-w-0 px-2 py-1 text-xs border border-indigo-300 rounded-lg focus:outline-none focus:ring-1 focus:ring-indigo-400 text-stone-900 bg-white"
                                />
                                <button
                                  onClick={() => updateCustomMeal(entry.id, editingMealText)}
                                  disabled={!editingMealText.trim()}
                                  className="p-2 text-indigo-600 hover:bg-indigo-50 rounded-lg transition-colors disabled:opacity-40"
                                >
                                  <Check size={14} />
                                </button>
                                <button
                                  onClick={() => setEditingMealId(null)}
                                  className="p-2 text-stone-400 hover:bg-stone-100 rounded-lg transition-colors"
                                >
                                  <X size={14} />
                                </button>
                              </div>
                            ) : (
                              <div className="flex justify-between items-center gap-2">
                                {entry.customMeal ? (
                                  <button
                                    onClick={() => { setEditingMealId(entry.id); setEditingMealText(entry.customMeal!); }}
                                    className="text-sm font-semibold text-stone-700 truncate flex-1 text-left hover:text-indigo-600 transition-colors"
                                    title="Tap to edit"
                                  >
                                    {entry.customMeal}
                                  </button>
                                ) : (
                                  <p className="text-sm font-semibold text-stone-700 truncate flex-1">{db.recipes.find(r => r.id === entry.recipeId)?.title}</p>
                                )}
                                <div className="flex items-center shrink-0">
                                  <button
                                    onClick={() => { setSwappingMeal({ entryId: entry.id, recipeId: entry.recipeId, day, type }); setSwapPrefs(''); }}
                                    className="p-2 text-stone-400 hover:text-amber-500 active:text-amber-500 rounded-lg transition-colors"
                                    title="Swap this meal"
                                  >
                                    <RefreshCw size={16} />
                                  </button>
                                  <button
                                    onClick={() => deleteMealEntry(entry.id)}
                                    className="p-2 text-stone-400 hover:text-red-500 active:text-red-500 rounded-lg transition-colors"
                                    title="Delete this meal"
                                  >
                                    <Trash2 size={16} />
                                  </button>
                                </div>
                              </div>
                            )
                          ) : isAdding ? (
                            <div className="flex items-center gap-1">
                              <input
                                type="text"
                                autoFocus
                                value={addingMealText}
                                onChange={e => setAddingMealText(e.target.value)}
                                onKeyDown={e => {
                                  if (e.key === 'Enter' && addingMealText.trim()) {
                                    addMealEntry(day, type, addingMealText.trim());
                                    setAddingMeal(null);
                                    setAddingMealText('');
                                  } else if (e.key === 'Escape') {
                                    setAddingMeal(null);
                                    setAddingMealText('');
                                  }
                                }}
                                placeholder={`${type.charAt(0) + type.slice(1).toLowerCase()}...`}
                                className="flex-1 min-w-0 px-2 py-1 text-xs border border-indigo-300 rounded-lg focus:outline-none focus:ring-1 focus:ring-indigo-400 text-stone-900 bg-white"
                              />
                              <button
                                onClick={() => {
                                  if (addingMealText.trim()) {
                                    addMealEntry(day, type, addingMealText.trim());
                                  }
                                  setAddingMeal(null);
                                  setAddingMealText('');
                                }}
                                className="p-2 text-indigo-600 hover:bg-indigo-50 active:bg-indigo-100 rounded-lg transition-colors"
                              >
                                <Plus size={16} />
                              </button>
                              <button
                                onClick={() => { setAddingMeal(null); setAddingMealText(''); }}
                                className="p-2 text-stone-400 hover:bg-stone-100 active:bg-stone-200 rounded-lg transition-colors"
                              >
                                <X size={16} />
                              </button>
                            </div>
                          ) : (
                            <button
                              onClick={() => { setAddingMeal({ dayStr, type }); setAddingMealText(''); }}
                              className="text-xs text-stone-400 hover:text-indigo-600 active:text-indigo-600 font-semibold flex items-center gap-1 py-1 transition-colors"
                            >
                              <Plus size={14} /> Add
                            </button>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      ) : activeRecipe ? (
        /* Recipe Detail View */
        <div className="space-y-6">
          <button
            onClick={() => setActiveRecipeId(null)}
            className="flex items-center gap-2 text-stone-500 hover:text-stone-800 font-bold text-sm transition-colors"
          >
            <ArrowLeft size={16} />
            Back to Recipe Box
          </button>

          <div className="bg-white rounded-[2.5rem] border border-stone-200 shadow-sm overflow-hidden">
            {/* Hero image */}
            {activeRecipe.image && !imgError ? (
              <div className="h-64 md:h-80 bg-stone-100">
                <img src={activeRecipe.image} onError={() => setImgError(true)} className="w-full h-full object-cover" alt={activeRecipe.title} />
              </div>
            ) : (
              <div className="h-48 md:h-64 bg-gradient-to-br from-stone-900 to-stone-800 flex flex-col items-center justify-center gap-4 px-8">
                <ChefHat size={36} className="text-stone-600 shrink-0" />
                <p className="text-white font-black text-2xl md:text-3xl text-center leading-tight">{activeRecipe.title}</p>
              </div>
            )}

            <div className="p-8 md:p-12 space-y-8">
              {/* Title + meta */}
              <div className="space-y-3">
                <div className="flex flex-wrap gap-2">
                  {activeRecipe.tags.map(tag => (
                    <span key={tag} className="text-[10px] font-black uppercase tracking-widest px-3 py-1 bg-amber-50 text-amber-600 rounded-full">{tag}</span>
                  ))}
                </div>
                <h2 className="text-3xl md:text-4xl font-black text-stone-900 leading-tight">{activeRecipe.title}</h2>
                <div className="flex items-center gap-4 text-stone-400 text-sm">
                  <span className="flex items-center gap-1">
                    <Users size={14} />
                    {activeRecipe.servings} servings
                  </span>
                  <span className="flex items-center gap-1">
                    <ListIcon size={14} />
                    {activeRecipe.ingredients.length} ingredients
                  </span>
                  <span className="flex items-center gap-1">
                    <Clock size={14} />
                    {activeRecipe.steps.length} steps
                  </span>
                </div>
              </div>

              <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
                {/* Ingredients */}
                <div className="bg-stone-50 rounded-3xl p-6 space-y-4">
                  <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest">Ingredients</h3>
                  <ul className="space-y-2">
                    {activeRecipe.ingredients.map((ing, i) => (
                      <li key={i} className="flex items-start gap-3 text-stone-700 text-sm">
                        <div className="w-2 h-2 rounded-full bg-amber-400 mt-1.5 shrink-0" />
                        {ing}
                      </li>
                    ))}
                  </ul>
                </div>

                {/* Steps */}
                <div className="lg:col-span-2 space-y-4">
                  <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest">Instructions</h3>
                  <ol className="space-y-6">
                    {activeRecipe.steps.map((step, i) => (
                      <li key={i} className="flex gap-4">
                        <div className="w-8 h-8 rounded-full bg-indigo-50 text-indigo-600 flex items-center justify-center font-black text-sm shrink-0">
                          {i + 1}
                        </div>
                        <p className="text-stone-700 leading-relaxed pt-1">{step}</p>
                      </li>
                    ))}
                  </ol>
                </div>
              </div>

              <div className="flex items-center justify-between pt-6 border-t border-stone-100">
                <button
                  onClick={() => deleteRecipe(activeRecipe.id)}
                  className="flex items-center gap-2 text-stone-400 hover:text-red-500 font-bold text-sm transition-colors"
                >
                  <Trash2 size={16} />
                  Delete Recipe
                </button>
                <button
                  onClick={() => openEditRecipe(activeRecipe)}
                  className="flex items-center gap-2 text-indigo-600 hover:text-indigo-700 font-bold text-sm transition-colors"
                >
                  <Pencil size={16} />
                  Edit Recipe
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : (
        /* Recipe Grid */
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {familyRecipes.length > 0 ? familyRecipes.map(recipe => (
            <div key={recipe.id} className="bg-white rounded-3xl border border-stone-200 overflow-hidden shadow-sm hover:shadow-md transition-shadow group">
              <div className="h-40 bg-stone-900 relative overflow-hidden">
                {recipe.image ? (
                  <img src={recipe.image} className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300" alt="" />
                ) : (
                  <div className="w-full h-full flex flex-col items-center justify-center gap-2 px-4 bg-gradient-to-br from-stone-900 to-stone-800 group-hover:from-stone-800 group-hover:to-stone-700 transition-all">
                    <ChefHat size={22} className="text-stone-600 shrink-0" />
                    <p className="text-white font-black text-sm text-center leading-snug line-clamp-3">{recipe.title}</p>
                  </div>
                )}
                {recipe.tags?.[0] && (
                  <div className="absolute top-3 right-3 bg-white/90 backdrop-blur-md px-3 py-1 rounded-full text-[10px] font-bold text-stone-800">
                    {recipe.tags[0]}
                  </div>
                )}
                <button
                  onClick={(e) => { e.stopPropagation(); deleteRecipe(recipe.id); }}
                  className="absolute top-3 left-3 p-2.5 bg-white/90 backdrop-blur-md rounded-full text-stone-400 hover:text-red-500 active:text-red-500 opacity-100 md:opacity-0 md:group-hover:opacity-100 transition-opacity"
                >
                  <Trash2 size={15} />
                </button>
              </div>
              <div className="p-5">
                <h4 className="text-lg font-bold text-stone-800 mb-1 line-clamp-1">{recipe.title}</h4>
                <p className="text-stone-500 text-sm line-clamp-2 mb-4">{recipe.steps[0]}</p>
                <div className="flex items-center justify-between pt-3 border-t border-stone-100">
                  <div className="flex items-center gap-3 text-xs text-stone-400">
                    <span>{recipe.ingredients.length} ingredients</span>
                    <span>{recipe.servings} servings</span>
                  </div>
                  <button
                    onClick={() => { setActiveRecipeId(recipe.id); setImgError(false); }}
                    className="text-indigo-600 font-bold text-sm hover:underline"
                  >
                    View
                  </button>
                </div>
              </div>
            </div>
          )) : (
            <div className="col-span-full py-20 text-center">
              <Utensils size={48} className="mx-auto text-stone-200 mb-4" />
              <p className="text-stone-400 font-medium">No recipes saved yet. Import one or try the AI generator!</p>
            </div>
          )}

        </div>
      )}
      {/* Edit Recipe Modal */}
      {isEditRecipeOpen && activeRecipe && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-lg rounded-3xl shadow-2xl overflow-hidden max-h-[90vh] flex flex-col">
            <div className="p-6 border-b border-stone-100 flex items-center justify-between shrink-0">
              <h2 className="text-2xl font-bold text-stone-800">Edit Recipe</h2>
              <button onClick={() => setIsEditRecipeOpen(false)} className="p-2 text-stone-400 hover:text-stone-600 rounded-xl hover:bg-stone-100">
                <X size={20} />
              </button>
            </div>
            <div className="flex-1 overflow-y-auto p-6 space-y-4">
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Recipe Title</label>
                <input type="text" value={editRecipeTitle} onChange={(e) => setEditRecipeTitle(e.target.value)}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900" />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-bold text-stone-700 mb-2">Servings</label>
                  <input type="number" value={editRecipeServings} onChange={(e) => setEditRecipeServings(e.target.value)}
                    className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900" />
                </div>
                <div>
                  <label className="block text-sm font-bold text-stone-700 mb-2">Tags (comma-separated)</label>
                  <input type="text" value={editRecipeTags} onChange={(e) => setEditRecipeTags(e.target.value)}
                    className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900"
                    placeholder="e.g., Healthy, Quick" />
                </div>
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Ingredients (one per line)</label>
                <textarea value={editRecipeIngredients} onChange={(e) => setEditRecipeIngredients(e.target.value)}
                  rows={6}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900 text-sm resize-none"
                  placeholder="1 cup flour&#10;2 eggs&#10;..." />
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Steps (separate with blank lines)</label>
                <textarea value={editRecipeSteps} onChange={(e) => setEditRecipeSteps(e.target.value)}
                  rows={8}
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900 text-sm resize-none"
                  placeholder="Step 1...&#10;&#10;Step 2..." />
              </div>
              <div className="pt-4 flex gap-3">
                <button onClick={() => setIsEditRecipeOpen(false)} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold">Cancel</button>
                <button onClick={updateRecipe} disabled={!editRecipeTitle.trim()} className="flex-1 py-3 bg-indigo-600 text-white rounded-xl font-bold shadow-lg shadow-indigo-100 disabled:opacity-50">Save</button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default Meals;

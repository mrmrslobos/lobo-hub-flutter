/**
 * Module catalogue — defines all available app modules.
 * Shared between App.tsx (routing) and AuthFlow (onboarding module picker).
 * Extracted to avoid circular imports.
 */

export const MODULE_GROUPS = [
  {
    label: 'Family',
    modules: [
      { path: '/chat',      name: 'Chat',       emoji: '💬', desc: 'Family messages & reactions' },
      { path: '/tasks',     name: 'Tasks',      emoji: '✅', desc: 'Shared to-dos & assignments' },
      { path: '/calendar',  name: 'Calendar',   emoji: '📅', desc: 'Events & family schedule' },
      { path: '/chores',    name: 'Chores',     emoji: '🧹', desc: 'Chore charts & tracking' },
      { path: '/lists',     name: 'Lists',      emoji: '📋', desc: 'Shopping & packing lists' },
      { path: '/polls',     name: 'Polls',      emoji: '🗳️', desc: 'Vote on family decisions' },
      { path: '/birthdays', name: 'Occasions',  emoji: '🎉', desc: 'Birthdays, anniversaries & special dates' },
      { path: '/photos',    name: 'Photos',     emoji: '📸', desc: 'Family album & milestones' },
      { path: '/location',  name: 'Location',   emoji: '📍', desc: 'See where everyone is' },
      { path: '/health',    name: 'Health',     emoji: '❤️', desc: 'Health records & emergency info' },
    ],
  },
  {
    label: 'Lifestyle',
    modules: [
      { path: '/meals',          name: 'Meals',          emoji: '🍽️', desc: 'Meal planning & recipes' },
      { path: '/fitness',        name: 'Fitness',        emoji: '💪', desc: 'Health & workout tracking' },
      { path: '/period-tracker', name: 'Period Tracker', emoji: '🌸', desc: 'Cycle & wellness tracking' },
      { path: '/devotional',     name: 'Devotional',     emoji: '📖', desc: 'Daily faith & reflection' },
      { path: '/prayer-wall',    name: 'Prayer Wall',    emoji: '🙏', desc: 'Gratitude & prayer sharing' },
    ],
  },
  {
    label: 'Money',
    modules: [
      { path: '/budget',  name: 'Budget',  emoji: '💰', desc: 'Family expense tracking' },
      { path: '/rewards', name: 'Rewards', emoji: '🎁', desc: 'Earn & redeem rewards' },
    ],
  },
] as const;

export const ALL_MODULE_PATHS = MODULE_GROUPS.flatMap(g => g.modules.map(m => m.path));

/** Sensible defaults for new families (shown pre-selected in onboarding). */
export const ESSENTIAL_MODULES = ['/tasks', '/calendar', '/chores', '/rewards', '/meals'];

export function getModulePath(moduleName: string): string {
  for (const group of MODULE_GROUPS) {
    const match = group.modules.find((m) => m.name === moduleName);
    if (match) return match.path;
  }
  return '/';
}

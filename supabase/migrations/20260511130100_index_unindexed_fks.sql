-- Cover unindexed FK columns flagged by perf advisor `0001`. All four are
-- `family_id` FKs that get joined on every family-scoped query.
--
-- Non-CONCURRENT (apply_migration wraps in a transaction). Tables are
-- small in prod (≤ a few hundred rows) so the lock window is negligible.

CREATE INDEX IF NOT EXISTS daily_habit_completions_family_id_idx
  ON public.daily_habit_completions (family_id);

CREATE INDEX IF NOT EXISTS fitness_family_id_idx
  ON public.fitness (family_id);

CREATE INDEX IF NOT EXISTS reminder_jobs_family_id_idx
  ON public.reminder_jobs (family_id);

CREATE INDEX IF NOT EXISTS rewards_family_id_idx
  ON public.rewards (family_id);

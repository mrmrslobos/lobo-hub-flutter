/**
 * Generate a collision-resistant client ID for local + Supabase upserts.
 * Prefers crypto.randomUUID() when available and falls back to timestamp+
 * random entropy for older runtimes.
 */
export function createId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `id_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}

import { useState, useEffect, useCallback } from 'react';
import { getDB, saveDB as rawSaveDB, notifyDBUpdate, DB, ChangeInfo, onDBUpdate } from '../services/db';
import { User } from '../types';

/**
 * Hook that provides a reactive DB + a save function that broadcasts changes
 * to other family members via Supabase Realtime.
 *
 * Usage:
 *   const { db, save } = useRealtimeDB(user);
 *   // save(newDb)                           — silent save (no notification)
 *   // save(newDb, 'checked off', 'Lists', 'Milk')  — save + broadcast
 */
export function useRealtimeDB(user: User) {
  const [db, setDb] = useState<DB>(getDB());

  // Re-read localStorage whenever an external refresh happens
  useEffect(() => {
    return onDBUpdate(() => setDb(getDB()));
  }, []);

  const save = useCallback(
    (newDb: DB, action?: string, module?: string, detail?: string) => {
      const change: ChangeInfo | undefined = action
        ? {
            userId: user.id,
            userName: user.name,
            action,
            module: module || '',
            detail: detail || '',
          }
        : undefined;

      rawSaveDB(newDb, change);
      setDb(newDb);
      // Notify all other modules on this device so their derived data
      // updates immediately without waiting for the cloud broadcast round-trip.
      notifyDBUpdate();
    },
    [user.id, user.name],
  );

  return { db, save };
}

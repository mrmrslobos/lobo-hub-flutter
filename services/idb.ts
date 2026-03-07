/**
 * Lightweight IndexedDB key-value wrapper.
 * Replaces localStorage for the main app DB so storage limits are no longer
 * an issue on large families (localStorage is capped at ~5 MB per origin).
 *
 * The API intentionally mirrors localStorage (get/set/delete) so migration
 * is straightforward.  All operations are async but the main DB service keeps
 * an in-memory cache so modules can still call getDB() synchronously.
 */

const IDB_NAME = 'lobohub';
const IDB_VERSION = 1;
const STORE_NAME = 'keyval';

let _dbPromise: Promise<IDBDatabase> | null = null;

function openIDB(): Promise<IDBDatabase> {
  if (_dbPromise) return _dbPromise;
  _dbPromise = new Promise<IDBDatabase>((resolve, reject) => {
    if (typeof indexedDB === 'undefined') {
      reject(new Error('IndexedDB not available'));
      return;
    }
    const req = indexedDB.open(IDB_NAME, IDB_VERSION);
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains(STORE_NAME)) {
        req.result.createObjectStore(STORE_NAME);
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => {
      _dbPromise = null; // allow retry
      reject(req.error);
    };
    req.onblocked = () => {
      _dbPromise = null;
      reject(new Error('IDB upgrade blocked by another tab'));
    };
  });
  return _dbPromise;
}

export async function idbGet<T>(key: string): Promise<T | undefined> {
  try {
    const db = await openIDB();
    return new Promise<T | undefined>((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readonly');
      const req = tx.objectStore(STORE_NAME).get(key);
      req.onsuccess = () => resolve(req.result as T | undefined);
      req.onerror = () => reject(req.error);
    });
  } catch {
    return undefined;
  }
}

export async function idbSet<T>(key: string, value: T): Promise<void> {
  try {
    const db = await openIDB();
    return new Promise<void>((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readwrite');
      tx.objectStore(STORE_NAME).put(value, key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  } catch (err) {
    console.warn('[IDB] Write failed, data may be lost on reload:', err);
  }
}

export async function idbDelete(key: string): Promise<void> {
  try {
    const db = await openIDB();
    return new Promise<void>((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readwrite');
      tx.objectStore(STORE_NAME).delete(key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    // Ignore — nothing to delete
  }
}

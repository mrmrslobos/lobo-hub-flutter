const CACHE_NAME = 'lobohub-cache-v3';
const APP_SHELL = ['/', '/manifest.webmanifest'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

// Handle notification clicks - open the app to the relevant module
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const urlPath = event.notification.data?.path || '/';
  const targetUrl = self.location.origin + '/#' + urlPath;

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      // If the app is already open, send it a message to navigate without a
      // full page reload (avoids clearing auth state).
      for (const client of clients) {
        if (client.url.startsWith(self.location.origin)) {
          client.focus();
          client.postMessage({ type: 'NAVIGATE', path: urlPath });
          return;
        }
      }
      // App is closed — open a new window at the target hash URL.
      return self.clients.openWindow(targetUrl);
    })
  );
});

// Handle server-sent web push notifications (requires VAPID setup)
self.addEventListener('push', (event) => {
  let data = { title: 'FamilyHub', body: '', path: '/', tag: 'lobohub-general' };
  try { data = { ...data, ...event.data.json() }; } catch { /* fallback */ }

  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: '/icons/icon-192.svg',
      badge: '/icons/icon-192.svg',
      tag: data.tag,
      data: { path: data.path },
      vibrate: [100, 50, 100],
      requireInteraction: false,
    })
  );
});

// Listen for messages from the app to show notifications
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SHOW_NOTIFICATION') {
    const { title, body, path, module } = event.data;
    self.registration.showNotification(title, {
      body,
      icon: '/icons/icon-192.svg',
      badge: '/icons/icon-192.svg',
      tag: `lobohub-${module || 'general'}`,
      data: { path: path || '/' },
      vibrate: [100, 50, 100],
    });
  }
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const requestUrl = new URL(event.request.url);
  const isHttpRequest = requestUrl.protocol === 'http:' || requestUrl.protocol === 'https:';
  const isSameOrigin = requestUrl.origin === self.location.origin;
  const isEnvConfig = requestUrl.pathname === '/env-config.js';

  // Ignore extension/browser-internal requests (e.g. chrome-extension://) and
  // cross-origin requests so Cache API put() only receives supported URLs.
  if (!isHttpRequest || !isSameOrigin || isEnvConfig) {
    return;
  }

  // Stale-While-Revalidate: serve the cached version immediately so the app
  // loads fast, then fetch the latest version in the background and update
  // the cache for the next visit.  Without this, a Cache-First strategy would
  // serve a stale index.html forever (Vite hashes JS/CSS but not index.html),
  // leaving beta testers stuck on old builds until they manually clear cache.
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      // Always kick off a background network fetch to refresh the cache.
      const fetchPromise = fetch(event.request)
        .then((networkResponse) => {
          if (networkResponse.ok) {
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(event.request, networkResponse.clone());
            });
          }
          return networkResponse;
        })
        .catch(() => {
          // Only serve the cached shell for page navigations — not for API or
          // asset fetches.  Returning index.html for a failed asset/API request
          // would cause the app to try parsing HTML as JSON and crash.
          if (event.request.mode === 'navigate') {
            return caches.match('/');
          }
          // For non-navigation requests let the failure propagate so the app's
          // own error handling can deal with it.
        });

      // Keep the SW alive until the background cache update is written.
      // Without this the browser may terminate the SW before cache.put()
      // finishes, silently discarding the update.
      event.waitUntil(fetchPromise);

      // Return the cached response immediately if we have one; otherwise wait
      // for the network (first visit or uncached resource).
      return cachedResponse || fetchPromise;
    })
  );
});

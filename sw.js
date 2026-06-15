const CACHE     = 'dither-v13';
const API_CACHE = 'dither-api-v13';

const STATIC = [
  '/',
  '/app.js',
  '/style.css',
  '/manifest.json',
  '/favicons/icon.svg',
  '/favicons/wordmark-horizontal.svg',
  '/favicons/favicon-32.png',
  '/favicons/favicon-16.png',
  '/favicons/favicon-180.png',
  '/favicons/favicon-192.png',
  '/favicons/favicon-512.png',
  '/favicons/maskable-192.png',
  '/favicons/maskable-512.png',
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(STATIC)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE && k !== API_CACHE).map(k => caches.delete(k)))
  ));
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // ── API calls ────────────────────────────────────────────────────────────────
  if (url.pathname.startsWith('/api')) {
    // GETs: network-first, fall back to last cached response when offline
    if (e.request.method === 'GET') {
      e.respondWith(
        fetch(e.request.url, {
          headers: Object.fromEntries(e.request.headers.entries()),
        })
          .then(res => {
            if (res.ok) {
              const clone = res.clone();
              caches.open(API_CACHE).then(c => c.put(e.request.url, clone));
            }
            return res;
          })
          .catch(async () => {
            const cached = await caches.open(API_CACHE).then(c => c.match(e.request.url));
            // Return cached data, or an empty array so the app renders gracefully
            return cached || new Response('[]', {
              status: 200,
              headers: { 'Content-Type': 'application/json' },
            });
          })
      );
    }
    // Mutations (POST/PUT/DELETE): pass straight to network — fail naturally when offline
    return;
  }

  // ── Static assets: cache-first ───────────────────────────────────────────────
  e.respondWith(
    caches.match(e.request).then(cached => {
      const fresh = fetch(e.request).then(res => {
        if (res.ok) caches.open(CACHE).then(c => c.put(e.request, res.clone()));
        return res;
      });
      return cached || fresh;
    })
  );
});

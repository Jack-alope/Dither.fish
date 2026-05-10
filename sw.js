const CACHE = 'dither-v5';
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
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
  ));
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Always go network-first for API calls
  if (url.pathname.startsWith('/api')) return;

  // Cache-first for static assets
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

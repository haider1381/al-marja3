/* Only public, explicitly listed assets are cached. Never cache API/auth/PDF/AI traffic. */
const CACHE_PREFIX = 'medbrain-pwa-';
const CACHE_NAME = CACHE_PREFIX + 'v1';
const ROOT = new URL('./', self.location.href);
const PUBLIC_PATHS = ['offline.html', 'assets/app-icon-192.png', 'assets/app-icon-512.png', 'assets/app-icon-maskable-512.png', 'assets/apple-touch-icon.png'];
const PUBLIC_URLS = new Set(PUBLIC_PATHS.map(path => new URL(path, ROOT).href));
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll([...PUBLIC_URLS])));
  // New workers activate after older app windows close; never interrupt unsaved work.
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter(name => name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME).map(name => caches.delete(name)));
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', event => {
  const request = event.request, url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== ROOT.origin || !url.pathname.startsWith(ROOT.pathname)) return;
  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      try { return await fetch(request, { cache: 'no-cache' }); }
      catch (_) {
        const offline = await caches.match(new URL('offline.html', ROOT).href);
        return offline || new Response('Medbrain يحتاج اتصالًا بالإنترنت. أعد المحاولة بعد الاتصال.', {status:503,headers:{'Content-Type':'text/plain; charset=utf-8'}});
      }
    })());
    return;
  }
  // No arbitrary runtime caching: query URLs, lecture content and signed links are excluded.
  if (!PUBLIC_URLS.has(url.href)) return;
  event.respondWith((async () => {
    const cached = await caches.match(request);
    if (cached) return cached;
    const response = await fetch(request);
    if (response.ok && response.type === 'basic') {
      const cache = await caches.open(CACHE_NAME);
      try { await cache.put(request, response.clone()); } catch (_) {}
    }
    return response;
  })());
});
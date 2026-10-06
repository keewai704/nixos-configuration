self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin || event.request.mode === 'navigate') return;
  if (!/^\/(api|pkg|canvaskit|assets)\//.test(url.pathname) && url.pathname !== '/mcp') return;
  url.pathname = '/openpencil' + url.pathname;
  event.respondWith(fetch(new Request(url, event.request)));
});

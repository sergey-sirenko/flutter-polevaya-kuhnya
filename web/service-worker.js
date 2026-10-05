// Retire the previous site's root worker when Flutter takes over its origin.
// No registration from Flutter, no storage/cache deletion, no forced reload.
self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    await self.clients.claim();
    await self.registration.unregister();
  })());
});
// Without a fetch handler existing clients use the network until they close.

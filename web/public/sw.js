// 推送通知：收到就显示，点了打开对应页面（已经开着 Badie 就切过去）。不缓存任何东西，只管推送
self.addEventListener('push', (event) => {
  const data = event.data ? event.data.json() : {};
  event.waitUntil(
    self.registration.showNotification(data.title || 'Badie', {
      body: data.body,
      icon: '/icon-192.png',
      tag: data.link,
      data: { link: (data.link || '/').replace(/^\/app\//, '/') },
    }),
  );
});

// 装好就接管已经打开的页面，点通知时才能把它切到对应页面
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL(event.notification.data.link, self.location.origin).href;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      const open = windows.find((w) => new URL(w.url).origin === self.location.origin);
      if (!open) return self.clients.openWindow(url);
      return open.focus().then((w) => w.navigate(url)).catch(() => self.clients.openWindow(url));
    }),
  );
});

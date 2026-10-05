/* Register click handling before importing Firebase Messaging as required by FCM. */
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
    const existing = clients.find((client) => 'focus' in client);
    return existing ? existing.focus() : self.clients.openWindow('/');
  }));
});
/* The Firebase web config is public client configuration, not a server credential. */
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCrQXS_3otSHGfPZnOoQxOim8rWCD1i2kw',
  authDomain: 'office-gossip.firebaseapp.com',
  projectId: 'office-gossip',
  storageBucket: 'office-gossip.firebasestorage.app',
  messagingSenderId: '128886034333',
  appId: '1:128886034333:web:7bbd726aef472e6d10a974',
});

const messaging = firebase.messaging();
messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  self.registration.showNotification(notification.title || 'Office Gossip', {
    body: notification.body || 'There is something new in your community.',
    icon: '/favicon.svg',
    data: payload.data || {},
  });
});

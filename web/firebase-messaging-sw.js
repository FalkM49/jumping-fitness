// Фоновые push-уведомления веб-версии (Firebase Cloud Messaging).
// Показывает уведомление, когда приложение закрыто или свёрнуто, и по тапу
// открывает приложение. Версия SDK — та же, что у firebase_core_web.
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');

// Публичные настройки веб-приложения (те же, что в lib/firebase_options.dart).
firebase.initializeApp({
  apiKey: 'AIzaSyCYpHpJu1TrDOSEjrWMwlh59siPzu5WIJo',
  appId: '1:792093077664:web:8c2323b4737ea1f25fd9c5',
  messagingSenderId: '792093077664',
  projectId: 'jumpingfitness',
  authDomain: 'jumpingfitness.firebaseapp.com',
  storageBucket: 'jumpingfitness.firebasestorage.app',
});

// Уведомления с полем notification браузер показывает сам.
firebase.messaging();

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if ('focus' in client) return client.focus();
      }
      return self.clients.openWindow('/');
    }),
  );
});

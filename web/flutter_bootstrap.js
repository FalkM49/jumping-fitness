{{flutter_js}}
{{flutter_build_config}}

// Устаревший service worker Flutter больше не регистрируем (docs/09, шаг 7).
// У тех, кто открывал сайт раньше, он ещё установлен и может отдавать старые
// файлы из своего кэша, — снимаем его. Push-воркер firebase-messaging-sw.js
// не трогаем.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(function (registrations) {
    registrations.forEach(function (registration) {
      var worker =
        registration.active || registration.waiting || registration.installing;
      if (worker && worker.scriptURL.indexOf('flutter_service_worker.js') !== -1) {
        registration.unregister();
      }
    });
  });
}

_flutter.loader.load();

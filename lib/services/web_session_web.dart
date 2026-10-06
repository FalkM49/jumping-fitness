import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _aliveKey = 'jf.alive';
const _routeKey = 'jf.route';

/// Метка «вкладка жива» в sessionStorage: ставится при старте, снимается
/// на `pagehide` (закрытие, переход, обычная перезагрузка). Если при старте
/// метка уже стоит — прошлый сеанс оборвался без `pagehide`: так Safari
/// перезагружает вкладку, которой не хватило памяти.
///
/// Возвращает экран, на котором это случилось, или `null`.
String? startSessionAndTakeUnexpectedReload() {
  try {
    final storage = web.window.sessionStorage;
    final crashed = storage.getItem(_aliveKey) == '1';
    final route = storage.getItem(_routeKey);
    storage.setItem(_aliveKey, '1');

    web.window.addEventListener(
      'pagehide',
      ((web.Event _) => storage.removeItem(_aliveKey)).toJS,
    );
    // Возврат из кэша «назад/вперёд» — та же вкладка, метку ставим снова.
    web.window.addEventListener(
      'pageshow',
      ((web.Event _) => storage.setItem(_aliveKey, '1')).toJS,
    );
    return crashed ? (route ?? '/') : null;
  } on Object {
    return null;
  }
}

/// Запомнить текущий экран — чтобы после перезагрузки знать, где она была.
void rememberRoute(String route) {
  try {
    web.window.sessionStorage.setItem(_routeKey, route);
  } on Object {
    // Хранилище недоступно (приватный режим) — не страшно.
  }
}

String userAgent() => web.window.navigator.userAgent;

/// Safari отобрал у страницы WebGL-контекст (событие шлёт web/index.html).
void onWebglLost(void Function() callback) {
  web.window.addEventListener(
    'jf-webgl-lost',
    ((web.Event _) => callback()).toJS,
  );
}

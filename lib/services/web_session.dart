// Сведения о вкладке браузера для журнала ошибок (docs/09, шаг 1.2).
// На телефоне и в тестах — заглушки.
export 'web_session_stub.dart'
    if (dart.library.js_interop) 'web_session_web.dart';

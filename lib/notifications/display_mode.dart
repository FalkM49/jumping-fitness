// Открыт ли сайт как установленное приложение (с экрана «Домой»).
// На телефоне и в тестах — всегда false: там это не имеет смысла.
export 'display_mode_stub.dart'
    if (dart.library.js_interop) 'display_mode_web.dart';

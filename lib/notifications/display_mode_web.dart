import 'package:web/web.dart' as web;

/// Сайт открыт с иконки на экране «Домой» (PWA), а не во вкладке браузера.
/// Только так iPhone разрешает веб-push (iOS 16.4+).
bool isStandaloneWebApp() =>
    web.window.matchMedia('(display-mode: standalone)').matches;

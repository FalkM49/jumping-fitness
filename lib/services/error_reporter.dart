import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Отправка отчёта на сервер (функция `reportClientError`).
typedef ErrorSender = Future<void> Function(Map<String, Object?> report);

/// Журнал ошибок веб-версии (docs/09, шаг 1): в Safari на iPhone консоль
/// без Mac не посмотреть, поэтому ошибки приложение присылает само —
/// в журнал функции в Yandex Cloud.
///
/// Включается только в веб-сборке release ([installErrorReporter]).
/// Отправка «выстрелил и забыл»: сбой отправки не влияет на приложение.
class ErrorReporter {
  ErrorReporter({
    required this._send,
    required this._context,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ErrorSender _send;
  final Map<String, Object?> Function() _context;
  final DateTime Function() _clock;

  /// Одно и то же сообщение — не чаще раза в [repeatWindow].
  static const repeatWindow = Duration(seconds: 10);
  final _lastSent = <String, DateTime>{};

  /// Отправить отчёт. [kind] — `flutter_error`, `zone_error`,
  /// `function_error`, `unexpected_reload`, `webgl_lost`.
  void report(
    String kind,
    Object error, [
    StackTrace? stack,
    Map<String, Object?> extra = const {},
  ]) {
    final message = error.toString();
    final key = '$kind|$message';
    final now = _clock();
    final last = _lastSent[key];
    if (last != null && now.difference(last) < repeatWindow) return;
    _lastSent[key] = now;
    if (_lastSent.length > 200) _lastSent.clear();

    try {
      final payload = {
        ..._context(),
        ...extra,
        'kind': kind,
        'message': message,
        'stack': stack?.toString(),
      };
      unawaited(_send(payload).catchError((Object _) {}));
    } on Object {
      // Журнал не должен ронять приложение.
    }
  }
}

ErrorReporter? _reporter;

/// Отчёт об ошибке, если журнал включён; иначе ничего не делает
/// (Android, debug-сборка, тесты).
void reportClientError(
  String kind,
  Object error, [
  StackTrace? stack,
  Map<String, Object?> extra = const {},
]) => _reporter?.report(kind, error, stack, extra);

/// Включить журнал: перехват необработанных ошибок Flutter и зоны.
/// Прежние обработчики продолжают работать.
void installErrorReporter(ErrorReporter reporter) {
  _reporter = reporter;

  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    reporter.report('flutter_error', details.exception, details.stack, {
      'library': details.library,
    });
    previousFlutter?.call(details);
  };

  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    reporter.report('zone_error', error, stack);
    return previousPlatform?.call(error, stack) ?? false;
  };
}

@visibleForTesting
void resetErrorReporterForTest() => _reporter = null;

/// Текущий экран — для отчётов и для обнаружения перезагрузок (шаг 1.2).
class AppRouteTracker extends NavigatorObserver {
  AppRouteTracker({this.onChange});

  /// Вызывается при каждой смене экрана с его именем.
  final void Function(String route)? onChange;

  static String current = '/';

  static String nameOf(Route<dynamic>? route) {
    if (route == null) return '/';
    final name = route.settings.name;
    if (name != null) return name;
    return route is PopupRoute ? 'dialog' : route.runtimeType.toString();
  }

  void _set(Route<dynamic>? route) {
    current = nameOf(route);
    onChange?.call(current);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _set(newRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);
}

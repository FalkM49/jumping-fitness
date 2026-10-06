import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/services/error_reporter.dart';

void main() {
  late List<Map<String, Object?>> sent;
  late DateTime now;

  ErrorReporter reporter() => ErrorReporter(
    send: (report) async => sent.add(report),
    context: () => {'route': '/', 'standalone': true, 'appVersion': '1.0.0+1'},
    clock: () => now,
  );

  setUp(() {
    sent = [];
    now = DateTime.utc(2026, 10, 6, 12);
  });

  tearDown(resetErrorReporterForTest);

  test('отчёт: тип, текст, стек и сведения об устройстве', () {
    reporter().report(
      'function_error',
      StateError('сломалось'),
      StackTrace.current,
      {'function': 'bookTraining'},
    );
    expect(sent, hasLength(1));
    final r = sent.single;
    expect(r['kind'], 'function_error');
    expect(r['message'], contains('сломалось'));
    expect(r['stack'], isNotNull);
    expect(r['function'], 'bookTraining');
    expect(r['standalone'], true);
    expect(r['appVersion'], '1.0.0+1');
  });

  test('одно и то же сообщение — не чаще раза в 10 секунд', () {
    final r = reporter();
    r.report('zone_error', 'x');
    r.report('zone_error', 'x');
    r.report('zone_error', 'другое');
    expect(sent, hasLength(2));
    now = now.add(const Duration(seconds: 11));
    r.report('zone_error', 'x');
    expect(sent, hasLength(3));
  });

  test('сбой отправки не выходит наружу', () {
    final r = ErrorReporter(
      send: (_) => Future.error(Exception('нет сети')),
      context: () => const {},
    );
    expect(() => r.report('zone_error', 'x'), returnsNormally);
  });

  test('без установки reportClientError ничего не делает', () {
    expect(() => reportClientError('zone_error', 'x'), returnsNormally);
    expect(sent, isEmpty);
  });

  test('ошибки Flutter уходят в журнал, прежний обработчик вызывается', () {
    final previous = FlutterError.onError;
    var previousCalls = 0;
    FlutterError.onError = (_) => previousCalls++;
    addTearDown(() => FlutterError.onError = previous);

    installErrorReporter(reporter());
    FlutterError.onError!(
      FlutterErrorDetails(exception: Exception('в build'), library: 'widgets'),
    );
    expect(sent.single['kind'], 'flutter_error');
    expect(sent.single['library'], 'widgets');
    expect(previousCalls, 1);

    reportClientError('webgl_lost', 'контекст потерян');
    expect(sent.last['kind'], 'webgl_lost');
  });

  testWidgets('текущий экран отслеживается по маршрутам', (tester) async {
    final seen = <String>[];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [AppRouteTracker(onChange: seen.add)],
        home: const SizedBox(),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SizedBox(),
        ),
      ),
    );
    navigator.currentState!.pushNamed('/settings');
    await tester.pumpAndSettle();
    expect(AppRouteTracker.current, '/settings');

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(AppRouteTracker.current, '/');
    expect(seen, containsAllInOrder(['/', '/settings', '/']));
  });
}

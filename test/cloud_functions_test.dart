import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/services/cloud_functions.dart';

void main() {
  test('отказ по правилу: текст сервера и причина для значка (i)', () {
    final failure = cloudFunctionFailureFrom(
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Свободных мест нет.',
        details: {'reason': 'full'},
      ),
    );
    expect(failure.message, 'Свободных мест нет.');
    expect(failure.code, 'failed-precondition');
    expect(failure.reason, 'full');
  });

  test('сбой связи — общий текст, без причины', () {
    final failure = cloudFunctionFailureFrom(
      FirebaseFunctionsException(code: 'unavailable', message: 'UNAVAILABLE'),
    );
    expect(failure.message, contains('Нет связи'));
    expect(failure.reason, isNull);
  });

  test('непредвиденная ошибка сервера не показывает технический текст', () {
    final failure = cloudFunctionFailureFrom(
      FirebaseFunctionsException(code: 'internal', message: 'TypeError: x'),
    );
    expect(failure.message, isNot(contains('TypeError')));
  });

  test('веб: HTTP-код, приписанный браузером, из текста убирается', () {
    for (final raw in [
      'Вы уже записаны на эту тренировку. [400]',
      'Вы уже записаны на эту тренировку. (400)',
    ]) {
      final failure = cloudFunctionFailureFrom(
        FirebaseFunctionsException(code: 'failed-precondition', message: raw),
      );
      expect(failure.message, 'Вы уже записаны на эту тренировку.');
    }
  });
}
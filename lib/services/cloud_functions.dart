import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_bootstrap.dart' show useFirebaseEmulators;

/// Регион Cloud Functions — тот же, что в functions/src/config.ts.
const String cloudFunctionsRegion = 'europe-west3';

/// Экземпляр Cloud Functions нужного региона.
FirebaseFunctions regionalFunctions() =>
    FirebaseFunctions.instanceFor(region: cloudFunctionsRegion);

/// Адрес шлюза серверных функций в Yandex Cloud (functions/src/yandex.ts,
/// выводит `npm run deploy:yc`). Пусто — функции Firebase (эмулятор).
/// Другой адрес при сборке: `--dart-define=FUNCTIONS_API_URL=https://…`.
const String functionsApiUrl = String.fromEnvironment(
  'FUNCTIONS_API_URL',
  defaultValue: useFirebaseEmulators
      ? ''
      : 'https://d5dg4jlie0pflgjhlb0c.fovt0b64.apigw.yandexcloud.net',
);

/// Вызов функции [name]: в Yandex Cloud — `<адрес шлюза>/<имя>`, протокол
/// тот же, что у Firebase (токен входа плагин добавляет сам).
HttpsCallable callableFor(FirebaseFunctions functions, String name) =>
    functionsApiUrl.isEmpty
    ? functions.httpsCallable(name)
    : functions.httpsCallableFromUrl('$functionsApiUrl/$name');

/// Ошибка вызова Cloud Function с текстом для пользователя.
class CloudFunctionFailure implements Exception {
  const CloudFunctionFailure(this.message, [this.code, this.reason]);

  final String message;

  /// Код ошибки функции (`permission-denied`, `failed-precondition`…).
  final String? code;

  /// Машинная причина отказа по бизнес-правилу (`full`, `frozen`,
  /// `cancel_window_passed`…) — список в docs/04_cloud_functions.md.
  final String? reason;

  @override
  String toString() => 'CloudFunctionFailure($code/$reason: $message)';
}

/// Код ошибки функции → текст. Для «ожидаемых» отказов берём сообщение
/// самой функции (она пишет по-русски), для остальных — общий текст.
CloudFunctionFailure cloudFunctionFailureFrom(
  FirebaseFunctionsException error,
) {
  final serverMessage = error.message;
  final message = switch (error.code) {
    'permission-denied' ||
    'failed-precondition' ||
    'not-found' ||
    'invalid-argument' when serverMessage != null && serverMessage.isNotEmpty =>
      serverMessage,
    'unauthenticated' => 'Сессия истекла. Войдите заново.',
    'unavailable' || 'deadline-exceeded' =>
      'Нет связи с сервером. Проверьте интернет и попробуйте снова.',
    _ => 'Не получилось выполнить действие. Попробуйте ещё раз.',
  };
  final details = error.details;
  final reason = details is Map ? details['reason'] : null;
  return CloudFunctionFailure(
    message,
    error.code,
    reason is String ? reason : null,
  );
}

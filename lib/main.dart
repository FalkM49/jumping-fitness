import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'notifications/display_mode.dart';
import 'services/cloud_functions.dart';
import 'services/error_reporter.dart';
import 'services/firebase_bootstrap.dart';
import 'services/theme_mode_storage.dart';
import 'services/web_session.dart';
import 'theme/theme_mode_controller.dart';

/// Версия приложения для журнала ошибок: передаётся при сборке
/// (`--dart-define=APP_VERSION=…`, см. tool/build_web.ps1).
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'dev',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Выбор темы читаем до первого кадра, чтобы не было мигания
  // светлой темы у тех, кто выбрал тёмную.
  final themeStorage = SharedPrefsThemeModeStorage();
  final initialThemeMode = await themeStorage.load();

  final firebaseStatus = await FirebaseBootstrap.initialize();

  if (kIsWeb && kReleaseMode && firebaseStatus == FirebaseStatus.ready) {
    _startWebErrorReporting();
  }

  runApp(
    ProviderScope(
      overrides: [
        themeModeStorageProvider.overrideWithValue(themeStorage),
        initialThemeModeProvider.overrideWithValue(initialThemeMode),
        firebaseStatusProvider.overrideWithValue(firebaseStatus),
      ],
      child: const JumpingFitnessApp(),
    ),
  );
}

/// Журнал ошибок веб-версии (docs/09, шаг 1): необработанные ошибки
/// и перезагрузки вкладки из-за нехватки памяти — в журнал функции.
void _startWebErrorReporting() {
  final callable = callableFor(regionalFunctions(), 'reportClientError');
  final standalone = isStandaloneWebApp();
  final agent = userAgent();
  installErrorReporter(
    ErrorReporter(
      send: (report) => callable.call<Object?>(report),
      context: () => {
        'route': AppRouteTracker.current,
        'userAgent': agent,
        'standalone': standalone,
        'appVersion': appVersion,
      },
    ),
  );

  onWebglLost(() => reportClientError('webgl_lost', 'WebGL-контекст потерян'));

  final crashedOn = startSessionAndTakeUnexpectedReload();
  if (crashedOn != null) {
    reportClientError(
      'unexpected_reload',
      'Вкладка перезагрузилась без pagehide (вероятно, не хватило памяти)',
      null,
      {'route': crashedOn},
    );
  }
}

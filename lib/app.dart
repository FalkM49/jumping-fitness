import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_keys.dart';
import 'routing/app_router.dart';
import 'services/error_reporter.dart';
import 'services/web_session.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_controller.dart';

/// Светлая тема приложения. Вынесена в провайдер, чтобы тесты могли
/// подставить тему без загрузки шрифтов из сети.
final lightThemeProvider = Provider<ThemeData>((ref) => AppTheme.light());

/// Тёмная тема приложения.
final darkThemeProvider = Provider<ThemeData>((ref) => AppTheme.dark());

class JumpingFitnessApp extends ConsumerWidget {
  const JumpingFitnessApp({super.key});

  static const Locale locale = Locale('ru');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Jumping Fitness',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appMessengerKey,

      // Тема: светлая / тёмная / как в системе (ТЗ 11.1).
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      themeMode: ref.watch(themeModeControllerProvider),

      // Интерфейс только на русском (ТЗ 9).
      locale: locale,
      supportedLocales: const [locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,

      initialRoute: AppRouter.initialRoute,
      onGenerateInitialRoutes: AppRouter.onGenerateInitialRoutes,
      onGenerateRoute: AppRouter.onGenerateRoute,
      // Текущий экран — для журнала ошибок веб-версии (docs/09, шаг 1).
      navigatorObservers: [AppRouteTracker(onChange: rememberRoute)],
    );
  }
}

import 'package:flutter/material.dart';

import '../screens/admin/trainer_requests_screen.dart';
import '../screens/auth/auth_gate.dart';
import '../screens/shared/not_found_screen.dart';
import '../screens/shared/notifications_screen.dart';
import '../screens/shared/settings_screen.dart';

/// Имена маршрутов. Единственное место, где они объявлены.
abstract final class AppRoutes {
  /// Корень: вход, регистрация или главный экран роли — решает [AuthGate].
  static const String home = '/';
  static const String settings = '/settings';

  /// «Заявки в тренеры» — только администратору (экран проверяет сам).
  static const String trainerRequests = '/trainer-requests';

  /// История уведомлений.
  static const String notifications = '/notifications';
}

/// Централизованный роутинг на встроенном Navigator.
///
/// Экранов в приложении мало: один главный экран на роль (календарь →
/// профиль → абонемент/клиенты) плюс модальные окна поверх него. Поэтому
/// достаточно таблицы именованных маршрутов без сторонних пакетов.
/// Какой главный экран показать, решает [AuthGate] по входу и роли
/// из Firestore — отдельных маршрутов для клиента и тренера нет, и попасть
/// на чужой экран по имени маршрута нельзя.
abstract final class AppRouter {
  static const String initialRoute = AppRoutes.home;

  static Route<void> onGenerateRoute(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      AppRoutes.home => const AuthGate(),
      AppRoutes.settings => const SettingsScreen(),
      AppRoutes.trainerRequests => const TrainerRequestsScreen(),
      AppRoutes.notifications => const NotificationsScreen(),
      _ => NotFoundScreen(routeName: settings.name),
    };
    return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
  }

  /// Стартовый стек — ровно один экран.
  static List<Route<dynamic>> onGenerateInitialRoutes(String initialRoute) {
    return [onGenerateRoute(RouteSettings(name: initialRoute))];
  }
}

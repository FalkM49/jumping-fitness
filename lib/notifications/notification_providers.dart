import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';
import '../models/models.dart';
import '../routing/app_keys.dart';
import '../routing/app_router.dart';
import '../screens/client/training_details_dialog.dart';
import '../screens/trainer/trainer_cell_dialog.dart';
import '../services/backend_providers.dart';
import '../widgets/app_dialog.dart';
import 'deep_link.dart';

/// История уведомлений вошедшего пользователя.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(currentProfileProvider.select((p) => p?.uid));
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationsRepositoryProvider).watch(uid);
});

/// Сколько непрочитанных — для значка на колокольчике.
final unreadNotificationsProvider = Provider<int>((ref) {
  final items = ref.watch(notificationsProvider).value ?? const [];
  return items.where((n) => !n.read).length;
});

/// Выход из аккаунта: сначала отвязываем устройство от push (пока ещё есть
/// права на запись), затем выходим. Сбой отвязки не мешает выйти.
Future<void> signOut(WidgetRef ref) async {
  final uid = ref.read(authUserProvider).value?.uid;
  if (uid != null) {
    await ref
        .read(pushServiceProvider)
        .stop(uid)
        .timeout(const Duration(seconds: 3), onTimeout: () {});
  }
  await ref.read(authRepositoryProvider).signOut();
}

/// Перейти туда, куда ведёт уведомление: закрыть открытые окна и открыть
/// нужное (ТЗ 7: тап по уведомлению об изменении тренировки открывает её
/// ячейку календаря).
void openDeepLink(WidgetRef ref, DeepLink link) {
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;
  navigator.popUntil((route) => route.isFirst);

  final profile = ref.read(currentProfileProvider);
  if (profile == null) return;
  final context = navigator.overlay?.context;
  if (context == null) return;

  switch (link) {
    case OpenTrainingCell(:final day, :final slot):
      unawaited(
        showAppDialog<void>(
          context: context,
          builder: (_) => profile.isStaff
              ? TrainerCellDialog(day: day, slot: slot)
              : TrainingDetailsDialog(day: day, slot: slot),
        ),
      );
    case OpenTrainerRequests() when profile.isAdmin:
      unawaited(navigator.pushNamed(AppRoutes.trainerRequests));
    case OpenTrainerRequests() || OpenHome() || OpenSubscription():
      // Главный экран уже открыт: абонемент и баннеры — на нём.
      break;
  }
}

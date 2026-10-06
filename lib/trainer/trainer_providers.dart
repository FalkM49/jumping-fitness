import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../client/client_providers.dart';
import '../models/models.dart';
import '../services/backend_providers.dart';
import 'client_list.dart';

/// Данные экрана тренера — живые подписки на Firestore.

final clientsProvider = StreamProvider<List<UserProfile>>(
  (ref) => ref.watch(studioRepositoryProvider).watchClients(),
);

final currentSubscriptionsProvider = StreamProvider<List<Subscription>>(
  (ref) => ref.watch(studioRepositoryProvider).watchCurrentSubscriptions(),
);

/// Все клиенты с их абонементами на сегодня (без поиска и сортировки).
final clientSummariesProvider = Provider<AsyncValue<List<ClientSummary>>>((
  ref,
) {
  final clients = ref.watch(clientsProvider);
  final subs = ref.watch(currentSubscriptionsProvider);
  final today = ref.watch(todayProvider);
  if (clients.hasError) {
    return AsyncError(clients.error!, clients.stackTrace ?? StackTrace.current);
  }
  if (subs.hasError) {
    return AsyncError(subs.error!, subs.stackTrace ?? StackTrace.current);
  }
  if (!clients.hasValue || !subs.hasValue) return const AsyncLoading();
  return AsyncData(
    summarizeClients(
      clients: clients.requireValue,
      currentSubscriptions: subs.requireValue,
      today: today,
    ),
  );
});

/// Записавшиеся на тренировку (активные записи).
final trainingBookingsProvider = StreamProvider.autoDispose
    .family<List<Booking>, String>(
      (ref, trainingId) =>
          ref.watch(studioRepositoryProvider).watchTrainingBookings(trainingId),
    );

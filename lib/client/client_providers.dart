import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';
import '../models/models.dart';
import '../services/backend_providers.dart';
import 'calendar_cells.dart';

/// Данные экрана клиента. Всё — живые подписки на Firestore: после записи
/// или отмены экран обновляется сам, когда сервер записал изменение.

typedef DayRange = ({CalendarDay from, CalendarDay to});

final settingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(studioRepositoryProvider).watchSettings(),
);

/// Сегодня по Москве.
final todayProvider = Provider<CalendarDay>(
  (ref) => CalendarDay.ofInstant(ref.watch(clockProvider)()),
);

final _trainingsProvider = StreamProvider.family<List<Training>, DayRange>(
  (ref, range) =>
      ref.watch(studioRepositoryProvider).watchTrainings(range.from, range.to),
);

final _slotsProvider = StreamProvider.family<List<CalendarSlot>, DayRange>(
  (ref, range) =>
      ref.watch(studioRepositoryProvider).watchSlots(range.from, range.to),
);

final _myBookingsProvider =
    StreamProvider.family<List<Booking>, ({String uid, CalendarDay from})>(
      (ref, key) => ref
          .watch(studioRepositoryProvider)
          .watchMyBookings(key.uid, key.from.atStudioTime(0, 0)),
    );

/// Всё, что нужно календарю на отрезок дней. `null` — ещё грузится.
final calendarDataProvider =
    Provider.family<AsyncValue<CalendarData>, DayRange>((ref, range) {
      // Свои записи нужны только клиенту: тренер видит тренировки целиком.
      final profile = ref.watch(currentProfileProvider);
      final uid = profile == null || profile.isStaff ? null : profile.uid;
      final trainings = ref.watch(_trainingsProvider(range));
      final slots = ref.watch(_slotsProvider(range));
      final settings = ref.watch(settingsProvider);
      final bookings = uid == null
          ? const AsyncData(<Booking>[])
          : ref.watch(_myBookingsProvider((uid: uid, from: range.from)));

      for (final part in <AsyncValue<Object?>>[
        trainings,
        slots,
        settings,
        bookings,
      ]) {
        if (part.hasError) {
          return AsyncError(part.error!, part.stackTrace ?? StackTrace.current);
        }
      }
      if (!trainings.hasValue ||
          !slots.hasValue ||
          !settings.hasValue ||
          !bookings.hasValue) {
        return const AsyncLoading();
      }
      return AsyncData(
        CalendarData(
          trainings: trainings.requireValue,
          slots: slots.requireValue,
          myBookings: bookings.requireValue,
          settings: settings.requireValue,
        ),
      );
    });

/// Текущий абонемент клиента (`null` — абонемента нет).
final currentSubscriptionProvider = StreamProvider<Subscription?>((ref) {
  final id = ref.watch(
    currentProfileProvider.select((p) => p?.currentSubscriptionId),
  );
  if (id == null) return Stream.value(null);
  return ref.watch(studioRepositoryProvider).watchSubscription(id);
});

/// Цветок месяца из справочника (`null` — ещё не назначен).
final monthlyFlowerProvider = StreamProvider<Flower?>((ref) {
  final flowerId = ref.watch(
    currentProfileProvider.select((p) => p?.monthlyFlower?.flowerId),
  );
  if (flowerId == null) return Stream.value(null);
  return ref.watch(studioRepositoryProvider).watchFlower(flowerId);
});

/// Попросить сервер назначить цветок на текущий месяц, если его нет.
/// Вызывается один раз на пользователя и месяц.
final ensureMonthlyFlowerProvider =
    FutureProvider.family<void, ({String uid, String month})>(
      (ref, key) => ref.read(studioFunctionsProvider).ensureMonthlyFlower(),
    );

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

/// Календарь грузится страницами по 14 дней с фиксированными границами
/// (docs/09, шаг 2): страница N — дни `[эпоха + 14·N, эпоха + 14·N + 13]`.
/// При прокрутке на день запрос не пересоздаётся, а ушедшие из вида
/// страницы закрываются сами (`autoDispose`): одновременно живут 3–4.
abstract final class CalendarPages {
  static const int days = 14;

  /// Понедельник — страницы совпадают с парами недель.
  static final CalendarDay epoch = CalendarDay(2024, 1, 1);

  /// Номер страницы, на которой лежит [day].
  static int of(CalendarDay day) {
    final offset = day.daysSince(epoch);
    return (offset / days).floor();
  }

  static DayRange range(int page) {
    final from = epoch.addDays(page * days);
    return (from: from, to: from.addDays(days - 1));
  }
}

final _trainingsProvider = StreamProvider.autoDispose
    .family<List<Training>, int>((ref, page) {
      final range = CalendarPages.range(page);
      return ref
          .watch(studioRepositoryProvider)
          .watchTrainings(range.from, range.to);
    });

final _slotsProvider = StreamProvider.autoDispose
    .family<List<CalendarSlot>, int>((ref, page) {
      final range = CalendarPages.range(page);
      return ref
          .watch(studioRepositoryProvider)
          .watchSlots(range.from, range.to);
    });

final _myBookingsProvider = StreamProvider.autoDispose
    .family<List<Booking>, ({String uid, int page})>((ref, key) {
      final range = CalendarPages.range(key.page);
      return ref
          .watch(studioRepositoryProvider)
          .watchMyBookings(
            key.uid,
            range.from.atStudioTime(0, 0),
            range.to.addDays(1).atStudioTime(0, 0),
          );
    });

/// Всё, что нужно календарю на страницу дней. Живёт, пока её кто-то
/// смотрит: календарь (видимые страницы и соседние) или открытое окно ячейки.
final calendarPageProvider = Provider.autoDispose
    .family<AsyncValue<CalendarData>, int>((ref, page) {
      // Свои записи нужны только клиенту: тренер видит тренировки целиком.
      final profile = ref.watch(currentProfileProvider);
      final uid = profile == null || profile.isStaff ? null : profile.uid;
      final trainings = ref.watch(_trainingsProvider(page));
      final slots = ref.watch(_slotsProvider(page));
      final settings = ref.watch(settingsProvider);
      final bookings = uid == null
          ? const AsyncData(<Booking>[])
          : ref.watch(_myBookingsProvider((uid: uid, page: page)));

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

/// Данные страницы, на которой лежит [day], — для окна ячейки.
final calendarDayProvider = Provider.autoDispose
    .family<AsyncValue<CalendarData>, CalendarDay>(
      (ref, day) => ref.watch(calendarPageProvider(CalendarPages.of(day))),
    );

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

import 'dart:async';

import 'package:jumping_fitness/client/calendar_cells.dart';
import 'package:jumping_fitness/models/models.dart';
import 'package:jumping_fitness/services/cloud_functions.dart';
import 'package:jumping_fitness/services/studio_functions.dart';
import 'package:jumping_fitness/services/studio_repository.dart';

/// Данные студии и Cloud Functions в памяти. Действия меняют данные так же,
/// как сервер (упрощённо), чтобы экран обновлялся через «подписки».
class FakeStudio implements StudioRepository, StudioFunctions {
  FakeStudio({required this.uid});

  /// Вошедший клиент — от его имени записи.
  final String uid;

  AppSettings settings = AppSettings.fallback;
  final Map<String, Training> trainings = {};
  final Map<String, CalendarSlot> slots = {};
  final Map<String, Booking> bookings = {};
  final Map<String, Subscription> subscriptions = {};
  final Map<String, Flower> flowers = {};

  final List<String> calls = [];
  int? frozenDays;
  int ensureFlowerCalls = 0;

  /// Следующий вызов функции упадёт с этой ошибкой.
  CloudFunctionFailure? nextFailure;

  final _changed = StreamController<void>.broadcast();
  void notify() => _changed.add(null);

  /// Сколько «подписок» сейчас открыто — для проверки, что календарь
  /// не копит запросы при прокрутке (docs/09, шаг 2).
  int openStreams = 0;

  Stream<T> _watch<T>(T Function() read) {
    StreamSubscription<void>? changes;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        openStreams++;
        controller.add(read());
        changes = _changed.stream.listen((_) => controller.add(read()));
      },
      onCancel: () {
        openStreams--;
        return changes?.cancel();
      },
    );
    return controller.stream;
  }

  // --------------------------------------------------------- чтение

  @override
  Stream<AppSettings> watchSettings() => _watch(() => settings);

  @override
  Stream<List<Training>> watchTrainings(CalendarDay from, CalendarDay to) =>
      _watch(
        () => [
          for (final t in trainings.values)
            if (t.date.isWithin(from, to)) t,
        ],
      );

  @override
  Stream<List<CalendarSlot>> watchSlots(CalendarDay from, CalendarDay to) =>
      _watch(
        () => [
          for (final s in slots.values)
            if (s.date.isWithin(from, to)) s,
        ],
      );

  @override
  Stream<List<Booking>> watchMyBookings(
    String uid,
    DateTime from,
    DateTime to,
  ) => _watch(
    () => [
      for (final b in bookings.values)
        if (b.clientId == uid &&
            !b.trainingStartAt.isBefore(from) &&
            b.trainingStartAt.isBefore(to))
          b,
    ],
  );

  @override
  Stream<Subscription?> watchSubscription(String subscriptionId) =>
      _watch(() => subscriptions[subscriptionId]);

  @override
  Stream<Flower?> watchFlower(String flowerId) =>
      _watch(() => flowers[flowerId]);

  /// Клиенты студии (для экрана тренера).
  final Map<String, UserProfile> clients = {};

  /// Записи на тренировки других клиентов: trainingId → записи.
  final Map<String, List<Booking>> trainingBookings = {};

  RenewCall? lastRenew;

  @override
  Stream<List<Booking>> watchTrainingBookings(String trainingId) => _watch(
    () => [
      for (final b in trainingBookings[trainingId] ?? const <Booking>[])
        if (b.isActive) b,
    ],
  );

  @override
  Stream<List<UserProfile>> watchClients() =>
      _watch(() => clients.values.toList());

  @override
  Stream<List<Subscription>> watchCurrentSubscriptions() => _watch(
    () => [
      for (final s in subscriptions.values)
        if (s.isCurrent) s,
    ],
  );

  // --------------------------------------------------------- функции

  void _failIfAsked() {
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
  }

  @override
  Future<void> bookTraining(Training training) async {
    calls.add(
      'book:${training.id ?? '${training.date}_${training.slot.wireName}'}',
    );
    _failIfAsked();
    final id = training.id ?? CalendarData.defaultTrainingId(training.slotKey);
    final booked = Training(
      id: id,
      date: training.date,
      slot: training.slot,
      startTime: training.startTime,
      startAt: training.startAt,
      durationMinutes: training.durationMinutes,
      capacity: training.capacity,
      bookedCount: training.bookedCount + 1,
      status: training.status,
      source: training.source,
    );
    trainings[id] = booked;
    bookings[id] = Booking(
      clientId: uid,
      clientName: 'Клиент',
      trainingId: id,
      trainingStartAt: training.startAt,
      status: BookingStatus.active,
      subscriptionId: 'sub',
    );
    notify();
  }

  @override
  Future<void> cancelBooking(String trainingId) async {
    calls.add('cancel:$trainingId');
    _failIfAsked();
    final b = bookings[trainingId]!;
    bookings[trainingId] = Booking(
      clientId: b.clientId,
      clientName: b.clientName,
      trainingId: b.trainingId,
      trainingStartAt: b.trainingStartAt,
      status: BookingStatus.cancelledByClient,
      subscriptionId: b.subscriptionId,
    );
    notify();
  }

  @override
  Future<void> freezeSubscription(int days) async {
    calls.add('freeze:$days');
    _failIfAsked();
    frozenDays = days;
  }

  @override
  Future<void> ensureMonthlyFlower() async {
    ensureFlowerCalls++;
  }

  int notifyTrainerRequestCalls = 0;

  @override
  Future<void> notifyTrainerRequest() async {
    notifyTrainerRequestCalls++;
  }

  @override
  Future<void> createTraining({
    required CalendarDay date,
    required DaySlot slot,
    required TimeOfDayHm startTime,
    required int durationMinutes,
    required int capacity,
  }) async {
    calls.add(
      'create:${slotKeyOf(date, slot)}:${startTime.format()}:$durationMinutes:$capacity',
    );
    _failIfAsked();
    final id = 'new_${slotKeyOf(date, slot)}';
    putTraining(
      id: id,
      date: date,
      slot: slot,
      time: startTime,
      capacity: capacity,
    );
    putSlot(date, slot, id);
    notify();
  }

  @override
  Future<void> updateTraining(
    Training training, {
    TimeOfDayHm? startTime,
    int? durationMinutes,
    int? capacity,
  }) async {
    calls.add(
      'update:${training.id ?? training.slotKey}:'
      '${startTime?.format()}:$durationMinutes:$capacity',
    );
    _failIfAsked();
  }

  @override
  Future<void> cancelTraining(Training training) async {
    calls.add('cancelTraining:${training.id ?? training.slotKey}');
    _failIfAsked();
    final id = training.id;
    if (id != null) {
      putTraining(
        id: id,
        date: training.date,
        slot: training.slot,
        time: training.startTime,
        status: TrainingStatus.cancelled,
      );
    }
    putSlot(training.date, training.slot, null);
    notify();
  }

  @override
  Future<void> removeClientFromTraining({
    required String trainingId,
    required String clientId,
  }) async {
    calls.add('remove:$trainingId:$clientId');
    _failIfAsked();
    trainingBookings[trainingId]?.removeWhere((b) => b.clientId == clientId);
    final t = trainings[trainingId];
    if (t != null) {
      putTraining(
        id: trainingId,
        date: t.date,
        slot: t.slot,
        time: t.startTime,
        capacity: t.capacity,
        bookedCount: t.bookedCount - 1,
      );
    }
    notify();
  }

  @override
  Future<void> renewSubscription({
    required String clientId,
    required CalendarDay startDate,
    required CalendarDay endDate,
    required int trainings,
    required int freezeLimitDays,
  }) async {
    lastRenew = (
      clientId: clientId,
      start: startDate,
      end: endDate,
      trainings: trainings,
      freezeLimitDays: freezeLimitDays,
    );
    calls.add('renew:$clientId');
    _failIfAsked();
  }

  // --------------------------------------------------------- помощники

  Training putTraining({
    required String id,
    required CalendarDay date,
    required DaySlot slot,
    required TimeOfDayHm time,
    int capacity = 13,
    int bookedCount = 0,
    TrainingStatus status = TrainingStatus.scheduled,
  }) {
    final training = Training(
      id: id,
      date: date,
      slot: slot,
      startTime: time,
      startAt: date.atStudioTime(time.hour, time.minute),
      durationMinutes: 60,
      capacity: capacity,
      bookedCount: bookedCount,
      status: status,
      source: TrainingSource.manual,
    );
    trainings[id] = training;
    return training;
  }

  void putSlot(CalendarDay date, DaySlot slot, String? activeTrainingId) {
    final key = slotKeyOf(date, slot);
    slots[key] = CalendarSlot(
      slotKey: key,
      date: date,
      slot: slot,
      activeTrainingId: activeTrainingId,
      overridesDefault: true,
    );
  }

  void putBooking(Training training, BookingStatus status) {
    bookings[training.id!] = Booking(
      clientId: uid,
      clientName: 'Клиент',
      trainingId: training.id!,
      trainingStartAt: training.startAt,
      status: status,
      subscriptionId: 'sub',
    );
  }
}

typedef RenewCall = ({
  String clientId,
  CalendarDay start,
  CalendarDay end,
  int trainings,
  int freezeLimitDays,
});

Subscription subscription({
  String id = 'sub',
  required String clientId,
  required CalendarDay start,
  required CalendarDay end,
  int total = 11,
  int left = 8,
  int freezeLimitDays = 3,
  SubscriptionFreeze? freeze,
  int burned = 0,
  DateTime? expiredAt,
}) => Subscription(
  id: id,
  clientId: clientId,
  isCurrent: true,
  startDate: start,
  endDate: end,
  originalEndDate: end,
  trainingsTotal: total,
  trainingsLeft: left,
  freezeLimitDays: freezeLimitDays,
  freeze: freeze,
  burnedTrainings: burned,
  expiredAt: expiredAt,
);

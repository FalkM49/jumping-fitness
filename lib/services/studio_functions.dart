import 'package:cloud_functions/cloud_functions.dart';

import '../models/models.dart';
import 'cloud_functions.dart';

/// Действия, которые меняют данные, — только через Cloud Functions
/// (docs/04_cloud_functions.md). Все проверки делает сервер; ошибки —
/// [CloudFunctionFailure] с готовым текстом и причиной отказа.
abstract interface class StudioFunctions {
  // ------------------------------------------------------------ клиент

  /// Записаться. Для тренировки по расписанию без документа передаются
  /// дата и строка сетки — сервер создаст её сам.
  Future<void> bookTraining(Training training);

  Future<void> cancelBooking(String trainingId);

  Future<void> freezeSubscription(int days);

  /// Назначить цветок на текущий месяц, если его ещё нет (ТЗ 4).
  Future<void> ensureMonthlyFlower();

  /// Сообщить администраторам о своей только что поданной заявке в тренеры
  /// (ТЗ 2). Повторный вызов ничего не шлёт.
  Future<void> notifyTrainerRequest();

  // ------------------------------------------------------------ тренер

  /// Новая тренировка в пустой ячейке (ТЗ 3.2).
  Future<void> createTraining({
    required CalendarDay date,
    required DaySlot slot,
    required TimeOfDayHm startTime,
    required int durationMinutes,
    required int capacity,
  });

  /// Правка тренировки; передаются только изменённые значения.
  Future<void> updateTraining(
    Training training, {
    TimeOfDayHm? startTime,
    int? durationMinutes,
    int? capacity,
  });

  Future<void> cancelTraining(Training training);

  /// «Мусорка»: удалить клиента с тренировки (ТЗ 3.2).
  Future<void> removeClientFromTraining({
    required String trainingId,
    required String clientId,
  });

  /// Новый абонемент клиенту (ТЗ 6).
  Future<void> renewSubscription({
    required String clientId,
    required CalendarDay startDate,
    required CalendarDay endDate,
    required int trainings,
    required int freezeLimitDays,
  });
}

class CloudStudioFunctions implements StudioFunctions {
  CloudStudioFunctions(this._functions);

  final FirebaseFunctions _functions;

  Future<void> _call(String name, Map<String, Object?> args) =>
      callFunction(_functions, name, args);

  /// Существующая тренировка — по ID, по расписанию без документа — по ячейке.
  static Map<String, Object?> _target(Training training) => training.id != null
      ? {'trainingId': training.id}
      : {'date': training.date.toKey(), 'slot': training.slot.wireName};

  @override
  Future<void> bookTraining(Training training) =>
      _call('bookTraining', _target(training));

  @override
  Future<void> cancelBooking(String trainingId) =>
      _call('cancelBooking', {'trainingId': trainingId});

  @override
  Future<void> freezeSubscription(int days) =>
      _call('freezeSubscription', {'days': days});

  @override
  Future<void> ensureMonthlyFlower() => _call('ensureMonthlyFlower', {});

  @override
  Future<void> notifyTrainerRequest() => _call('notifyTrainerRequest', {});

  @override
  Future<void> createTraining({
    required CalendarDay date,
    required DaySlot slot,
    required TimeOfDayHm startTime,
    required int durationMinutes,
    required int capacity,
  }) => _call('createTraining', {
    'date': date.toKey(),
    'slot': slot.wireName,
    'startTime': startTime.format(),
    'durationMinutes': durationMinutes,
    'capacity': capacity,
  });

  @override
  Future<void> updateTraining(
    Training training, {
    TimeOfDayHm? startTime,
    int? durationMinutes,
    int? capacity,
  }) => _call('updateTraining', {
    ..._target(training),
    'startTime': ?startTime?.format(),
    'durationMinutes': ?durationMinutes,
    'capacity': ?capacity,
  });

  @override
  Future<void> cancelTraining(Training training) =>
      _call('cancelTraining', _target(training));

  @override
  Future<void> removeClientFromTraining({
    required String trainingId,
    required String clientId,
  }) => _call('removeClientFromTraining', {
    'trainingId': trainingId,
    'clientId': clientId,
  });

  @override
  Future<void> renewSubscription({
    required String clientId,
    required CalendarDay startDate,
    required CalendarDay endDate,
    required int trainings,
    required int freezeLimitDays,
  }) => _call('renewSubscription', {
    'clientId': clientId,
    'startDate': startDate.toKey(),
    'endDate': endDate.toKey(),
    'trainings': trainings,
    'freezeLimitDays': freezeLimitDays,
  });
}

class UnavailableStudioFunctions implements StudioFunctions {
  const UnavailableStudioFunctions();

  static const _failure = CloudFunctionFailure(
    'Приложение ещё не подключено к серверу.',
  );

  @override
  Future<void> bookTraining(Training training) => Future.error(_failure);

  @override
  Future<void> cancelBooking(String trainingId) => Future.error(_failure);

  @override
  Future<void> freezeSubscription(int days) => Future.error(_failure);

  @override
  Future<void> ensureMonthlyFlower() async {}

  @override
  Future<void> notifyTrainerRequest() async {}

  @override
  Future<void> createTraining({
    required CalendarDay date,
    required DaySlot slot,
    required TimeOfDayHm startTime,
    required int durationMinutes,
    required int capacity,
  }) => Future.error(_failure);

  @override
  Future<void> updateTraining(
    Training training, {
    TimeOfDayHm? startTime,
    int? durationMinutes,
    int? capacity,
  }) => Future.error(_failure);

  @override
  Future<void> cancelTraining(Training training) => Future.error(_failure);

  @override
  Future<void> removeClientFromTraining({
    required String trainingId,
    required String clientId,
  }) => Future.error(_failure);

  @override
  Future<void> renewSubscription({
    required String clientId,
    required CalendarDay startDate,
    required CalendarDay endDate,
    required int trainings,
    required int freezeLimitDays,
  }) => Future.error(_failure);
}

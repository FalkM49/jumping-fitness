import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../client/booking_rules.dart';
import '../../client/calendar_cells.dart';
import '../../client/client_providers.dart';
import '../../models/models.dart';
import '../../services/backend_providers.dart';
import '../../services/cloud_functions.dart';
import '../../theme/theme_context.dart';
import '../../utils/ru_format.dart';

/// Окно тренировки для клиента (ТЗ 3.1): дата, время, длительность,
/// свободные места и кнопка записи. Закрывается тапом вне окна (ТЗ 9).
///
/// Окно следит за теми же данными, что и календарь: после записи кнопка
/// сама сменится на «Отменить запись», как только сервер запишет изменение.
class TrainingDetailsDialog extends ConsumerWidget {
  const TrainingDetailsDialog({
    super.key,
    required this.day,
    required this.slot,
    required this.range,
  });

  final CalendarDay day;
  final DaySlot slot;
  final DayRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final data = ref.watch(calendarDataProvider(range)).value;
    final cell = data?.cellAt(day, slot, now);
    final textTheme = Theme.of(context).textTheme;

    final title = '${RuFormat.weekdayLong(day)}, ${RuFormat.dayMonth(day)}';

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: switch (cell) {
          TrainingCell() => _TrainingDetails(cell: cell, data: data!),
          CancelledCell(:final training) => Text(
            'Тренер отменил тренировку в ${training.startTime.format()}. '
            'Тренировка вернулась на ваш абонемент.',
            style: textTheme.bodyMedium,
          ),
          EmptyCell() => Text(
            'В это время тренировки нет.',
            style: textTheme.bodyMedium,
          ),
          null => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        },
      ),
    );
  }
}

class _TrainingDetails extends StatelessWidget {
  const _TrainingDetails({required this.cell, required this.data});

  final TrainingCell cell;
  final CalendarData data;

  @override
  Widget build(BuildContext context) {
    final training = cell.training;
    final end = TimeOfDayHm(
      (training.startTime.minutesOfDay + training.durationMinutes) ~/ 60 % 24,
      (training.startTime.minutesOfDay + training.durationMinutes) % 60,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoRow(
          label: 'Время',
          value: '${training.startTime.format()}–${end.format()}',
        ),
        _InfoRow(
          label: 'Длительность',
          value: '${training.durationMinutes} мин',
        ),
        _InfoRow(
          label: 'Свободно мест',
          value: '${training.freePlaces} из ${training.capacity}',
        ),
        const SizedBox(height: 20),
        if (cell.isPast)
          Text(
            cell.isBooked
                ? 'Тренировка уже прошла — вы были записаны.'
                : 'Тренировка уже прошла.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          )
        else
          _BookingAction(
            cell: cell,
            cancelWindowHours: data.settings.cancelWindowHours,
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              fontFamily: context.textStyles.counter.fontFamily,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопка записи / отмены. Смена «Записаться» → «Отменить запись» —
/// единственная характерная анимация приложения: кнопка коротко
/// «раскрывается» за 250 мс (ТЗ 11.4).
class _BookingAction extends ConsumerStatefulWidget {
  const _BookingAction({required this.cell, required this.cancelWindowHours});

  final TrainingCell cell;
  final int cancelWindowHours;

  @override
  ConsumerState<_BookingAction> createState() => _BookingActionState();
}

class _BookingActionState extends ConsumerState<_BookingAction> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on CloudFunctionFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _book() => _run(
    () => ref.read(studioFunctionsProvider).bookTraining(widget.cell.training),
  );

  Future<void> _cancel() async {
    final training = widget.cell.training;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить запись?'),
        content: Text(
          'Тренировка ${RuFormat.dayMonth(training.date)} в '
          '${training.startTime.format()} вернётся на абонемент.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Отменить запись'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(studioFunctionsProvider).cancelBooking(training.id!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final now = ref.watch(clockProvider)();
    final today = ref.watch(todayProvider);
    final subscription = ref.watch(currentSubscriptionProvider).value;

    final String? blocked;
    final Widget button;
    if (cell.isBooked) {
      blocked = cancelBlockReason(
        training: cell.training,
        now: now,
        cancelWindowHours: widget.cancelWindowHours,
      );
      button = OutlinedButton(
        key: const ValueKey('cancel'),
        onPressed: _busy || blocked != null ? null : _cancel,
        child: _busy ? const _Spinner() : const Text('Отменить запись'),
      );
    } else {
      blocked = bookingBlockReason(
        training: cell.training,
        booking: cell.booking,
        subscription: subscription,
        today: today,
        now: now,
      );
      button = FilledButton(
        key: const ValueKey('book'),
        onPressed: _busy || blocked != null ? null : _book,
        child: _busy ? const _Spinner() : const Text('Записаться'),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cell.isBooked)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Вы записаны на эту тренировку.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.85, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: SizedBox(
                  key: button.key,
                  width: double.infinity,
                  child: button,
                ),
              ),
            ),
            if (blocked != null) ...[
              const SizedBox(width: 4),
              _ReasonButton(reason: blocked),
            ],
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.colors.error),
          ),
        ],
      ],
    );
  }
}

/// Значок (i) рядом с неактивной кнопкой: по нажатию — конкретная причина.
class _ReasonButton extends StatelessWidget {
  const _ReasonButton({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Почему недоступно',
      icon: const Icon(Icons.info_outline_rounded),
      onPressed: () => unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(reason),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Понятно'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

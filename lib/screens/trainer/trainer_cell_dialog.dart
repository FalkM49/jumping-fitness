import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../client/client_providers.dart';
import '../../models/models.dart';
import '../../services/backend_providers.dart';
import '../../services/cloud_functions.dart';
import '../../theme/theme_context.dart';
import '../../trainer/client_list.dart';
import '../../trainer/trainer_providers.dart';
import '../../utils/ru_format.dart';
import '../../widgets/number_stepper.dart';

/// Окно ячейки календаря для тренера (ТЗ 3.2). Закрывается тапом вне окна.
///
/// Пустая ячейка — назначить тренировку (поля по умолчанию из ТЗ 7).
/// Заполненная — правка времени, длительности и мест, список записавшихся
/// с «мусоркой» и отмена тренировки. Все изменения — через Cloud Functions.
class TrainerCellDialog extends ConsumerWidget {
  const TrainerCellDialog({
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
    final data = ref.watch(calendarDataProvider(range)).value;
    final training = data?.activeTrainingAt(day, slot);
    final settings = data?.settings ?? AppSettings.fallback;

    return AlertDialog(
      scrollable: true,
      title: Text('${RuFormat.weekdayLong(day)}, ${RuFormat.dayMonth(day)}'),
      content: SizedBox(
        width: 380,
        child: data == null
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : training == null
            ? _CreateTrainingForm(day: day, slot: slot, settings: settings)
            : _EditTrainingForm(
                key: ValueKey(training.id ?? 'virtual-${training.slotKey}'),
                training: training,
              ),
      ),
    );
  }
}

// ------------------------------------------------------------------ общее

/// Время с выбором в стандартном окне (24 часа).
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final TimeOfDayHm value;
  final bool enabled;
  final ValueChanged<TimeOfDayHm> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) onChanged(TimeOfDayHm(picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Время начала',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        OutlinedButton(
          onPressed: enabled ? () => unawaited(_pick(context)) : null,
          style: OutlinedButton.styleFrom(minimumSize: const Size(100, 40)),
          child: Text(
            value.format(),
            style: TextStyle(
              fontFamily: context.textStyles.counter.fontFamily,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}

/// Время должно попадать в свою строку сетки: утро — до 14:00, вечер — с 14:00.
String? _slotError(DaySlot slot, TimeOfDayHm time) {
  if (slot.admits(time)) return null;
  return slot == DaySlot.morning
      ? 'Утренняя тренировка начинается раньше ${DaySlot.eveningStartsAt.format()}.'
      : 'Вечерняя тренировка начинается не раньше ${DaySlot.eveningStartsAt.format()}.';
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.colors.error),
    ),
  );
}

class _BusyLabel extends StatelessWidget {
  const _BusyLabel({required this.busy, required this.label});

  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) => busy
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(label);
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Нет'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ------------------------------------------------------------------ создание

class _CreateTrainingForm extends ConsumerStatefulWidget {
  const _CreateTrainingForm({
    required this.day,
    required this.slot,
    required this.settings,
  });

  final CalendarDay day;
  final DaySlot slot;
  final AppSettings settings;

  @override
  ConsumerState<_CreateTrainingForm> createState() =>
      _CreateTrainingFormState();
}

class _CreateTrainingFormState extends ConsumerState<_CreateTrainingForm> {
  late TimeOfDayHm _time = widget.slot == DaySlot.morning
      ? widget.settings.training.morningTime
      : widget.settings.training.eveningTime;
  late int _duration = widget.settings.training.durationMinutes;
  late int _capacity = widget.settings.training.capacity;
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(studioFunctionsProvider)
          .createTraining(
            date: widget.day,
            slot: widget.slot,
            startTime: _time,
            durationMinutes: _duration,
            capacity: _capacity,
          );
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Тренировка назначена.')),
      );
    } on CloudFunctionFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slotError = _slotError(widget.slot, _time);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.slot.label}: тренировки нет. Назначить?',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _TimeRow(
          value: _time,
          enabled: !_busy,
          onChanged: (t) => setState(() => _time = t),
        ),
        NumberStepper(
          label: 'Длительность',
          value: _duration,
          min: 15,
          max: 300,
          step: 5,
          suffix: 'мин',
          enabled: !_busy,
          onChanged: (v) => setState(() => _duration = v),
        ),
        NumberStepper(
          label: 'Мест',
          value: _capacity,
          min: 1,
          max: 100,
          enabled: !_busy,
          onChanged: (v) => setState(() => _capacity = v),
        ),
        if (slotError != null) _ErrorText(slotError),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || slotError != null ? null : _create,
          child: _BusyLabel(busy: _busy, label: 'Назначить тренировку'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ правка

class _EditTrainingForm extends ConsumerStatefulWidget {
  const _EditTrainingForm({super.key, required this.training});

  final Training training;

  @override
  ConsumerState<_EditTrainingForm> createState() => _EditTrainingFormState();
}

class _EditTrainingFormState extends ConsumerState<_EditTrainingForm> {
  late TimeOfDayHm _time = widget.training.startTime;
  late int _duration = widget.training.durationMinutes;
  late int _capacity = widget.training.capacity;
  bool _busy = false;
  String? _error;
  String? _capacityWarning;

  Training get _t => widget.training;

  bool get _changed =>
      _time != _t.startTime ||
      _duration != _t.durationMinutes ||
      _capacity != _t.capacity;

  Future<void> _run(
    Future<void> Function() action, {
    String? success,
    bool close = true,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (close) navigator.pop();
      if (success != null) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
    } on CloudFunctionFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() {
    final scheduleChanged =
        _time != _t.startTime || _duration != _t.durationMinutes;
    return _run(
      () => ref
          .read(studioFunctionsProvider)
          .updateTraining(
            _t,
            startTime: _time != _t.startTime ? _time : null,
            durationMinutes: _duration != _t.durationMinutes ? _duration : null,
            capacity: _capacity != _t.capacity ? _capacity : null,
          ),
      success: scheduleChanged && _t.bookedCount > 0
          ? 'Изменения сохранены. Записанные получат уведомление.'
          : 'Изменения сохранены.',
    );
  }

  Future<void> _cancelTraining() async {
    final n = _t.bookedCount;
    final confirmed = await _confirm(
      context,
      title: 'Отменить тренировку?',
      text: n == 0
          ? 'Тренировка ${_t.startTime.format()} будет отменена, ячейка освободится.'
          : 'Всем записанным (${RuFormat.count(n, 'человек', 'человека', 'человек')}) '
                'тренировка вернётся на абонемент, им придёт уведомление. '
                'Ячейка освободится для новой тренировки.',
      action: 'Отменить тренировку',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(studioFunctionsProvider).cancelTraining(_t),
      success: 'Тренировка отменена.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final started = _t.hasStartedAt(now);
    final editable = !started && !_busy;
    final slotError = _slotError(_t.slot, _time);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (started)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Тренировка уже началась — изменить или отменить её нельзя.',
              style: textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        _TimeRow(
          value: _time,
          enabled: editable,
          onChanged: (t) => setState(() => _time = t),
        ),
        NumberStepper(
          label: 'Длительность',
          value: _duration,
          min: 15,
          max: 300,
          step: 5,
          suffix: 'мин',
          enabled: editable,
          onChanged: (v) => setState(() => _duration = v),
        ),
        NumberStepper(
          label: 'Мест',
          value: _capacity,
          // Меньше, чем уже записано, нельзя (ТЗ 3.2).
          min: _t.bookedCount < 1 ? 1 : _t.bookedCount,
          max: 100,
          enabled: editable,
          onChanged: (v) => setState(() {
            _capacity = v;
            _capacityWarning = null;
          }),
          onBelowMin: _t.bookedCount > 0
              ? () => setState(
                  () => _capacityWarning =
                      'Нельзя поставить меньше ${_t.bookedCount}: уже записано '
                      '${RuFormat.count(_t.bookedCount, 'человек', 'человека', 'человек')}.',
                )
              : null,
        ),
        if (_capacityWarning != null) _ErrorText(_capacityWarning!),
        if (slotError != null) _ErrorText(slotError),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 8),
        _BookedClients(training: _t, busy: _busy),
        if (!started) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: editable && _changed && slotError == null ? _save : null,
            child: _BusyLabel(busy: _busy, label: 'Сохранить изменения'),
          ),
          const SizedBox(height: 4),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: context.palette.cancelled,
            ),
            onPressed: editable ? _cancelTraining : null,
            child: const Text('Отменить тренировку'),
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ записавшиеся

/// Список записавшихся — свёрнут по умолчанию (ТЗ 3.2). У каждого — остаток
/// дней и тренировок по абонементу и ненавязчивая «мусорка».
class _BookedClients extends ConsumerWidget {
  const _BookedClients({required this.training, required this.busy});

  final Training training;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = training.id;
    final count = training.bookedCount;
    final textTheme = Theme.of(context).textTheme;

    return Theme(
      // Без линий-разделителей ExpansionTile поверх «лепестка» окна.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          count == 0
              ? 'Записавшихся пока нет'
              : 'Записаны: ${RuFormat.count(count, 'человек', 'человека', 'человек')}',
          style: textTheme.titleSmall,
        ),
        enabled: count > 0 && id != null,
        children: [if (id != null) _BookedList(trainingId: id, busy: busy)],
      ),
    );
  }
}

class _BookedList extends ConsumerWidget {
  const _BookedList({required this.trainingId, required this.busy});

  final String trainingId;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(trainingBookingsProvider(trainingId));
    final summaries = {
      for (final s
          in ref.watch(clientSummariesProvider).value ??
              const <ClientSummary>[])
        s.profile.uid: s,
    };

    return switch (bookings) {
      AsyncValue(:final value?) => Column(
        children: [
          for (final booking in [
            ...value,
          ]..sort((a, b) => compareRussian(a.clientName, b.clientName)))
            _BookedRow(
              trainingId: trainingId,
              booking: booking,
              summary: summaries[booking.clientId],
              busy: busy,
            ),
        ],
      ),
      AsyncValue(hasError: true) => const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Не удалось загрузить список.'),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    };
  }
}

class _BookedRow extends ConsumerStatefulWidget {
  const _BookedRow({
    required this.trainingId,
    required this.booking,
    required this.summary,
    required this.busy,
  });

  final String trainingId;
  final Booking booking;
  final ClientSummary? summary;
  final bool busy;

  @override
  ConsumerState<_BookedRow> createState() => _BookedRowState();
}

class _BookedRowState extends ConsumerState<_BookedRow> {
  bool _removing = false;

  Future<void> _remove() async {
    final name = widget.booking.clientName;
    final confirmed = await _confirm(
      context,
      title: 'Удалить с тренировки?',
      text:
          '$name будет удалён(а) с этой тренировки. Тренировка вернётся на '
          'абонемент, записаться именно на эту тренировку снова будет нельзя. '
          'Клиенту придёт уведомление.',
      action: 'Удалить',
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _removing = true);
    try {
      await ref
          .read(studioFunctionsProvider)
          .removeClientFromTraining(
            trainingId: widget.trainingId,
            clientId: widget.booking.clientId,
          );
      messenger.showSnackBar(
        SnackBar(content: Text('$name удалён(а) с тренировки.')),
      );
    } on CloudFunctionFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final textTheme = Theme.of(context).textTheme;
    final colors = context.colors;
    final palette = context.palette;

    final meta = summary == null
        ? null
        : summary.subscription == null
        ? 'Нет абонемента'
        : 'Осталось ${RuFormat.count(summary.daysLeft, 'день', 'дня', 'дней')} · '
              '${RuFormat.count(summary.trainingsLeft, 'тренировка', 'тренировки', 'тренировок')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: summary == null
                  ? palette.line
                  : palette.remainingColor(
                      remaining: summary.trainingsLeft,
                      total: summary.subscription?.trainingsTotal ?? 0,
                    ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.booking.clientName, style: textTheme.bodyMedium),
                if (meta != null)
                  Text(
                    meta,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          // Ненавязчивая мусорка с отступом от текста — чтобы не задеть
          // случайно (ТЗ 3.2). Удаление — только после подтверждения.
          const SizedBox(width: 16),
          _removing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Удалить с тренировки',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                  onPressed: widget.busy ? null : _remove,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
        ],
      ),
    );
  }
}

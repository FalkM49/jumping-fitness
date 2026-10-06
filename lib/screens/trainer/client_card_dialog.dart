import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/phone_number.dart';
import '../../client/client_providers.dart';
import '../../models/models.dart';
import '../../services/backend_providers.dart';
import '../../services/cloud_functions.dart';
import '../../theme/theme_context.dart';
import '../../trainer/client_list.dart';
import '../../trainer/trainer_providers.dart';
import '../../utils/ru_format.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/number_stepper.dart';

/// Карточка клиента (ТЗ 6): ФИО, срок абонемента, сколько дней осталось,
/// остаток тренировок с цветовой индикацией и «Продлить абонемент».
class ClientCardDialog extends ConsumerWidget {
  const ClientCardDialog({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(clientSummariesProvider).value;
    final client = summaries
        ?.where((c) => c.profile.uid == clientId)
        .firstOrNull;
    final textTheme = Theme.of(context).textTheme;
    final palette = context.palette;
    final colors = context.colors;

    if (client == null) {
      return const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    final sub = client.subscription;
    return AlertDialog(
      title: Text(client.profile.fullName),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              PhoneNumber.format(client.profile.phone),
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            if (sub == null)
              Text('Абонемент ещё не оформлялся.', style: textTheme.bodyMedium)
            else ...[
              Text(
                'Абонемент ${RuFormat.period(sub.startDate, sub.endDate)}',
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: 2),
              Text(
                client.isActive
                    ? 'Осталось ${RuFormat.count(client.daysLeft, 'день', 'дня', 'дней')}'
                    : client.daysLeft == 0
                    ? 'Срок истёк'
                    : 'Ещё не начался',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color:
                      client.isActive &&
                          client.daysLeft >
                              (ref.watch(settingsProvider).value ??
                                      AppSettings.fallback)
                                  .endingSoonDays
                      ? palette.remainingHigh
                      : palette.remainingLow,
                ),
              ),
              if (sub.freeze != null)
                Text(
                  'Заморозка: ${RuFormat.period(sub.freeze!.startDate, sub.freeze!.endDate)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                '${client.trainingsLeft}',
                style: context.textStyles.counter.copyWith(
                  color: palette.remainingColor(
                    remaining: client.trainingsLeft,
                    total: sub.trainingsTotal,
                  ),
                ),
              ),
              Text(
                'из ${sub.trainingsTotal} — '
                '${RuFormat.plural(client.trainingsLeft, 'тренировка осталась', 'тренировки осталось', 'тренировок осталось')}',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => showAppDialog<void>(
                context: context,
                builder: (_) => RenewSubscriptionDialog(client: client),
              ),
              child: Text(
                sub == null ? 'Оформить абонемент' : 'Продлить абонемент',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Продление (ТЗ 6): период «с» и «по», количество тренировок, лимит
/// заморозки. Значения по умолчанию — из ТЗ 7 (30 дней, 11 тренировок,
/// 3 дня заморозки), тренер правит на месте.
class RenewSubscriptionDialog extends ConsumerStatefulWidget {
  const RenewSubscriptionDialog({super.key, required this.client});

  final ClientSummary client;

  @override
  ConsumerState<RenewSubscriptionDialog> createState() =>
      _RenewSubscriptionDialogState();
}

class _RenewSubscriptionDialogState
    extends ConsumerState<RenewSubscriptionDialog> {
  late final AppSettings _settings =
      ref.read(settingsProvider).value ?? AppSettings.fallback;
  late CalendarDay _start = ref.read(todayProvider);
  late CalendarDay _end = _start.addDays(
    _settings.subscription.durationDays - 1,
  );
  late int _trainings = _settings.subscription.trainings;
  late int _freezeLimit = _settings.subscription.freezeLimitDays;
  bool _busy = false;
  String? _error;

  String? get _validation {
    final today = ref.read(todayProvider);
    if (_end.isBefore(_start)) return 'Дата «по» раньше даты «с».';
    if (_end.isBefore(today)) return 'Абонемент закончился бы в прошлом.';
    if (_end.daysSince(_start) + 1 > 366) {
      return 'Абонемент не может быть длиннее года.';
    }
    return null;
  }

  Future<CalendarDay?> _pickDate(CalendarDay initial) async {
    final today = ref.read(todayProvider);
    // Как showAppDialog: без возврата фокуса и клавиатуры (docs/09, шаг 4).
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(const Duration(days: 90)),
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    return picked == null
        ? null
        : CalendarDay(picked.year, picked.month, picked.day);
  }

  Future<void> _submit() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Оформить абонемент?'),
        content: Text(
          '${widget.client.profile.fullName}: '
          '${RuFormat.period(_start, _end)}, '
          '${RuFormat.count(_trainings, 'тренировка', 'тренировки', 'тренировок')}, '
          'заморозка до ${RuFormat.count(_freezeLimit, 'дня', 'дней', 'дней')}. '
          '${widget.client.subscription == null ? '' : 'Текущий абонемент сохранится в истории.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Оформить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(studioFunctionsProvider)
          .renewSubscription(
            clientId: widget.client.profile.uid,
            startDate: _start,
            endDate: _end,
            trainings: _trainings,
            freezeLimitDays: _freezeLimit,
          );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Абонемент оформлен: ${widget.client.profile.fullName}.',
          ),
        ),
      );
    } on CloudFunctionFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final validation = _validation;
    final textTheme = Theme.of(context).textTheme;

    Widget dateRow(
      String label,
      CalendarDay value,
      ValueChanged<CalendarDay> set,
    ) => Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => unawaited(
                  _pickDate(value).then((d) {
                    if (d != null && mounted) setState(() => set(d));
                  }),
                ),
          child: Text('${RuFormat.dayMonth(value)} ${value.year}'),
        ),
      ],
    );

    return AlertDialog(
      scrollable: true,
      title: const Text('Продление абонемента'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.client.profile.fullName, style: textTheme.titleMedium),
            const SizedBox(height: 12),
            dateRow('С', _start, (d) {
              // Сдвигаем «по» вместе с «с», сохраняя длину периода.
              final length = _end.daysSince(_start);
              _start = d;
              _end = d.addDays(length);
            }),
            const SizedBox(height: 6),
            dateRow('По', _end, (d) => _end = d),
            const SizedBox(height: 6),
            NumberStepper(
              label: 'Тренировок',
              value: _trainings,
              min: 1,
              max: 200,
              enabled: !_busy,
              onChanged: (v) => setState(() => _trainings = v),
            ),
            NumberStepper(
              label: 'Заморозка, дней',
              value: _freezeLimit,
              min: 0,
              max: 60,
              enabled: !_busy,
              onChanged: (v) => setState(() => _freezeLimit = v),
            ),
            if (validation != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  validation,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || validation != null ? null : _submit,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Обновить'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../client/client_providers.dart';
import '../../models/models.dart';
import '../../services/backend_providers.dart';
import '../../services/cloud_functions.dart';
import '../../theme/app_radii.dart';
import '../../theme/theme_context.dart';
import '../../utils/ru_format.dart';
import '../../widgets/ice_cube_icon.dart';
import '../../widgets/info_notice.dart';
import '../../widgets/petal_card.dart';

/// Блок «Абонемент» клиента (ТЗ 5).
class SubscriptionCard extends ConsumerWidget {
  const SubscriptionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(currentSubscriptionProvider);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.fallback;
    final today = ref.watch(todayProvider);

    return switch (async) {
      AsyncValue(:final value?) => _SubscriptionDetails(
        subscription: value,
        today: today,
        settings: settings,
      ),
      AsyncValue(hasValue: true) => const PetalCard(child: _NoSubscription()),
      AsyncValue(hasError: true) => PetalCard(
        child: Text(
          'Не удалось загрузить абонемент. Проверьте интернет.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      _ => const PetalCard(
        child: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
    };
  }
}

class _NoSubscription extends StatelessWidget {
  const _NoSubscription();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Абонемент', style: _titleStyle(context)),
        const SizedBox(height: 8),
        Text(
          'Абонемента пока нет. Оформите его у тренера — после этого '
          'можно будет записываться на тренировки.',
          style: textTheme.bodyMedium,
        ),
      ],
    );
  }
}

TextStyle? _titleStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelLarge?.copyWith(
      color: context.colors.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

enum _Status { active, frozen, notStarted, expired }

class _SubscriptionDetails extends StatelessWidget {
  const _SubscriptionDetails({
    required this.subscription,
    required this.today,
    required this.settings,
  });

  final Subscription subscription;
  final CalendarDay today;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final sub = subscription;
    final palette = context.palette;
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;

    final status = sub.isExpiredOn(today) || sub.expiredAt != null
        ? _Status.expired
        : today.isBefore(sub.startDate)
        ? _Status.notStarted
        : sub.isFrozenOn(today)
        ? _Status.frozen
        : _Status.active;
    final daysLeft = sub.daysLeftOn(today);
    final endingSoon =
        status != _Status.expired && daysLeft <= settings.endingSoonDays;
    final left = status == _Status.expired ? 0 : sub.trainingsLeft;

    return PetalCard(
      // Тень — только у самого важного блока: действующего абонемента (ТЗ 11.3).
      emphasized: status == _Status.active || status == _Status.frozen,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Абонемент', style: _titleStyle(context)),
              const SizedBox(width: 8),
              _StatusChip(status: status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            RuFormat.period(sub.startDate, sub.endDate).replaceFirst('с', 'С'),
            style: textTheme.bodyLarge,
          ),
          const SizedBox(height: 2),
          if (status != _Status.expired)
            Text(
              'Осталось ${RuFormat.count(daysLeft, 'день', 'дня', 'дней')}',
              style: textTheme.bodyMedium?.copyWith(
                // Выделение, когда до конца немного дней (ТЗ 5).
                color: endingSoon
                    ? palette.remainingLow
                    : palette.remainingHigh,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (status == _Status.frozen && sub.freeze != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Заморожен по ${RuFormat.dayMonth(sub.freeze!.endDate)} включительно',
                style: textTheme.bodyMedium?.copyWith(color: IceCubeIcon.ice),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            '$left',
            style: context.textStyles.counter.copyWith(
              // Зелёный → красный по доле оставшихся, 0 — чёрный/белый (ТЗ 5).
              color: palette.remainingColor(
                remaining: left,
                total: sub.trainingsTotal,
              ),
            ),
          ),
          Text(
            left == 0
                ? 'тренировок осталось'
                : '${RuFormat.plural(left, 'тренировка', 'тренировки', 'тренировок')} '
                      '${RuFormat.plural(left, 'осталась', 'осталось', 'осталось')}',
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (left == 0) ...[
            const SizedBox(height: 12),
            const InfoNotice(
              tone: NoticeTone.alert,
              text: 'Абонемент закончился — продлите у тренера',
            ),
          ],
          if (status != _Status.expired) ...[
            const SizedBox(height: 14),
            _FreezeButton(subscription: sub, today: today, status: status),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _Status status;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colors = context.colors;
    final (label, color) = switch (status) {
      _Status.active => ('Активен', palette.remainingHigh),
      _Status.frozen => ('Заморожен', IceCubeIcon.ice),
      _Status.notStarted => ('Ещё не начался', colors.onSurfaceVariant),
      _Status.expired => ('Неактивен', colors.onSurfaceVariant),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: AppRadii.dense),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: const Color(0xFFFFFFFF),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// «Заморозить абонемент» — компактная контурная кнопка со значком
/// кубика льда (ТЗ 5, 11.2): второстепенное действие, подпись Manrope
/// SemiBold основным цветом текста.
class _FreezeButton extends ConsumerWidget {
  const _FreezeButton({
    required this.subscription,
    required this.today,
    required this.status,
  });

  final Subscription subscription;
  final CalendarDay today;
  final _Status status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final freeze = subscription.freeze;
    final available =
        status == _Status.active &&
        subscription.canFreeze &&
        subscription.freezeLimitDays > 0;

    final note = freeze != null
        ? 'Заморозка использована: ${RuFormat.period(freeze.startDate, freeze.endDate)}'
        : subscription.freezeLimitDays <= 0
        ? 'Заморозка для этого абонемента не предусмотрена'
        : status == _Status.notStarted
        ? 'Заморозка станет доступна, когда абонемент начнёт действовать'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: context.textStyles.freezeButtonLabel,
          ),
          onPressed: available
              ? () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      FreezeDialog(subscription: subscription, today: today),
                )
              : null,
          icon: IceCubeIcon(
            color: available ? null : context.colors.onSurfaceVariant,
          ),
          label: const Text('Заморозить абонемент'),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              note,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Выбор числа дней заморозки в пределах лимита тренера (ТЗ 5).
class FreezeDialog extends ConsumerStatefulWidget {
  const FreezeDialog({
    super.key,
    required this.subscription,
    required this.today,
  });

  final Subscription subscription;
  final CalendarDay today;

  @override
  ConsumerState<FreezeDialog> createState() => _FreezeDialogState();
}

class _FreezeDialogState extends ConsumerState<FreezeDialog> {
  int _days = 1;
  bool _busy = false;
  String? _error;

  int get _limit => widget.subscription.freezeLimitDays;

  Future<void> _freeze() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(studioFunctionsProvider).freezeSubscription(_days);
      if (mounted) Navigator.of(context).pop();
    } on CloudFunctionFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final lastFrozen = widget.today.addDays(_days - 1);
    final newEnd = widget.subscription.endDate.addDays(_days);

    return AlertDialog(
      title: const Text('Заморозить абонемент'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'На сколько дней? Можно до ${RuFormat.count(_limit, 'дня', 'дней', 'дней')}.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  tooltip: 'Меньше',
                  onPressed: _busy || _days <= 1
                      ? null
                      : () => setState(() => _days--),
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    '$_days',
                    textAlign: TextAlign.center,
                    style: context.textStyles.counter,
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Больше',
                  onPressed: _busy || _days >= _limit
                      ? null
                      : () => setState(() => _days++),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            Center(
              child: Text(
                RuFormat.plural(_days, 'день', 'дня', 'дней'),
                style: textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Заморозка ${RuFormat.period(widget.today, lastFrozen)} включительно. '
              'Абонемент продлится до ${RuFormat.dayMonth(newEnd)}. '
              'Пока идёт заморозка, записываться на тренировки нельзя; '
              'уже сделанные записи сохранятся. Заморозить можно один раз за период.',
              style: textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: textTheme.bodyMedium?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _freeze,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Заморозить'),
        ),
      ],
    );
  }
}

/// Баннеры внутри приложения о состоянии абонемента (ТЗ 5): скоро
/// закончится по сроку, мало тренировок, истёк и тренировки сгорели.
/// Push с тем же смыслом придут на этапе 7.
List<InfoNotice> subscriptionBanners({
  required Subscription? subscription,
  required CalendarDay today,
  required AppSettings settings,
}) {
  final sub = subscription;
  if (sub == null) return const [];

  if (sub.isExpiredOn(today) || sub.expiredAt != null) {
    return [
      InfoNotice(
        tone: NoticeTone.alert,
        text: sub.burnedTrainings > 0
            ? 'Срок абонемента истёк, оставшиеся тренировки сгорели. '
                  'Продлите абонемент у тренера.'
            : 'Срок абонемента истёк. Продлите абонемент у тренера.',
      ),
    ];
  }
  if (today.isBefore(sub.startDate)) return const [];

  final daysLeft = sub.daysLeftOn(today);
  return [
    if (daysLeft <= settings.endingSoonDays)
      InfoNotice(
        tone: NoticeTone.warning,
        text: daysLeft == 1
            ? 'Сегодня последний день абонемента.'
            : 'Абонемент заканчивается через ${RuFormat.count(daysLeft, 'день', 'дня', 'дней')} — '
                  '${RuFormat.dayMonth(sub.endDate)} последний день.',
      ),
    if (sub.trainingsLeft > 0 &&
        sub.trainingsLeft <= settings.lowTrainingsThreshold)
      InfoNotice(
        tone: NoticeTone.warning,
        icon: Icons.confirmation_number_outlined,
        text:
            'На абонементе ${RuFormat.plural(sub.trainingsLeft, 'осталась', 'осталось', 'осталось')} '
            '${RuFormat.count(sub.trainingsLeft, 'тренировка', 'тренировки', 'тренировок')}.',
      ),
  ];
}

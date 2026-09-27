import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../routing/app_router.dart';
import '../../theme/app_radii.dart';
import '../../theme/theme_context.dart';
import '../../utils/ru_format.dart';
import 'trainer_requests_screen.dart';

/// Вход в «Заявки в тренеры» на главном экране администратора (ТЗ 2):
/// одна строка со счётчиком новых заявок — видно сразу, без меню.
class TrainerRequestsEntry extends ConsumerWidget {
  const TrainerRequestsEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingTrainerRequestsProvider).value?.length;
    final colors = context.colors;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final hasNew = (pending ?? 0) > 0;

    return Material(
      color: hasNew ? palette.bloomTint : palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.dense,
        side: BorderSide(color: palette.line, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.trainerRequests),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.how_to_reg_outlined,
                color: hasNew ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Заявки в тренеры',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                pending == null
                    ? ''
                    : pending == 0
                    ? 'новых нет'
                    : RuFormat.count(pending, 'новая', 'новые', 'новых'),
                style: textTheme.bodySmall?.copyWith(
                  color: hasNew ? colors.primary : colors.onSurfaceVariant,
                  fontWeight: hasNew ? FontWeight.w700 : null,
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

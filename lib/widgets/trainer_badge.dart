import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/theme_context.dart';

/// Плашка «Тренер» рядом с ФИО в профиле (ТЗ 4). Полностью скруглённая,
/// как в макете, — согласованное исключение из ТЗ 11.3 (AppRadii.badge).
class TrainerBadge extends StatelessWidget {
  const TrainerBadge({super.key, this.label = 'Тренер'});

  /// «Тренер» или «Администратор» (у админа все права тренера).
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.coralTint,
        borderRadius: AppRadii.badge,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: context.colors.secondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

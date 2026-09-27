import 'package:flutter/material.dart';

import '../theme/theme_context.dart';

/// Число с кнопками «−» и «+»: места, длительность, тренировки, дни.
/// Крупное число — шрифтом заголовков (ТЗ 11.2).
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.suffix,
    this.enabled = true,
    this.onBelowMin,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;

  /// Подпись после числа: «мин», «дн.».
  final String? suffix;
  final bool enabled;
  final ValueChanged<int> onChanged;

  /// Нажали «−» на минимуме — например, чтобы объяснить, почему меньше нельзя.
  final VoidCallback? onBelowMin;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canDecrease = enabled && (value - step >= min || onBelowMin != null);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          tooltip: '$label: меньше',
          visualDensity: VisualDensity.compact,
          onPressed: canDecrease
              ? () => value - step >= min
                    ? onChanged(value - step)
                    : onBelowMin?.call()
              : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 76,
          child: Text(
            suffix == null ? '$value' : '$value $suffix',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              fontFamily: context.textStyles.counter.fontFamily,
              fontSize: 15,
            ),
          ),
        ),
        IconButton(
          tooltip: '$label: больше',
          visualDensity: VisualDensity.compact,
          onPressed: enabled && value + step <= max
              ? () => onChanged(value + step)
              : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

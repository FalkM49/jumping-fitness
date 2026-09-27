import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/theme_context.dart';

/// Насколько важна плашка.
enum NoticeTone {
  /// Нейтральная подсказка.
  info,

  /// Стоит обратить внимание (скоро закончится, мало тренировок).
  warning,

  /// Уже случилось (срок истёк, тренировки сгорели).
  alert,
}

/// Плашка-подсказка или баннер внутри приложения.
class InfoNotice extends StatelessWidget {
  const InfoNotice({
    super.key,
    required this.text,
    this.icon,
    this.tone = NoticeTone.info,
  });

  final String text;
  final IconData? icon;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = context.palette;
    final (background, foreground, defaultIcon) = switch (tone) {
      NoticeTone.info => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
        Icons.info_outline_rounded,
      ),
      NoticeTone.warning => (
        palette.coralTint,
        colors.onSurface,
        Icons.schedule_outlined,
      ),
      NoticeTone.alert => (
        palette.cancelled.withValues(alpha: 0.14),
        colors.onSurface,
        Icons.error_outline_rounded,
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.dense,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon ?? defaultIcon,
              size: 20,
              color: tone == NoticeTone.alert ? palette.cancelled : foreground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

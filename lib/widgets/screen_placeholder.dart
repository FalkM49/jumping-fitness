import 'package:flutter/material.dart';

/// Временное содержимое экрана-заглушки: название экрана по центру.
/// Удаляется по мере наполнения экранов на этапах 5–7.
class ScreenPlaceholder extends StatelessWidget {
  const ScreenPlaceholder({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              for (final action in actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: action,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

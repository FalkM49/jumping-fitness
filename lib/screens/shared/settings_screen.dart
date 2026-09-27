import 'package:flutter/material.dart';

import '../../widgets/theme_mode_selector.dart';

/// Настройки приложения. На этапе 1 — только выбор темы (ТЗ 11.1).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('Настройки', style: textTheme.titleLarge)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Тема оформления',
              style: textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const ThemeModeSelector(),
        ],
      ),
    );
  }
}

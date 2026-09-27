import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_radii.dart';
import '../theme/theme_context.dart';
import '../theme/theme_mode_controller.dart';

/// Переключатель «Светлая / Тёмная / Как в системе» (ТЗ 11.1).
///
/// Вертикальный список, а не сегменты в строку: подпись «Как в системе»
/// длинная и на узких экранах в сегменте не помещалась бы целиком.
class ThemeModeSelector extends ConsumerWidget {
  const ThemeModeSelector({super.key});

  static const List<ThemeMode> order = [
    ThemeMode.light,
    ThemeMode.dark,
    ThemeMode.system,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeControllerProvider);
    final palette = context.palette;

    // Material, а не DecoratedBox: ListTile рисует фон и «волну» нажатия
    // на ближайшем Material, и цветная подложка скрыла бы их.
    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.dense,
        side: BorderSide(color: palette.line, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, mode) in order.indexed) ...[
            if (index > 0) const Divider(height: 1),
            _ThemeModeTile(
              mode: mode,
              selected: mode == current,
              onTap: () => unawaited(
                ref
                    .read(themeModeControllerProvider.notifier)
                    .setThemeMode(mode),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ListTile(
        onTap: onTap,
        shape: AppRadii.denseShape,
        title: Text(mode.label),
        trailing: selected
            ? Icon(Icons.check_rounded, color: colors.primary)
            : null,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_typography.dart';

/// Короткий доступ к расширениям темы из виджетов:
/// `context.palette.monthToneFor(date)`, `context.textStyles.appTitle` и т.д.
extension AppThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);

  ColorScheme get colors => Theme.of(this).colorScheme;

  AppPalette get palette {
    final palette = Theme.of(this).extension<AppPalette>();
    assert(palette != null, 'AppPalette не подключена к ThemeData.extensions');
    return palette ?? AppPalette.light;
  }

  AppTextStyles get textStyles {
    final styles = Theme.of(this).extension<AppTextStyles>();
    assert(
      styles != null,
      'AppTextStyles не подключены к ThemeData.extensions',
    );
    return styles!;
  }
}

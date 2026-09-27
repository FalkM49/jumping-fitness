import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_palette.dart';
import 'app_radii.dart';
import 'app_typography.dart';

/// Светлая и тёмная темы приложения (ТЗ, раздел 11).
///
/// Что где:
/// * цвета — `app_colors.dart` (сырые токены) → [ColorScheme] + [AppPalette];
/// * шрифты — `app_typography.dart` (Unbounded + Manrope через google_fonts);
/// * скругления — `app_radii.dart` (4px «плотные» и 24/4/4/4 «лепесток»);
/// * выбор светлая/тёмная/системная — `theme_mode_controller.dart`.
abstract final class AppTheme {
  /// Светлая тема. [font] подменяется только в тестах.
  static ThemeData light({FontApplier font = googleFontApplier}) =>
      _build(scheme: lightScheme, palette: AppPalette.light, font: font);

  /// Тёмная тема. [font] подменяется только в тестах.
  static ThemeData dark({FontApplier font = googleFontApplier}) =>
      _build(scheme: darkScheme, palette: AppPalette.dark, font: font);

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.bloom,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: AppColors.bloomTintLight,
    onPrimaryContainer: AppColors.bloom,
    secondary: AppColors.coralPop,
    onSecondary: AppColors.inkPlum,
    secondaryContainer: AppColors.coralTintLight,
    onSecondaryContainer: AppColors.inkPlum,
    error: AppColors.remainingLow,
    onError: Color(0xFFFFFFFF),
    surface: AppColors.chalk,
    onSurface: AppColors.inkPlum,
    onSurfaceVariant: AppColors.stone,
    surfaceContainerLowest: AppColors.cardLight,
    surfaceContainerLow: AppColors.cardLight,
    surfaceContainer: AppColors.cardLight,
    surfaceContainerHigh: AppColors.cardLight,
    surfaceContainerHighest: AppColors.cardLight,
    outline: AppColors.stone,
    outlineVariant: AppColors.lineLight,
    shadow: AppColors.warmShadowLight,
    inverseSurface: AppColors.inkPlum,
    onInverseSurface: AppColors.chalk,
    inversePrimary: AppColors.bloomDark,
    // Без розового «налёта» Material 3 на приподнятых поверхностях.
    surfaceTint: Color(0x00000000),
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.bloomDark,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: AppColors.bloomTintDark,
    onPrimaryContainer: AppColors.bloomDark,
    secondary: AppColors.coralPopDark,
    onSecondary: AppColors.inkBase,
    secondaryContainer: AppColors.coralTintDark,
    onSecondaryContainer: AppColors.chalkText,
    error: AppColors.remainingLow,
    onError: Color(0xFFFFFFFF),
    surface: AppColors.inkBase,
    onSurface: AppColors.chalkText,
    onSurfaceVariant: AppColors.stoneDark,
    surfaceContainerLowest: AppColors.cardDark,
    surfaceContainerLow: AppColors.cardDark,
    surfaceContainer: AppColors.cardDark,
    surfaceContainerHigh: AppColors.cardDark,
    surfaceContainerHighest: AppColors.cardDark,
    outline: AppColors.stoneDark,
    outlineVariant: AppColors.lineDark,
    shadow: AppColors.warmShadowDark,
    inverseSurface: AppColors.chalkText,
    onInverseSurface: AppColors.inkBase,
    inversePrimary: AppColors.bloom,
    surfaceTint: Color(0x00000000),
  );

  static ThemeData _build({
    required ColorScheme scheme,
    required AppPalette palette,
    required FontApplier font,
  }) {
    // Базовая тема нужна, чтобы получить стандартную геометрию текста
    // Material 3 с уже проставленными цветами из схемы.
    final base = ThemeData(colorScheme: scheme);
    final textTheme = buildAppTextTheme(base.textTheme, font);
    final textStyles = AppTextStyles.build(
      scheme: scheme,
      palette: palette,
      font: font,
    );

    final thinLine = BorderSide(color: palette.line, width: 0.5);

    return ThemeData(
      colorScheme: scheme,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      dividerColor: palette.line,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[palette, textStyles],

      // Шапка: название «Jumping Fitness» стилем appTitle, без теней.
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: const Color(0x00000000),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: textStyles.appTitle,
      ),

      // Обычные карточки/строки — «плотные» (4px), без тени, с тонкой линией.
      // Смысловые блоки используют виджет PetalCard (лепесток 24/4/4/4).
      cardTheme: CardThemeData(
        color: palette.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.dense,
          side: thinLine,
        ),
      ),

      // Всплывающие окна — смысловые блоки: форма «лепесток».
      // Закрытие по тапу вне окна — поведение showDialog по умолчанию (ТЗ 9).
      dialogTheme: DialogThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: const Color(0x00000000),
        elevation: 0,
        shape: AppRadii.petalShape,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      // Кнопки — «плотные» элементы (4px).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: AppRadii.denseShape,
          minimumSize: const Size(64, 44),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: AppRadii.denseShape,
          minimumSize: const Size(64, 44),
          textStyle: textTheme.labelLarge,
        ),
      ),
      // Контурная кнопка (например, «Заморозить абонемент»):
      // тонкая рамка, текст основным цветом, а не серым.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: palette.line, width: 1.5),
          shape: AppRadii.denseShape,
          minimumSize: const Size(64, 44),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: AppRadii.denseShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: palette.card,
          foregroundColor: scheme.onSurface,
          selectedBackgroundColor: palette.bloomTint,
          selectedForegroundColor: scheme.primary,
          side: BorderSide(color: palette.line),
          shape: AppRadii.denseShape,
          textStyle: textTheme.labelLarge,
        ),
      ),

      // Поля ввода — «плотные» (4px).
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: palette.card,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadii.dense,
          borderSide: thinLine,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.dense,
          borderSide: thinLine,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.dense,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.dense,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadii.dense,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: palette.line,
        thickness: 0.5,
        space: 1,
      ),

      // Линейные иконки единой толщины (ТЗ 11.5).
      iconTheme: IconThemeData(color: scheme.onSurface, size: 22),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: AppRadii.denseShape,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
    );
  }
}

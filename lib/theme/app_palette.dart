import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Цвета приложения, которых нет в стандартной [ColorScheme]:
/// тона месяцев, функциональная шкала остатка, статус «Отменено» и т.п.
///
/// Подключается к [ThemeData.extensions], в виджетах берётся через
/// `context.palette` (см. `theme_context.dart`).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.card,
    required this.line,
    required this.bloomTint,
    required this.coralTint,
    required this.monthTones,
    required this.remainingHigh,
    required this.remainingLow,
    required this.remainingEmpty,
    required this.cancelled,
    required this.emphasisShadow,
  });

  /// Фон карточек и ячеек календаря.
  final Color card;

  /// Тонкие линии, рамки, разделители.
  final Color line;

  /// Мягкая подложка брендового цвета (доступная для записи ячейка).
  final Color bloomTint;

  /// Мягкая подложка акцентного цвета (плашка «Тренер»).
  final Color coralTint;

  /// Чередующиеся тона фона групп дней по месяцам (цикл).
  final List<Color> monthTones;

  /// Функциональная шкала: много осталось.
  final Color remainingHigh;

  /// Функциональная шкала: мало осталось.
  final Color remainingLow;

  /// Функциональная шкала: закончилось (чёрный / белый в тёмной теме).
  final Color remainingEmpty;

  /// Статус «Отменено».
  final Color cancelled;

  /// Едва заметная тёплая тень — только для самого важного элемента экрана.
  final List<BoxShadow> emphasisShadow;

  static const AppPalette light = AppPalette(
    card: AppColors.cardLight,
    line: AppColors.lineLight,
    bloomTint: AppColors.bloomTintLight,
    coralTint: AppColors.coralTintLight,
    monthTones: AppColors.monthTonesLight,
    remainingHigh: AppColors.remainingHigh,
    remainingLow: AppColors.remainingLow,
    remainingEmpty: AppColors.remainingEmptyLight,
    cancelled: AppColors.cancelled,
    emphasisShadow: [
      BoxShadow(
        color: AppColors.warmShadowLight,
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
    ],
  );

  static const AppPalette dark = AppPalette(
    card: AppColors.cardDark,
    line: AppColors.lineDark,
    bloomTint: AppColors.bloomTintDark,
    coralTint: AppColors.coralTintDark,
    monthTones: AppColors.monthTonesDark,
    remainingHigh: AppColors.remainingHigh,
    remainingLow: AppColors.remainingLow,
    remainingEmpty: AppColors.remainingEmptyDark,
    cancelled: AppColors.cancelled,
    emphasisShadow: [
      BoxShadow(
        color: AppColors.warmShadowDark,
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
    ],
  );

  /// Тон фона для месяца даты [date]. Индекс считается от абсолютного номера
  /// месяца, поэтому соседние месяцы всегда разного цвета, а один и тот же
  /// месяц — всегда одного, независимо от прокрутки ленты.
  Color monthToneFor(DateTime date) {
    final absoluteMonth = date.year * 12 + (date.month - 1);
    return monthTones[absoluteMonth % monthTones.length];
  }

  /// Цвет остатка тренировок/дней: плавно от зелёного (всё осталось)
  /// к красному (почти ничего), при нуле — [remainingEmpty] (ТЗ 5, 11.1).
  ///
  /// Интерполяция идёт в HSV, поэтому промежуточные значения проходят через
  /// жёлто-оранжевые тона (как `#E8A93D` в макете), а не через грязно-бурый,
  /// который дала бы прямая интерполяция RGB.
  Color remainingColor({required int remaining, required int total}) {
    if (remaining <= 0 || total <= 0) return remainingEmpty;
    if (remaining >= total) return remainingHigh;
    final t = remaining / total;
    return HSVColor.lerp(
      HSVColor.fromColor(remainingLow),
      HSVColor.fromColor(remainingHigh),
      t,
    )!.toColor();
  }

  @override
  AppPalette copyWith({
    Color? card,
    Color? line,
    Color? bloomTint,
    Color? coralTint,
    List<Color>? monthTones,
    Color? remainingHigh,
    Color? remainingLow,
    Color? remainingEmpty,
    Color? cancelled,
    List<BoxShadow>? emphasisShadow,
  }) {
    return AppPalette(
      card: card ?? this.card,
      line: line ?? this.line,
      bloomTint: bloomTint ?? this.bloomTint,
      coralTint: coralTint ?? this.coralTint,
      monthTones: monthTones ?? this.monthTones,
      remainingHigh: remainingHigh ?? this.remainingHigh,
      remainingLow: remainingLow ?? this.remainingLow,
      remainingEmpty: remainingEmpty ?? this.remainingEmpty,
      cancelled: cancelled ?? this.cancelled,
      emphasisShadow: emphasisShadow ?? this.emphasisShadow,
    );
  }

  @override
  AppPalette lerp(covariant ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      card: Color.lerp(card, other.card, t)!,
      line: Color.lerp(line, other.line, t)!,
      bloomTint: Color.lerp(bloomTint, other.bloomTint, t)!,
      coralTint: Color.lerp(coralTint, other.coralTint, t)!,
      monthTones: _lerpColorList(monthTones, other.monthTones, t),
      remainingHigh: Color.lerp(remainingHigh, other.remainingHigh, t)!,
      remainingLow: Color.lerp(remainingLow, other.remainingLow, t)!,
      remainingEmpty: Color.lerp(remainingEmpty, other.remainingEmpty, t)!,
      cancelled: Color.lerp(cancelled, other.cancelled, t)!,
      emphasisShadow:
          BoxShadow.lerpList(emphasisShadow, other.emphasisShadow, t) ??
          const [],
    );
  }

  static List<Color> _lerpColorList(List<Color> a, List<Color> b, double t) {
    if (a.length != b.length) return t < 0.5 ? a : b;
    return List<Color>.generate(
      a.length,
      (i) => Color.lerp(a[i], b[i], t)!,
      growable: false,
    );
  }
}

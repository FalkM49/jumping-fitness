import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

/// Семейства шрифтов (ТЗ 11.2).
abstract final class AppFonts {
  /// Заголовки, даты, крупные числовые счётчики.
  static const String heading = 'Unbounded';

  /// Основной текст интерфейса: списки, подписи, кнопки, детали.
  static const String body = 'Manrope';
}

/// Способ применить семейство шрифта к стилю.
///
/// В приложении — [googleFontApplier] (шрифты из Google Fonts через пакет
/// `google_fonts`). В тестах подставляется [plainFontApplier], чтобы тесты
/// не ходили в сеть за файлами шрифтов.
typedef FontApplier = TextStyle Function(String family, TextStyle base);

TextStyle googleFontApplier(String family, TextStyle base) =>
    GoogleFonts.getFont(family, textStyle: base);

TextStyle plainFontApplier(String family, TextStyle base) =>
    base.copyWith(fontFamily: family);

/// Собирает [TextTheme]: Unbounded — для display/headline/titleLarge,
/// Manrope — для всего остального.
///
/// Верхний регистр нигде не включается (ТЗ 11.2) — различия только за счёт
/// шрифта, размера и начертания.
TextTheme buildAppTextTheme(TextTheme base, FontApplier font) {
  TextStyle? heading(TextStyle? s) =>
      s == null ? null : font(AppFonts.heading, s);
  TextStyle? body(TextStyle? s) => s == null ? null : font(AppFonts.body, s);

  return base.copyWith(
    displayLarge: heading(base.displayLarge),
    displayMedium: heading(base.displayMedium),
    displaySmall: heading(base.displaySmall),
    headlineLarge: heading(base.headlineLarge),
    headlineMedium: heading(base.headlineMedium),
    headlineSmall: heading(base.headlineSmall),
    titleLarge: heading(base.titleLarge),
    titleMedium: body(base.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
    titleSmall: body(base.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
    bodyLarge: body(base.bodyLarge),
    bodyMedium: body(base.bodyMedium),
    bodySmall: body(base.bodySmall),
    labelLarge: body(base.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
    labelMedium: body(base.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
    labelSmall: body(base.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
  );
}

/// Именованные стили для особых мест интерфейса, прямо описанных в ТЗ 11.2.
/// В виджетах берутся через `context.textStyles`.
@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  const AppTextStyles({
    required this.appTitle,
    required this.dayPart,
    required this.counter,
    required this.cancelledLabel,
    required this.freezeButtonLabel,
    required this.moodCaption,
  });

  factory AppTextStyles.build({
    required ColorScheme scheme,
    required AppPalette palette,
    required FontApplier font,
  }) {
    return AppTextStyles(
      // «Jumping Fitness»: Unbounded, полужирный, увеличенный трекинг,
      // основной брендовый цвет, без эффектов.
      appTitle: font(
        AppFonts.heading,
        TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          height: 1.2,
          color: scheme.primary,
        ),
      ),
      // «Утро» / «Вечер»: Manrope 700, основной цвет текста, крупнее
      // обычного второстепенного текста.
      dayPart: font(
        AppFonts.body,
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.2,
          color: scheme.onSurface,
        ),
      ),
      // Крупный счётчик тренировок. Цвет задаётся на месте
      // через `palette.remainingColor(...)`.
      counter: font(
        AppFonts.heading,
        TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          height: 1.1,
          color: scheme.onSurface,
        ),
      ),
      // «Отменено»: Unbounded, полужирный, функциональный красный,
      // чуть крупнее обычного текста ячейки.
      cancelledLabel: font(
        AppFonts.heading,
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.2,
          color: palette.cancelled,
        ),
      ),
      // Подпись кнопки «Заморозить абонемент»: Manrope SemiBold,
      // основной (не серый) цвет текста.
      freezeButtonLabel: font(
        AppFonts.body,
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: scheme.onSurface,
        ),
      ),
      // «В этом месяце ты:» — заметно мельче цветочного блока.
      moodCaption: font(
        AppFonts.body,
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.3,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  final TextStyle appTitle;
  final TextStyle dayPart;
  final TextStyle counter;
  final TextStyle cancelledLabel;
  final TextStyle freezeButtonLabel;
  final TextStyle moodCaption;

  @override
  AppTextStyles copyWith({
    TextStyle? appTitle,
    TextStyle? dayPart,
    TextStyle? counter,
    TextStyle? cancelledLabel,
    TextStyle? freezeButtonLabel,
    TextStyle? moodCaption,
  }) {
    return AppTextStyles(
      appTitle: appTitle ?? this.appTitle,
      dayPart: dayPart ?? this.dayPart,
      counter: counter ?? this.counter,
      cancelledLabel: cancelledLabel ?? this.cancelledLabel,
      freezeButtonLabel: freezeButtonLabel ?? this.freezeButtonLabel,
      moodCaption: moodCaption ?? this.moodCaption,
    );
  }

  @override
  AppTextStyles lerp(covariant ThemeExtension<AppTextStyles>? other, double t) {
    if (other is! AppTextStyles) return this;
    return AppTextStyles(
      appTitle: TextStyle.lerp(appTitle, other.appTitle, t)!,
      dayPart: TextStyle.lerp(dayPart, other.dayPart, t)!,
      counter: TextStyle.lerp(counter, other.counter, t)!,
      cancelledLabel: TextStyle.lerp(cancelledLabel, other.cancelledLabel, t)!,
      freezeButtonLabel: TextStyle.lerp(
        freezeButtonLabel,
        other.freezeButtonLabel,
        t,
      )!,
      moodCaption: TextStyle.lerp(moodCaption, other.moodCaption, t)!,
    );
  }
}

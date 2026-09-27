import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/theme/app_colors.dart';
import 'package:jumping_fitness/theme/app_palette.dart';
import 'package:jumping_fitness/theme/app_radii.dart';
import 'package:jumping_fitness/theme/app_theme.dart';
import 'package:jumping_fitness/theme/app_typography.dart';

void main() {
  group('Токены ТЗ 11.1', () {
    test('светлая палитра', () {
      const s = AppTheme.lightScheme;
      expect(s.surface, const Color(0xFFF2F4EF)); // Chalk
      expect(s.primary, const Color(0xFFC81E5E)); // Bloom
      expect(s.secondary, const Color(0xFFFF6B5B)); // Coral Pop
      expect(s.onSurface, const Color(0xFF2B1D2A)); // Ink Plum
      expect(s.onSurfaceVariant, const Color(0xFF8B8478)); // Stone
    });

    test('тёмная палитра', () {
      const s = AppTheme.darkScheme;
      expect(s.surface, const Color(0xFF1C1418)); // Ink Base
      expect(s.primary, const Color(0xFFE85A8C)); // Bloom (тёмная)
      expect(s.secondary, const Color(0xFFFF8A73)); // Coral Pop (тёмная)
      expect(s.onSurface, const Color(0xFFF2F4EF)); // Chalk Text
      expect(s.onSurfaceVariant, const Color(0xFFA6A093)); // Stone (тёмная)
    });

    test('тона месяцев светлой темы', () {
      expect(AppColors.monthTonesLight, const [
        Color(0xFFF2F4EF),
        Color(0xFFEFE7EC),
        Color(0xFFE9F0EA),
      ]);
    });
  });

  group('AppPalette', () {
    const palette = AppPalette.light;

    test('соседние месяцы получают разные тона, цикл из трёх', () {
      final sep = palette.monthToneFor(DateTime(2026, 9, 25));
      final oct = palette.monthToneFor(DateTime(2026, 10, 1));
      final nov = palette.monthToneFor(DateTime(2026, 11, 1));
      final dec = palette.monthToneFor(DateTime(2026, 12, 1));
      expect({sep, oct, nov}.length, 3);
      expect(dec, sep);
    });

    test('тон месяца не зависит от дня внутри месяца', () {
      expect(
        palette.monthToneFor(DateTime(2026, 9, 1)),
        palette.monthToneFor(DateTime(2026, 9, 30)),
      );
    });

    test('граница года не ломает чередование', () {
      expect(
        palette.monthToneFor(DateTime(2026, 12, 1)),
        isNot(palette.monthToneFor(DateTime(2027, 1, 1))),
      );
    });

    test('шкала остатка: полный → зелёный, ноль → чёрный/белый', () {
      expect(
        palette.remainingColor(remaining: 11, total: 11),
        AppColors.remainingHigh,
      );
      expect(
        palette.remainingColor(remaining: 0, total: 11),
        const Color(0xFF000000),
      );
      expect(
        AppPalette.dark.remainingColor(remaining: 0, total: 11),
        const Color(0xFFFFFFFF),
      );
    });

    test('шкала остатка: середина — тёплый жёлто-оранжевый', () {
      final mid = HSVColor.fromColor(
        palette.remainingColor(remaining: 5, total: 11),
      );
      expect(mid.hue, inInclusiveRange(30, 90));
    });

    test('остаток больше начального не выходит за шкалу', () {
      expect(
        palette.remainingColor(remaining: 15, total: 11),
        AppColors.remainingHigh,
      );
    });

    test('«Отменено» — функциональный красный в обеих темах', () {
      expect(AppPalette.light.cancelled, const Color(0xFFE14F4F));
      expect(AppPalette.dark.cancelled, const Color(0xFFE14F4F));
    });
  });

  group('Радиусы ТЗ 11.3', () {
    test('плотные элементы — 4px', () {
      expect(AppRadii.dense, BorderRadius.circular(4));
    });

    test('лепесток — один угол 24px, остальные 4px', () {
      expect(AppRadii.petal.topLeft, const Radius.circular(24));
      expect(AppRadii.petal.topRight, const Radius.circular(4));
      expect(AppRadii.petal.bottomLeft, const Radius.circular(4));
      expect(AppRadii.petal.bottomRight, const Radius.circular(4));
    });
  });

  group('ThemeData', () {
    for (final (name, theme) in [
      ('светлая', AppTheme.light(font: plainFontApplier)),
      ('тёмная', AppTheme.dark(font: plainFontApplier)),
    ]) {
      test('$name: подключены расширения и шрифты', () {
        expect(theme.extension<AppPalette>(), isNotNull);
        expect(theme.extension<AppTextStyles>(), isNotNull);
        expect(theme.textTheme.headlineSmall?.fontFamily, AppFonts.heading);
        expect(theme.textTheme.bodyMedium?.fontFamily, AppFonts.body);
        expect(theme.textTheme.labelLarge?.fontFamily, AppFonts.body);

        final styles = theme.extension<AppTextStyles>()!;
        expect(styles.appTitle.fontFamily, AppFonts.heading);
        expect(styles.appTitle.color, theme.colorScheme.primary);
        expect(styles.cancelledLabel.color, const Color(0xFFE14F4F));
        expect(styles.dayPart.color, theme.colorScheme.onSurface);
        expect(styles.freezeButtonLabel.color, theme.colorScheme.onSurface);
      });

      test('$name: окна — «лепесток», кнопки и поля — 4px', () {
        expect(theme.dialogTheme.shape, AppRadii.petalShape);
        final border = theme.inputDecorationTheme.border;
        expect(border, isA<OutlineInputBorder>());
        expect((border! as OutlineInputBorder).borderRadius, AppRadii.dense);
      });
    }
  });
}

import 'package:flutter/widgets.dart';

/// Два языка скругления (ТЗ 11.3).
///
/// * [dense] — «плотные» элементы: ячейки календаря, обычные кнопки, поля ввода.
/// * [petal] — «смысловые» блоки-акценты: карточка абонемента, карточка-цветок,
///   окна подтверждения. Один угол 24px (верхний левый, как в mockup_v2),
///   остальные — 4px: лёгкая отсылка к лепестку.
abstract final class AppRadii {
  static const double denseValue = 4;
  static const double petalAccentValue = 24;

  static const Radius denseRadius = Radius.circular(denseValue);
  static const Radius petalAccentRadius = Radius.circular(petalAccentValue);

  /// Радиус 4px для всех углов.
  static const BorderRadius dense = BorderRadius.all(denseRadius);

  /// Асимметричный «лепесток»: 24px сверху слева, 4px на остальных углах.
  static const BorderRadius petal = BorderRadius.only(
    topLeft: petalAccentRadius,
    topRight: denseRadius,
    bottomLeft: denseRadius,
    bottomRight: denseRadius,
  );

  /// Плашка роли «Тренер» в профиле — полностью скруглённая, как в mockup_v2.
  /// Осознанное исключение из ТЗ 11.3, согласованное с заказчиком;
  /// для остальных элементов — только [dense] и [petal].
  static const BorderRadius badge = BorderRadius.all(Radius.circular(999));

  /// Готовые формы для `shape:` у Material-виджетов.
  static const RoundedRectangleBorder denseShape = RoundedRectangleBorder(
    borderRadius: dense,
  );

  static const RoundedRectangleBorder petalShape = RoundedRectangleBorder(
    borderRadius: petal,
  );
}

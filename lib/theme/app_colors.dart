import 'package:flutter/painting.dart';

/// Сырые цветовые токены (раздел 11.1 ТЗ + недостающие оттенки из mockup_v2).
///
/// Напрямую в виджетах эти константы не используются: виджеты берут цвета
/// из темы (`Theme.of(context).colorScheme` или `context.palette`), чтобы
/// светлая и тёмная тема переключались автоматически.
abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Светлая тема — брендовая палитра (ТЗ 11.1)
  // ---------------------------------------------------------------------------

  /// Chalk — основной фон приложения.
  static const Color chalk = Color(0xFFF2F4EF);

  /// Bloom — основной брендовый цвет: активные элементы, ключевые CTA.
  static const Color bloom = Color(0xFFC81E5E);

  /// Coral Pop — энергичный акцент: важные кнопки, бейджи.
  static const Color coralPop = Color(0xFFFF6B5B);

  /// Ink Plum — основной цвет текста (вместо чистого чёрного).
  static const Color inkPlum = Color(0xFF2B1D2A);

  /// Stone — второстепенный текст, разделители, неактивные элементы.
  static const Color stone = Color(0xFF8B8478);

  // Вспомогательные оттенки светлой темы (из mockup_v2.html).
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color lineLight = Color(0xFFE3E0D7);
  static const Color bloomTintLight = Color(0xFFF7DDE7);
  static const Color coralTintLight = Color(0xFFFFE3DD);

  // ---------------------------------------------------------------------------
  // Тёмная тема (ТЗ 11.1)
  // ---------------------------------------------------------------------------

  /// Ink Base — основной фон тёмной темы.
  static const Color inkBase = Color(0xFF1C1418);

  /// Bloom (тёмная) — светлее и мягче для контраста на тёмном фоне.
  static const Color bloomDark = Color(0xFFE85A8C);

  /// Coral Pop (тёмная) — слегка приглушённый акцент.
  static const Color coralPopDark = Color(0xFFFF8A73);

  /// Chalk Text — основной текст на тёмном фоне.
  static const Color chalkText = Color(0xFFF2F4EF);

  /// Stone (тёмная) — второстепенный текст, разделители.
  static const Color stoneDark = Color(0xFFA6A093);

  // Вспомогательные оттенки тёмной темы (из mockup_v2.html).
  static const Color cardDark = Color(0xFF2A1F24);
  static const Color lineDark = Color(0xFF3A2E33);
  static const Color bloomTintDark = Color(0xFF3A2530);
  static const Color coralTintDark = Color(0xFF3A2620);

  // ---------------------------------------------------------------------------
  // Тона месяцев в календаре — цикл из 3 оттенков (ТЗ 11.1)
  // ---------------------------------------------------------------------------

  static const List<Color> monthTonesLight = [
    Color(0xFFF2F4EF), // базовый
    Color(0xFFEFE7EC), // лёгкий розовый подтон
    Color(0xFFE9F0EA), // лёгкий зелёный подтон
  ];

  /// В ТЗ для тёмной темы не заданы — взяты из mockup_v2.html
  /// (те же подтоны, построенные от Ink Base).
  static const List<Color> monthTonesDark = [
    Color(0xFF1C1418),
    Color(0xFF241820),
    Color(0xFF1B211D),
  ];

  // ---------------------------------------------------------------------------
  // Функциональная шкала остатка тренировок/дней (ТЗ 11.1)
  // ---------------------------------------------------------------------------

  /// Много осталось.
  static const Color remainingHigh = Color(0xFF4CAF7D);

  /// Мало осталось. Этот же красный — статус «Отменено» в обеих темах.
  static const Color remainingLow = Color(0xFFE14F4F);

  /// Закончилось — светлая тема.
  static const Color remainingEmptyLight = Color(0xFF000000);

  /// Закончилось — тёмная тема (белый, чтобы оставаться контрастным).
  static const Color remainingEmptyDark = Color(0xFFFFFFFF);

  /// Статус «Отменено» (ТЗ 11.2) — одинаковый в обеих темах.
  static const Color cancelled = remainingLow;

  // ---------------------------------------------------------------------------
  // Тени (ТЗ 11.3): только под самым важным элементом, тёплого оттенка.
  // ---------------------------------------------------------------------------

  static const Color warmShadowLight = Color(0x1F8A3A4A);
  static const Color warmShadowDark = Color(0x66000000);
}

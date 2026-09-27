import 'package:flutter/material.dart';

import '../theme/theme_context.dart';

/// Название приложения в шапке (ТЗ 3, 11.2): Unbounded, полужирный,
/// увеличенный трекинг, брендовый цвет. Без обводок, теней и верхнего регистра.
class AppTitle extends StatelessWidget {
  const AppTitle({super.key});

  static const String text = 'Jumping Fitness';

  @override
  Widget build(BuildContext context) {
    // На узком экране (iPhone, 375 точек, три значка в шапке) название
    // чуть уменьшается целиком, а не обрезается.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        style: context.textStyles.appTitle,
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}

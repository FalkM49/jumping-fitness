import 'package:flutter/material.dart';

import '../theme/theme_context.dart';

/// Название приложения в шапке (ТЗ 3, 11.2): Unbounded, полужирный,
/// увеличенный трекинг, брендовый цвет. Без обводок, теней и верхнего регистра.
class AppTitle extends StatelessWidget {
  const AppTitle({super.key});

  static const String text = 'Jumping Fitness';

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: context.textStyles.appTitle,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
    );
  }
}

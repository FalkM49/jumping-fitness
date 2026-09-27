import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/theme_context.dart';

/// Карточка для смысловых блоков-акцентов (ТЗ 11.3): абонемент,
/// карточка-цветок в профиле. Форма «лепесток» 24/4/4/4.
///
/// [emphasized] — включает едва заметную тёплую тень. По ТЗ тень допустима
/// только у самого важного элемента экрана, поэтому по умолчанию выключена.
class PetalCard extends StatelessWidget {
  const PetalCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.emphasized = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: AppRadii.petal,
        border: Border.all(color: palette.line, width: 0.5),
        boxShadow: emphasized ? palette.emphasisShadow : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

import 'package:flutter/material.dart';

/// Открыть окно поверх экрана — везде вместо `showDialog` (docs/09, шаг 4).
///
/// Перед открытием фокус снимается, а само окно фокус не забирает
/// (`requestFocus: false`). Иначе после закрытия Flutter возвращал фокус
/// в поле «Поиск по ФИО», и на iPhone выезжала клавиатура: Safari сдвигал
/// страницу, и нажатия начинали попадать мимо кнопок.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    useRootNavigator: true,
    requestFocus: false,
  );
}

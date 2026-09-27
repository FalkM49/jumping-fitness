import 'package:flutter/material.dart';

import '../../widgets/petal_card.dart';

/// Общая раскладка экранов входа и регистрации: заголовок, пояснение
/// и форма в карточке-«лепестке» по центру, с прокруткой, чтобы
/// клавиатура ничего не перекрывала.
class AuthFormLayout extends StatelessWidget {
  const AuthFormLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.notice,
  });

  final String title;
  final Widget subtitle;
  final List<Widget> children;

  /// Необязательное предупреждение над формой.
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (notice != null) ...[notice!, const SizedBox(height: 16)],
                PetalCard(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title, style: textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      DefaultTextStyle.merge(
                        style: textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        child: subtitle,
                      ),
                      const SizedBox(height: 20),
                      ...children,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка с индикатором загрузки вместо текста, пока идёт запрос.
class BusyFilledButton extends StatelessWidget {
  const BusyFilledButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}

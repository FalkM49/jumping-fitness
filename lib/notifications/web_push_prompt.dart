import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';
import '../services/backend_providers.dart';
import '../widgets/info_notice.dart';
import 'display_mode.dart';
import 'push_service.dart';

/// Что подсказать на главном экране веб-версии.
enum WebPushHint {
  /// Ничего: push уже работает, запрещён или браузер их не умеет.
  none,

  /// iPhone, сайт открыт в Safari: сначала добавить на экран «Домой».
  installToHomeScreen,

  /// Можно включить уведомления кнопкой.
  enable,
}

/// Подсказка для текущего устройства. Не в браузере — всегда [WebPushHint.none].
@visibleForTesting
WebPushHint webPushHintFor({
  required bool isWeb,
  required bool isIos,
  required bool standalone,
  required PushPermission permission,
}) {
  if (!isWeb) return WebPushHint.none;
  return switch (permission) {
    PushPermission.notAsked => WebPushHint.enable,
    PushPermission.unsupported when isIos && !standalone =>
      WebPushHint.installToHomeScreen,
    _ => WebPushHint.none,
  };
}

/// Плашка над главным экраном веб-версии (для iPhone без App Store):
/// «Добавьте на экран Домой» или «Включите уведомления». В браузере
/// разрешение можно запросить только по нажатию — отсюда кнопка.
class WebPushPrompt extends ConsumerStatefulWidget {
  const WebPushPrompt({super.key});

  @override
  ConsumerState<WebPushPrompt> createState() => _WebPushPromptState();
}

class _WebPushPromptState extends ConsumerState<WebPushPrompt> {
  WebPushHint _hint = WebPushHint.none;
  bool _busy = false;
  bool _dismissed = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final permission = await ref.read(pushServiceProvider).permission();
    if (!mounted) return;
    setState(
      () => _hint = webPushHintFor(
        isWeb: kIsWeb,
        isIos: defaultTargetPlatform == TargetPlatform.iOS,
        standalone: isStandaloneWebApp(),
        permission: permission,
      ),
    );
  }

  Future<void> _enable() async {
    final uid = ref.read(currentProfileProvider)?.uid;
    if (uid == null || _busy) return;
    setState(() => _busy = true);
    final enabled = await ref.read(pushServiceProvider).enable(uid);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = enabled
          ? 'Готово: уведомления будут приходить на это устройство.'
          : 'Уведомления не включены. Разрешить их можно в настройках '
                'браузера или телефона.';
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final result = _result;
    if (result != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InfoNotice(icon: Icons.notifications_outlined, text: result),
      );
    }
    return switch (_hint) {
      WebPushHint.none => const SizedBox.shrink(),
      WebPushHint.installToHomeScreen => _Card(
        icon: Icons.add_to_home_screen_rounded,
        text:
            'Установите приложение: в Safari нажмите «Поделиться» → '
            '«На экран „Домой“» и открывайте его с иконки. Так будут '
            'приходить уведомления об изменениях тренировок.',
        onClose: () => setState(() => _dismissed = true),
      ),
      WebPushHint.enable => _Card(
        icon: Icons.notifications_active_outlined,
        text:
            'Включите уведомления, чтобы узнавать об отмене и переносе '
            'тренировок и о сроке абонемента.',
        action: _busy ? null : () => unawaited(_enable()),
        actionLabel: 'Включить уведомления',
        onClose: () => setState(() => _dismissed = true),
      ),
    };
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.text,
    required this.onClose,
    this.action,
    this.actionLabel,
  });

  final IconData icon;
  final String text;
  final VoidCallback onClose;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 28),
                child: InfoNotice(icon: icon, text: text),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  tooltip: 'Скрыть',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onClose,
                ),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: action, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

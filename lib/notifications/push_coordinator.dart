import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../routing/app_keys.dart';
import '../services/backend_providers.dart';
import 'deep_link.dart';
import 'notification_providers.dart';
import 'push_service.dart';

/// Push для вошедшего пользователя — живёт вокруг главного экрана.
///
/// - Приложение открыто: пришедший push показывается баннером внутри
///   приложения с кнопкой «Открыть».
/// - Приложение в фоне или закрыто: система сама показывает уведомление;
///   по тапу приложение открывается, и здесь выполняется переход к нужному
///   экрану.
class PushCoordinator extends ConsumerStatefulWidget {
  const PushCoordinator({super.key, required this.uid, required this.child});

  final String uid;
  final Widget child;

  @override
  ConsumerState<PushCoordinator> createState() => _PushCoordinatorState();
}

class _PushCoordinatorState extends ConsumerState<PushCoordinator> {
  final _subscriptions = <StreamSubscription<PushMessage>>[];

  @override
  void initState() {
    super.initState();
    final push = ref.read(pushServiceProvider);
    _subscriptions
      ..add(push.foreground.listen(_showBanner))
      ..add(push.opened.listen(_openLater));
    unawaited(push.start(widget.uid));
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  /// Тап по системному уведомлению: переход после ближайшего кадра, чтобы
  /// главный экран (и навигатор) уже был построен — например, при запуске
  /// приложения из закрытого состояния.
  void _openLater(PushMessage message) {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (mounted) openDeepLink(ref, DeepLink.fromData(message.data));
    });
    binding.scheduleFrame();
  }

  void _showBanner(PushMessage message) {
    final messenger = appMessengerKey.currentState;
    if (messenger == null) return;
    final link = DeepLink.fromData(message.data);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.title.isNotEmpty)
                Text(
                  message.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              if (message.body.isNotEmpty) Text(message.body),
            ],
          ),
          action: link is OpenHome
              ? null
              : SnackBarAction(
                  label: 'Открыть',
                  onPressed: () => openDeepLink(ref, link),
                ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

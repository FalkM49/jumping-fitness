import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/session.dart';
import '../../models/models.dart';
import '../../notifications/deep_link.dart';
import '../../notifications/notification_providers.dart';
import '../../services/backend_providers.dart';
import '../../theme/app_radii.dart';
import '../../theme/theme_context.dart';
import '../../utils/ru_format.dart';

/// История уведомлений (этап 7): всё, что приходило push-сообщениями,
/// даже если push пропустили. Открытие экрана отмечает всё прочитанным.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _marked = <String>{};

  void _markRead(List<AppNotification> items) {
    final uid = ref.read(currentProfileProvider)?.uid;
    final unread = [
      for (final n in items)
        if (!n.read && !_marked.contains(n.id)) n.id,
    ];
    if (uid == null || unread.isEmpty) return;
    _marked.addAll(unread);
    unawaited(
      ref
          .read(notificationsRepositoryProvider)
          .markRead(uid, unread)
          .catchError((Object e) => debugPrint('Уведомления: $e')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider);
    final textTheme = Theme.of(context).textTheme;
    final items = async.value;
    if (items != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _markRead(items));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Уведомления', style: textTheme.titleLarge)),
      body: switch (async) {
        AsyncValue(:final value?) when value.isEmpty => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Уведомлений пока нет.',
              style: textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        AsyncValue(:final value?) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _NotificationTile(notification: value[i]),
        ),
        AsyncValue(hasError: true) => const Center(
          child: Text('Не удалось загрузить уведомления.'),
        ),
        _ => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      },
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  /// Линейные значки одной толщины (ТЗ 11.5).
  static IconData iconFor(String kind) => switch (kind) {
    'training_changed' => Icons.schedule_outlined,
    'training_cancelled' => Icons.event_busy_outlined,
    'removed_from_training' => Icons.person_remove_outlined,
    'subscription_ending_soon' => Icons.hourglass_bottom_outlined,
    'subscription_low_trainings' => Icons.confirmation_number_outlined,
    'subscription_expired' => Icons.error_outline_rounded,
    'trainer_request_new' => Icons.how_to_reg_outlined,
    'trainer_request_approved' => Icons.verified_outlined,
    'trainer_request_rejected' => Icons.person_off_outlined,
    _ => Icons.notifications_none_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final palette = context.palette;
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final link = DeepLink.fromData(n.data);

    return Material(
      color: n.read ? palette.card : palette.bloomTint,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.dense,
        side: BorderSide(color: palette.line, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: link is OpenHome ? null : () => openDeepLink(ref, link),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                iconFor(n.kind),
                color: n.read ? colors.onSurfaceVariant : colors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(n.body, style: textTheme.bodyMedium),
                    if (n.createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        RuFormat.dateTime(n.createdAt!),
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

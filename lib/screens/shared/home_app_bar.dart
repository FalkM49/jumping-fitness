import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/notification_providers.dart';
import '../../routing/app_router.dart';
import '../../widgets/app_title.dart';

/// Общая шапка главных экранов клиента и тренера: слева — уведомления со
/// счётчиком непрочитанных, по центру — название приложения, справа —
/// настройки и выход. У всех ролей одинаковая, и название стоит ровно
/// по центру (вход в «Заявки в тренеры» у администратора — строкой на
/// главном экране).
///
/// Статус «Тренер» в шапке не показывается — по ТЗ (раздел 4) он живёт
/// плашкой рядом с ФИО в профиле.
class HomeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);

    return AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: unread == 0 ? 'Уведомления' : 'Уведомления: новых $unread',
        onPressed: () =>
            Navigator.of(context).pushNamed(AppRoutes.notifications),
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 9 ? '9+' : '$unread'),
          child: Icon(
            unread > 0
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
          ),
        ),
      ),
      title: const AppTitle(),
      actions: [
        IconButton(
          tooltip: 'Настройки',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
        ),
        IconButton(
          tooltip: 'Выйти',
          icon: const Icon(Icons.logout_rounded),
          onPressed: () => unawaited(_confirmSignOut(context, ref)),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Чтобы войти снова, понадобятся почта и пароль.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (confirmed == true) await signOut(ref);
  }
}

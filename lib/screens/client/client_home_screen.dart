import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/session.dart';
import '../../client/calendar_cells.dart';
import '../../client/client_providers.dart';
import '../../models/models.dart';
import '../../notifications/web_push_prompt.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/info_notice.dart';
import '../../widgets/section_title.dart';
import '../shared/home_app_bar.dart';
import '../shared/profile_card.dart';
import '../shared/studio_calendar.dart';
import 'subscription_card.dart';
import 'training_details_dialog.dart';

/// Главный экран клиента (ТЗ 9): календарь → профиль → абонемент.
/// Экран прокручивается, если не помещается, но остаётся компактным.
class ClientHomeScreen extends ConsumerWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final request = profile == null
        ? null
        : ref.watch(ownTrainerRequestProvider(profile.uid)).value;
    final subscription = ref.watch(currentSubscriptionProvider).value;
    final settings = ref.watch(settingsProvider).value ?? AppSettings.fallback;
    final today = ref.watch(todayProvider);

    final requestNotice = switch (request?.status) {
      TrainerRequestStatus.pending =>
        'Заявка на роль тренера отправлена. Пока администратор её '
            'рассматривает, вы пользуетесь приложением как клиент.',
      TrainerRequestStatus.rejected =>
        'Заявку на роль тренера отклонили. Если это ошибка, обратитесь '
            'к администратору студии.',
      TrainerRequestStatus.approved || null => null,
    };
    final banners = [
      ...subscriptionBanners(
        subscription: subscription,
        today: today,
        settings: settings,
      ),
      if (requestNotice != null) InfoNotice(text: requestNotice),
    ];

    return Scaffold(
      appBar: const HomeAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          const WebPushPrompt(),
          for (final banner in banners)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: banner),
          const SectionTitle('Календарь'),
          StudioCalendar(
            mode: CalendarMode.client,
            onOpenCell: (context, day, slot) => showAppDialog<void>(
              context: context,
              builder: (_) => TrainingDetailsDialog(day: day, slot: slot),
            ),
          ),
          const SectionTitle('Профиль'),
          const ProfileCard(),
          const SectionTitle('Абонемент'),
          const SubscriptionCard(),
        ],
      ),
    );
  }
}

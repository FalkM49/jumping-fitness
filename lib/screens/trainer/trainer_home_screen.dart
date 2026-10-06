import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/session.dart';
import '../../client/calendar_cells.dart';
import '../../notifications/web_push_prompt.dart';
import '../../widgets/section_title.dart';
import '../../widgets/trainer_badge.dart';
import '../admin/trainer_requests_entry.dart';
import '../shared/home_app_bar.dart';
import '../shared/profile_card.dart';
import '../shared/studio_calendar.dart';
import 'clients_section.dart';
import 'trainer_cell_dialog.dart';

/// Главный экран тренера (ТЗ 9): общий календарь → профиль с плашкой
/// «Тренер» → список клиентов с поиском. Администратор видит этот же экран
/// (у него все права тренера) и дополнительно раздел заявок в шапке.
class TrainerHomeScreen extends ConsumerWidget {
  const TrainerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final isTrainer = profile?.isTrainer ?? false;
    final isAdmin = profile?.isAdmin ?? false;

    return Scaffold(
      appBar: const HomeAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          const WebPushPrompt(),
          if (isAdmin) ...[
            const SizedBox(height: 8),
            const TrainerRequestsEntry(),
          ],
          const SectionTitle('Календарь (общий)'),
          StudioCalendar(
            mode: CalendarMode.trainer,
            onOpenCell: (context, day, slot) => showDialog<void>(
              context: context,
              builder: (_) => TrainerCellDialog(day: day, slot: slot),
            ),
          ),
          const SectionTitle('Профиль'),
          ProfileCard(
            trailing: TrainerBadge(
              label: isTrainer ? 'Тренер' : 'Администратор',
            ),
          ),
          const SectionTitle('Клиенты'),
          const ClientsSection(),
        ],
      ),
    );
  }
}

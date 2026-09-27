import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/session.dart';
import '../../client/client_providers.dart';
import '../../models/models.dart';
import '../../theme/theme_context.dart';
import '../../widgets/flower_art.dart';
import '../../widgets/petal_card.dart';

/// Блок профиля (ТЗ 4): «В этом месяце ты:» — над цветком, цветок в тонкой
/// рамке (тап — окно с названием, описанием и значением), ФИО отдельно под
/// цветочным блоком. [trailing] — например, плашка «Тренер» (этап 6).
class ProfileCard extends ConsumerWidget {
  const ProfileCard({super.key, this.trailing});

  final Widget? trailing;

  static const double flowerSize = 112;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final flower = ref.watch(monthlyFlowerProvider).value;
    final today = ref.watch(todayProvider);
    if (profile == null) return const SizedBox.shrink();

    // Цветка на этот месяц ещё нет — просим сервер назначить (раз в месяц).
    if (profile.monthlyFlower?.month != today.monthKey) {
      ref.watch(
        ensureMonthlyFlowerProvider((uid: profile.uid, month: today.monthKey)),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    return PetalCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        children: [
          Text('В этом месяце ты:', style: context.textStyles.moodCaption),
          const SizedBox(height: 10),
          Semantics(
            button: flower != null,
            label: flower == null
                ? 'Цветок месяца'
                : 'Цветок месяца: ${flower.name}',
            child: GestureDetector(
              onTap: flower == null ? null : () => _showFlower(context, flower),
              child: _FlowerFrame(flowerId: flower?.id),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                profile.fullName,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }

  static void _showFlower(BuildContext context, Flower flower) {
    showDialog<void>(
      context: context,
      builder: (_) => FlowerDialog(flower: flower),
    );
  }
}

/// Цветок в тонкой рамке-обводке, форма рамки — «лепесток», как в макете.
class _FlowerFrame extends StatelessWidget {
  const _FlowerFrame({required this.flowerId});

  final String? flowerId;

  static const BorderRadius shape = BorderRadius.only(
    topLeft: Radius.circular(56),
    bottomRight: Radius.circular(56),
    topRight: Radius.circular(12),
    bottomLeft: Radius.circular(12),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: ProfileCard.flowerSize,
      height: ProfileCard.flowerSize,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(color: palette.line, width: 1.5),
        color: palette.monthTones.length > 1 ? palette.monthTones[1] : null,
      ),
      child: flowerId == null
          ? Center(
              child: Icon(
                Icons.local_florist_outlined,
                color: context.colors.onSurfaceVariant,
                size: 36,
              ),
            )
          : FlowerArt(flowerId: flowerId),
    );
  }
}

/// Окно цветка: название, краткое описание, значение на языке цветов (ТЗ 4, 12).
class FlowerDialog extends StatelessWidget {
  const FlowerDialog({super.key, required this.flower});

  final Flower flower;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(flower.name),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: FlowerArt(flowerId: flower.id, size: 120)),
            const SizedBox(height: 16),
            Text(flower.description, style: textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text(
              'Значение на языке цветов',
              style: textTheme.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(flower.meaning, style: textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

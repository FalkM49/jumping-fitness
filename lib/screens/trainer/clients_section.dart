import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_radii.dart';
import '../../theme/theme_context.dart';
import '../../trainer/client_list.dart';
import '../../trainer/trainer_providers.dart';
import '../../utils/ru_format.dart';
import '../../widgets/app_dialog.dart';
import 'client_card_dialog.dart';

/// Список клиентов под профилем тренера (ТЗ 6): поиск по ФИО на лету,
/// сортировка (по умолчанию — по оставшимся тренировкам), тап — карточка.
/// Список не ограничен по длине и прокручивается вместе с экраном.
class ClientsSection extends ConsumerStatefulWidget {
  const ClientsSection({super.key});

  @override
  ConsumerState<ClientsSection> createState() => _ClientsSectionState();
}

class _ClientsSectionState extends ConsumerState<ClientsSection> {
  final _search = TextEditingController();
  ClientSort _sort = ClientSort.trainings;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(clientSummariesProvider);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          // «Готово» на клавиатуре и нажатие вне поля убирают клавиатуру.
          // Окна открываются через showAppDialog — фокус сюда не вернётся.
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          // Не прокручивать ленту к полю при появлении клавиатуры: в Safari
          // это сдвигало страницу (docs/09, шаг 4).
          scrollPadding: EdgeInsets.zero,
          decoration: InputDecoration(
            hintText: 'Поиск по ФИО',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Очистить',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        SegmentedButton<ClientSort>(
          showSelectedIcon: false,
          segments: [
            for (final sort in ClientSort.values)
              ButtonSegment(value: sort, label: Text(sort.label)),
          ],
          selected: {_sort},
          onSelectionChanged: (s) => setState(() => _sort = s.first),
        ),
        const SizedBox(height: 10),
        switch (async) {
          AsyncValue(:final value?) => _ClientList(
            clients: sortClients(searchClients(value, _search.text), _sort),
            hasAny: value.isNotEmpty,
          ),
          AsyncValue(hasError: true) => Text(
            'Не удалось загрузить клиентов. Проверьте интернет.',
            style: textTheme.bodyMedium,
          ),
          _ => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        },
      ],
    );
  }
}

class _ClientList extends StatelessWidget {
  const _ClientList({required this.clients, required this.hasAny});

  final List<ClientSummary> clients;
  final bool hasAny;

  @override
  Widget build(BuildContext context) {
    if (clients.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          hasAny ? 'Никого не нашли.' : 'Клиентов пока нет.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final client in clients)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ClientRow(client: client),
          ),
      ],
    );
  }
}

/// Строка клиента: точка цвета остатка, ФИО, «N тренировок · M дней».
class ClientRow extends StatelessWidget {
  const ClientRow({super.key, required this.client});

  final ClientSummary client;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final sub = client.subscription;

    final meta = sub == null
        ? 'Нет абонемента'
        : !client.isActive && client.daysLeft == 0
        ? 'Абонемент истёк'
        : 'Осталось ${RuFormat.count(client.trainingsLeft, 'тренировка', 'тренировки', 'тренировок')} · '
              '${RuFormat.count(client.daysLeft, 'день', 'дня', 'дней')}';

    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.dense,
        side: BorderSide(color: palette.line, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAppDialog<void>(
          context: context,
          builder: (_) => ClientCardDialog(clientId: client.profile.uid),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.remainingColor(
                    remaining: client.trainingsLeft,
                    total: sub?.trainingsTotal ?? 0,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.profile.fullName,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

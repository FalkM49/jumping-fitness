import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/phone_number.dart';
import '../../auth/session.dart';
import '../../models/trainer_request.dart';
import '../../services/backend_providers.dart';
import '../../services/cloud_functions.dart';
import '../../theme/theme_context.dart';
import '../../utils/ru_format.dart';
import '../../widgets/app_dialog.dart';

/// Ожидающие заявки в тренеры — живой список из Firestore.
final pendingTrainerRequestsProvider =
    StreamProvider.autoDispose<List<TrainerRequest>>(
      (ref) => ref.watch(trainerRequestsRepositoryProvider).watchPending(),
    );

/// «Заявки в тренеры» (ТЗ 2) — только для администратора.
///
/// Один экран-список: ФИО, телефон, дата подачи и две кнопки. Заявка
/// исчезает из списка сама, как только сервер записал решение.
class TrainerRequestsScreen extends ConsumerWidget {
  const TrainerRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(currentProfileProvider)?.isAdmin ?? false;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Заявки в тренеры', style: textTheme.titleLarge),
      ),
      body: isAdmin
          ? const _RequestsList()
          : const _Message(
              title: 'Нет доступа',
              text: 'Этот раздел доступен только администратору.',
            ),
    );
  }
}

class _RequestsList extends ConsumerWidget {
  const _RequestsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(pendingTrainerRequestsProvider);

    return switch (requests) {
      AsyncValue(:final value?) when value.isEmpty => const _Message(
        title: 'Новых заявок нет',
        text:
            'Когда кто-то при регистрации выберет «Хочу стать тренером», '
            'заявка появится здесь.',
      ),
      AsyncValue(:final value?) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: value.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) =>
            _RequestCard(key: ValueKey(value[i].uid), request: value[i]),
      ),
      AsyncValue(:final error?) => _Message(
        title: 'Не удалось загрузить заявки',
        text: 'Проверьте интернет и попробуйте снова.',
        action: FilledButton(
          onPressed: () => ref.invalidate(pendingTrainerRequestsProvider),
          child: const Text('Повторить'),
        ),
        debugError: error,
      ),
      _ => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    };
  }
}

enum _Decision {
  approve(confirmTitle: 'Одобрить заявку?', confirmAction: 'Одобрить'),
  reject(confirmTitle: 'Отклонить заявку?', confirmAction: 'Отклонить');

  const _Decision({required this.confirmTitle, required this.confirmAction});

  final String confirmTitle;
  final String confirmAction;
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({super.key, required this.request});

  final TrainerRequest request;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  _Decision? _inProgress;

  Future<void> _decide(_Decision decision) async {
    final request = widget.request;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(decision.confirmTitle),
        content: Text(switch (decision) {
          _Decision.approve =>
            '${request.fullName} получит права тренера и уведомление.',
          _Decision.reject =>
            '${request.fullName} останется клиентом. Подать заявку '
                'повторно из приложения будет нельзя.',
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(decision.confirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(trainerRequestsRepositoryProvider);
    setState(() => _inProgress = decision);
    try {
      switch (decision) {
        case _Decision.approve:
          await repository.approve(request.uid);
        case _Decision.reject:
          await repository.reject(request.uid);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (decision) {
            _Decision.approve => '${request.fullName} теперь тренер.',
            _Decision.reject => 'Заявка ${request.fullName} отклонена.',
          }),
        ),
      );
    } on CloudFunctionFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _inProgress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final textTheme = Theme.of(context).textTheme;
    final colors = context.colors;
    final createdAt = request.createdAt;
    final busy = _inProgress != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(request.fullName, style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              PhoneNumber.format(request.phone),
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Text(
              createdAt == null
                  ? 'Подана только что'
                  : 'Подана ${RuFormat.dateTime(createdAt)}',
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => _decide(_Decision.approve),
                    child: _inProgress == _Decision.approve
                        ? const _ButtonSpinner()
                        : const Text('Одобрить'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _decide(_Decision.reject),
                    child: _inProgress == _Decision.reject
                        ? const _ButtonSpinner()
                        : const Text('Отклонить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.text,
    this.action,
    this.debugError,
  });

  final String title;
  final String text;
  final Widget? action;
  final Object? debugError;

  @override
  Widget build(BuildContext context) {
    if (debugError != null) debugPrint('Заявки: $debugError');
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

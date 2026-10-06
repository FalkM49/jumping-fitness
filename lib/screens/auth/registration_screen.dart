import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_repository.dart';
import '../../auth/full_name.dart';
import '../../auth/phone_number.dart';
import '../../services/backend_providers.dart';
import '../../services/user_repository.dart';
import '../../theme/app_radii.dart';
import '../../theme/theme_context.dart';
import '../../widgets/app_title.dart';
import 'auth_form_layout.dart';

/// Первая регистрация (ТЗ 2): ФИО, телефон для связи и выбор роли.
///
/// «Хочу стать тренером» создаёт заявку, но доступ сразу выдаётся
/// клиентский — чтобы человек не ждал решения администратора впустую.
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key, required this.user});

  final AuthUser user;

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  bool _wantsTrainerRole = false;
  bool _busy = false;
  String? _nameError;
  String? _phoneError;
  String? _submitError;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final nameError = fullNameError(_fullName.text);
    final phone = PhoneNumber.normalize(_phone.text);
    setState(() {
      _nameError = nameError;
      _phoneError = phone == null
          ? 'Введите номер полностью, например +7 999 123-45-67.'
          : null;
      _submitError = null;
    });
    if (nameError != null || phone == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(userRepositoryProvider)
          .register(
            user: widget.user,
            fullName: _fullName.text,
            phone: phone,
            wantsTrainerRole: _wantsTrainerRole,
          );
      // Администраторам — уведомление о заявке. Ошибка не мешает: заявка
      // уже подана и видна на экране заявок.
      if (_wantsTrainerRole) {
        unawaited(
          ref
              .read(studioFunctionsProvider)
              .notifyTrainerRequest()
              .catchError((Object e) => debugPrint('Заявка: $e')),
        );
      }
      // Экран сменится сам, как только появится профиль.
    } on RegistrationFailure catch (failure) {
      if (mounted) setState(() => _submitError = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() => ref.read(authRepositoryProvider).signOut();

  @override
  Widget build(BuildContext context) {
    final email = widget.user.email;

    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _busy ? null : () => unawaited(_signOut()),
          ),
        ],
      ),
      body: AuthFormLayout(
        title: 'Знакомство',
        subtitle: Text(
          email == null
              ? 'Осталось представиться.'
              : 'Почта $email подтверждена. Осталось представиться.',
        ),
        children: [
          TextField(
            controller: _fullName,
            autofocus: true,
            readOnly: _busy,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            maxLength: 100,
            decoration: InputDecoration(
              labelText: 'ФИО',
              hintText: 'Смирнова Анна Сергеевна',
              helperText: 'По ним тренер найдёт вас в списке клиентов',
              counterText: '',
              errorText: _nameError,
              errorMaxLines: 2,
            ),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            readOnly: _busy,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d+()\- ]')),
              LengthLimitingTextInputFormatter(20),
            ],
            decoration: InputDecoration(
              labelText: 'Телефон',
              hintText: '+7 999 123-45-67',
              helperText: 'Для связи: его видит тренер',
              errorText: _phoneError,
              errorMaxLines: 2,
            ),
            onChanged: (_) {
              if (_phoneError != null) setState(() => _phoneError = null);
            },
            onSubmitted: (_) => unawaited(_submit()),
          ),
          const SizedBox(height: 20),
          Text('Кто вы?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _RoleOption(
            title: 'Клиент',
            description: 'Запись на тренировки и учёт абонемента.',
            selected: !_wantsTrainerRole,
            enabled: !_busy,
            onTap: () => setState(() => _wantsTrainerRole = false),
          ),
          const SizedBox(height: 8),
          _RoleOption(
            title: 'Хочу стать тренером',
            description:
                'Заявку рассмотрит администратор. Пока решения нет, '
                'вы пользуетесь приложением как клиент.',
            selected: _wantsTrainerRole,
            enabled: !_busy,
            onTap: () => setState(() => _wantsTrainerRole = true),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 16),
            Text(
              _submitError!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.colors.error),
            ),
          ],
          const SizedBox(height: 20),
          BusyFilledButton(
            label: 'Готово',
            busy: _busy,
            onPressed: () => unawaited(_submit()),
          ),
        ],
      ),
    );
  }
}

/// Вариант роли: карточка с отметкой, выбирается нажатием.
class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.title,
    required this.description,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? palette.bloomTint : palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.dense,
          side: BorderSide(
            color: selected ? colors.primary : palette.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
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

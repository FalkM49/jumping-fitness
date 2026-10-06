import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/login_controller.dart';
import '../../routing/app_router.dart';
import '../../services/firebase_bootstrap.dart';
import '../../theme/theme_context.dart';
import '../../widgets/app_title.dart';
import '../../widgets/info_notice.dart';
import 'auth_form_layout.dart';

/// Вход, регистрация и сброс пароля по почте. После регистрации приложение
/// попросит подтвердить почту, затем — представиться (ФИО, телефон, роль).
class EmailLoginScreen extends ConsumerStatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  ConsumerState<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends ConsumerState<EmailLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  LoginController get _controller => ref.read(loginControllerProvider.notifier);

  void _submit(LoginMode mode) {
    unawaited(switch (mode) {
      LoginMode.signIn => _controller.signIn(_email.text, _password.text),
      LoginMode.signUp => _controller.signUp(
        _email.text,
        _password.text,
        _repeat.text,
      ),
      LoginMode.resetPassword => _controller.resetPassword(_email.text),
    });
  }

  void _switchTo(LoginMode mode) {
    _password.clear();
    _repeat.clear();
    _controller.setMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginControllerProvider);
    final configured =
        ref.watch(firebaseStatusProvider) == FirebaseStatus.ready;
    final mode = state.mode;

    final (title, subtitle, action) = switch (mode) {
      LoginMode.signIn => ('Вход', 'Войдите по почте и паролю.', 'Войти'),
      LoginMode.signUp => (
        'Регистрация',
        'Придумайте пароль — на почту придёт письмо для подтверждения.',
        'Зарегистрироваться',
      ),
      LoginMode.resetPassword => (
        'Новый пароль',
        'Пришлём на почту ссылку, по которой можно задать новый пароль.',
        'Отправить ссылку',
      ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
          ),
        ],
      ),
      body: AutofillGroup(
        child: AuthFormLayout(
          title: title,
          subtitle: Text(subtitle),
          notice: configured
              ? null
              : const InfoNotice(
                  icon: Icons.cloud_off_outlined,
                  text:
                      'Приложение ещё не подключено к серверу, поэтому вход '
                      'пока не работает.',
                ),
          children: [
            TextField(
              controller: _email,
              readOnly: state.busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: mode == LoginMode.resetPassword
                  ? TextInputAction.done
                  : TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              inputFormatters: [LengthLimitingTextInputFormatter(254)],
              decoration: InputDecoration(
                labelText: 'Почта',
                hintText: 'anna@mail.ru',
                errorText: state.emailError,
                errorMaxLines: 3,
              ),
              onChanged: (_) => _controller.clearErrors(),
              onSubmitted: mode == LoginMode.resetPassword
                  ? (_) => _submit(mode)
                  : null,
            ),
            if (mode != LoginMode.resetPassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                readOnly: state.busy,
                obscureText: !_showPassword,
                textInputAction: mode == LoginMode.signUp
                    ? TextInputAction.next
                    : TextInputAction.done,
                autofillHints: [
                  mode == LoginMode.signUp
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                inputFormatters: [LengthLimitingTextInputFormatter(128)],
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  helperText: mode == LoginMode.signUp
                      ? 'Не короче 8 символов'
                      : null,
                  errorText: mode == LoginMode.signIn
                      ? state.passwordError
                      : null,
                  errorMaxLines: 2,
                  suffixIcon: IconButton(
                    tooltip: _showPassword
                        ? 'Скрыть пароль'
                        : 'Показать пароль',
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                onChanged: (_) => _controller.clearErrors(),
                onSubmitted: mode == LoginMode.signIn
                    ? (_) => _submit(mode)
                    : null,
              ),
            ],
            if (mode == LoginMode.signUp) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _repeat,
                readOnly: state.busy,
                obscureText: !_showPassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                inputFormatters: [LengthLimitingTextInputFormatter(128)],
                decoration: InputDecoration(
                  labelText: 'Пароль ещё раз',
                  errorText: state.passwordError,
                  errorMaxLines: 2,
                ),
                onChanged: (_) => _controller.clearErrors(),
                onSubmitted: (_) => _submit(mode),
              ),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 12),
              Text(
                state.error!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: context.colors.error),
              ),
            ],
            if (state.info != null) ...[
              const SizedBox(height: 12),
              InfoNotice(
                icon: Icons.mark_email_read_outlined,
                text: state.info!,
              ),
            ],
            const SizedBox(height: 16),
            BusyFilledButton(
              label: action,
              busy: state.busy,
              onPressed: () => _submit(mode),
            ),
            const SizedBox(height: 8),
            if (mode == LoginMode.signIn) ...[
              TextButton(
                onPressed: state.busy
                    ? null
                    : () => _switchTo(LoginMode.resetPassword),
                child: const Text('Забыли пароль?'),
              ),
              TextButton(
                onPressed: state.busy
                    ? null
                    : () => _switchTo(LoginMode.signUp),
                child: const Text('Впервые здесь? Зарегистрироваться'),
              ),
            ] else
              TextButton(
                onPressed: state.busy
                    ? null
                    : () => _switchTo(LoginMode.signIn),
                child: const Text('Уже есть аккаунт? Войти'),
              ),
          ],
        ),
      ),
    );
  }
}

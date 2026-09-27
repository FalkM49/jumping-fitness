import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_repository.dart';
import '../../services/backend_providers.dart';
import '../../theme/theme_context.dart';
import '../../utils/ru_format.dart';
import '../../widgets/app_title.dart';
import '../../widgets/info_notice.dart';
import 'auth_form_layout.dart';

/// «Подтвердите почту»: человек вошёл, но ещё не открыл ссылку из письма.
///
/// Проверяем подтверждение по кнопке и сами — когда человек возвращается
/// в приложение из почты. Как только почта подтверждена, экран сменится
/// на регистрацию (или главный экран, если профиль уже есть).
class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key, required this.user});

  final AuthUser user;

  /// Пауза перед повторной отправкой письма.
  static const int resendCooldownSeconds = 60;

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  late final AppLifecycleListener _lifecycle;
  Timer? _cooldown;
  int _resendSecondsLeft = EmailVerificationScreen.resendCooldownSeconds;
  bool _busy = false;
  String? _error;
  String? _info;

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  @override
  void initState() {
    super.initState();
    // Письмо только что ушло (при регистрации) — сразу повторно не шлём.
    _startCooldown();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_check(silent: true)),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _cooldown?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldown?.cancel();
    _resendSecondsLeft = EmailVerificationScreen.resendCooldownSeconds;
    _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendSecondsLeft--);
      if (_resendSecondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_busy) return;
    setState(() {
      _busy = !silent;
      _error = null;
      _info = null;
    });
    try {
      await _auth.reloadUser();
      // Подтверждено — экран сменится сам, этот виджет уйдёт.
      if (mounted && !silent) {
        setState(
          () => _error =
              'Почта ещё не подтверждена. Откройте ссылку из письма — '
              'если его нет, проверьте папку «Спам».',
        );
      }
    } on AuthFailure catch (failure) {
      if (mounted && !silent) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || _resendSecondsLeft > 0) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await _auth.sendEmailVerification();
      if (mounted) {
        setState(() => _info = 'Письмо отправлено ещё раз.');
        _startCooldown();
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.user.email;
    final address = email == null || email.isEmpty ? 'вашу почту' : email;

    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _busy ? null : () => unawaited(_auth.signOut()),
          ),
        ],
      ),
      body: AuthFormLayout(
        title: 'Подтвердите почту',
        subtitle: Text(
          'Отправили письмо на $address. Откройте в нём ссылку и вернитесь '
          'в приложение.',
        ),
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.colors.error),
            ),
            const SizedBox(height: 12),
          ],
          if (_info != null) ...[
            InfoNotice(icon: Icons.mark_email_read_outlined, text: _info!),
            const SizedBox(height: 12),
          ],
          BusyFilledButton(
            label: 'Я подтвердил(а) почту',
            busy: _busy,
            onPressed: () => unawaited(_check()),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy || _resendSecondsLeft > 0
                ? null
                : () => unawaited(_resend()),
            child: Text(
              _resendSecondsLeft > 0
                  ? 'Отправить письмо ещё раз через '
                        '${RuFormat.countdown(_resendSecondsLeft)}'
                  : 'Отправить письмо ещё раз',
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => unawaited(_auth.signOut()),
            child: const Text('Другая почта'),
          ),
        ],
      ),
    );
  }
}

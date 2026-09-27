import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/session.dart';
import '../../notifications/push_coordinator.dart';
import '../../services/backend_providers.dart';
import '../../widgets/app_title.dart';
import '../client/client_home_screen.dart';
import '../trainer/trainer_home_screen.dart';
import 'email_login_screen.dart';
import 'email_verification_screen.dart';
import 'registration_screen.dart';

/// Корень приложения: показывает экран по состоянию входа и роли.
///
/// Роль берётся из профиля в Firestore в реальном времени, поэтому после
/// одобрения заявки клиент сразу попадает на экран тренера, а после выхода
/// из аккаунта — на экран входа.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Сменился пользователь или его права — закрываем всё, что открыто
    // поверх главного экрана (настройки, заявки, окна).
    ref.listen(sessionProvider.select(sessionFingerprint), (previous, next) {
      if (previous != next) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

    return switch (ref.watch(sessionProvider)) {
      SessionLoading() => const _SplashScreen(),
      SignedOut() => const EmailLoginScreen(),
      NeedsEmailVerification(:final user) => EmailVerificationScreen(
        key: ValueKey('verify-${user.uid}'),
        user: user,
      ),
      NeedsRegistration(:final user) => RegistrationScreen(user: user),
      SignedIn(:final home, :final user) => PushCoordinator(
        uid: user.uid,
        child: switch (home) {
          HomeKind.client => const ClientHomeScreen(),
          HomeKind.trainer => const TrainerHomeScreen(),
        },
      ),
      SessionError(:final error) => _SessionErrorScreen(error: error),
    };
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTitle(),
            SizedBox(height: 24),
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionErrorScreen extends ConsumerWidget {
  const _SessionErrorScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    debugPrint('Сессия: $error');

    return Scaffold(
      appBar: AppBar(title: const AppTitle()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Не удалось загрузить профиль',
                style: textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Проверьте интернет и попробуйте снова.',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  ref.invalidate(authUserProvider);
                  ref.invalidate(userProfileProvider);
                },
                child: const Text('Повторить'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    unawaited(ref.read(authRepositoryProvider).signOut()),
                child: const Text('Выйти'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

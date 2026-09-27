import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/trainer_request.dart';
import '../models/user_profile.dart';
import '../services/backend_providers.dart';
import 'auth_repository.dart';

/// Кто сейчас пользуется приложением — от этого зависит, какой экран
/// показывать (ТЗ 2, 10.3).
sealed class Session {
  const Session();
}

/// Ещё не известно: Firebase поднимает сохранённый вход или грузит профиль.
final class SessionLoading extends Session {
  const SessionLoading();
}

/// Никто не вошёл — экран входа по почте.
final class SignedOut extends Session {
  const SignedOut();
}

/// Вошёл, но ещё не открыл ссылку из письма — экран «Подтвердите почту».
final class NeedsEmailVerification extends Session {
  const NeedsEmailVerification(this.user);

  final AuthUser user;
}

/// Почта подтверждена, но профиля ещё нет — экран ФИО, телефона и роли.
final class NeedsRegistration extends Session {
  const NeedsRegistration(this.user);

  final AuthUser user;
}

/// Зарегистрированный пользователь.
final class SignedIn extends Session {
  const SignedIn(this.user, this.profile);

  final AuthUser user;
  final UserProfile profile;

  /// Какой главный экран положен: тренер и админ — экран тренера
  /// (у администратора все права тренера), остальные — экран клиента.
  HomeKind get home => profile.isStaff ? HomeKind.trainer : HomeKind.client;
}

/// Не удалось загрузить вход или профиль.
final class SessionError extends Session {
  const SessionError(this.error);

  final Object error;
}

enum HomeKind { client, trainer }

/// Вошедший пользователь Firebase Auth.
final authUserProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// Профиль `users/{uid}` в реальном времени: смена роли (одобрение заявки)
/// или флага админа сразу меняет экран.
final userProfileProvider = StreamProvider.family<UserProfile?, String>(
  (ref, uid) => ref.watch(userRepositoryProvider).watchProfile(uid),
);

/// Своя заявка в тренеры.
final ownTrainerRequestProvider =
    StreamProvider.family<TrainerRequest?, String>(
      (ref, uid) =>
          ref.watch(userRepositoryProvider).watchOwnTrainerRequest(uid),
    );

final sessionProvider = Provider<Session>((ref) {
  final auth = ref.watch(authUserProvider);
  if (auth.hasError) return SessionError(auth.error!);
  if (!auth.hasValue) return const SessionLoading();

  final user = auth.requireValue;
  if (user == null) return const SignedOut();
  // Без подтверждённой почты правила Firestore не дадут прочитать профиль.
  if (!user.emailVerified) return NeedsEmailVerification(user);

  final profile = ref.watch(userProfileProvider(user.uid));
  if (profile.hasError) return SessionError(profile.error!);
  if (!profile.hasValue) return const SessionLoading();

  final value = profile.requireValue;
  return value == null ? NeedsRegistration(user) : SignedIn(user, value);
});

/// Профиль вошедшего пользователя или `null`.
final currentProfileProvider = Provider<UserProfile?>((ref) {
  return switch (ref.watch(sessionProvider)) {
    SignedIn(:final profile) => profile,
    _ => null,
  };
});

/// «Отпечаток» сессии для навигации: когда он меняется (вход, выход,
/// новая роль, флаг админа), открытые поверх главного экрана окна
/// закрываются — чтобы, например, бывший админ не остался на списке заявок.
String sessionFingerprint(Session session) => switch (session) {
  SessionLoading() => 'loading',
  SignedOut() => 'signed-out',
  NeedsEmailVerification(:final user) => 'verify-email:${user.uid}',
  NeedsRegistration(:final user) => 'registration:${user.uid}',
  SignedIn(:final user, :final profile) =>
    'signed-in:${user.uid}:${profile.role.wireName}:${profile.isAdmin}',
  SessionError() => 'error',
};

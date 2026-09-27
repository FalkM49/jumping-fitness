import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

/// Вход по почте и паролю через Firebase Authentication.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth) {
    // Письма Firebase (подтверждение, сброс пароля) — по-русски.
    _auth.setLanguageCode('ru');
  }

  final FirebaseAuth _auth;

  /// `userChanges`, а не `authStateChanges`: только он сообщает
  /// о подтверждении почты после [reloadUser].
  @override
  Stream<AuthUser?> authStateChanges() => _auth.userChanges().map(
    (user) => user == null
        ? null
        : AuthUser(
            uid: user.uid,
            email: user.email,
            emailVerified: user.emailVerified,
          ),
  );

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(
        () => _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        ),
      );

  @override
  Future<void> signUp({
    required String email,
    required String password,
  }) => _guard(() async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.sendEmailVerification();
  });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<void> sendEmailVerification() =>
      _guard(() async => _auth.currentUser?.sendEmailVerification());

  @override
  Future<void> reloadUser() => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
    // Новый токен несёт email_verified: без него правила Firestore
    // ещё считали бы почту неподтверждённой.
    if (_auth.currentUser?.emailVerified ?? false) {
      await _auth.currentUser?.getIdToken(true);
    }
  });

  @override
  Future<void> signOut() => _auth.signOut();

  static Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      debugPrint('Auth: ${error.code} — ${error.message}');
      throw AuthFailure(authFailureKindForCode(error.code), error.code);
    }
  }
}

/// Код ошибки Firebase Auth → причина для пользователя.
@visibleForTesting
AuthFailureKind authFailureKindForCode(String code) => switch (code) {
  'invalid-email' || 'missing-email' => AuthFailureKind.invalidEmail,
  // Firebase нарочно не говорит, что именно неверно: почта или пароль.
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' ||
  'invalid-login-credentials' => AuthFailureKind.wrongCredentials,
  'email-already-in-use' => AuthFailureKind.emailInUse,
  'weak-password' => AuthFailureKind.weakPassword,
  'too-many-requests' => AuthFailureKind.tooManyRequests,
  'network-request-failed' => AuthFailureKind.network,
  'user-disabled' => AuthFailureKind.userDisabled,
  'operation-not-allowed' => AuthFailureKind.notConfigured,
  _ => AuthFailureKind.unknown,
};

/// Firebase ещё не подключён: никто не вошёл, войти нельзя.
class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository();

  static Future<void> _unavailable() =>
      Future.error(const AuthFailure(AuthFailureKind.notConfigured));

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(null);

  @override
  Future<void> signIn({required String email, required String password}) =>
      _unavailable();

  @override
  Future<void> signUp({required String email, required String password}) =>
      _unavailable();

  @override
  Future<void> sendPasswordReset(String email) => _unavailable();

  @override
  Future<void> sendEmailVerification() => _unavailable();

  @override
  Future<void> reloadUser() async {}

  @override
  Future<void> signOut() async {}
}

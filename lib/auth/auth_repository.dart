import 'package:flutter/foundation.dart';

/// Вошедший пользователь Firebase Auth — ровно то, что нужно приложению.
@immutable
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    this.emailVerified = true,
  });

  final String uid;

  /// Почта, с которой человек вошёл.
  final String? email;

  /// Почта подтверждена по ссылке из письма. Без этого приложение дальше
  /// экрана «Подтвердите почту» не пускает, а правила Firestore — не дают
  /// ни читать, ни регистрироваться.
  final bool emailVerified;

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.uid == uid &&
      other.email == email &&
      other.emailVerified == emailVerified;

  @override
  int get hashCode => Object.hash(uid, email, emailVerified);
}

/// Причины неудачи входа — у каждой понятный текст для пользователя.
enum AuthFailureKind {
  invalidEmail('Проверьте адрес почты: похоже, в нём ошибка.'),
  wrongCredentials('Неверная почта или пароль.'),
  emailInUse(
    'Эта почта уже зарегистрирована. Войдите или восстановите пароль.',
  ),
  weakPassword('Пароль слишком простой. Придумайте не короче 8 символов.'),
  tooManyRequests(
    'Слишком много попыток. Подождите немного и попробуйте снова.',
  ),
  network('Нет связи с сервером. Проверьте интернет и попробуйте снова.'),
  userDisabled('Этот аккаунт заблокирован. Обратитесь к администратору.'),
  notConfigured(
    'Вход пока недоступен: приложение ещё не подключено к серверу.',
  ),
  unknown('Не получилось войти. Попробуйте ещё раз.');

  const AuthFailureKind(this.message);

  final String message;
}

class AuthFailure implements Exception {
  const AuthFailure(this.kind, [this.details]);

  final AuthFailureKind kind;

  /// Исходная ошибка — для логов, не для пользователя.
  final Object? details;

  String get message => kind.message;

  @override
  String toString() =>
      'AuthFailure(${kind.name}${details == null ? '' : ': $details'})';
}

/// Вход по почте и паролю с подтверждением почты (согласованная замена
/// входа по SMS из ТЗ 2). Реализации: Firebase Auth и заглушка «сервер
/// не подключён»; в тестах — подделка в памяти.
///
/// Все ошибки — [AuthFailure].
abstract interface class AuthRepository {
  /// Текущий пользователь и все его смены: вход, выход, подтверждение почты.
  Stream<AuthUser?> authStateChanges();

  Future<void> signIn({required String email, required String password});

  /// Новый аккаунт. Сразу выполняет вход и отправляет письмо
  /// для подтверждения почты.
  Future<void> signUp({required String email, required String password});

  /// Письмо со ссылкой для нового пароля.
  Future<void> sendPasswordReset(String email);

  /// Письмо для подтверждения почты — повторно.
  Future<void> sendEmailVerification();

  /// Перечитать пользователя с сервера: подтвердил ли он почту. Заодно
  /// обновляет токен, чтобы правила Firestore увидели подтверждение.
  Future<void> reloadUser();

  Future<void> signOut();
}

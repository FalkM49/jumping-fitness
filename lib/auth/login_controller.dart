import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backend_providers.dart';
import 'auth_repository.dart';
import 'email_address.dart';

enum LoginMode {
  /// Вход в существующий аккаунт.
  signIn,

  /// Новый аккаунт.
  signUp,

  /// Письмо для сброса пароля.
  resetPassword,
}

/// Состояние экрана входа.
@immutable
class LoginState {
  const LoginState({
    this.mode = LoginMode.signIn,
    this.busy = false,
    this.emailError,
    this.passwordError,
    this.error,
    this.info,
  });

  final LoginMode mode;

  /// Идёт запрос к серверу — кнопки неактивны.
  final bool busy;

  /// Подсказки под полями.
  final String? emailError;
  final String? passwordError;

  /// Ошибка сервера под формой.
  final String? error;

  /// Сообщение об успехе (например, «письмо отправлено»).
  final String? info;

  LoginState copyWith({
    LoginMode? mode,
    bool? busy,
    String? Function()? emailError,
    String? Function()? passwordError,
    String? Function()? error,
    String? Function()? info,
  }) {
    return LoginState(
      mode: mode ?? this.mode,
      busy: busy ?? this.busy,
      emailError: emailError == null ? this.emailError : emailError(),
      passwordError: passwordError == null
          ? this.passwordError
          : passwordError(),
      error: error == null ? this.error : error(),
      info: info == null ? this.info : info(),
    );
  }
}

/// Вход, регистрация и сброс пароля по почте. Проверки ввода — здесь,
/// всё остальное решает Firebase Auth. После входа или регистрации экран
/// сменится сам: придёт новый пользователь Firebase Auth.
class LoginController extends Notifier<LoginState> {
  @override
  LoginState build() => const LoginState();

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  void setMode(LoginMode mode) {
    if (state.busy) return;
    state = LoginState(mode: mode);
  }

  Future<void> signIn(String emailInput, String password) async {
    final email = _validEmail(emailInput);
    if (email == null) return;
    if (password.isEmpty) {
      state = state.copyWith(passwordError: () => 'Введите пароль.');
      return;
    }
    await _run(() => _auth.signIn(email: email, password: password));
  }

  Future<void> signUp(String emailInput, String password, String repeat) async {
    final email = _validEmail(emailInput);
    if (email == null) return;
    final passwordError =
        newPasswordError(password) ??
        (password == repeat ? null : 'Пароли не совпадают.');
    if (passwordError != null) {
      state = state.copyWith(passwordError: () => passwordError);
      return;
    }
    await _run(() => _auth.signUp(email: email, password: password));
  }

  Future<void> resetPassword(String emailInput) async {
    final email = _validEmail(emailInput);
    if (email == null) return;
    final ok = await _run(() => _auth.sendPasswordReset(email));
    if (ok && ref.mounted) {
      // Назад ко входу: следующий шаг — войти с новым паролем.
      state = LoginState(
        info:
            'Если аккаунт с почтой $email есть, на неё пришло письмо '
            'со ссылкой для нового пароля. Проверьте и папку «Спам».',
      );
    }
  }

  void clearErrors() {
    if (state.emailError != null ||
        state.passwordError != null ||
        state.error != null) {
      state = state.copyWith(
        emailError: () => null,
        passwordError: () => null,
        error: () => null,
      );
    }
  }

  String? _validEmail(String input) {
    if (state.busy) return null;
    final email = EmailAddress.normalize(input);
    if (email == null) {
      state = state.copyWith(
        emailError: () => 'Введите почту полностью, например anna@mail.ru.',
        info: () => null,
      );
    }
    return email;
  }

  /// Запрос к серверу с индикатором и текстом ошибки. `true` — успех.
  Future<bool> _run(Future<void> Function() action) async {
    state = state.copyWith(
      busy: true,
      emailError: () => null,
      passwordError: () => null,
      error: () => null,
      info: () => null,
    );
    try {
      await action();
      if (ref.mounted) state = state.copyWith(busy: false);
      return true;
    } on AuthFailure catch (failure) {
      if (ref.mounted) {
        state = state.copyWith(busy: false, error: () => failure.message);
      }
      return false;
    }
  }
}

/// Живёт, пока открыт экран входа: после выхода из аккаунта вход
/// начинается с чистого листа.
final loginControllerProvider =
    NotifierProvider.autoDispose<LoginController, LoginState>(
      LoginController.new,
    );

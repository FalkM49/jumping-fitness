/// Адрес почты для входа.
abstract final class EmailAddress {
  /// Обрезает пробелы и приводит к нижнему регистру. `null` — адрес
  /// явно неполный. Окончательно адрес проверяет письмо со ссылкой.
  static String? normalize(String input) {
    final email = input.trim().toLowerCase();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ? email : null;
  }
}

/// Пароль нового аккаунта: подсказка под полем или `null`, если подходит.
String? newPasswordError(String password) {
  if (password.length < 8) return 'Пароль — не короче 8 символов.';
  if (password.length > 128) return 'Пароль — не длиннее 128 символов.';
  return null;
}

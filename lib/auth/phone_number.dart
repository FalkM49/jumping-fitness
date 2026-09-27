/// Номер телефона для связи — указывается при регистрации.
///
/// Пользователь вводит номер как привык: `8 999 123-45-67`, `+7 (999) 123 45 67`,
/// `9991234567`. Хранится в формате E.164: `+79991234567` — его же
/// проверяют правила Firestore.
abstract final class PhoneNumber {
  /// Приводит ввод к E.164. `null` — номер неполный или некорректный.
  ///
  /// Без «+» номер считается российским: 10 цифр, либо 11 цифр с ведущей
  /// 7 или 8. С «+» принимается любой международный номер (8–15 цифр) —
  /// например, казахстанский или белорусский.
  static String? normalize(String input) {
    final trimmed = input.trim();
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');

    if (trimmed.startsWith('+')) {
      if (digits.startsWith('7')) {
        return digits.length == 11 ? '+$digits' : null;
      }
      final valid =
          digits.length >= 8 && digits.length <= 15 && !digits.startsWith('0');
      return valid ? '+$digits' : null;
    }
    if (digits.length == 10) return '+7$digits';
    if (digits.length == 11 &&
        (digits.startsWith('7') || digits.startsWith('8'))) {
      return '+7${digits.substring(1)}';
    }
    return null;
  }

  /// Для показа: `+79991234567` → `+7 999 123-45-67`. Прочие номера — как есть.
  static String format(String e164) {
    final match = RegExp(r'^\+7(\d{3})(\d{3})(\d{2})(\d{2})$').firstMatch(e164);
    if (match == null) return e164;
    return '+7 ${match[1]} ${match[2]}-${match[3]}-${match[4]}';
  }
}

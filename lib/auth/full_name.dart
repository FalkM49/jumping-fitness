import '../models/user_profile.dart';

/// Ошибка в ФИО для подсказки под полем, `null` — всё в порядке.
///
/// Та же проверка, что в правилах Firestore (`validFullName`): иначе
/// сервер отклонит регистрацию, а пользователь не поймёт почему.
String? fullNameError(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return 'Введите ФИО.';
  if (name.runes.length < 3) {
    return 'Слишком коротко — нужно минимум 3 символа.';
  }
  if (name.runes.length > 100) {
    return 'Слишком длинно — не больше 100 символов.';
  }
  if (!UserProfile.isValidFullName(name)) {
    return 'Уберите переносы строк и служебные символы.';
  }
  return null;
}

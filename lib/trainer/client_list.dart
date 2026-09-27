import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Список клиентов тренера (ТЗ 6): кто сколько тренировок и дней имеет,
/// поиск по ФИО, сортировка.

/// Порядок сортировки.
enum ClientSort {
  /// По возрастанию оставшихся тренировок — по умолчанию (ТЗ 6).
  trainings('По тренировкам'),

  /// По возрастанию оставшихся дней абонемента.
  days('По дням');

  const ClientSort(this.label);

  final String label;
}

/// Клиент и состояние его текущего абонемента на сегодня.
@immutable
class ClientSummary {
  ClientSummary({
    required this.profile,
    required this.subscription,
    required CalendarDay today,
  }) : isActive =
           subscription != null &&
           subscription.isCurrent &&
           !subscription.isExpiredOn(today) &&
           subscription.expiredAt == null &&
           !today.isBefore(subscription.startDate),
       trainingsLeft = _trainingsLeft(subscription, today),
       daysLeft = _daysLeft(subscription, today);

  final UserProfile profile;

  /// Текущий абонемент (`null` — ни разу не оформлялся).
  final Subscription? subscription;

  /// Действует сегодня.
  final bool isActive;

  /// Для сортировки и показа: у истёкшего абонемента — 0.
  final int trainingsLeft;
  final int daysLeft;

  static int _trainingsLeft(Subscription? sub, CalendarDay today) {
    if (sub == null || sub.isExpiredOn(today) || sub.expiredAt != null) {
      return 0;
    }
    return sub.trainingsLeft;
  }

  static int _daysLeft(Subscription? sub, CalendarDay today) {
    if (sub == null || sub.expiredAt != null) return 0;
    return sub.daysLeftOn(today);
  }
}

/// Собрать список: клиенты + их текущие абонементы. Администратор-разработчик
/// (флаг isAdmin) в список клиентов не попадает.
List<ClientSummary> summarizeClients({
  required List<UserProfile> clients,
  required List<Subscription> currentSubscriptions,
  required CalendarDay today,
}) {
  final byClient = {
    for (final s in currentSubscriptions)
      if (s.isCurrent) s.clientId: s,
  };
  return [
    for (final client in clients)
      if (client.role == UserRole.client && !client.isAdmin)
        ClientSummary(
          profile: client,
          subscription: client.currentSubscriptionId == null
              ? null
              : byClient[client.uid],
          today: today,
        ),
  ];
}

/// Фильтр по ФИО «на лету» (ТЗ 6): без учёта регистра, «ё» = «е»,
/// каждое слово запроса должно встретиться в ФИО.
List<ClientSummary> searchClients(List<ClientSummary> clients, String query) {
  final words = _normalize(query).split(' ').where((w) => w.isNotEmpty);
  if (words.isEmpty) return clients;
  return [
    for (final c in clients)
      if (words.every(_normalize(c.profile.fullName).contains)) c,
  ];
}

/// Сортировка (ТЗ 6): у кого меньше осталось — выше; при равенстве —
/// по алфавиту (русскому, «ё» сразу после «е»).
List<ClientSummary> sortClients(List<ClientSummary> clients, ClientSort sort) {
  int key(ClientSummary c) => switch (sort) {
    ClientSort.trainings => c.trainingsLeft,
    ClientSort.days => c.daysLeft,
  };
  return [...clients]..sort((a, b) {
    final byKey = key(a).compareTo(key(b));
    return byKey != 0
        ? byKey
        : compareRussian(a.profile.fullName, b.profile.fullName);
  });
}

String _normalize(String s) =>
    s.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ').trim();

const String _alphabet = 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';

/// Сравнение строк по русскому алфавиту. Побайтовое сравнение ставит «ё»
/// после «я» — «Ёлкина» оказалась бы в конце списка.
int compareRussian(String a, String b) {
  final x = a.toLowerCase();
  final y = b.toLowerCase();
  final length = x.length < y.length ? x.length : y.length;
  for (var i = 0; i < length; i++) {
    final cx = _rank(x[i]);
    final cy = _rank(y[i]);
    if (cx != cy) return cx.compareTo(cy);
  }
  return x.length.compareTo(y.length);
}

int _rank(String char) {
  final index = _alphabet.indexOf(char);
  // Пробел и знаки — раньше букв; латиница и прочее — после кириллицы.
  if (index >= 0) return 1000 + index;
  final code = char.codeUnitAt(0);
  return code < 0x41 ? code : 2000 + code;
}

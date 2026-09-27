import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'firestore_parsing.dart';

/// Роль в `users/{uid}.role`. Администратор — отдельный флаг [UserProfile.isAdmin].
enum UserRole {
  client('client'),
  trainer('trainer');

  const UserRole(this.wireName);

  final String wireName;

  static UserRole fromWire(String value) => values.firstWhere(
    (role) => role.wireName == value,
    orElse: () => throw FormatException('Неизвестная роль', value),
  );
}

/// Цветок месяца (ТЗ 4).
@immutable
class MonthlyFlower {
  const MonthlyFlower({required this.month, required this.flowerId});

  /// `YYYY-MM`.
  final String month;
  final String flowerId;
}

/// Профиль `users/{uid}`.
@immutable
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.isAdmin,
    required this.createdAt,
    this.currentSubscriptionId,
    this.monthlyFlower,
    this.recentFlowerIds = const [],
  });

  factory UserProfile.fromMap(String uid, Map<String, Object?> data) {
    final r = FirestoreReader('users/$uid', data);
    final flower = r.nested('monthlyFlower');
    return UserProfile(
      uid: uid,
      fullName: r.string('fullName'),
      phone: r.string('phone'),
      role: r.parsed('role', UserRole.fromWire),
      isAdmin: r.booleanOr('isAdmin', false),
      // Сразу после создания serverTimestamp ещё не вернулся с сервера —
      // в локальном снимке поле пустое, это нормально.
      createdAt: r.optionalTimestamp('createdAt'),
      currentSubscriptionId: r.optionalString('currentSubscriptionId'),
      monthlyFlower: flower == null
          ? null
          : MonthlyFlower(
              month: flower.string('month'),
              flowerId: flower.string('flowerId'),
            ),
      recentFlowerIds: r.stringList('recentFlowerIds'),
    );
  }

  factory UserProfile.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => UserProfile.fromMap(snapshot.id, snapshot.data() ?? const {});

  final String uid;
  final String fullName;
  final String phone;
  final UserRole role;
  final bool isAdmin;
  final DateTime? createdAt;
  final String? currentSubscriptionId;
  final MonthlyFlower? monthlyFlower;
  final List<String> recentFlowerIds;

  bool get isTrainer => role == UserRole.trainer;

  /// Тренер или администратор — видит всех клиентов и управляет календарём.
  bool get isStaff => isTrainer || isAdmin;

  /// ФИО, которое пропустят правила Firestore (`validFullName`):
  /// 3–100 символов, без пробелов по краям и управляющих символов.
  /// Проверять уже обрезанную строку — [registrationData] делает `trim()`.
  static bool isValidFullName(String name) {
    final length = name.runes.length;
    return length >= 3 &&
        length <= 100 &&
        name == name.trim() &&
        !_controlChars.hasMatch(name);
  }

  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

  /// Данные для создания профиля при регистрации. Ровно те поля, которые
  /// пропускают правила Firestore (роль — всегда client).
  static Map<String, Object?> registrationData({
    required String fullName,
    required String phone,
  }) => {
    'fullName': fullName.trim(),
    'phone': phone,
    'role': UserRole.client.wireName,
    'isAdmin': false,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

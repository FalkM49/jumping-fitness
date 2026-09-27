import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/auth_repository.dart';
import '../models/firestore_paths.dart';
import '../models/trainer_request.dart';
import '../models/user_profile.dart';

/// Ошибка регистрации с текстом для пользователя.
class RegistrationFailure implements Exception {
  const RegistrationFailure(this.message);

  final String message;

  @override
  String toString() => 'RegistrationFailure($message)';
}

/// Профиль пользователя и его заявка в тренеры (коллекции `users`,
/// `trainer_requests`, docs/02_firestore_schema.md).
abstract interface class UserRepository {
  /// Профиль `users/{uid}`; `null` — ещё не зарегистрирован.
  Stream<UserProfile?> watchProfile(String uid);

  /// Своя заявка `trainer_requests/{uid}`; `null` — заявки нет.
  Stream<TrainerRequest?> watchOwnTrainerRequest(String uid);

  /// Регистрация (ТЗ 2): профиль с ролью client и, если выбрано
  /// «Хочу стать тренером», заявка со статусом pending — одним batch,
  /// чтобы не остаться с профилем без заявки или наоборот.
  ///
  /// [phone] — в E.164 (`PhoneNumber.normalize`), для связи с клиентом.
  Future<void> register({
    required AuthUser user,
    required String fullName,
    required String phone,
    required bool wantsTrainerRole,
  });
}

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<UserProfile?> watchProfile(String uid) => _db
      .doc(FirestorePaths.user(uid))
      .snapshots()
      .map((snap) => snap.exists ? UserProfile.fromSnapshot(snap) : null);

  @override
  Stream<TrainerRequest?> watchOwnTrainerRequest(String uid) => _db
      .doc(FirestorePaths.trainerRequest(uid))
      .snapshots()
      .map((snap) => snap.exists ? TrainerRequest.fromSnapshot(snap) : null);

  @override
  Future<void> register({
    required AuthUser user,
    required String fullName,
    required String phone,
    required bool wantsTrainerRole,
  }) async {
    final batch = _db.batch()
      ..set(
        _db.doc(FirestorePaths.user(user.uid)),
        UserProfile.registrationData(fullName: fullName, phone: phone),
      );
    if (wantsTrainerRole) {
      batch.set(
        _db.doc(FirestorePaths.trainerRequest(user.uid)),
        TrainerRequest.creationData(
          uid: user.uid,
          fullName: fullName,
          phone: phone,
        ),
      );
    }

    try {
      await batch.commit();
    } on FirebaseException catch (error) {
      throw RegistrationFailure(switch (error.code) {
        'permission-denied' =>
          'Сервер не принял данные. Проверьте ФИО и телефон или обратитесь '
              'к администратору.',
        'unavailable' =>
          'Нет связи с сервером. Проверьте интернет и попробуйте снова.',
        _ => 'Не получилось зарегистрироваться. Попробуйте ещё раз.',
      });
    }
  }
}

/// Firebase ещё не подключён: профилей нет, регистрация недоступна.
class UnavailableUserRepository implements UserRepository {
  const UnavailableUserRepository();

  @override
  Stream<UserProfile?> watchProfile(String uid) => Stream.value(null);

  @override
  Stream<TrainerRequest?> watchOwnTrainerRequest(String uid) =>
      Stream.value(null);

  @override
  Future<void> register({
    required AuthUser user,
    required String fullName,
    required String phone,
    required bool wantsTrainerRole,
  }) => Future.error(
    const RegistrationFailure('Приложение ещё не подключено к серверу.'),
  );
}

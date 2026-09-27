import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
import '../auth/firebase_auth_repository.dart';
import '../notifications/notifications_repository.dart';
import '../notifications/push_service.dart';
import 'cloud_functions.dart';
import 'firebase_bootstrap.dart';
import 'studio_functions.dart';
import 'studio_repository.dart';
import 'trainer_requests_repository.dart';
import 'user_repository.dart';

/// Репозитории выбираются по состоянию Firebase: настоящие, если он
/// подключён, иначе заглушки «сервер не подключён». В тестах подменяются
/// подделками через `ProviderScope(overrides: ...)`.

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return ref.watch(firebaseStatusProvider) == FirebaseStatus.ready
      ? FirebaseAuthRepository(FirebaseAuth.instance)
      : const UnavailableAuthRepository();
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return ref.watch(firebaseStatusProvider) == FirebaseStatus.ready
      ? FirestoreUserRepository(FirebaseFirestore.instance)
      : const UnavailableUserRepository();
});

final studioRepositoryProvider = Provider<StudioRepository>((ref) {
  return ref.watch(firebaseStatusProvider) == FirebaseStatus.ready
      ? FirestoreStudioRepository(FirebaseFirestore.instance)
      : const UnavailableStudioRepository();
});

final studioFunctionsProvider = Provider<StudioFunctions>((ref) {
  return ref.watch(firebaseStatusProvider) == FirebaseStatus.ready
      ? CloudStudioFunctions(regionalFunctions())
      : const UnavailableStudioFunctions();
});

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return ref.watch(firebaseStatusProvider) == FirebaseStatus.ready
      ? FirestoreNotificationsRepository(FirebaseFirestore.instance)
      : const UnavailableNotificationsRepository();
});

final pushServiceProvider = Provider<PushService>((ref) {
  return ref.watch(firebaseStatusProvider) == FirebaseStatus.ready
      ? FirebasePushService(
          FirebaseMessaging.instance,
          FirebaseFirestore.instance,
        )
      : const UnavailablePushService();
});

/// Текущее время. Подменяется в тестах; решения всё равно принимает сервер
/// по своему времени — здесь время нужно только для показа.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final trainerRequestsRepositoryProvider = Provider<TrainerRequestsRepository>((
  ref,
) {
  return ref.watch(firebaseStatusProvider) == FirebaseStatus.ready
      ? FirebaseTrainerRequestsRepository(
          FirebaseFirestore.instance,
          regionalFunctions(),
        )
      : const UnavailableTrainerRequestsRepository();
});

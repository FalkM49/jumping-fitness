import 'dart:async';

import 'package:jumping_fitness/auth/auth_repository.dart';
import 'package:jumping_fitness/models/trainer_request.dart';
import 'package:jumping_fitness/models/user_profile.dart';
import 'package:jumping_fitness/services/cloud_functions.dart';
import 'package:jumping_fitness/services/trainer_requests_repository.dart';
import 'package:jumping_fitness/services/user_repository.dart';

/// Firebase Auth в памяти: аккаунты «почта → пароль», письма не уходят,
/// подтверждение почты — [confirmEmail].
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthUser? signedIn}) : current = signedIn;

  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? current;

  /// Зарегистрированные аккаунты: почта → пароль.
  final Map<String, String> accounts = {};
  final Set<String> _verified = {};

  int signInCalls = 0;
  int signUpCalls = 0;
  int verificationEmails = 0;
  final List<String> resetEmails = [];

  /// Следующий запрос упадёт с этой ошибкой.
  AuthFailure? nextFailure;

  static String uidFor(String email) => 'uid$email';

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield current;
    yield* _changes.stream;
  }

  void _failIfAsked() {
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    _failIfAsked();
    if (accounts[email] != password) {
      throw const AuthFailure(AuthFailureKind.wrongCredentials);
    }
    _emit(email);
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    signUpCalls++;
    _failIfAsked();
    if (accounts.containsKey(email)) {
      throw const AuthFailure(AuthFailureKind.emailInUse);
    }
    accounts[email] = password;
    verificationEmails++;
    _emit(email);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _failIfAsked();
    resetEmails.add(email);
  }

  @override
  Future<void> sendEmailVerification() async {
    _failIfAsked();
    verificationEmails++;
  }

  @override
  Future<void> reloadUser() async {
    _failIfAsked();
    final email = current?.email;
    if (email != null) _emit(email);
  }

  /// Человек открыл ссылку из письма (видно после [reloadUser]).
  void confirmEmail(String email) => _verified.add(email);

  /// Сразу войти пользователем с подтверждённой почтой — для тестов экранов.
  /// Идентификатор может быть любым (в старых тестах — номер телефона).
  void signInAs(String email) {
    _verified.add(email);
    _emit(email);
  }

  void _emit(String email) {
    current = AuthUser(
      uid: uidFor(email),
      email: email,
      emailVerified: _verified.contains(email),
    );
    _changes.add(current);
  }

  @override
  Future<void> signOut() async {
    current = null;
    _changes.add(null);
  }
}

/// Firestore + Cloud Functions в памяти: профили, заявки, решения админа.
class FakeBackend implements UserRepository, TrainerRequestsRepository {
  final Map<String, UserProfile> profiles = {};
  final Map<String, TrainerRequest> requests = {};
  final List<String> approved = [];
  final List<String> rejected = [];

  /// Следующее решение по заявке упадёт с этой ошибкой.
  CloudFunctionFailure? decisionFailure;

  final _changed = StreamController<void>.broadcast();

  void _notify() => _changed.add(null);

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changed.stream.map((_) => read());
  }

  void putProfile(UserProfile profile) {
    profiles[profile.uid] = profile;
    _notify();
  }

  void putRequest(TrainerRequest request) {
    requests[request.uid] = request;
    _notify();
  }

  @override
  Stream<UserProfile?> watchProfile(String uid) => _watch(() => profiles[uid]);

  @override
  Stream<TrainerRequest?> watchOwnTrainerRequest(String uid) =>
      _watch(() => requests[uid]);

  @override
  Future<void> register({
    required AuthUser user,
    required String fullName,
    required String phone,
    required bool wantsTrainerRole,
  }) async {
    profiles[user.uid] = profile(
      uid: user.uid,
      fullName: fullName.trim(),
      phone: phone,
    );
    if (wantsTrainerRole) {
      requests[user.uid] = request(
        uid: user.uid,
        fullName: fullName.trim(),
        phone: phone,
      );
    }
    _notify();
  }

  @override
  Stream<List<TrainerRequest>> watchPending() => _watch(
    () => sortedByCreation(
      requests.values.where((r) => r.status == TrainerRequestStatus.pending),
    ),
  );

  @override
  Future<void> approve(String uid) => _decide(uid, approve: true);

  @override
  Future<void> reject(String uid) => _decide(uid, approve: false);

  Future<void> _decide(String uid, {required bool approve}) async {
    final failure = decisionFailure;
    if (failure != null) {
      decisionFailure = null;
      throw failure;
    }
    final current = requests[uid]!;
    requests[uid] = TrainerRequest(
      uid: uid,
      fullName: current.fullName,
      phone: current.phone,
      status: approve
          ? TrainerRequestStatus.approved
          : TrainerRequestStatus.rejected,
      createdAt: current.createdAt,
    );
    if (approve) {
      final user = profiles[uid]!;
      profiles[uid] = profile(
        uid: uid,
        fullName: user.fullName,
        phone: user.phone,
        role: UserRole.trainer,
        isAdmin: user.isAdmin,
      );
      approved.add(uid);
    } else {
      rejected.add(uid);
    }
    _notify();
  }
}

UserProfile profile({
  required String uid,
  String fullName = 'Анна Смирнова',
  String phone = '+79990000001',
  UserRole role = UserRole.client,
  bool isAdmin = false,
}) => UserProfile(
  uid: uid,
  fullName: fullName,
  phone: phone,
  role: role,
  isAdmin: isAdmin,
  createdAt: DateTime.utc(2026, 9, 1),
);

TrainerRequest request({
  required String uid,
  String fullName = 'Ольга Петрова',
  String phone = '+79990000002',
  DateTime? createdAt,
}) => TrainerRequest(
  uid: uid,
  fullName: fullName,
  phone: phone,
  status: TrainerRequestStatus.pending,
  createdAt: createdAt,
);

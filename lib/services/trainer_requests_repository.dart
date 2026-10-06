import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/firestore_paths.dart';
import '../models/trainer_request.dart';
import 'cloud_functions.dart';

/// Заявки в тренеры для экрана администратора (ТЗ 2).
///
/// Читает приложение напрямую (правила пускают к списку только админа),
/// а решение принимает Cloud Function: роль меняется только на сервере.
abstract interface class TrainerRequestsRepository {
  /// Ожидающие заявки, старые — сверху.
  Stream<List<TrainerRequest>> watchPending();

  /// Одобрить: роль → trainer, push заявителю. Ошибки — [CloudFunctionFailure].
  Future<void> approve(String uid);

  /// Отклонить. Ошибки — [CloudFunctionFailure].
  Future<void> reject(String uid);
}

class FirebaseTrainerRequestsRepository implements TrainerRequestsRepository {
  FirebaseTrainerRequestsRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  @override
  Stream<List<TrainerRequest>> watchPending() => _db
      .collection(FirestorePaths.trainerRequests)
      .where('status', isEqualTo: TrainerRequestStatus.pending.wireName)
      .snapshots()
      // Сортировка в памяти: заявок единицы, а составной индекс
      // status + createdAt ради этого не нужен.
      .map(
        (query) =>
            sortedByCreation(query.docs.map(TrainerRequest.fromSnapshot)),
      );

  @override
  Future<void> approve(String uid) => _call('approveTrainerRequest', uid);

  @override
  Future<void> reject(String uid) => _call('rejectTrainerRequest', uid);

  Future<void> _call(String name, String uid) =>
      callFunction(_functions, name, {'uid': uid});
}

/// Порядок показа: раньше поданные — выше; заявка без даты (только что
/// созданная, время сервера ещё не пришло) — в конце.
List<TrainerRequest> sortedByCreation(Iterable<TrainerRequest> requests) {
  final list = requests.toList();
  list.sort((a, b) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime == null && bTime == null) return a.fullName.compareTo(b.fullName);
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return aTime.compareTo(bTime);
  });
  return List.unmodifiable(list);
}

/// Firebase ещё не подключён.
class UnavailableTrainerRequestsRepository
    implements TrainerRequestsRepository {
  const UnavailableTrainerRequestsRepository();

  static const _failure = CloudFunctionFailure(
    'Приложение ещё не подключено к серверу.',
  );

  @override
  Stream<List<TrainerRequest>> watchPending() => Stream.value(const []);

  @override
  Future<void> approve(String uid) => Future.error(_failure);

  @override
  Future<void> reject(String uid) => Future.error(_failure);
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'firestore_parsing.dart';

enum TrainerRequestStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const TrainerRequestStatus(this.wireName);

  final String wireName;

  static TrainerRequestStatus fromWire(String value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => throw FormatException('Неизвестный статус заявки', value),
  );
}

/// Заявка в тренеры `trainer_requests/{uid}` (ТЗ 2).
@immutable
class TrainerRequest {
  const TrainerRequest({
    required this.uid,
    required this.fullName,
    required this.phone,
    required this.status,
    this.createdAt,
    this.decidedAt,
    this.decidedBy,
  });

  factory TrainerRequest.fromMap(String uid, Map<String, Object?> data) {
    final r = FirestoreReader('trainer_requests/$uid', data);
    return TrainerRequest(
      uid: uid,
      fullName: r.string('fullName'),
      phone: r.string('phone'),
      status: r.parsed('status', TrainerRequestStatus.fromWire),
      createdAt: r.optionalTimestamp('createdAt'),
      decidedAt: r.optionalTimestamp('decidedAt'),
      decidedBy: r.optionalString('decidedBy'),
    );
  }

  factory TrainerRequest.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => TrainerRequest.fromMap(snapshot.id, snapshot.data() ?? const {});

  final String uid;
  final String fullName;
  final String phone;
  final TrainerRequestStatus status;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String? decidedBy;

  /// Данные новой заявки — ровно те поля, что пропускают правила.
  static Map<String, Object?> creationData({
    required String uid,
    required String fullName,
    required String phone,
  }) => {
    'uid': uid,
    'fullName': fullName.trim(),
    'phone': phone,
    'status': TrainerRequestStatus.pending.wireName,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

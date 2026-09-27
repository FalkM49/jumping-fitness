import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'firestore_parsing.dart';

/// Цветок из справочника `flowers/{id}` (ТЗ 4, 12).
@immutable
class Flower {
  const Flower({
    required this.id,
    required this.name,
    required this.description,
    required this.meaning,
    required this.image,
    required this.order,
  });

  factory Flower.fromMap(String id, Map<String, Object?> data) {
    final r = FirestoreReader('flowers/$id', data);
    return Flower(
      id: id,
      name: r.string('name'),
      description: r.string('description'),
      meaning: r.string('meaning'),
      image: r.string('image'),
      order: r.integerOr('order', 0),
    );
  }

  factory Flower.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => Flower.fromMap(snapshot.id, snapshot.data() ?? const {});

  final String id;
  final String name;
  final String description;

  /// Значение на языке цветов.
  final String meaning;

  /// Путь к ассету в приложении.
  final String image;
  final int order;
}

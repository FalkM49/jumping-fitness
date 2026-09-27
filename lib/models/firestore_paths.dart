/// Имена коллекций Firestore — единственное место, где они записаны.
/// Схема: docs/02_firestore_schema.md.
abstract final class FirestorePaths {
  static const String users = 'users';
  static const String devices = 'devices'; // users/{uid}/devices
  static const String trainerRequests = 'trainer_requests';
  static const String settings = 'settings';
  static const String settingsDefaultsDoc = 'defaults'; // settings/defaults
  static const String calendarSlots = 'calendar_slots';
  static const String trainings = 'trainings';
  static const String bookings = 'bookings'; // trainings/{id}/bookings
  static const String subscriptions = 'subscriptions';
  static const String flowers = 'flowers';

  static String user(String uid) => '$users/$uid';
  static String userDevice(String uid, String deviceId) =>
      '$users/$uid/$devices/$deviceId';
  static String trainerRequest(String uid) => '$trainerRequests/$uid';
  static String calendarSlot(String slotKey) => '$calendarSlots/$slotKey';
  static String training(String trainingId) => '$trainings/$trainingId';
  static String booking(String trainingId, String clientUid) =>
      '$trainings/$trainingId/$bookings/$clientUid';
  static String subscription(String subscriptionId) =>
      '$subscriptions/$subscriptionId';
  static String flower(String flowerId) => '$flowers/$flowerId';
  static const String settingsDefaults = '$settings/$settingsDefaultsDoc';
}

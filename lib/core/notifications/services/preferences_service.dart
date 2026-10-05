import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification_preferences.dart';

/// Stores notification preferences on the user document, so they follow the
/// account across devices rather than living only on one phone.
class NotificationPreferencesService {
  NotificationPreferencesService({FirebaseFirestore? db, required this.uid})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final String uid;

  DocumentReference<Map<String, dynamic>> get _doc => _db.collection('users').doc(uid);

  Stream<NotificationPreferences> watch() => _doc.snapshots().map(_fromSnapshot);

  Future<NotificationPreferences> load() async => _fromSnapshot(await _doc.get());

  NotificationPreferences _fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final raw = snap.data()?['notificationPreferences'];
    if (raw is! Map) return const NotificationPreferences();
    return NotificationPreferences.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> save(NotificationPreferences preferences) => _doc.set(
        {'notificationPreferences': preferences.toJson()},
        SetOptions(merge: true),
      );
}

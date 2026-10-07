import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_preferences.dart';

/// Reads and writes [AppPreferences] on the user document.
///
/// It shares the document with the notification preferences and merges on
/// write, so saving one group never clobbers the other.
class AppPreferencesService {
  AppPreferencesService({FirebaseFirestore? db, required this.uid})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final String uid;

  DocumentReference<Map<String, dynamic>> get _doc => _db.collection('users').doc(uid);

  Stream<AppPreferences> watch() => _doc.snapshots().map(_fromSnapshot);

  Future<AppPreferences> load() async => _fromSnapshot(await _doc.get());

  AppPreferences _fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final raw = snap.data()?['appPreferences'];
    if (raw is! Map) return const AppPreferences();
    return AppPreferences.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> save(AppPreferences preferences) => _doc.set(
        {'appPreferences': preferences.toJson()},
        SetOptions(merge: true),
      );
}

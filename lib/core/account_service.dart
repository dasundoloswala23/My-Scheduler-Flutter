import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'attachment_service.dart';

/// Permanently deletes the signed-in user's account and every byte of their
/// data. Google Play and the App Store both require this to be possible
/// in-app for any app that lets people sign up.
///
/// Order matters:
///  1. Re-authenticate, because Firebase refuses deletion of a session that
///     is not recent.
///  2. Remove attachment files from Storage, so none are orphaned.
///  3. Remove Firestore documents, collection by collection.
///  4. Delete the Auth account last, so a failure part-way can be retried
///     while the user can still sign in.
class AccountService {
  AccountService({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  /// Collections directly under users/{uid}. Tasks are handled separately so
  /// their attachments are removed first.
  static const _collections = [
    'boards',
    'lists',
    'categories',
    'notes',
    'reminders',
    'holidays',
    'focusSessions',
  ];

  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw StateError('No signed-in email account to re-authenticate.');
    }
    final credential = EmailAuthProvider.credential(email: user.email!, password: password);
    await user.reauthenticateWithCredential(credential);
  }

  /// Google accounts re-authenticate through their provider, not a password.
  Future<void> reauthenticateWithProvider(AuthProvider provider) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    await user.reauthenticateWithProvider(provider);
  }

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    final uid = user.uid;
    final userRef = _db.collection('users').doc(uid);

    // 1. Attachment files and their metadata.
    final attachments = AttachmentService(db: _db, uid: uid);
    final tasks = await userRef.collection('tasks').get();
    for (final task in tasks.docs) {
      await attachments.deleteAllFor(task.id);
    }

    // 2. Tasks, then everything else under the user.
    await _deleteCollection(userRef.collection('tasks'));
    for (final name in _collections) {
      await _deleteCollection(userRef.collection(name));
    }
    await userRef.delete();

    // 3. The Auth account itself.
    await user.delete();
  }

  /// Deletes every document in a collection in batches of 400, which stays
  /// under Firestore's 500-write batch limit.
  Future<void> _deleteCollection(CollectionReference<Map<String, dynamic>> ref) async {
    while (true) {
      final snap = await ref.limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}

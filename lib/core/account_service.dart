import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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
  AccountService({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    this.cancelLocalReminders,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  /// Clears every reminder and alarm scheduled on this device, so nothing
  /// fires for an account that no longer exists.
  final Future<void> Function()? cancelLocalReminders;

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
    'projectFlows',
    'flowStages',
    'flowTaskLinks',
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

  /// Apple accounts can't reuse `reauthenticateWithProvider` on iOS/macOS the
  /// way Google can: each Sign in with Apple request needs its own nonce, so
  /// this mirrors `AuthService.signInWithApple` rather than delegating to it.
  Future<void> reauthenticateWithAppleCredential() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in.');

    final rawNonce = _randomNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      nonce: hashedNonce,
    );

    final credential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );
    await user.reauthenticateWithCredential(credential);
  }

  static String _randomNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in.');

    await deleteUserData(user.uid);

    // The Auth account itself, last, so a failure above can be retried while
    // the person can still sign in.
    await user.delete();
  }

  /// Removes everything stored for [uid]: attachment files, tasks, flows and
  /// every other collection, then the user document, then the local reminders.
  ///
  /// Safe to run again after a partial failure: each step only deletes what is
  /// still there. Nothing outside `users/{uid}` is touched, so shared data such
  /// as the built-in holiday tables is never affected.
  Future<void> deleteUserData(String uid, {AttachmentService? attachments}) async {
    final userRef = _db.collection('users').doc(uid);

    // 1. Attachment files and their metadata.
    final files = attachments ?? AttachmentService(db: _db, uid: uid);
    final tasks = await userRef.collection('tasks').get();
    for (final task in tasks.docs) {
      await files.deleteAllFor(task.id);
    }

    // 2. Tasks, then everything else under the user, flows included.
    await _deleteCollection(userRef.collection('tasks'));
    for (final name in _collections) {
      await _deleteCollection(userRef.collection(name));
    }
    await userRef.delete();

    // 3. Reminders already scheduled on this device.
    try {
      await cancelLocalReminders?.call();
    } catch (_) {
      // The data is gone either way; a stale local alert is not worth failing for.
    }
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

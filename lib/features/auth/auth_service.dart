import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Wraps every sign-in method so the UI only deals with [User] or an error.
///
/// Google:
///  - Android / iOS: native google_sign_in, then a Firebase credential.
///  - Windows / macOS / Web: Firebase's own OAuth popup or redirect flow.
/// Apple: native Sign in with Apple, iOS only (per the agreed scope).
/// Email/password: works on every platform.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> get authChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Apple sign-in is only offered on iOS.
  bool get supportsAppleSignIn => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get _usesNativeGoogle =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> signInWithGoogle() async {
    if (_usesNativeGoogle) {
      await GoogleSignIn.instance.initialize();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await _auth.signInWithCredential(credential);
      return;
    }

    final provider = GoogleAuthProvider()..addScope('email');
    if (kIsWeb) {
      await _auth.signInWithPopup(provider);
    } else {
      // Desktop has no native Google SDK, so Firebase opens the browser.
      await _auth.signInWithProvider(provider);
    }
  }

  Future<void> signInWithApple() async {
    if (!supportsAppleSignIn) {
      throw UnsupportedError('Apple sign-in is only available on iOS.');
    }

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
    await _auth.signInWithCredential(credential);
  }

  Future<void> signInWithEmail({required String email, required String password}) {
    return _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user?.updateDisplayName(name.trim());
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    if (_usesNativeGoogle) {
      await GoogleSignIn.instance.signOut();
    }
    await _auth.signOut();
  }

  static String _randomNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }
}

/// Used by the UI to show a friendly message for [FirebaseAuthException].
String authErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'Choose a stronger password (6+ characters).';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Sign-in was cancelled.';
    }
    return error.message ?? 'Sign-in failed. Please try again.';
  }
  if (error is UnsupportedError) return error.message ?? 'Not supported on this device.';
  return 'Sign-in failed. Please try again.';
}

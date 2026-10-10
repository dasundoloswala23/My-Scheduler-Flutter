import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'desktop_google_auth.dart';

/// Wraps every sign-in method so the UI only deals with [User] or an error.
///
/// Google:
///  - Android / iOS: native google_sign_in, then a Firebase credential.
///  - Windows: system browser with a loopback redirect (see [DesktopGoogleAuth]),
///    because Firebase's `signInWithProvider` is not supported on Windows.
///  - Web: Firebase's own popup.
/// Apple: native Sign in with Apple, iOS and macOS.
/// Email/password: works on every platform.
class AuthService {
  AuthService({FirebaseAuth? auth, DesktopGoogleAuth? desktopGoogle})
      : _auth = auth ?? FirebaseAuth.instance,
        _desktopGoogle = desktopGoogle ?? DesktopGoogleAuth(clientId: _desktopClientId, clientSecret: _desktopClientSecret);

  final FirebaseAuth _auth;
  final DesktopGoogleAuth _desktopGoogle;

  /// The Google OAuth client of type "Desktop app", supplied at build time:
  /// `--dart-define=GOOGLE_DESKTOP_CLIENT_ID=... --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=...`
  static const _desktopClientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const _desktopClientSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');

  /// The iOS/macOS OAuth client. Google sign-in on Apple platforms also needs
  /// `GIDClientID` and the reversed-client-ID URL scheme in Info.plist; until
  /// both exist the button is hidden rather than shown and throwing on tap.
  /// Supply at build time to re-enable:
  /// `--dart-define=GOOGLE_IOS_CLIENT_ID=...`
  static const _appleClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  bool get _usesDesktopGoogle => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Stream<User?> get authChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Apple sign-in is offered on iOS and macOS, where the native plugin works.
  bool get supportsAppleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

  bool get _usesNativeGoogle =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Whether to offer Google at all. A provider that cannot complete is worse
  /// than one that is absent, so each platform is gated on its own config:
  /// Android ships its client in google-services.json, Windows needs the
  /// desktop OAuth pair, and Apple platforms need [_appleClientId].
  bool get supportsGoogleSignIn {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => true,
      TargetPlatform.windows => _desktopGoogle.isConfigured,
      TargetPlatform.iOS || TargetPlatform.macOS => _appleClientId.isNotEmpty,
      _ => false,
    };
  }

  Future<void> signInWithGoogle() async {
    if (_usesNativeGoogle) {
      // Android reads its client from google-services.json; Apple platforms
      // need it passed explicitly (or set as GIDClientID in Info.plist).
      await GoogleSignIn.instance.initialize(
        clientId: _appleClientId.isEmpty ? null : _appleClientId,
      );
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        // Firebase cannot build a credential without it, and the failure it
        // raises on its own says nothing useful.
        throw StateError('Google did not return an ID token.');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await _auth.signInWithCredential(credential);
      return;
    }

    if (_usesDesktopGoogle) {
      final idToken = await _desktopGoogle.signIn();
      await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      return;
    }

    final provider = GoogleAuthProvider()..addScope('email');
    if (kIsWeb) {
      await _auth.signInWithPopup(provider);
    } else {
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
  if (error is DesktopGoogleAuthException) return error.message;
  // Native Google (iOS/Android) reports cancellation as an exception of its
  // own, not as a FirebaseAuthException, so it needs its own arm or a cancelled
  // sign-in reads as a failure.
  if (error is GoogleSignInException) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled => 'Sign-in was cancelled.',
      GoogleSignInExceptionCode.interrupted ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google sign-in is unavailable right now. Please try again.',
      _ => 'Google sign-in failed. Please try again.',
    };
  }
  if (error is StateError) return 'Google sign-in failed. Please try again.';
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

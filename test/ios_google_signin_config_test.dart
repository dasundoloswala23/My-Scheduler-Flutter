// Guards the iOS Google Sign-In configuration contract in Info.plist.
//
// Google Sign-In on iOS needs two values that must agree: GIDClientID (the
// OAuth client) and a CFBundleURLSchemes entry holding the *reversed* form of
// that same client, which is how the OAuth callback gets back into the app.
// Half the pair is useless, and a placeholder is worse than nothing — an
// earlier release was rejected by the App Store validator with
// "URL schemes ... not in the correct format: [REPLACE_WITH_REVERSED_CLIENT_ID]".
//
// These tests pass both before the values are configured (neither present) and
// after (both present and consistent), so they hold through the change.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:myschedule/features/auth/auth_service.dart';

const _plistPath = 'ios/Runner/Info.plist';

String _plist() => File(_plistPath).readAsStringSync();

/// The value of a top-level `<key>name</key><string>value</string>` pair.
String? _stringValue(String plist, String key) {
  final match = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<string>(.*?)</string>',
    dotAll: true,
  ).firstMatch(plist);
  return match?.group(1)?.trim();
}

void main() {
  group('iOS Info.plist Google Sign-In contract', () {
    test('the plist exists and parses as text', () {
      expect(File(_plistPath).existsSync(), isTrue, reason: '$_plistPath must exist');
      expect(_plist(), contains('CFBundleIdentifier'));
    });

    test('no placeholder ever ships in the plist', () {
      // This is the exact string that caused the App Store validator rejection.
      expect(
        _plist(),
        isNot(contains('REPLACE_WITH')),
        reason: 'a placeholder in GIDClientID or a URL scheme fails App Store validation',
      );
    });

    test('GIDClientID and the reversed-client-ID URL scheme are both present or both absent', () {
      final plist = _plist();
      final hasClientId = _stringValue(plist, 'GIDClientID') != null;
      final hasReversedScheme = plist.contains('com.googleusercontent.apps.');

      expect(
        hasClientId,
        hasReversedScheme,
        reason: hasClientId
            ? 'GIDClientID is set but the reversed-client-ID URL scheme is missing, so the '
                'OAuth callback cannot return to the app'
            : 'a reversed-client-ID URL scheme is set but GIDClientID is missing',
      );
    });

    test('when configured, the URL scheme is the reversed form of GIDClientID', () {
      final plist = _plist();
      final clientId = _stringValue(plist, 'GIDClientID');
      if (clientId == null) {
        // Not configured yet: covered by the pairing test above.
        return;
      }

      expect(
        clientId,
        endsWith('.apps.googleusercontent.com'),
        reason: 'GIDClientID must be an iOS OAuth client, not a web client id',
      );

      final expectedScheme =
          'com.googleusercontent.apps.${clientId.replaceAll('.apps.googleusercontent.com', '')}';
      expect(
        plist,
        contains(expectedScheme),
        reason: 'the URL scheme must be exactly the reversed GIDClientID',
      );
    });
  });

  // The checks above go quiet while nothing is configured, so exercise the same
  // matching logic against samples to prove it would actually catch a bad pair.
  group('the contract logic itself', () {
    String wrap(String body) => '<plist version="1.0"><dict>$body</dict></plist>';

    const clientId = '455014733188-abc123.apps.googleusercontent.com';
    const reversed = 'com.googleusercontent.apps.455014733188-abc123';

    String reversedOf(String id) =>
        'com.googleusercontent.apps.${id.replaceAll('.apps.googleusercontent.com', '')}';

    test('reads GIDClientID out of a plist', () {
      final p = wrap('<key>GIDClientID</key><string>$clientId</string>');
      expect(_stringValue(p, 'GIDClientID'), clientId);
    });

    test('derives the reversed scheme that must accompany a client id', () {
      expect(reversedOf(clientId), reversed);
    });

    test('catches a client id whose URL scheme is missing', () {
      final p = wrap('<key>GIDClientID</key><string>$clientId</string>');
      expect(p.contains('com.googleusercontent.apps.'), isFalse);
    });

    test('catches a URL scheme that belongs to a different client id', () {
      final p = wrap(
        '<key>GIDClientID</key><string>$clientId</string>'
        '<key>CFBundleURLSchemes</key><array>'
        '<string>com.googleusercontent.apps.999-wrong</string></array>',
      );
      expect(p.contains(reversedOf(clientId)), isFalse,
          reason: 'a mismatched scheme must not be mistaken for the right one');
    });

    test('accepts a correctly paired configuration', () {
      final p = wrap(
        '<key>GIDClientID</key><string>$clientId</string>'
        '<key>CFBundleURLSchemes</key><array><string>$reversed</string></array>',
      );
      expect(_stringValue(p, 'GIDClientID'), clientId);
      expect(p.contains(reversedOf(clientId)), isTrue);
    });
  });

  group('Google sign-in error mapping', () {
    test('a cancelled native sign-in reads as cancelled, not as a failure', () {
      const cancelled = GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
      expect(authErrorMessage(cancelled), 'Sign-in was cancelled.');
    });

    test('other Google failures get a Google-specific message', () {
      const failed = GoogleSignInException(code: GoogleSignInExceptionCode.unknownError);
      expect(authErrorMessage(failed), contains('Google sign-in failed'));
    });

    test('a missing ID token does not surface as a generic failure', () {
      expect(
        authErrorMessage(StateError('Google did not return an ID token.')),
        contains('Google sign-in failed'),
      );
    });
  });
}

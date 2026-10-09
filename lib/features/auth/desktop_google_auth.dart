import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Why a desktop Google sign-in did not produce a token.
enum DesktopGoogleFailure {
  /// No OAuth client was supplied to this build.
  notConfigured,

  /// The person closed or denied the Google page.
  cancelled,

  /// Nothing came back from the browser in time.
  timedOut,

  /// The browser could not be opened.
  browserFailed,

  /// The redirect did not match what was asked for (wrong state, no code).
  invalidResponse,

  /// Google refused to exchange the code.
  exchangeFailed,
}

class DesktopGoogleAuthException implements Exception {
  DesktopGoogleAuthException(this.failure, [this.detail]);

  final DesktopGoogleFailure failure;

  /// A short, non-secret explanation for logs.
  final String? detail;

  String get message => switch (failure) {
        DesktopGoogleFailure.notConfigured =>
          'Google sign-in is not set up in this build. Use email, or ask for a build with Google sign-in enabled.',
        DesktopGoogleFailure.cancelled => 'Google sign-in was cancelled.',
        DesktopGoogleFailure.timedOut => 'Google sign-in timed out. Please try again.',
        DesktopGoogleFailure.browserFailed => 'Could not open your browser for Google sign-in.',
        DesktopGoogleFailure.invalidResponse =>
          'Google sign-in returned an unexpected response. Please try again.',
        DesktopGoogleFailure.exchangeFailed =>
          'Google would not complete the sign-in. Please try again.',
      };

  @override
  String toString() => 'DesktopGoogleAuthException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// PKCE (RFC 7636) helpers, public so they can be tested against the RFC's own vector.
class Pkce {
  const Pkce._();

  static const _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// A random verifier of [length] characters (43 to 128 are allowed).
  static String verifier({int length = 64, Random? random}) {
    final r = random ?? Random.secure();
    return List.generate(length, (_) => _chars[r.nextInt(_chars.length)]).join();
  }

  /// `BASE64URL(SHA256(verifier))` with no padding.
  static String challenge(String verifier) =>
      base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

  /// An unguessable value for the `state` parameter.
  static String state({Random? random}) => verifier(length: 32, random: random);
}

typedef OpenBrowser = Future<void> Function(Uri url);
typedef TokenPost = Future<Map<String, dynamic>> Function(Uri url, Map<String, String> form);

/// Google sign-in for desktop: the system browser plus a loopback redirect.
///
/// This is Google's documented flow for installed apps (OAuth 2.0 authorization
/// code with PKCE). The app listens on `127.0.0.1` on a random port, opens the
/// consent page, receives the redirect, and exchanges the code for an ID token,
/// which Firebase then accepts through `signInWithCredential`. Firebase's own
/// `signInWithProvider` is not available on Windows, so this replaces it there.
///
/// It needs an OAuth client of type **Desktop app**. Android and Web clients are
/// different kinds and cannot be used here. For an installed app Google does not
/// treat the client secret as confidential, but it still lives in build-time
/// configuration and not in the repository.
class DesktopGoogleAuth {
  DesktopGoogleAuth({
    required this.clientId,
    required this.clientSecret,
    OpenBrowser? openBrowser,
    TokenPost? post,
    this.timeout = const Duration(minutes: 3),
    this.random,
  })  : _openBrowser = openBrowser ?? _defaultOpen,
        _post = post ?? _defaultPost;

  final String clientId;
  final String clientSecret;
  final Duration timeout;
  final OpenBrowser _openBrowser;
  final TokenPost _post;
  /// For tests: a seeded generator makes the verifier and state predictable.
  final Random? random;

  static const authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const tokenEndpoint = 'https://oauth2.googleapis.com/token';

  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;

  /// Runs the whole flow and returns Google's ID token.
  Future<String> signIn() async {
    if (!isConfigured) throw DesktopGoogleAuthException(DesktopGoogleFailure.notConfigured);

    final verifier = Pkce.verifier(random: random);
    final state = Pkce.state(random: random);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';

    try {
      final url = Uri.parse(authEndpoint).replace(queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': 'openid email profile',
        'code_challenge': Pkce.challenge(verifier),
        'code_challenge_method': 'S256',
        'state': state,
        // Always show the account chooser, so signing out and in can switch accounts.
        'prompt': 'select_account',
      });

      // Start listening before the browser opens, so a fast redirect is not lost.
      final request = server.first.timeout(timeout, onTimeout: () {
        throw DesktopGoogleAuthException(DesktopGoogleFailure.timedOut);
      });

      // If we bail out before awaiting it (browser failed), its later error must not
      // surface as an unhandled one.
      request.ignore();

      try {
        await _openBrowser(url);
      } catch (e) {
        throw DesktopGoogleAuthException(DesktopGoogleFailure.browserFailed, e.runtimeType.toString());
      }

      final req = await request;
      final params = req.uri.queryParameters;
      await _reply(req.response, ok: params['code'] != null && params['error'] == null);

      if (params['error'] != null) {
        throw DesktopGoogleAuthException(
          params['error'] == 'access_denied'
              ? DesktopGoogleFailure.cancelled
              : DesktopGoogleFailure.invalidResponse,
          params['error'],
        );
      }
      if (params['state'] != state) {
        throw DesktopGoogleAuthException(DesktopGoogleFailure.invalidResponse, 'state mismatch');
      }
      final code = params['code'];
      if (code == null || code.isEmpty) {
        throw DesktopGoogleAuthException(DesktopGoogleFailure.invalidResponse, 'no code');
      }

      final Map<String, dynamic> token;
      try {
        token = await _post(Uri.parse(tokenEndpoint), {
          'client_id': clientId,
          'client_secret': clientSecret,
          'code': code,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
          'redirect_uri': redirect,
        });
      } catch (e) {
        throw DesktopGoogleAuthException(DesktopGoogleFailure.exchangeFailed, e.runtimeType.toString());
      }

      final idToken = token['id_token'];
      if (idToken is! String || idToken.isEmpty) {
        // Google's error code is safe to keep (e.g. invalid_client); nothing else is.
        throw DesktopGoogleAuthException(
            DesktopGoogleFailure.exchangeFailed, token['error']?.toString() ?? 'no id_token');
      }
      return idToken;
    } finally {
      await server.close(force: true);
    }
  }

  static Future<void> _reply(HttpResponse response, {required bool ok}) async {
    response.headers.contentType = ContentType.html;
    response.write('<!doctype html><meta charset="utf-8"><title>My Scheduler</title>'
        '<body style="font-family:system-ui;text-align:center;margin-top:20vh">'
        '<h2>${ok ? 'Signed in' : 'Sign-in did not complete'}</h2>'
        '<p>${ok ? 'You can close this tab and return to the app.' : 'You can close this tab and try again in the app.'}</p>');
    await response.close();
  }

  /// Opens [url] in the default browser. `rundll32` takes the URL as one argument,
  /// so the `&` in a query string is never interpreted by a shell.
  static Future<void> _defaultOpen(Uri url) async {
    if (!Platform.isWindows) throw UnsupportedError('Desktop Google sign-in is Windows-only.');
    final result = await Process.run('rundll32', ['url.dll,FileProtocolHandler', url.toString()]);
    if (result.exitCode != 0) throw StateError('rundll32 exit ${result.exitCode}');
  }

  static Future<Map<String, dynamic>> _defaultPost(Uri url, Map<String, String> form) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(url);
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(form.entries
          .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } finally {
      client.close();
    }
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/features/auth/auth_service.dart';
import 'package:myschedule/features/auth/desktop_google_auth.dart';

/// A "browser" that, instead of opening a page, reads the authorisation URL the
/// app built and calls back to the app's real loopback server, as Google's
/// redirect would.
OpenBrowser fakeBrowser(
  void Function(Uri auth)? inspect, {
  Map<String, String> Function(Uri auth)? query,
  Duration delay = Duration.zero,
}) =>
    (auth) async {
      inspect?.call(auth);
      final redirect = Uri.parse(auth.queryParameters['redirect_uri']!);
      final params = query?.call(auth) ??
          {'code': 'AUTH-CODE', 'state': auth.queryParameters['state']!};
      Future<void>.delayed(delay, () async {
        final client = HttpClient();
        try {
          final req = await client.getUrl(redirect.replace(queryParameters: params));
          await (await req.close()).drain<void>();
        } finally {
          client.close();
        }
      });
    };

DesktopGoogleAuth make({
  OpenBrowser? browser,
  TokenPost? post,
  String id = 'client-id',
  String secret = 'client-secret',
  Duration timeout = const Duration(seconds: 5),
}) =>
    DesktopGoogleAuth(
      clientId: id,
      clientSecret: secret,
      openBrowser: browser ?? fakeBrowser(null),
      post: post ?? (url, form) async => {'id_token': 'ID-TOKEN'},
      timeout: timeout,
    );

Future<DesktopGoogleFailure> failureOf(Future<Object?> f) async {
  try {
    await f;
  } on DesktopGoogleAuthException catch (e) {
    return e.failure;
  }
  fail('expected a DesktopGoogleAuthException');
}

void main() {
  group('PKCE', () {
    test('matches the RFC 7636 appendix B vector', () {
      expect(
        Pkce.challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('verifiers are long enough, URL-safe, and different each time', () {
      final a = Pkce.verifier();
      final b = Pkce.verifier();
      expect(a.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(a), isTrue);
      expect(a, isNot(b));
    });
  });

  group('the flow', () {
    test('asks Google for an installed-app code flow with PKCE and a loopback redirect', () async {
      Uri? seen;
      await make(browser: fakeBrowser((u) => seen = u)).signIn();
      final q = seen!.queryParameters;
      expect(seen!.host, 'accounts.google.com');
      expect(q['client_id'], 'client-id');
      expect(q['response_type'], 'code');
      expect(q['code_challenge_method'], 'S256');
      expect(q['code_challenge'], isNotEmpty);
      expect(q['scope'], contains('openid'));
      expect(Uri.parse(q['redirect_uri']!).host, '127.0.0.1');
      expect(q['state']!.length, greaterThanOrEqualTo(16));
    });

    test('returns the ID token after exchanging the code with the PKCE verifier', () async {
      Map<String, String>? form;
      Uri? auth;
      final token = await make(
        browser: fakeBrowser((u) => auth = u),
        post: (url, f) async {
          form = f;
          return {'id_token': 'ID-TOKEN'};
        },
      ).signIn();
      expect(token, 'ID-TOKEN');
      expect(form!['code'], 'AUTH-CODE');
      expect(form!['grant_type'], 'authorization_code');
      expect(form!['redirect_uri'], auth!.queryParameters['redirect_uri']);
      // The verifier sent must be the one whose hash was sent to Google first.
      expect(Pkce.challenge(form!['code_verifier']!), auth!.queryParameters['code_challenge']);
    });

    test('a redirect with the wrong state is rejected and nothing is exchanged', () async {
      var exchanged = false;
      final f = await failureOf(make(
        browser: fakeBrowser(null, query: (_) => {'code': 'x', 'state': 'forged'}),
        post: (u, f) async {
          exchanged = true;
          return {'id_token': 't'};
        },
      ).signIn());
      expect(f, DesktopGoogleFailure.invalidResponse);
      expect(exchanged, isFalse);
    });

    test('a redirect with no code is rejected', () async {
      final f = await failureOf(
          make(browser: fakeBrowser(null, query: (a) => {'state': a.queryParameters['state']!})).signIn());
      expect(f, DesktopGoogleFailure.invalidResponse);
    });

    test('denying access on the Google page is a cancellation, not an error', () async {
      final f = await failureOf(make(
        browser: fakeBrowser(null, query: (a) => {'error': 'access_denied', 'state': a.queryParameters['state']!}),
      ).signIn());
      expect(f, DesktopGoogleFailure.cancelled);
    });

    test('closing the browser (nothing ever comes back) times out instead of spinning forever', () async {
      final f = await failureOf(make(
        browser: (_) async {},
        timeout: const Duration(milliseconds: 300),
      ).signIn());
      expect(f, DesktopGoogleFailure.timedOut);
    });

    test('a browser that cannot be opened is reported', () async {
      final f = await failureOf(make(browser: (_) async => throw StateError('no browser')).signIn());
      expect(f, DesktopGoogleFailure.browserFailed);
    });

    test('Google refusing the code (bad client) is reported with its error code only', () async {
      DesktopGoogleAuthException? caught;
      try {
        await make(post: (u, f) async => {'error': 'invalid_client', 'error_description': 'secret details'}).signIn();
      } on DesktopGoogleAuthException catch (e) {
        caught = e;
      }
      expect(caught!.failure, DesktopGoogleFailure.exchangeFailed);
      expect(caught.detail, 'invalid_client');
      expect(caught.toString(), isNot(contains('secret details')));
    });

    test('a network failure during the exchange is reported', () async {
      final f = await failureOf(make(post: (u, f) async => throw const SocketException('down')).signIn());
      expect(f, DesktopGoogleFailure.exchangeFailed);
    });

    test('the loopback port is released afterwards, success or failure', () async {
      Uri? seen;
      await make(browser: fakeBrowser((u) => seen = u)).signIn();
      final port = Uri.parse(seen!.queryParameters['redirect_uri']!).port;
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await server.close();
    });

    test('without a client it says so and never opens a browser', () async {
      var opened = false;
      final f = await failureOf(
          make(id: '', secret: '', browser: (_) async => opened = true).signIn());
      expect(f, DesktopGoogleFailure.notConfigured);
      expect(opened, isFalse);
    });
  });

  group('messages', () {
    test('each failure has a plain, secret-free message the sign-in page can show', () {
      for (final f in DesktopGoogleFailure.values) {
        final msg = authErrorMessage(DesktopGoogleAuthException(f, 'secret-detail'));
        expect(msg, isNotEmpty);
        expect(msg, isNot(contains('secret-detail')));
      }
    });
  });
}

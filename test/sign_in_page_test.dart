import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/app/theme.dart';
import 'package:myschedule/features/auth/auth_service.dart';
import 'package:myschedule/features/auth/sign_in_page.dart';

/// Records calls; never touches Firebase. [hold] keeps a sign-in "in flight".
class FakeAuth extends Fake implements AuthService {
  final calls = <String>[];
  Completer<void>? hold;
  Object? failWith;
  bool googleEnabled = true;
  bool appleEnabled = false;

  @override
  bool get supportsAppleSignIn => appleEnabled;

  @override
  bool get supportsGoogleSignIn => googleEnabled;

  Future<void> _go(String name) async {
    calls.add(name);
    await hold?.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> signInWithEmail({required String email, required String password}) => _go('email');

  @override
  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) => _go('signup');

  @override
  Future<void> signInWithGoogle() => _go('google');

  @override
  Future<void> sendPasswordReset(String email) => _go('reset');
}

Future<FakeAuth> pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  FakeAuth? auth,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final a = auth ?? FakeAuth();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness: brightness),
      home: SignInPage(auth: a),
    ),
  );
  await tester.pump();
  return a;
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  testWidgets('shows the real logo asset, not a coloured block', (tester) async {
    await pump(tester);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/logo.png');
    expect(image.fit, BoxFit.contain);
    expect(image.width, image.height, reason: 'the 512x512 logo keeps its 1:1 proportion');
  });

  testWidgets('has the hierarchy in order', (tester) async {
    await pump(tester);
    for (final t in [
      'MY SCHEDULER',
      'Welcome back',
      'Sign in to continue planning your day.',
      'Forgot password?',
      'Continue with Google',
      'Create an account',
      'Terms',
      'Privacy Policy',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(field('Email'), findsOneWidget);
    expect(field('Password'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Welcome back')).dy,
      lessThan(tester.getTopLeft(field('Email')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Sign in').last).dy,
      lessThan(tester.getTopLeft(find.text('Continue with Google')).dy),
    );
  });

  testWidgets('password visibility toggles', (tester) async {
    await pump(tester);
    EditableText pw() => tester.widget<EditableText>(
      find.descendant(of: field('Password'), matching: find.byType(EditableText)),
    );
    expect(pw().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(pw().obscureText, isFalse);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(pw().obscureText, isTrue);
  });

  testWidgets('validation messages appear and nothing is submitted', (tester) async {
    final auth = await pump(tester);
    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('At least 6 characters'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('while signing in: spinner, everything disabled, one submission only', (
    tester,
  ) async {
    final auth = FakeAuth()..hold = Completer<void>();
    await pump(tester, auth: auth);
    await tester.enterText(field('Email'), 'a@b.co');
    await tester.enterText(field('Password'), 'secret1');
    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final google = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('Continue with Google'), matching: find.byType(OutlinedButton)),
    );
    expect(google.onPressed, isNull);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(auth.calls, ['email']);
    auth.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failure shows a message and keeps what was typed', (tester) async {
    final auth = FakeAuth()..failWith = Exception('x');
    await pump(tester, auth: auth);
    await tester.enterText(field('Email'), 'a@b.co');
    await tester.enterText(field('Password'), 'secret1');
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
    expect(find.text('Sign-in failed. Please try again.'), findsOneWidget);
    expect(find.text('a@b.co'), findsOneWidget);
  });

  testWidgets('Google button calls the existing auth service', (tester) async {
    final auth = await pump(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['google']);
  });

  testWidgets('create-account switches mode and shows the name field', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Create an account'));
    await tester.pump();
    expect(find.text('Create your account'), findsOneWidget);
    expect(field('Full name'), findsOneWidget);
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('forgot password uses the reset flow and confirms', (tester) async {
    final auth = await pump(tester);
    await tester.enterText(field('Email'), 'a@b.co');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['reset']);
    expect(find.text('Password reset email sent.'), findsOneWidget);
  });

  // A provider that cannot complete is worse than one that is absent: on a
  // platform with no OAuth client configured the button must not be offered.
  testWidgets('an unconfigured Google provider is not offered', (tester) async {
    await pump(tester, auth: FakeAuth()..googleEnabled = false);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('Sign in'), findsWidgets, reason: 'email sign-in still works');
  });

  testWidgets('the "or" rule is dropped when no provider follows it', (tester) async {
    await pump(tester, auth: FakeAuth()..googleEnabled = false);
    expect(find.text('or'), findsNothing);
  });

  testWidgets('the "or" rule stays when a provider remains', (tester) async {
    await pump(tester, auth: FakeAuth()..googleEnabled = false..appleEnabled = true);
    expect(find.text('or'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });

  for (final b in Brightness.values) {
    for (final (name, size) in [
      ('small phone', const Size(320, 568)),
      ('phone', const Size(390, 844)),
      ('desktop', const Size(1400, 900)),
    ]) {
      testWidgets('${b.name} / $name renders without overflow', (tester) async {
        await pump(tester, size: size, brightness: b);
        expect(tester.takeException(), isNull);
        final w = tester.getSize(field('Email')).width;
        expect(w, lessThanOrEqualTo(420), reason: 'the form never stretches across a wide window');
      });
    }
  }
}

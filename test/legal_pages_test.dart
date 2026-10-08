import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/app/theme.dart';
import 'package:myschedule/features/legal/legal_content.dart';
import 'package:myschedule/features/legal/legal_pages.dart';

void main() {
  final all = [...kPrivacySections, ...kTermsSections];

  test('the wording makes no absolute promises it cannot keep', () {
    final text = all.map((s) => '${s.heading} ${s.body}').join(' ').toLowerCase();
    for (final phrase in ['100%', 'completely safe', 'totally secure', 'unhackable', 'guaranteed']) {
      expect(text, isNot(contains(phrase)), reason: phrase);
    }
  });

  test('the privacy policy covers storage, deletion and what is not done', () {
    final headings = kPrivacySections.map((s) => s.heading).toList();
    expect(headings, containsAll(['What we store', 'Where it is stored', 'Keeping and deleting your data']));
    final text = kPrivacySections.map((s) => s.body).join(' ');
    expect(text, contains('Firebase'));
    expect(text, contains('Delete account'));
  });

  for (final brightness in Brightness.values) {
    testWidgets('both pages render in ${brightness.name} mode', (tester) async {
      for (final page in [const PrivacyPolicyPage(), const TermsPage()]) {
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(brightness: brightness),
          home: page,
        ));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Last updated'), findsOneWidget);
      }
    });
  }

  testWidgets('the sign-in links open each page', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(brightness: Brightness.light),
      home: const Scaffold(body: LegalLinks()),
    ));
    await tester.tap(find.text('Privacy Policy'));
    await tester.pumpAndSettle();
    expect(find.text('What we store'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terms'));
    await tester.pumpAndSettle();
    expect(find.text('Using the app'), findsOneWidget);
  });
}

// Screenshots of the REAL app (real widgets, real data from the live test
// account) in light and dark at a desktop and a compact width, for a human to
// review. It touches no other window: each frame is read straight from the
// Flutter layer with `RepaintBoundary.toImage`.
//
//   flutter test integration_test/windows_visual_sweep_test.dart -d windows \
//     --dart-define=MYS_TEST_EMAIL=... --dart-define=MYS_TEST_PASSWORD=... \
//     --dart-define=SWEEP_DIR=C:/some/folder
//
// It is read-only against the account (it opens screens and dialogs, saves
// nothing) and writes PNGs to SWEEP_DIR.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:myschedule/core/providers.dart';
import 'package:myschedule/firebase_options.dart';
import 'package:myschedule/main.dart' show MyScheduleApp;

const _email = String.fromEnvironment('MYS_TEST_EMAIL');
const _password = String.fromEnvironment('MYS_TEST_PASSWORD');
const _dir = String.fromEnvironment('SWEEP_DIR', defaultValue: 'build/sweep');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(_email, isNotEmpty, reason: 'pass --dart-define=MYS_TEST_EMAIL/PASSWORD');
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email, password: _password);
    Directory(_dir).createSync(recursive: true);
  });

  Future<void> pumpFor(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<bool> waitFor(WidgetTester tester, Finder f, {int seconds = 20}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 150));
      if (f.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final (name, size) in [
      ('desktop', const Size(1400, 900)),
      ('compact', const Size(420, 880)),
    ]) {
      testWidgets('${mode.name} / $name', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: ProviderScope(
            overrides: [themeModeProvider.overrideWithValue(mode)],
            child: const MyScheduleApp(),
          ),
        ));
        expect(await waitFor(tester, find.textContaining('Good ')), isTrue);
        await pumpFor(tester, const Duration(seconds: 3));

        Future<void> shot(String screen) async {
          await pumpFor(tester, const Duration(milliseconds: 900));
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
          final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
          File('$_dir/${mode.name}-$name-$screen.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        }

        Future<void> go(String label) async {
          final f = find.text(label);
          if (f.evaluate().isEmpty) return;
          await tester.tap(f.first);
          await pumpFor(tester, const Duration(milliseconds: 1200));
        }

        await shot('today');
        await go('Boards');
        await shot('boards');
        await go('Calendar');
        await shot('calendar');
        await go('Inbox');
        await shot('inbox');
        await go('More');
        await shot('more');

        // Project Flows: sidebar on desktop, a tile on the More page when compact.
        await go('Project Flows');
        await shot('flows');
        if (find.text('New flow').evaluate().isNotEmpty) {
          await tester.tap(find.text('New flow').first);
          await pumpFor(tester, const Duration(milliseconds: 1200));
          await shot('flows-create');
          await tester.pageBack();
          await pumpFor(tester, const Duration(milliseconds: 600));
        }
        if (find.byTooltip('Back').evaluate().isNotEmpty) {
          await tester.pageBack();
          await pumpFor(tester, const Duration(milliseconds: 600));
        }

        // Quick Add and its pickers.
        final quick = find.text('Quick add');
        if (quick.evaluate().isNotEmpty) {
          await tester.tap(quick.first);
        } else if (find.byType(FloatingActionButton).evaluate().isNotEmpty) {
          await tester.tap(find.byType(FloatingActionButton).first);
        }
        if (await waitFor(tester, find.text('Save Task'), seconds: 8)) {
          await shot('quick-add');
          if (find.text('Time').evaluate().isNotEmpty) {
            await tester.ensureVisible(find.text('Time'));
            await tester.tap(find.text('Time'));
            await pumpFor(tester, const Duration(milliseconds: 1200));
            await shot('time-picker');
            if (find.text('Cancel').evaluate().isNotEmpty) {
              await tester.tap(find.text('Cancel').last);
              await pumpFor(tester, const Duration(milliseconds: 600));
            }
          }
          if (find.text('Priority').evaluate().isNotEmpty) {
            await tester.ensureVisible(find.text('Priority'));
            await tester.tap(find.text('Priority'));
            await pumpFor(tester, const Duration(milliseconds: 900));
            await shot('priority-sheet');
            await tester.tapAt(const Offset(10, 10));
            await pumpFor(tester, const Duration(milliseconds: 600));
          }
        }
      });
    }
  }
}

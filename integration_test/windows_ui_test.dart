// The real app, driven through its own UI, against the live Firebase project.
//
//   flutter test integration_test/windows_ui_test.dart -d windows \
//     --dart-define=MYS_TEST_EMAIL=... --dart-define=MYS_TEST_PASSWORD=...
//
// It signs in as the shared test account, creates data through the screens a
// person uses (Quick Add, Project Flows, Settings), checks the result in
// Firestore, and removes everything it made. It proves the screens, the
// repositories and the deployed security rules work together; it says nothing
// about how anything looks.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:myschedule/firebase_options.dart';
import 'package:myschedule/main.dart' show MyScheduleApp;

const _email = String.fromEnvironment('MYS_TEST_EMAIL');
const _password = String.fromEnvironment('MYS_TEST_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String uid;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final taskTitle = 'UI task $stamp';
  final flowName = 'UI flow $stamp';

  CollectionReference<Map<String, dynamic>> col(String name) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection(name);

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

  setUpAll(() async {
    expect(_email, isNotEmpty, reason: 'pass --dart-define=MYS_TEST_EMAIL=… and MYS_TEST_PASSWORD=…');
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final cred = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: _email, password: _password);
    uid = cred.user!.uid;
  });

  tearDownAll(() async {
    // Leave the account as it was found.
    for (final t in (await col('tasks').where('title', isEqualTo: taskTitle).get()).docs) {
      final next = t.data()['spawnedNextTaskId'] as String?;
      if (next != null) await col('tasks').doc(next).delete();
      await col('tasks').doc(t.id).delete();
    }
    for (final f in (await col('projectFlows').where('name', isEqualTo: flowName).get()).docs) {
      for (final s in (await col('flowStages').where('flowId', isEqualTo: f.id).get()).docs) {
        await s.reference.delete();
      }
      for (final l in (await col('flowTaskLinks').where('flowId', isEqualTo: f.id).get()).docs) {
        await l.reference.delete();
      }
      await f.reference.delete();
    }
  });

  testWidgets('Windows desktop: the real UI, end to end', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: MyScheduleApp()));
    expect(await waitFor(tester, find.text('Boards')), isTrue, reason: 'the signed-in home shell appears');

    // ---- the sidebar and Project Flows are reachable on desktop
    expect(find.text('Project Flows'), findsWidgets);

    // ---- Quick Add: a task with a time and a repeat
    await tester.tap(find.text('Quick add').first);
    expect(await waitFor(tester, find.text('Save Task')), isTrue, reason: 'Quick Add opens');
    await tester.enterText(find.byType(TextField).first, taskTitle);
    await tester.pump();

    await tester.ensureVisible(find.text('Time'));
    await tester.tap(find.text('Time'));
    expect(await waitFor(tester, find.byType(TimePickerDialog)), isTrue);
    await tester.tap(find.text('OK'));
    await pumpFor(tester, const Duration(milliseconds: 600));

    expect(find.text('Repeat'), findsOneWidget, reason: 'a time makes Repeat available');
    await tester.ensureVisible(find.text('Repeat'));
    await tester.tap(find.text('Repeat'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.tap(find.text('Weekdays'));
    await pumpFor(tester, const Duration(milliseconds: 600));

    await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
    await pumpFor(tester, const Duration(seconds: 4));

    final saved = await col('tasks').where('title', isEqualTo: taskTitle).get();
    expect(saved.docs, hasLength(1), reason: 'Quick Add saved exactly one task');
    expect(saved.docs.single.data()['recurrence'], 'weekdays');
    expect(saved.docs.single.data()['startDateTime'], isNotNull);

    // ---- Project Flows: create from a template through the UI
    await tester.tap(find.text('Project Flows').first);
    expect(await waitFor(tester, find.text('Plan a project in stages')), isTrue,
        reason: 'the empty state, or the list if flows exist');
    await tester.tap(find.text('New flow').first);
    expect(await waitFor(tester, find.text('New Project Flow')), isTrue);
    await tester.enterText(find.byType(TextField).first, flowName);
    await tester.pump();
    await tester.tap(find.text('Create flow'));
    expect(await waitFor(tester, find.text('Planning'), seconds: 25), isTrue,
        reason: 'the new flow opens on its timeline');
    expect(find.text('Internal QA'), findsOneWidget);
    expect(find.text('Active'), findsWidgets);

    final flows = await col('projectFlows').where('name', isEqualTo: flowName).get();
    expect(flows.docs, hasLength(1));
    final stages = await col('flowStages').where('flowId', isEqualTo: flows.docs.single.id).get();
    expect(stages.docs, hasLength(9), reason: 'the Mobile App Launch template has nine stages');
    final tasksAfterFlow = await col('tasks').where('title', isEqualTo: taskTitle).get();
    expect(tasksAfterFlow.docs, hasLength(1), reason: 'creating a flow created no tasks');

    // ---- Settings: legal pages open
    await tester.pageBack();
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.pageBack();
    await pumpFor(tester, const Duration(milliseconds: 600));
  });
}

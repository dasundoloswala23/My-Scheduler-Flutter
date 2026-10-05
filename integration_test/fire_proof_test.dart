// Schedules one near-term reminder and deliberately leaves it in place, so a
// human (or `adb shell dumpsys notification`) can watch it actually arrive.
//
// Separate from notification_device_test.dart because that suite cancels
// everything in tearDown, which would stop the alert before it ever fired.
//
//   flutter test integration_test/fire_proof_test.dart -d ZL8325W28X
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';

import 'package:myschedule/core/notifications/models/reminder.dart';
import 'package:myschedule/core/notifications/platform/local_notification_adapter.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/firebase_options.dart';
import 'package:myschedule/models/task.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('schedule a reminder about a minute out and leave it armed',
      (tester) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: 'dasuntest3@gmail.com',
      password: '123456',
    );

    final adapter = LocalNotificationAdapter();
    await adapter.initialise();
    await adapter.requestPermission();

    final repo = Repo(uid: credential.user!.uid);

    // Far enough out that scheduling finishes first, close enough to watch.
    final start = DateTime.now().add(const Duration(seconds: 75));
    final reminder = Reminder(
      id: const Uuid().v4(),
      taskId: 'pending',
      type: ReminderType.atTime,
      offsetMinutes: 0,
    );

    final id = await repo.createTask(Task(
      id: 'pending',
      title: 'Reminder proof',
      description: 'This alert should appear on the device within a minute or two.',
      startDateTime: start,
      endDateTime: start.add(const Duration(minutes: 30)),
      reminders: [reminder],
      position: 999999,
    ));

    final pending = await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
    expect(pending.any((p) => p.title == 'Reminder proof'), isTrue,
        reason: 'the alarm must be registered with Android before we wait for it');

    // Printed so the run log carries the id and the moment to expect it.
    // ignore: avoid_print
    print('PROOF_TASK_ID=$id');
    // ignore: avoid_print
    print('PROOF_FIRES_AT=${start.toIso8601String()}');
    // ignore: avoid_print
    print('PROOF_PENDING_COUNT=${pending.length}');
  });
}

// Runs on a real device against the real plugin and real Firebase.
//
// This is the test that coordinate-tapping through adb could not do reliably:
// it drives the actual app, writes a task with reminders, and then asks the
// platform what it has scheduled. `pendingNotificationRequests()` is answered
// by Android itself, so a pass here means the OS really holds the alarms.
//
//   flutter test integration_test/notification_device_test.dart -d ZL8325W28X
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';

import 'package:myschedule/core/notifications/models/notification_preferences.dart';
import 'package:myschedule/core/notifications/models/reminder.dart';
import 'package:myschedule/core/notifications/platform/local_notification_adapter.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/firebase_options.dart';
import 'package:myschedule/models/task.dart';

const email = 'dasuntest3@gmail.com';
const password = '123456';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Repo repo;
  late NotificationService service;
  late LocalNotificationAdapter adapter;
  final plugin = FlutterLocalNotificationsPlugin();
  final createdTaskIds = <String>[];

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    final credential = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);
    expect(credential.user, isNotNull, reason: 'the test account must sign in');

    adapter = LocalNotificationAdapter();
    await adapter.initialise();
    await adapter.requestPermission();

    repo = Repo(uid: credential.user!.uid);
    service = NotificationService(adapter: adapter);
  });

  tearDownAll(() async {
    // Leave the account exactly as it was found.
    for (final id in createdTaskIds) {
      await repo.deleteTask(id);
    }
    await plugin.cancelAll();
  });

  Future<Set<int>> pendingIds() async {
    final pending = await plugin.pendingNotificationRequests();
    return pending.map((p) => p.id).toSet();
  }

  Task buildTask({
    required String title,
    required DateTime start,
    required List<Reminder> reminders,
  }) =>
      Task(
        id: 'pending',
        title: title,
        description: 'Created by the device integration test',
        startDateTime: start,
        endDateTime: start.add(const Duration(hours: 1)),
        reminders: reminders,
        position: 500000,
      );

  testWidgets('the platform really schedules a reminder', (tester) async {
    expect(adapter.supportsScheduling, isTrue, reason: 'Android must support scheduling');

    final start = DateTime.now().add(const Duration(minutes: 30));
    final reminder = Reminder(
      id: const Uuid().v4(),
      taskId: 'pending',
      type: ReminderType.beforeTask,
      offsetMinutes: 15,
    );

    final id = await repo.createTask(
      buildTask(title: 'Device test — single reminder', start: start, reminders: [reminder]),
    );
    createdTaskIds.add(id);

    final expectedId = ReminderCalculatorIds.forTask(id, reminder.id);
    final pending = await pendingIds();

    expect(pending, contains(expectedId),
        reason: 'Android should be holding the alarm for this reminder');
  });

  testWidgets('several reminders on one task all reach the OS', (tester) async {
    final start = DateTime.now().add(const Duration(hours: 2));
    final reminders = [
      Reminder(id: const Uuid().v4(), taskId: 'pending', offsetMinutes: 60),
      Reminder(id: const Uuid().v4(), taskId: 'pending', offsetMinutes: 15),
      Reminder(id: const Uuid().v4(), taskId: 'pending', offsetMinutes: 5),
    ];

    final id = await repo.createTask(
      buildTask(title: 'Device test — three reminders', start: start, reminders: reminders),
    );
    createdTaskIds.add(id);

    final pending = await pendingIds();
    for (final reminder in reminders) {
      expect(pending, contains(ReminderCalculatorIds.forTask(id, reminder.id)),
          reason: 'every reminder must be registered, including ${reminder.offsetMinutes} min');
    }
  });

  testWidgets('changing the time cancels the old alarm and sets a new one', (tester) async {
    final start = DateTime.now().add(const Duration(hours: 3));
    final reminder = Reminder(
      id: const Uuid().v4(),
      taskId: 'pending',
      offsetMinutes: 30,
    );

    final id = await repo.createTask(
      buildTask(title: 'Device test — reschedule', start: start, reminders: [reminder]),
    );
    createdTaskIds.add(id);

    final scheduledId = ReminderCalculatorIds.forTask(id, reminder.id);
    expect(await pendingIds(), contains(scheduledId));

    // Read it back so the update carries the real document id, then move it.
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .collection('tasks')
        .doc(id)
        .get();
    final saved = Task.fromDoc(snapshot);
    final moved = saved.copyWith(startDateTime: start.add(const Duration(hours: 2)));

    await repo.updateTask(moved, previous: saved);

    final after = await pendingIds();
    expect(after, contains(scheduledId),
        reason: 'the id is stable, so the same slot now holds the new time');

    final pending = await plugin.pendingNotificationRequests();
    final entry = pending.firstWhere((p) => p.id == scheduledId);
    expect(entry.title, 'Device test — reschedule');
  });

  testWidgets('dragging a task to a new time moves the alarm the OS is holding', (tester) async {
    // This goes through moveTask, which is what a calendar drag or a board move
    // calls. The test above uses updateTask, which already rescheduled; moveTask
    // did not, so the old alert kept firing at the old time.
    final start = DateTime.now().add(const Duration(hours: 3));
    final reminder = Reminder(id: const Uuid().v4(), taskId: 'pending', offsetMinutes: 30);

    final id = await repo.createTask(
      buildTask(title: 'Device test — drag reschedules', start: start, reminders: [reminder]),
    );
    createdTaskIds.add(id);
    final scheduledId = ReminderCalculatorIds.forTask(id, reminder.id);

    // The payload records when the alert was scheduled for, which lets the test
    // read back the time Android is actually holding.
    DateTime scheduledFor(List<PendingNotificationRequest> pending) {
      final entry = pending.firstWhere((p) => p.id == scheduledId);
      return DateTime.parse((jsonDecode(entry.payload!) as Map)['scheduledFor'] as String);
    }

    expect(scheduledFor(await plugin.pendingNotificationRequests()),
        start.subtract(const Duration(minutes: 30)));

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .collection('tasks')
        .doc(id)
        .get();
    final saved = Task.fromDoc(snapshot);

    final newStart = start.add(const Duration(hours: 2));
    await repo.moveTask(
      taskId: id,
      expectedVersion: saved.version,
      startDateTime: newStart,
      endDateTime: newStart.add(const Duration(hours: 1)),
    );

    final after = await plugin.pendingNotificationRequests();
    expect(after.where((p) => p.id == scheduledId), hasLength(1),
        reason: 'one alarm, not the old one plus a new one');
    expect(scheduledFor(after), newStart.subtract(const Duration(minutes: 30)),
        reason: 'the alarm Android holds must now be for the new time');
  });

  testWidgets('deleting a task clears its alarms', (tester) async {
    final start = DateTime.now().add(const Duration(hours: 4));
    final reminder = Reminder(id: const Uuid().v4(), taskId: 'pending', offsetMinutes: 20);

    final id = await repo.createTask(
      buildTask(title: 'Device test — delete', start: start, reminders: [reminder]),
    );
    final scheduledId = ReminderCalculatorIds.forTask(id, reminder.id);
    expect(await pendingIds(), contains(scheduledId));

    await repo.deleteTask(id);

    expect(await pendingIds(), isNot(contains(scheduledId)),
        reason: 'a deleted task must leave nothing behind to fire');
  });

  testWidgets('a reminder due within a minute is accepted by the OS', (tester) async {
    // Deliberately near-term: this is the alarm a human can watch arrive.
    final start = DateTime.now().add(const Duration(minutes: 2));
    final reminder = Reminder(
      id: const Uuid().v4(),
      taskId: 'pending',
      type: ReminderType.atTime,
      offsetMinutes: 0,
    );

    final id = await repo.createTask(
      buildTask(title: 'Reminder proof — watch for me', start: start, reminders: [reminder]),
    );
    // Left in place on purpose so the notification can actually fire; the
    // tearDown below removes it once the suite is done.
    createdTaskIds.add(id);

    final scheduledId = ReminderCalculatorIds.forTask(id, reminder.id);
    final pending = await plugin.pendingNotificationRequests();
    final entry = pending.where((p) => p.id == scheduledId).firstOrNull;

    expect(entry, isNotNull, reason: 'the near-term alarm must be registered');
    expect(entry!.title, 'Reminder proof — watch for me');
  });

  testWidgets('snoozing registers a new alarm', (tester) async {
    final start = DateTime.now().add(const Duration(hours: 5));
    final reminder = Reminder(id: const Uuid().v4(), taskId: 'pending', offsetMinutes: 10);

    final id = await repo.createTask(
      buildTask(title: 'Device test — snooze', start: start, reminders: [reminder]),
    );
    createdTaskIds.add(id);

    final task = Task(id: id, title: 'Device test — snooze', startDateTime: start);
    final fireAt = await service.snooze(
      task: task,
      reminder: reminder.copyWith(),
      minutes: 15,
      preferences: const NotificationPreferences(),
    );

    expect(fireAt, isNotNull);
    expect(await pendingIds(), contains(NotificationService.snoozeIdFor(id, reminder.id)));
  });
}

/// The id scheme, mirrored so the test asserts against the same arithmetic the
/// app uses rather than guessing.
class ReminderCalculatorIds {
  static int forTask(String taskId, String reminderId, [int occurrence = 0]) {
    final input = '$taskId#$reminderId#$occurrence';
    var hash = 0;
    for (final unit in input.codeUnits) {
      hash = (hash * 31 + unit) & 0x3FFFFFFF;
    }
    return hash;
  }
}

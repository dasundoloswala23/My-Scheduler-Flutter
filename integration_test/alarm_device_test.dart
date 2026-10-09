// Alarm, sound and notification-action behaviour, on a real device.
//
// These ask Android itself what it did, not the app: the channels are read back
// from the OS notification manager, and a due alarm is looked up among the
// notifications Android is actually showing. A pass here means the system
// accepted the configuration, which a unit test cannot say.
//
//   flutter test integration_test/alarm_device_test.dart -d ZL8325W28X
//
// What this cannot do: hear a sound, feel a vibration, or look at a locked
// screen. Those need a person, and are listed as such in
// docs/MOBILE_FINAL_QA_REPORT.md.
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
import 'package:myschedule/core/notifications/platform/background_actions.dart';
import 'package:myschedule/core/notifications/platform/local_notification_adapter.dart';
import 'package:myschedule/core/notifications/scheduling/reminder_calculator.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/firebase_options.dart';
import 'package:myschedule/models/task.dart';

// Credentials come from the command line, never from the repository:
//   --dart-define=MYS_TEST_EMAIL=… --dart-define=MYS_TEST_PASSWORD=…
const email = String.fromEnvironment('MYS_TEST_EMAIL');
const password = String.fromEnvironment('MYS_TEST_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Repo repo;
  late LocalNotificationAdapter adapter;
  late String uid;
  final plugin = FlutterLocalNotificationsPlugin();
  final createdTaskIds = <String>[];

  AndroidFlutterLocalNotificationsPlugin android() => plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()!;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final credential =
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    uid = credential.user!.uid;

    adapter = LocalNotificationAdapter();
    await adapter.initialise();
    await adapter.requestPermission();

    repo = Repo(uid: uid);
    repo.notificationPreferences = const NotificationPreferences();
  });

  tearDownAll(() async {
    for (final id in createdTaskIds) {
      await repo.deleteTask(id);
    }
    await plugin.cancelAll();
  });

  DocumentReference<Map<String, dynamic>> taskDoc(String id) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').doc(id);

  Future<Set<int>> pendingIds() async =>
      (await plugin.pendingNotificationRequests()).map((p) => p.id).toSet();

  PlannedNotification planned({
    required int id,
    required DateTime fireAt,
    AlertMode mode = AlertMode.notification,
    String? sound,
    bool vibrate = true,
    String title = 'Alarm device test',
  }) =>
      PlannedNotification(
        notificationId: id,
        reminderId: 'device-test',
        taskId: 'device-test-task',
        title: title,
        body: 'Starting now',
        fireAt: fireAt,
        style: NotificationStyle.normal,
        alertMode: mode,
        soundId: sound,
        vibrate: vibrate,
      );

  Future<String> createTaskWithReminder(String title, Reminder reminder,
      {Duration startsIn = const Duration(hours: 3)}) async {
    final start = DateTime.now().add(startsIn);
    final id = await repo.createTask(Task(
      id: 'pending',
      title: title,
      description: 'Created by the alarm device test',
      startDateTime: start,
      endDateTime: start.add(const Duration(hours: 1)),
      reminders: [reminder.withTaskId('pending')],
      position: 500000,
    ));
    createdTaskIds.add(id);
    return id;
  }

  group('Android channels carry the configured sound and behaviour', () {
    testWidgets('an alarm gets a max-importance channel on the alarm audio stream',
        (tester) async {
      final far = DateTime.now().add(const Duration(hours: 6));
      await adapter.schedule(
        planned(id: 900001, fireAt: far, mode: AlertMode.alarm, sound: 'urgent'),
        const NotificationPreferences(),
      );

      final channels = await android().getNotificationChannels() ?? [];
      final channel = channels.firstWhere(
        (c) => c.id == 'rem3_alarm_urgent_v',
        orElse: () => throw TestFailure(
            'no alarm channel was created. Channels: ${channels.map((c) => c.id).toList()}'),
      );

      expect(channel.importance, Importance.max);
      expect(channel.playSound, isTrue);
      expect(channel.enableVibration, isTrue);
      expect(channel.audioAttributesUsage, AudioAttributesUsage.alarm,
          reason: 'an alarm must use the alarm stream, so it sounds at alarm volume');
      expect(channel.sound, isA<RawResourceAndroidNotificationSound>());
      expect((channel.sound as RawResourceAndroidNotificationSound).sound, 'urgent');
    });

    testWidgets('a chosen sound is the sound on the notification channel', (tester) async {
      final far = DateTime.now().add(const Duration(hours: 6));
      await adapter.schedule(
        planned(id: 900002, fireAt: far, sound: 'chime'),
        const NotificationPreferences(),
      );

      final channels = await android().getNotificationChannels() ?? [];
      final channel = channels.firstWhere((c) => c.id == 'rem3_normal_chime_v');

      expect(channel.playSound, isTrue);
      expect((channel.sound as RawResourceAndroidNotificationSound).sound, 'chime');
      expect(channel.audioAttributesUsage, AudioAttributesUsage.notification,
          reason: 'a notification is not an alarm');
    });

    testWidgets('different sounds get different channels, so they really differ',
        (tester) async {
      final far = DateTime.now().add(const Duration(hours: 6));
      for (final (i, sound) in ['soft_bell', 'digital', 'alert'].indexed) {
        await adapter.schedule(
          planned(id: 900010 + i, fireAt: far, sound: sound),
          const NotificationPreferences(),
        );
      }
      final channels = await android().getNotificationChannels() ?? [];
      final sounds = {
        for (final c in channels)
          if (c.id.startsWith('rem3_normal_')) c.id: (c.sound as RawResourceAndroidNotificationSound?)?.sound,
      };

      expect(sounds['rem3_normal_soft_bell_v'], 'soft_bell');
      expect(sounds['rem3_normal_digital_v'], 'digital');
      expect(sounds['rem3_normal_alert_v'], 'alert');
    });

    testWidgets('a silent reminder gets a channel that makes no sound', (tester) async {
      final far = DateTime.now().add(const Duration(hours: 6));
      await adapter.schedule(
        planned(id: 900020, fireAt: far, sound: 'silent'),
        const NotificationPreferences(),
      );
      final channels = await android().getNotificationChannels() ?? [];
      final channel = channels.firstWhere((c) => c.id == 'rem3_normal_silent_v');
      expect(channel.playSound, isFalse);
    });

    testWidgets('vibration off gets its own channel without vibration', (tester) async {
      final far = DateTime.now().add(const Duration(hours: 6));
      await adapter.schedule(
        planned(id: 900030, fireAt: far, sound: 'alert', vibrate: false),
        const NotificationPreferences(vibration: VibrationPattern.none),
      );
      final channels = await android().getNotificationChannels() ?? [];
      final channel = channels.firstWhere((c) => c.id == 'rem3_normal_alert_q');
      expect(channel.enableVibration, isFalse);
    });

    testWidgets('all of those alerts are held by the OS', (tester) async {
      final pending = await pendingIds();
      expect(pending, containsAll([900001, 900002, 900010, 900011, 900012, 900020, 900030]));
      await plugin.cancelAll();
    });
  });

  group('an alarm actually arrives', () {
    testWidgets('a due alarm is posted by Android, on its alarm channel, and stays up',
        (tester) async {
      await plugin.cancelAll();
      const id = 900100;
      final fireAt = DateTime.now().add(const Duration(seconds: 40));
      await adapter.schedule(
        planned(
          id: id,
          fireAt: fireAt,
          mode: AlertMode.alarm,
          sound: 'urgent',
          title: 'ALARM-PROOF-7731',
        ),
        const NotificationPreferences(),
      );
      expect(await pendingIds(), contains(id));

      // Wait for Android to deliver it.
      ActiveNotification? posted;
      final deadline = DateTime.now().add(const Duration(seconds: 100));
      while (DateTime.now().isBefore(deadline)) {
        final active = await android().getActiveNotifications();
        posted = active.where((n) => n.id == id).firstOrNull;
        if (posted != null) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }

      expect(posted, isNotNull, reason: 'Android never posted the due alarm');
      expect(posted!.channelId, 'rem3_alarm_urgent_v');
      expect(posted.title, 'ALARM-PROOF-7731');

      // A marker for the outside world: while this is printed the alarm is on
      // screen, so its flags can be read with `adb shell dumpsys notification`.
      // ignore: avoid_print
      print('ALARM_POSTED id=$id');
      await Future<void>.delayed(const Duration(seconds: 25));

      // An alarm is ongoing, so it must still be there rather than having been
      // dismissed on its own.
      final still = await android().getActiveNotifications();
      expect(still.any((n) => n.id == id), isTrue,
          reason: 'an alarm must persist until the user acts on it');

      await plugin.cancel(id: id);
      final gone = await android().getActiveNotifications();
      expect(gone.any((n) => n.id == id), isFalse, reason: 'cancelling must silence it');
    });
  });

  group('lock-screen actions, run through the real background handler', () {
    NotificationResponse action(String taskId, String? actionId, {String reminderId = 'r'}) =>
        NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          id: 1,
          actionId: actionId,
          payload: jsonEncode({'taskId': taskId, 'reminderId': reminderId}),
        );

    testWidgets('Complete marks the task done and cancels its reminders', (tester) async {
      final reminder = Reminder(
        id: const Uuid().v4(),
        taskId: 'pending',
        type: ReminderType.beforeTask,
        offsetMinutes: 30,
        alertMode: AlertMode.alarm,
      );
      final id = await createTaskWithReminder('Device test — complete from notification', reminder);
      final scheduled = ReminderCalculator.notificationIdFor(id, reminder.id);
      expect(await pendingIds(), contains(scheduled));

      final before = (await taskDoc(id).get()).data()!;
      expect(before['completed'], isFalse);
      final versionBefore = before['version'] as num;

      await BackgroundActions.handle(action(id, 'complete', reminderId: reminder.id));

      final after = (await taskDoc(id).get()).data()!;
      expect(after['completed'], isTrue, reason: 'the same Firestore task must be completed');
      expect(after['completedAt'], isNotNull);
      expect(after['version'] as num, greaterThan(versionBefore),
          reason: 'it must bump the version, like any other edit');
      expect(await pendingIds(), isNot(contains(scheduled)),
          reason: 'a completed task must not keep reminding');
    });

    testWidgets('Snooze replaces the alert with one later, without duplicating', (tester) async {
      final reminder = Reminder(
        id: const Uuid().v4(),
        taskId: 'pending',
        type: ReminderType.beforeTask,
        offsetMinutes: 30,
        alertMode: AlertMode.alarm,
        soundId: 'chime',
      );
      final id = await createTaskWithReminder('Device test — snooze from notification', reminder);
      final original = ReminderCalculator.notificationIdFor(id, reminder.id);
      final snoozeId = NotificationService.snoozeIdFor(id, reminder.id);
      expect(await pendingIds(), contains(original));

      await BackgroundActions.handle(action(id, 'snooze', reminderId: reminder.id));

      final pending = await pendingIds();
      expect(pending, contains(snoozeId));
      expect(pending, isNot(contains(original)), reason: 'the original must be replaced');

      // Snoozing again must still leave exactly one.
      await BackgroundActions.handle(action(id, 'snooze', reminderId: reminder.id));
      final count = (await pendingIds()).where((p) => p == snoozeId).length;
      expect(count, 1);

      // The task itself is untouched by a snooze.
      expect((await taskDoc(id).get()).data()!['completed'], isFalse);
    });

    testWidgets('an action for a task that no longer exists does nothing', (tester) async {
      const ghost = 'task-that-was-deleted';
      await BackgroundActions.handle(action(ghost, 'complete'));
      expect((await taskDoc(ghost).get()).exists, isFalse,
          reason: 'it must not create a task out of thin air');
    });

    testWidgets('Open is left to the app, not done in the background', (tester) async {
      final reminder = Reminder(id: const Uuid().v4(), taskId: 'pending', offsetMinutes: 30);
      final id = await createTaskWithReminder('Device test — open', reminder);

      await BackgroundActions.handle(action(id, null));

      expect((await taskDoc(id).get()).data()!['completed'], isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/notifications/models/notification_preferences.dart';
import 'package:myschedule/core/notifications/models/reminder.dart';
import 'package:myschedule/core/notifications/platform/notification_adapter.dart';
import 'package:myschedule/core/notifications/scheduling/reminder_calculator.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/models/task.dart';

/// End-to-end scheduling flows, driven by a fake clock and a fake platform, so
/// the whole lifecycle is asserted in milliseconds rather than real hours.
final kNow = DateTime(2026, 10, 5, 9, 0);

Task task({
  String id = 'task-1',
  DateTime? start,
  bool completed = false,
  Recurrence recurrence = Recurrence.none,
  List<Reminder> reminders = const [],
}) =>
    Task(
      id: id,
      title: 'Company meeting',
      startDateTime: start,
      endDateTime: start?.add(const Duration(hours: 1)),
      completed: completed,
      recurrence: recurrence,
      reminders: reminders,
    );

Reminder before(int minutes, {String? id}) => Reminder(
      id: id ?? 'r-$minutes',
      taskId: 'task-1',
      type: minutes == 0 ? ReminderType.atTime : ReminderType.beforeTask,
      offsetMinutes: minutes,
    );

void main() {
  late FakeClock clock;
  late FakeNotificationAdapter adapter;
  late NotificationService service;

  setUp(() {
    clock = FakeClock(kNow);
    adapter = FakeNotificationAdapter();
    service = NotificationService(adapter: adapter, clock: clock);
  });

  group('FLOW 1 — create a task with reminders', () {
    test('schedules one alert per reminder', () async {
      final reminders = [before(60, id: 'a'), before(15, id: 'b')];
      final subject = task(start: DateTime(2026, 10, 5, 18, 0), reminders: reminders);

      await service.sync(task: subject, reminders: reminders);

      expect(adapter.scheduled, hasLength(2));
      expect(
        adapter.scheduled.values.map((n) => n.fireAt).toSet(),
        {DateTime(2026, 10, 5, 17, 0), DateTime(2026, 10, 5, 17, 45)},
      );
    });

    test('a task with no reminders schedules nothing', () async {
      await service.sync(task: task(start: DateTime(2026, 10, 5, 18, 0)), reminders: const []);
      expect(adapter.scheduled, isEmpty);
    });
  });

  group('FLOW 2 — edit the task time', () {
    test('the old alert is cancelled and only the new one remains', () async {
      final reminders = [before(30)];

      // Meeting at 10:00 → reminder at 09:30.
      final original = task(start: DateTime(2026, 10, 5, 10, 0), reminders: reminders);
      await service.sync(task: original, reminders: reminders);

      final firstId = adapter.scheduled.keys.single;
      expect(adapter.scheduled[firstId]!.fireAt, DateTime(2026, 10, 5, 9, 30));

      // Moved to 14:00 → reminder must now be 13:30, and only that.
      adapter.cancelled.clear();
      final moved = original.copyWith(startDateTime: DateTime(2026, 10, 5, 14, 0));
      await service.sync(task: moved, reminders: reminders, previousReminders: reminders);

      expect(adapter.cancelled, contains(firstId),
          reason: 'the alert for the old time must be cancelled');
      expect(adapter.scheduled, hasLength(1));
      expect(adapter.scheduled.values.single.fireAt, DateTime(2026, 10, 5, 13, 30));
    });

    test('removing a reminder cancels exactly that one', () async {
      final both = [before(60, id: 'keep'), before(15, id: 'drop')];
      final subject = task(start: DateTime(2026, 10, 5, 18, 0), reminders: both);
      await service.sync(task: subject, reminders: both);
      expect(adapter.scheduled, hasLength(2));

      final remaining = [both.first];
      await service.sync(task: subject, reminders: remaining, previousReminders: both);

      expect(adapter.scheduled, hasLength(1));
      expect(adapter.scheduled.values.single.reminderId, 'keep');
    });

    test('changing an offset moves the alert rather than adding one', () async {
      final subject = task(start: DateTime(2026, 10, 5, 18, 0));
      final original = [Reminder(id: 'r1', taskId: 'task-1', offsetMinutes: 15)];
      await service.sync(task: subject, reminders: original);

      final changed = [original.first.copyWith(offsetMinutes: 45)];
      await service.sync(task: subject, reminders: changed, previousReminders: original);

      expect(adapter.scheduled, hasLength(1));
      expect(adapter.scheduled.values.single.fireAt, DateTime(2026, 10, 5, 17, 15));
    });
  });

  group('FLOW 3 — delete the task', () {
    test('every alert belonging to it is cancelled', () async {
      final reminders = [before(60, id: 'a'), before(15, id: 'b'), before(0, id: 'c')];
      final subject = task(start: DateTime(2026, 10, 5, 18, 0), reminders: reminders);
      await service.sync(task: subject, reminders: reminders);
      expect(adapter.scheduled, hasLength(3));

      await service.cancelForTask(subject, reminders);

      expect(adapter.scheduled, isEmpty, reason: 'a deleted task must never fire');
      expect(await adapter.pendingIds(), isEmpty);
    });

    test('deleting one task leaves another task alone', () async {
      final a = task(id: 'task-a', start: DateTime(2026, 10, 5, 18, 0));
      final b = task(id: 'task-b', start: DateTime(2026, 10, 5, 19, 0));
      final ra = [Reminder(id: 'r', taskId: 'task-a', offsetMinutes: 30)];
      final rb = [Reminder(id: 'r', taskId: 'task-b', offsetMinutes: 30)];

      await service.sync(task: a, reminders: ra);
      await service.sync(task: b, reminders: rb);
      expect(adapter.scheduled, hasLength(2));

      await service.cancelForTask(a, ra);

      expect(adapter.scheduled, hasLength(1));
      expect(adapter.scheduled.values.single.taskId, 'task-b');
    });
  });

  group('FLOW 4 — snooze', () {
    test('cancels the original and schedules a new alert', () async {
      final reminders = [before(30)];
      final subject = task(start: DateTime(2026, 10, 5, 10, 0), reminders: reminders);
      await service.sync(task: subject, reminders: reminders);

      final originalId = adapter.scheduled.keys.single;
      final fireAt = await service.snooze(
        task: subject,
        reminder: reminders.single,
        minutes: 10,
      );

      expect(adapter.cancelled, contains(originalId));
      expect(fireAt, kNow.add(const Duration(minutes: 10)));
      expect(adapter.scheduled.values.single.fireAt, kNow.add(const Duration(minutes: 10)));
    });

    test('every snooze duration works', () async {
      final reminder = before(30);
      final subject = task(start: DateTime(2026, 10, 5, 18, 0));

      for (final minutes in [5, 10, 15, 30, 60]) {
        adapter.reset();
        final fireAt = await service.snooze(task: subject, reminder: reminder, minutes: minutes);
        expect(fireAt, kNow.add(Duration(minutes: minutes)));
      }
    });

    test('the snooze id cannot collide with a scheduled occurrence', () async {
      final windowIds = {
        for (var i = 0; i < ReminderCalculator.recurringWindow; i++)
          ReminderCalculator.notificationIdFor('task-1', 'r-30', i),
      };
      expect(windowIds.contains(NotificationService.snoozeIdFor('task-1', 'r-30')), isFalse);
    });
  });

  group('FLOW 5 — completing a task', () {
    test('a completed task schedules nothing', () async {
      final reminders = [before(30)];
      final subject = task(
        start: DateTime(2026, 10, 5, 18, 0),
        completed: true,
        reminders: reminders,
      );

      await service.sync(task: subject, reminders: reminders);
      expect(adapter.scheduled, isEmpty);
    });

    test('un-completing restores its alerts', () async {
      final reminders = [before(30)];
      final done = task(start: DateTime(2026, 10, 5, 18, 0), completed: true);
      await service.sync(task: done, reminders: reminders);
      expect(adapter.scheduled, isEmpty);

      await service.sync(task: done.copyWith(completed: false), reminders: reminders);
      expect(adapter.scheduled, hasLength(1));
    });
  });

  group('FLOW 7 — recurring series', () {
    test('a window of occurrences is scheduled, bounded', () async {
      final reminders = [before(30)];
      final subject = task(
        start: DateTime(2026, 10, 5, 18, 0),
        recurrence: Recurrence.daily,
        reminders: reminders,
      );

      await service.sync(task: subject, reminders: reminders);

      expect(adapter.scheduled, hasLength(ReminderCalculator.recurringWindow));
      expect(adapter.scheduled.length, lessThanOrEqualTo(64),
          reason: 'iOS caps pending notifications at 64');
    });

    test('advancing the series re-schedules cleanly, without piling up', () async {
      final reminders = [before(30)];
      var subject = task(
        start: DateTime(2026, 10, 5, 18, 0),
        recurrence: Recurrence.daily,
        reminders: reminders,
      );
      await service.sync(task: subject, reminders: reminders);
      final firstRun = adapter.scheduled.length;

      // The next occurrence, as completing one would produce.
      subject = subject.copyWith(startDateTime: DateTime(2026, 10, 6, 18, 0));
      await service.sync(task: subject, reminders: reminders, previousReminders: reminders);

      expect(adapter.scheduled, hasLength(firstRun),
          reason: 'the window must be replaced, not appended to');
      expect(adapter.scheduled.values.first.fireAt, DateTime(2026, 10, 6, 17, 30));
    });
  });

  group('daily summary', () {
    test('is scheduled for the next occurrence of its time', () async {
      const prefs = NotificationPreferences(
        dailySummary: true,
        dailySummaryTime: DayTime(8, 0),
      );

      // The clock says 09:00, so 08:00 today has gone; it must be tomorrow.
      final when = await service.scheduleDailySummary(preferences: prefs, taskCount: 6);

      expect(when, DateTime(2026, 10, 6, 8, 0));
      expect(adapter.scheduled[NotificationService.dailySummaryId]!.body, contains('6 tasks'));
    });

    test('later today when the time has not passed', () async {
      const prefs = NotificationPreferences(
        dailySummary: true,
        dailySummaryTime: DayTime(20, 0),
      );
      final when = await service.scheduleDailySummary(preferences: prefs, taskCount: 1);
      expect(when, DateTime(2026, 10, 5, 20, 0));
      expect(adapter.scheduled[NotificationService.dailySummaryId]!.body, contains('1 task'));
    });

    test('is cancelled when switched off', () async {
      await service.scheduleDailySummary(
        preferences: const NotificationPreferences(dailySummary: true),
        taskCount: 3,
      );
      expect(adapter.scheduled.containsKey(NotificationService.dailySummaryId), isTrue);

      final when = await service.scheduleDailySummary(
        preferences: const NotificationPreferences(),
        taskCount: 3,
      );
      expect(when, isNull);
      expect(adapter.scheduled.containsKey(NotificationService.dailySummaryId), isFalse);
    });
  });

  group('offline and platform behaviour', () {
    test('scheduling needs no network — it is entirely local', () async {
      // The fake adapter has no network at all; scheduling still succeeds,
      // which is the property that matters when the device is offline.
      final reminders = [before(15)];
      await service.sync(
        task: task(start: DateTime(2026, 10, 5, 18, 0)),
        reminders: reminders,
      );
      expect(adapter.scheduled, hasLength(1));
    });

    test('a platform that cannot schedule is a no-op, not a crash', () async {
      final unsupported = FakeNotificationAdapter(supportsScheduling: false);
      final web = NotificationService(adapter: unsupported, clock: clock);

      final plan = await web.sync(
        task: task(start: DateTime(2026, 10, 5, 18, 0)),
        reminders: [before(15)],
      );

      expect(plan.scheduled, isEmpty);
      expect(unsupported.scheduled, isEmpty);
    });
  });

  group('legacy documents', () {
    test('a task saved with the old offsets still schedules', () async {
      final legacy = Task(
        id: 'legacy-1',
        title: 'Old task',
        startDateTime: DateTime(2026, 10, 5, 18, 0),
        reminderOffsets: const [15, 60],
      );

      expect(legacy.effectiveReminders, hasLength(2));
      await service.sync(task: legacy, reminders: legacy.effectiveReminders);
      expect(adapter.scheduled, hasLength(2));
    });

    test('the rich list wins when both are present', () {
      final mixed = Task(
        id: 'mixed',
        title: 'Both',
        reminderOffsets: const [5, 10, 15],
        reminders: [before(30)],
      );
      expect(mixed.effectiveReminders, hasLength(1));
      expect(mixed.effectiveReminders.single.offsetMinutes, 30);
    });
  });
}

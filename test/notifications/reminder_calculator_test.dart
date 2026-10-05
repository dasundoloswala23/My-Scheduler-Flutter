import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/notifications/models/notification_preferences.dart';
import 'package:myschedule/core/notifications/models/reminder.dart';
import 'package:myschedule/core/notifications/scheduling/reminder_calculator.dart';
import 'package:myschedule/models/task.dart';

/// 9 AM on a Monday, so weekday recurrence is easy to reason about.
final kNow = DateTime(2026, 10, 5, 9, 0);

Task task({
  String id = 'task-1',
  DateTime? start,
  bool completed = false,
  Recurrence recurrence = Recurrence.none,
  String? categoryId,
}) =>
    Task(
      id: id,
      title: 'Upload Kitty Meow video',
      startDateTime: start,
      endDateTime: start?.add(const Duration(hours: 1)),
      completed: completed,
      recurrence: recurrence,
      categoryId: categoryId,
    );

Reminder before(int minutes, {String? id, bool enabled = true}) => Reminder(
      id: id ?? 'r-$minutes',
      taskId: 'task-1',
      type: minutes == 0 ? ReminderType.atTime : ReminderType.beforeTask,
      offsetMinutes: minutes,
      enabled: enabled,
    );

void main() {
  late FakeClock clock;
  late ReminderCalculator calculator;

  setUp(() {
    clock = FakeClock(kNow);
    calculator = ReminderCalculator(clock: clock);
  });

  group('offset maths', () {
    test('30 minutes before a 10:00 task fires at 09:30', () {
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 10, 0)),
        reminders: [before(30)],
      );

      expect(plan.scheduled, hasLength(1));
      expect(plan.scheduled.single.fireAt, DateTime(2026, 10, 5, 9, 30));
    });

    test('"at time" fires exactly at the start', () {
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 10, 0)),
        reminders: [before(0)],
      );
      expect(plan.scheduled.single.fireAt, DateTime(2026, 10, 5, 10, 0));
    });

    test('every preset lands at the right moment', () {
      // Far enough ahead that even the 2-days-before preset is still future.
      final start = DateTime(2026, 10, 12, 18, 0);
      for (final preset in kReminderPresets) {
        final plan = calculator.plan(task: task(start: start), reminders: [before(preset)]);
        expect(
          plan.scheduled.single.fireAt,
          start.subtract(Duration(minutes: preset)),
          reason: 'preset $preset',
        );
      }
    });

    test('custom offsets in hours and days work', () {
      final start = DateTime(2026, 10, 8, 12, 0);

      final ninety = calculator.plan(task: task(start: start), reminders: [before(90)]);
      expect(ninety.scheduled.single.fireAt, DateTime(2026, 10, 8, 10, 30));

      final twoDays = calculator.plan(task: task(start: start), reminders: [before(2880)]);
      expect(twoDays.scheduled.single.fireAt, DateTime(2026, 10, 6, 12, 0));
    });

    test('a reminder whose moment has passed is skipped, not scheduled', () {
      // Task at 09:15 with a 30-minute reminder would have fired at 08:45,
      // which is before the clock's 09:00.
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 9, 15)),
        reminders: [before(30)],
      );

      expect(plan.scheduled, isEmpty);
      expect(plan.skipped.single.reason, SkipReason.inThePast);
    });

    test('the boundary is strict: a reminder due exactly now does not fire', () {
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 9, 30)),
        reminders: [before(30)], // due at exactly 09:00
      );
      expect(plan.scheduled, isEmpty);

      // One minute earlier on the clock and it is in the future again.
      clock.current = kNow.subtract(const Duration(minutes: 1));
      final later = ReminderCalculator(clock: clock).plan(
        task: task(start: DateTime(2026, 10, 5, 9, 30)),
        reminders: [before(30)],
      );
      expect(later.scheduled, hasLength(1));
    });

    test('a task with no start time schedules nothing', () {
      final plan = calculator.plan(task: task(), reminders: [before(15)]);
      expect(plan.scheduled, isEmpty);
      expect(plan.skipped.single.reason, SkipReason.noStartTime);
    });
  });

  group('multiple reminders', () {
    test('a task can carry several, each with its own moment and id', () {
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 18, 0)),
        reminders: [before(60, id: 'a'), before(15, id: 'b'), before(5, id: 'c'), before(0, id: 'd')],
      );

      expect(plan.scheduled, hasLength(4));
      expect(
        plan.scheduled.map((n) => n.fireAt).toList(),
        [
          DateTime(2026, 10, 5, 17, 0),
          DateTime(2026, 10, 5, 17, 45),
          DateTime(2026, 10, 5, 17, 55),
          DateTime(2026, 10, 5, 18, 0),
        ],
      );
      expect(plan.scheduled.map((n) => n.notificationId).toSet(), hasLength(4));
    });

    test('a disabled reminder is kept but not scheduled', () {
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 18, 0)),
        reminders: [before(60, id: 'on'), before(15, id: 'off', enabled: false)],
      );

      expect(plan.scheduled, hasLength(1));
      expect(plan.scheduled.single.reminderId, 'on');
      expect(plan.skipped.single.reason, SkipReason.disabled);
    });
  });

  group('recurrence', () {
    test('a daily task schedules a bounded window, never unbounded', () {
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 18, 0), recurrence: Recurrence.daily),
        reminders: [before(30)],
      );

      expect(plan.scheduled, hasLength(ReminderCalculator.recurringWindow));
      expect(plan.scheduled.first.fireAt, DateTime(2026, 10, 5, 17, 30));
      expect(plan.scheduled[1].fireAt, DateTime(2026, 10, 6, 17, 30));
    });

    test('weekday recurrence skips the weekend', () {
      // Friday 9 October.
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 9, 18, 0), recurrence: Recurrence.weekdays),
        reminders: [before(0)],
      );

      final days = plan.scheduled.map((n) => n.fireAt.weekday).toList();
      expect(days.contains(DateTime.saturday), isFalse);
      expect(days.contains(DateTime.sunday), isFalse);
    });

    test('each occurrence gets its own notification id', () {
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 18, 0), recurrence: Recurrence.weekly),
        reminders: [before(15)],
      );
      expect(
        plan.scheduled.map((n) => n.notificationId).toSet(),
        hasLength(plan.scheduled.length),
      );
    });
  });

  group('preferences', () {
    final start = DateTime(2026, 10, 5, 18, 0);

    test('the master switch stops everything', () {
      final plan = calculator.plan(
        task: task(start: start),
        reminders: [before(15)],
        preferences: const NotificationPreferences(masterEnabled: false),
      );
      expect(plan.scheduled, isEmpty);
      expect(plan.skipped.single.reason, SkipReason.masterOff);
    });

    test('turning task reminders off stops them', () {
      final plan = calculator.plan(
        task: task(start: start),
        reminders: [before(15)],
        preferences: const NotificationPreferences(taskReminders: false),
      );
      expect(plan.skipped.single.reason, SkipReason.typeOff);
    });

    test('turning early reminders off keeps the at-time one', () {
      final plan = calculator.plan(
        task: task(start: start),
        reminders: [before(0, id: 'at'), before(30, id: 'early')],
        preferences: const NotificationPreferences(earlyReminders: false),
      );
      expect(plan.scheduled.single.reminderId, 'at');
      expect(plan.skipped.single.reminderId, 'early');
    });

    test('a muted category schedules nothing', () {
      final plan = calculator.plan(
        task: task(start: start, categoryId: 'cat-youtube'),
        reminders: [before(15)],
        preferences: const NotificationPreferences(mutedCategoryIds: {'cat-youtube'}),
      );
      expect(plan.skipped.single.reason, SkipReason.categoryMuted);
    });

    test('a different muted category does not affect this task', () {
      final plan = calculator.plan(
        task: task(start: start, categoryId: 'cat-job'),
        reminders: [before(15)],
        preferences: const NotificationPreferences(mutedCategoryIds: {'cat-youtube'}),
      );
      expect(plan.scheduled, hasLength(1));
    });

    test('a completed task stops nagging', () {
      final plan = calculator.plan(
        task: task(start: start, completed: true),
        reminders: [before(15)],
      );
      expect(plan.skipped.single.reason, SkipReason.taskCompleted);
    });
  });

  group('quiet hours', () {
    const quiet = NotificationPreferences(
      quietHoursEnabled: true,
      quietHoursStart: DayTime(22, 0),
      quietHoursEnd: DayTime(7, 0),
    );

    test('a reminder inside the window is suppressed', () {
      // Fires at 23:00, inside 22:00 to 07:00.
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 23, 30)),
        reminders: [before(30)],
        preferences: quiet,
      );
      expect(plan.scheduled, isEmpty);
      expect(plan.skipped.single.reason, SkipReason.quietHours);
    });

    test('a reminder after the window still fires', () {
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 10, 0)),
        reminders: [before(30)],
        preferences: quiet,
      );
      expect(plan.scheduled, hasLength(1));
    });

    test('the window wraps past midnight', () {
      // 03:00 is inside a 22:00 to 07:00 window.
      expect(quiet.isQuietAt(DateTime(2026, 10, 6, 3, 0)), isTrue);
      expect(quiet.isQuietAt(DateTime(2026, 10, 6, 23, 0)), isTrue);
      expect(quiet.isQuietAt(DateTime(2026, 10, 6, 12, 0)), isFalse);
      // Exactly at the end is outside.
      expect(quiet.isQuietAt(DateTime(2026, 10, 6, 7, 0)), isFalse);
    });

    test('a same-day window does not wrap', () {
      const daytime = NotificationPreferences(
        quietHoursEnabled: true,
        quietHoursStart: DayTime(9, 0),
        quietHoursEnd: DayTime(17, 0),
      );
      expect(daytime.isQuietAt(DateTime(2026, 10, 6, 12, 0)), isTrue);
      expect(daytime.isQuietAt(DateTime(2026, 10, 6, 20, 0)), isFalse);
    });

    test('urgent reminders may be allowed through', () {
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 23, 30)),
        reminders: [before(30)],
        preferences: quiet.copyWith(
          style: NotificationStyle.urgent,
          urgentIgnoresQuietHours: true,
        ),
      );
      expect(plan.scheduled, hasLength(1));
    });

    test('urgent reminders are held when the user says so', () {
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 23, 30)),
        reminders: [before(30)],
        preferences: quiet.copyWith(
          style: NotificationStyle.urgent,
          urgentIgnoresQuietHours: false,
        ),
      );
      expect(plan.scheduled, isEmpty);
    });

    test('quiet hours off means nothing is suppressed', () {
      final plan = calculator.plan(
        task: task(start: DateTime(2026, 10, 5, 23, 30)),
        reminders: [before(30)],
        preferences: const NotificationPreferences(),
      );
      expect(plan.scheduled, hasLength(1));
    });
  });

  group('notification ids', () {
    test('are stable for the same task, reminder and occurrence', () {
      expect(
        ReminderCalculator.notificationIdFor('t', 'r', 0),
        ReminderCalculator.notificationIdFor('t', 'r', 0),
      );
    });

    test('differ by task, by reminder and by occurrence', () {
      final ids = {
        ReminderCalculator.notificationIdFor('t1', 'r1', 0),
        ReminderCalculator.notificationIdFor('t2', 'r1', 0),
        ReminderCalculator.notificationIdFor('t1', 'r2', 0),
        ReminderCalculator.notificationIdFor('t1', 'r1', 1),
      };
      expect(ids, hasLength(4));
    });

    test('stay inside the 32-bit range platforms accept', () {
      for (var i = 0; i < 200; i++) {
        final id = ReminderCalculator.notificationIdFor(
          'a-reasonably-long-firestore-document-id-$i',
          'another-uuid-like-reminder-id-$i',
          i % 8,
        );
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThan(1 << 31));
      }
    });

    test('do not collide across a realistic workload', () {
      final ids = <int>{};
      var generated = 0;
      for (var t = 0; t < 120; t++) {
        for (var r = 0; r < 4; r++) {
          for (var o = 0; o < 8; o++) {
            ids.add(ReminderCalculator.notificationIdFor('task-$t', 'rem-$r', o));
            generated++;
          }
        }
      }
      expect(ids, hasLength(generated), reason: 'a collision would silently drop a reminder');
    });
  });

  group('offset labels', () {
    test('read naturally', () {
      expect(describeOffset(0), 'At the time');
      expect(describeOffset(1), '1 minute before');
      expect(describeOffset(45), '45 minutes before');
      expect(describeOffset(60), '1 hour before');
      expect(describeOffset(120), '2 hours before');
      expect(describeOffset(1440), '1 day before');
      expect(describeOffset(2880), '2 days before');
    });

    test('split back into the unit they were entered in', () {
      expect(splitOffset(90), (90, ReminderUnit.minutes));
      expect(splitOffset(120), (2, ReminderUnit.hours));
      expect(splitOffset(2880), (2, ReminderUnit.days));
      expect(splitOffset(0), (0, ReminderUnit.minutes));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/notifications.dart';
import 'package:myschedule/core/reminder_scheduler.dart';

void main() {
  group('Notifications.reminderId', () {
    test('is stable for the same task and offset', () {
      final a = Notifications.reminderId('task-123', 15);
      final b = Notifications.reminderId('task-123', 15);
      expect(a, b, reason: 'a reschedule must replace the same alert');
    });

    test('differs per offset, so several reminders coexist', () {
      final ids = {
        for (final offset in [0, 5, 10, 15, 30, 60, 1440])
          Notifications.reminderId('task-123', offset),
      };
      expect(ids, hasLength(7));
    });

    test('differs per task', () {
      expect(
        Notifications.reminderId('task-a', 15),
        isNot(Notifications.reminderId('task-b', 15)),
      );
    });

    test('stays inside the 32-bit range platforms accept', () {
      for (final offset in [0, 5, 60, 1440, -1]) {
        final id = Notifications.reminderId('some-fairly-long-task-id-0123456789', offset);
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThan(1 << 31));
      }
    });

    test('the snooze slot cannot collide with a preset', () {
      final snoozeId = Notifications.reminderId('task-123', -1);
      final presetIds = ReminderOffset.presets
          .map((p) => Notifications.reminderId('task-123', p.minutes))
          .toSet();
      expect(presetIds.contains(snoozeId), isFalse);
    });
  });

  group('ReminderOffset', () {
    test('offers the documented presets', () {
      expect(
        ReminderOffset.presets.map((p) => p.minutes).toList(),
        [0, 5, 10, 15, 30, 60, 1440],
      );
    });

    test('labels presets by name', () {
      expect(ReminderOffset.labelFor(0), 'At the time');
      expect(ReminderOffset.labelFor(15), '15 minutes before');
      expect(ReminderOffset.labelFor(1440), '1 day before');
    });

    test('labels custom values sensibly', () {
      expect(ReminderOffset.labelFor(90), '90 minutes before');
      expect(ReminderOffset.labelFor(120), '2 hours before');
      expect(ReminderOffset.labelFor(2880), '2 days before');
    });
  });
}

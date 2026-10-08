import '../../../models/task.dart';
import '../models/reminder.dart';

/// Where a reminder falls relative to now, for the Reminders list.
enum ReminderBucket { missed, today, tomorrow, later }

extension ReminderBucketX on ReminderBucket {
  String get label => switch (this) {
        ReminderBucket.missed => 'Missed',
        ReminderBucket.today => 'Today',
        ReminderBucket.tomorrow => 'Tomorrow',
        ReminderBucket.later => 'Later',
      };
}

/// One task reminder, with the moment it fires.
class UpcomingReminder {
  const UpcomingReminder({required this.task, required this.reminder, required this.fireAt});

  final Task task;
  final Reminder reminder;
  final DateTime fireAt;
}

/// How far back a reminder still counts as "missed" rather than just old.
const Duration kMissedWindow = Duration(hours: 24);

/// The reminders on [tasks], grouped for the Reminders screen.
///
/// They are derived from the tasks, never copied: the task is the one record,
/// so a reminder here is always the live one, and moving a task moves its
/// reminders with it.
///
/// Left out: a completed task (it must not nag), a disabled reminder, and a
/// reminder that cannot be placed because the task has no start time. A
/// reminder that fired more than a day ago is dropped rather than listed for
/// ever as missed.
Map<ReminderBucket, List<UpcomingReminder>> groupUpcomingReminders(
  Iterable<Task> tasks,
  DateTime now,
) {
  final result = {for (final b in ReminderBucket.values) b: <UpcomingReminder>[]};
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final dayAfter = tomorrow.add(const Duration(days: 1));

  for (final task in tasks) {
    if (task.completed || task.startDateTime == null) continue;

    for (final reminder in task.effectiveReminders) {
      if (!reminder.enabled) continue;
      final fireAt = reminder.fireTimeFor(task.startDateTime);
      if (fireAt == null) continue;

      final item = UpcomingReminder(task: task, reminder: reminder, fireAt: fireAt);

      if (fireAt.isBefore(now)) {
        if (now.difference(fireAt) <= kMissedWindow) {
          result[ReminderBucket.missed]!.add(item);
        }
      } else if (fireAt.isBefore(tomorrow)) {
        result[ReminderBucket.today]!.add(item);
      } else if (fireAt.isBefore(dayAfter)) {
        result[ReminderBucket.tomorrow]!.add(item);
      } else {
        result[ReminderBucket.later]!.add(item);
      }
    }
  }

  for (final list in result.values) {
    list.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  }
  return result;
}

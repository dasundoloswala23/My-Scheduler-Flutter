import '../models/task.dart';
import 'notifications.dart';

/// The reminder offsets offered in the UI, in minutes before the start time.
class ReminderOffset {
  const ReminderOffset(this.minutes, this.label);

  final int minutes;
  final String label;

  static const atTime = ReminderOffset(0, 'At the time');
  static const presets = [
    atTime,
    ReminderOffset(5, '5 minutes before'),
    ReminderOffset(10, '10 minutes before'),
    ReminderOffset(15, '15 minutes before'),
    ReminderOffset(30, '30 minutes before'),
    ReminderOffset(60, '1 hour before'),
    ReminderOffset(1440, '1 day before'),
  ];

  /// Reads back a stored offset, including custom values that are not presets.
  static String labelFor(int minutes) {
    for (final preset in presets) {
      if (preset.minutes == minutes) return preset.label;
    }
    if (minutes % 1440 == 0) return '${minutes ~/ 1440} days before';
    if (minutes % 60 == 0) return '${minutes ~/ 60} hours before';
    return '$minutes minutes before';
  }
}

/// Keeps a task's scheduled notifications in step with its data.
///
/// Every reminder id is derived from the task id and its offset, so
/// rescheduling replaces a task's own alerts and cannot leave stale ones
/// behind or double up.
class ReminderScheduler {
  const ReminderScheduler();

  /// How far a snooze pushes a reminder.
  static const snooze = Duration(minutes: 10);

  /// Cancels the task's existing reminders and schedules its current set.
  Future<void> sync(Task task) async {
    if (!Notifications.supported) return;
    await cancelFor(task);

    // Nothing to fire without a start time, and a finished task stays quiet.
    if (task.startDateTime == null || task.completed) return;

    for (final offset in task.reminderOffsets) {
      final when = task.startDateTime!.subtract(Duration(minutes: offset));
      if (!when.isAfter(DateTime.now())) continue;

      await Notifications.schedule(
        id: Notifications.reminderId(task.id, offset),
        title: task.title,
        body: offset == 0 ? 'Starting now' : 'Starts in ${ReminderOffset.labelFor(offset).replaceAll(' before', '')}',
        when: when,
        taskId: task.id,
      );
    }
  }

  /// Cancels every reminder belonging to a task, including offsets it no
  /// longer uses, so edits never strand an old alert.
  Future<void> cancelFor(Task task) async {
    if (!Notifications.supported) return;
    final offsets = {
      ...task.reminderOffsets,
      ...ReminderOffset.presets.map((p) => p.minutes),
      if (task.reminderMinutesBefore != null) task.reminderMinutesBefore!,
    };
    for (final offset in offsets) {
      await Notifications.cancel(Notifications.reminderId(task.id, offset));
    }
  }

  /// Fires the task's reminder again a short while from now.
  Future<void> snoozeTask(Task task) async {
    if (!Notifications.supported) return;
    final when = DateTime.now().add(snooze);
    await Notifications.schedule(
      // Offset -1 is reserved for snoozes, so it never clashes with a preset.
      id: Notifications.reminderId(task.id, -1),
      title: task.title,
      body: 'Snoozed reminder',
      when: when,
      taskId: task.id,
    );
  }
}

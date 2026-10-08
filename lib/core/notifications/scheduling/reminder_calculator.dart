import '../../../models/task.dart';
import '../../recurrence.dart';
import '../models/notification_preferences.dart';
import '../models/reminder.dart';

/// Supplies "now". Injecting it is what makes every scheduling rule testable
/// in milliseconds instead of waiting real hours.
abstract class Clock {
  DateTime now();
  const factory Clock.system() = _SystemClock;
}

class _SystemClock implements Clock {
  const _SystemClock();
  @override
  DateTime now() => DateTime.now();
}

/// A clock the tests drive by hand.
class FakeClock implements Clock {
  FakeClock(this.current);

  /// The moment this clock reports. Tests assign to it directly.
  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration by) => current = current.add(by);
}

/// Why a reminder was not scheduled. Useful in tests and in the UI, which can
/// explain the silence rather than leaving the user guessing.
enum SkipReason {
  disabled,
  inThePast,
  noStartTime,
  taskCompleted,
  masterOff,
  typeOff,
  categoryMuted,
  quietHours,
}

/// One alert that should exist on the platform.
class PlannedNotification {
  const PlannedNotification({
    required this.notificationId,
    required this.reminderId,
    required this.taskId,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.style,
    this.alertMode = AlertMode.notification,
    this.soundId,
    this.vibrate = true,
  });

  final int notificationId;
  final String reminderId;
  final String taskId;
  final String title;
  final String body;
  final DateTime fireAt;
  final NotificationStyle style;

  /// Already resolved against the user's settings: an alarm reminder is
  /// [AlertMode.notification] here when alarms are switched off.
  final AlertMode alertMode;

  /// A catalogue id, or null for the default of this mode. The adapter turns
  /// it into whatever the platform can actually play.
  final String? soundId;
  final bool vibrate;

  bool get isAlarm => alertMode == AlertMode.alarm;

  @override
  String toString() => 'PlannedNotification($taskId/$reminderId at $fireAt)';
}

/// One alert that was deliberately not scheduled.
class SkippedNotification {
  const SkippedNotification({required this.reminderId, required this.reason});
  final String reminderId;
  final SkipReason reason;

  @override
  String toString() => 'Skipped($reminderId: ${reason.name})';
}

class SchedulePlan {
  const SchedulePlan({this.scheduled = const [], this.skipped = const []});
  final List<PlannedNotification> scheduled;
  final List<SkippedNotification> skipped;

  bool get isEmpty => scheduled.isEmpty;
}

/// Works out exactly which notifications a task should have.
///
/// This class is pure: it touches no plugin, no Firestore and no platform. It
/// takes a task, its reminders, the user's preferences and a clock, and returns
/// a plan. The adapter then makes reality match the plan.
class ReminderCalculator {
  const ReminderCalculator({this.clock = const Clock.system()});

  final Clock clock;

  /// How many future occurrences of a repeating task to schedule at once.
  ///
  /// Platforms cap pending notifications (iOS allows 64), so a daily task
  /// cannot be scheduled forever. A rolling window is topped up whenever the
  /// app syncs the task.
  static const int recurringWindow = 8;

  SchedulePlan plan({
    required Task task,
    required List<Reminder> reminders,
    NotificationPreferences preferences = const NotificationPreferences(),
  }) {
    final scheduled = <PlannedNotification>[];
    final skipped = <SkippedNotification>[];
    final now = clock.now();

    void skip(Reminder r, SkipReason reason) =>
        skipped.add(SkippedNotification(reminderId: r.id, reason: reason));

    // Whole-app and whole-type switches come first: if these are off, nothing
    // is registered with the OS at all.
    if (!preferences.masterEnabled) {
      for (final r in reminders) {
        skip(r, SkipReason.masterOff);
      }
      return SchedulePlan(skipped: skipped);
    }
    if (!preferences.taskReminders) {
      for (final r in reminders) {
        skip(r, SkipReason.typeOff);
      }
      return SchedulePlan(skipped: skipped);
    }
    if (task.categoryId != null && preferences.mutedCategoryIds.contains(task.categoryId)) {
      for (final r in reminders) {
        skip(r, SkipReason.categoryMuted);
      }
      return SchedulePlan(skipped: skipped);
    }
    if (task.completed) {
      for (final r in reminders) {
        skip(r, SkipReason.taskCompleted);
      }
      return SchedulePlan(skipped: skipped);
    }

    // Repeating tasks get a rolling window of occurrences; everything else has
    // exactly one start time.
    final occurrences = _occurrencesFor(task);

    for (final reminder in reminders) {
      if (!reminder.enabled) {
        skip(reminder, SkipReason.disabled);
        continue;
      }
      if (reminder.offsetMinutes > 0 && !preferences.earlyReminders) {
        skip(reminder, SkipReason.typeOff);
        continue;
      }
      if (reminder.type == ReminderType.recurring && !preferences.recurringTasks) {
        skip(reminder, SkipReason.typeOff);
        continue;
      }

      // An alarm reminder is only an alarm while alarms are switched on.
      // Otherwise it is downgraded to a notification, not dropped, so turning
      // alarms off never silently loses a reminder.
      final mode = reminder.alertMode == AlertMode.alarm && preferences.alarmsEnabled
          ? AlertMode.alarm
          : AlertMode.notification;

      var placedAny = false;
      var lastReason = SkipReason.noStartTime;

      for (var occurrence = 0; occurrence < occurrences.length; occurrence++) {
        final start = occurrences[occurrence];
        final fireAt = reminder.fireTimeFor(start);

        if (fireAt == null) {
          lastReason = SkipReason.noStartTime;
          continue;
        }
        if (!fireAt.isAfter(now)) {
          lastReason = SkipReason.inThePast;
          continue;
        }
        if (_isSuppressedByQuietHours(fireAt, preferences, mode)) {
          lastReason = SkipReason.quietHours;
          continue;
        }

        scheduled.add(PlannedNotification(
          notificationId: notificationIdFor(task.id, reminder.id, occurrence),
          reminderId: reminder.id,
          taskId: task.id,
          title: task.title,
          body: _bodyFor(reminder, start),
          fireAt: fireAt,
          style: preferences.style,
          alertMode: mode,
          soundId: reminder.soundId ??
              (mode == AlertMode.alarm
                  ? preferences.alarmSoundId
                  : preferences.notificationSoundId),
          vibrate: reminder.vibrate ?? preferences.vibration != VibrationPattern.none,
        ));
        placedAny = true;
      }

      if (!placedAny) skip(reminder, lastReason);
    }

    return SchedulePlan(scheduled: scheduled, skipped: skipped);
  }

  /// Start times to schedule for. One for a normal task; a rolling window for
  /// a repeating one, so a daily task never queues thousands of alerts.
  List<DateTime> _occurrencesFor(Task task) {
    final start = task.startDateTime;
    if (start == null) return const [];
    if (task.recurrence == Recurrence.none) return [start];

    final out = <DateTime>[start];
    var cursor = start;
    for (var i = 1; i < recurringWindow; i++) {
      final next = nextOccurrence(cursor, task.recurrence);
      if (next == null) break;
      out.add(next);
      cursor = next;
    }
    return out;
  }

  /// Quiet hours hold back notifications. An alarm gets through only when the
  /// user has explicitly allowed that; the default is that it does not. This is
  /// the app's own rule and never overrides the OS's Do Not Disturb.
  bool _isSuppressedByQuietHours(
    DateTime fireAt,
    NotificationPreferences prefs,
    AlertMode mode,
  ) {
    if (!prefs.quietHoursEnabled) return false;
    if (mode == AlertMode.alarm && prefs.alarmsIgnoreQuietHours) return false;
    if (prefs.style == NotificationStyle.urgent && prefs.urgentIgnoresQuietHours) return false;
    return prefs.isQuietAt(fireAt);
  }

  String _bodyFor(Reminder reminder, DateTime start) {
    if (reminder.type == ReminderType.customTime) return 'Reminder';
    if (reminder.offsetMinutes == 0) return 'Starting now';
    return 'Starts in ${describeOffset(reminder.offsetMinutes).replaceAll(' before', '')}';
  }

  /// A stable platform id for one task, reminder and occurrence.
  ///
  /// Deterministic so a reschedule replaces the same alert instead of stacking
  /// another one, and distinct per occurrence so a repeating task's window does
  /// not collapse onto a single id.
  static int notificationIdFor(String taskId, String reminderId, [int occurrence = 0]) {
    final input = '$taskId#$reminderId#$occurrence';
    var hash = 0;
    for (final unit in input.codeUnits) {
      hash = (hash * 31 + unit) & 0x3FFFFFFF;
    }
    return hash;
  }
}

import '../../../models/task.dart';
import '../models/notification_preferences.dart';
import '../models/reminder.dart';
import '../platform/notification_adapter.dart';
import '../scheduling/reminder_calculator.dart';

/// Makes the platform match what the calculator says a task should have.
///
/// Scheduling is always "cancel then schedule": every id a task could own is
/// cleared first, so an edit can never leave a stale alert behind. That is the
/// single most visible notification bug, and this is where it is prevented.
class NotificationService {
  NotificationService({
    required this.adapter,
    this.clock = const Clock.system(),
  });

  final NotificationAdapter adapter;
  final Clock clock;

  ReminderCalculator get _calculator => ReminderCalculator(clock: clock);

  /// Every id a task could have used, across all its reminders and the whole
  /// recurring window. Cancelling this set is what makes rescheduling exact
  /// even when a reminder was deleted or its offset changed.
  Set<int> idsOwnedBy(Task task, List<Reminder> reminders) {
    final ids = <int>{};
    for (final reminder in reminders) {
      for (var occurrence = 0; occurrence < ReminderCalculator.recurringWindow; occurrence++) {
        ids.add(ReminderCalculator.notificationIdFor(task.id, reminder.id, occurrence));
      }
      // The snooze slot for this reminder.
      ids.add(snoozeIdFor(task.id, reminder.id));
    }
    return ids;
  }

  /// Brings the platform in line with the task's current reminders.
  /// Returns the plan that was applied, which the tests assert against.
  Future<SchedulePlan> sync({
    required Task task,
    required List<Reminder> reminders,
    NotificationPreferences preferences = const NotificationPreferences(),
    List<Reminder> previousReminders = const [],
  }) async {
    if (!adapter.supportsScheduling) return const SchedulePlan();

    // Clear both the current and the previous sets, so a reminder that was
    // just deleted cannot survive.
    final toCancel = {
      ...idsOwnedBy(task, reminders),
      ...idsOwnedBy(task, previousReminders),
    };
    for (final id in toCancel) {
      await adapter.cancel(id);
    }

    final plan = _calculator.plan(task: task, reminders: reminders, preferences: preferences);
    for (final notification in plan.scheduled) {
      await adapter.schedule(notification, preferences);
    }
    return plan;
  }

  /// Cancels everything belonging to a task. Called before the task is deleted
  /// so nothing is left to fire for something that no longer exists.
  Future<void> cancelForTask(Task task, List<Reminder> reminders) async {
    if (!adapter.supportsScheduling) return;
    for (final id in idsOwnedBy(task, reminders)) {
      await adapter.cancel(id);
    }
  }

  /// Cancels one reminder's alerts, leaving the task's others alone.
  Future<void> cancelReminder(String taskId, Reminder reminder) async {
    if (!adapter.supportsScheduling) return;
    for (var occurrence = 0; occurrence < ReminderCalculator.recurringWindow; occurrence++) {
      await adapter.cancel(ReminderCalculator.notificationIdFor(taskId, reminder.id, occurrence));
    }
    await adapter.cancel(snoozeIdFor(taskId, reminder.id));
  }

  /// Re-fires a reminder after [minutes]. The original alert is cancelled so a
  /// snooze replaces it rather than doubling it up.
  Future<DateTime?> snooze({
    required Task task,
    required Reminder reminder,
    required int minutes,
    NotificationPreferences preferences = const NotificationPreferences(),
  }) async {
    if (!adapter.supportsScheduling) return null;

    await cancelReminder(task.id, reminder);
    final fireAt = clock.now().add(Duration(minutes: minutes));

    await adapter.schedule(
      PlannedNotification(
        notificationId: snoozeIdFor(task.id, reminder.id),
        reminderId: reminder.id,
        taskId: task.id,
        title: task.title,
        body: 'Snoozed reminder',
        fireAt: fireAt,
        style: preferences.style,
      ),
      preferences,
    );
    return fireAt;
  }

  /// Schedules the opt-in daily summary for the next occurrence of its time.
  Future<DateTime?> scheduleDailySummary({
    required NotificationPreferences preferences,
    required int taskCount,
  }) async {
    if (!adapter.supportsScheduling) return null;
    if (!preferences.masterEnabled || !preferences.dailySummary) {
      await adapter.cancel(dailySummaryId);
      return null;
    }

    final now = clock.now();
    var next = DateTime(
      now.year,
      now.month,
      now.day,
      preferences.dailySummaryTime.hour,
      preferences.dailySummaryTime.minute,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));

    await adapter.cancel(dailySummaryId);
    await adapter.schedule(
      PlannedNotification(
        notificationId: dailySummaryId,
        reminderId: 'daily-summary',
        taskId: '',
        title: 'Good morning',
        body: taskCount == 0
            ? 'Nothing scheduled today.'
            : 'You have $taskCount ${taskCount == 1 ? 'task' : 'tasks'} today.',
        fireAt: next,
        style: preferences.style,
      ),
      preferences,
    );
    return next;
  }

  /// A fixed id, since there is only ever one daily summary.
  static const int dailySummaryId = 777000001;

  /// Snooze ids are derived from a reserved occurrence index that the normal
  /// window never reaches, so a snooze cannot collide with a scheduled alert.
  static int snoozeIdFor(String taskId, String reminderId) =>
      ReminderCalculator.notificationIdFor(taskId, reminderId, 9999);
}

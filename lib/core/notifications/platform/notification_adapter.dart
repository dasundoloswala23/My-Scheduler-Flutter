import '../models/notification_preferences.dart';
import '../scheduling/reminder_calculator.dart';

/// What the user chose on a notification.
enum NotificationAction { open, complete, snooze }

/// A notification the user acted on.
class NotificationEvent {
  const NotificationEvent({
    required this.action,
    required this.taskId,
    this.reminderId,
    this.snoozeMinutes,
    this.notificationId,
  });

  final NotificationAction action;
  final String taskId;
  final String? reminderId;
  final int? snoozeMinutes;

  /// The platform id of the notification that was tapped. An alarm stays on
  /// screen until dismissed, so acting on it has to be able to clear it.
  final int? notificationId;
}

/// The boundary between scheduling logic and the operating system.
///
/// Everything above this interface is pure Dart and fully testable; everything
/// below it is platform plumbing. Tests use [FakeNotificationAdapter] and never
/// touch the plugin.
abstract class NotificationAdapter {
  Future<void> initialise();

  /// True when the OS will actually deliver notifications.
  Future<bool> hasPermission();

  /// Asks the OS. Only call this after telling the user why.
  Future<bool> requestPermission();

  /// Registers one alert.
  Future<void> schedule(PlannedNotification notification, NotificationPreferences preferences);

  /// Removes one alert by its platform id.
  Future<void> cancel(int notificationId);

  /// Removes every alert this app scheduled.
  Future<void> cancelAll();

  /// Ids currently registered with the OS.
  Future<Set<int>> pendingIds();

  /// Shows something immediately, used by the daily summary and by tests.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  /// Whether this platform can show action buttons.
  bool get supportsActions;

  /// Whether this platform can schedule anything at all.
  bool get supportsScheduling;
}

/// An adapter that records calls instead of talking to an OS.
///
/// This is what makes the notification suite deterministic: a test can assert
/// exactly which ids were scheduled and cancelled, with no waiting.
class FakeNotificationAdapter implements NotificationAdapter {
  FakeNotificationAdapter({
    this.permissionGranted = true,
    this.supportsActions = true,
    this.supportsScheduling = true,
  });

  bool permissionGranted;
  @override
  final bool supportsActions;
  @override
  final bool supportsScheduling;

  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];
  final List<String> shownNow = [];
  bool initialised = false;
  int permissionRequests = 0;

  @override
  Future<void> initialise() async => initialised = true;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> schedule(PlannedNotification n, NotificationPreferences p) async {
    scheduled[n.notificationId] = n;
  }

  @override
  Future<void> cancel(int notificationId) async {
    cancelled.add(notificationId);
    scheduled.remove(notificationId);
  }

  @override
  Future<void> cancelAll() async {
    cancelled.addAll(scheduled.keys);
    scheduled.clear();
  }

  @override
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    shownNow.add(title);
  }

  void reset() {
    scheduled.clear();
    cancelled.clear();
    shownNow.clear();
    permissionRequests = 0;
  }
}

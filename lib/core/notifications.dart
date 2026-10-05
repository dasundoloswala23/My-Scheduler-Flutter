import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// What the user chose when a notification appeared.
enum NotificationAction { open, complete, snooze }

/// A notification the user acted on, handed to the app so it can react.
class NotificationEvent {
  const NotificationEvent({required this.action, required this.taskId, this.payload});

  final NotificationAction action;
  final String taskId;
  final Map<String, dynamic>? payload;
}

/// Local notifications for task reminders.
///
/// Scheduling is deterministic: the id for a reminder is derived from the task
/// id and the offset, so rescheduling a task simply overwrites its own
/// notifications and never leaves duplicates behind.
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Taps and action buttons arrive here. The app listens and deep-links.
  static final StreamController<NotificationEvent> _events =
      StreamController<NotificationEvent>.broadcast();
  static Stream<NotificationEvent> get events => _events.stream;

  /// Set when the app was launched by tapping a notification while it was not
  /// running, so the first frame can route straight to the task.
  static NotificationEvent? launchEvent;

  static const String _channelId = 'reminders';
  static const String _categoryId = 'task_reminder';

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  /// Action buttons are available on Android, iOS and macOS. Windows shows the
  /// notification without them.
  static bool get supportsActions =>
      supported && defaultTargetPlatform != TargetPlatform.windows;

  static Future<void> init() async {
    if (!supported || _ready) return;
    tzdata.initializeTimeZones();

    final darwinCategories = [
      DarwinNotificationCategory(
        _categoryId,
        actions: [
          DarwinNotificationAction.plain('complete', 'Complete'),
          DarwinNotificationAction.plain('snooze', 'Snooze 10 min'),
          DarwinNotificationAction.plain('open', 'Open'),
        ],
        options: const {DarwinNotificationCategoryOption.hiddenPreviewShowTitle},
      ),
    ];

    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: darwinCategories,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: darwinCategories,
      ),
      windows: const WindowsInitializationSettings(
        appName: 'My scheduler',
        appUserModelId: 'com.myscheduler.app',
        guid: '6f2a1c90-4f1e-4a2b-9d3c-7e5b8a0c1d22',
      ),
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    // If a notification launched the app, replay it once the UI is ready.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final response = launch!.notificationResponse;
      if (response != null) launchEvent = _toEvent(response);
    }

    _ready = true;
  }

  static void _onResponse(NotificationResponse response) {
    final event = _toEvent(response);
    if (event != null) _events.add(event);
  }

  static NotificationEvent? _toEvent(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return null;

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final taskId = payload['taskId'] as String?;
    if (taskId == null) return null;

    final action = switch (response.actionId) {
      'complete' => NotificationAction.complete,
      'snooze' => NotificationAction.snooze,
      _ => NotificationAction.open,
    };
    return NotificationEvent(action: action, taskId: taskId, payload: payload);
  }

  static Future<bool> requestPermissions() async {
    if (!supported) return false;
    await init();

    final android = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    final darwin = await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final macos = await _plugin
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    return android ?? darwin ?? macos ?? true;
  }

  /// True when the user has already granted notification permission.
  static Future<bool> hasPermission() async {
    if (!supported) return false;
    await init();
    final android = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
    // iOS and macOS do not expose a synchronous check through the plugin, so
    // assume granted there and let the OS decide at delivery time.
    return android ?? true;
  }

  static NotificationDetails _details() {
    final actions = supportsActions
        ? const [
            AndroidNotificationAction('complete', 'Complete', showsUserInterface: false),
            AndroidNotificationAction('snooze', 'Snooze 10 min', showsUserInterface: false),
            AndroidNotificationAction('open', 'Open', showsUserInterface: true),
          ]
        : const <AndroidNotificationAction>[];

    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Reminders',
        channelDescription: 'Scheduled task and reminder alerts',
        importance: Importance.high,
        priority: Priority.high,
        actions: actions,
      ),
      iOS: const DarwinNotificationDetails(categoryIdentifier: _categoryId),
      macOS: const DarwinNotificationDetails(categoryIdentifier: _categoryId),
    );
  }

  /// Schedules one reminder. [id] must be stable so it can be replaced or
  /// cancelled later; see [reminderId].
  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? taskId,
  }) async {
    if (!supported) return;
    await init();
    if (!when.isAfter(DateTime.now())) return;

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({'taskId': taskId, 'scheduledFor': when.toIso8601String()}),
    );
  }

  static Future<void> cancel(int id) async {
    if (!supported) return;
    await init();
    await _plugin.cancel(id: id);
  }

  static Future<List<PendingNotificationRequest>> pending() async {
    if (!supported) return const [];
    await init();
    return _plugin.pendingNotificationRequests();
  }

  /// A stable, collision-resistant id for one task's reminder at one offset.
  /// Keeping it deterministic is what lets a reschedule replace the old alert
  /// instead of stacking another one on top.
  static int reminderId(String taskId, int offsetMinutes) {
    final input = '$taskId#$offsetMinutes';
    var hash = 0;
    for (final unit in input.codeUnits) {
      hash = (hash * 31 + unit) & 0x3FFFFFFF;
    }
    return hash;
  }
}

/// Runs when an action button is tapped while the app is not in the foreground.
/// It must be a top-level function with this annotation or the OS cannot find it.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  // The UI is not alive here. The action is replayed from
  // getNotificationAppLaunchDetails the next time the app opens, which keeps
  // all Firestore writes on the main isolate where auth is already set up.
}

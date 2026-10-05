import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/notification_preferences.dart';
import '../scheduling/reminder_calculator.dart';
import 'notification_adapter.dart';

/// The real adapter, backed by flutter_local_notifications.
///
/// All platform quirks live here and nowhere else, so the scheduling rules
/// above stay testable.
class LocalNotificationAdapter implements NotificationAdapter {
  LocalNotificationAdapter({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const String categoryId = 'task_reminder';

  /// Taps and action buttons. The app listens and routes.
  static final StreamController<NotificationEvent> _events =
      StreamController<NotificationEvent>.broadcast();
  static Stream<NotificationEvent> get events => _events.stream;

  /// Set when a notification launched the app from cold, so the first frame
  /// can deep-link instead of dropping the tap.
  static NotificationEvent? launchEvent;

  @override
  bool get supportsScheduling =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  /// Windows toasts from this plugin carry no action buttons.
  @override
  bool get supportsActions =>
      supportsScheduling && defaultTargetPlatform != TargetPlatform.windows;

  @override
  Future<void> initialise() async {
    if (!supportsScheduling || _ready) return;
    tzdata.initializeTimeZones();

    final darwinCategories = [
      DarwinNotificationCategory(
        categoryId,
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
        appUserModelId: 'com.myplanscheduler.app',
        guid: '6f2a1c90-4f1e-4a2b-9d3c-7e5b8a0c1d22',
      ),
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    await _createAndroidChannels();

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final response = launch!.notificationResponse;
      if (response != null) launchEvent = _toEvent(response);
    }

    _ready = true;
  }

  /// One channel per style. A channel's importance is fixed once created, which
  /// is exactly why each style needs its own.
  Future<void> _createAndroidChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    for (final style in NotificationStyle.values) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          style.channelId,
          style.channelName,
          description: switch (style) {
            NotificationStyle.normal => 'Everyday task reminders',
            NotificationStyle.important => 'Reminders you asked to stand out',
            NotificationStyle.urgent => 'Reminders that should interrupt you',
          },
          importance: switch (style) {
            NotificationStyle.normal => Importance.defaultImportance,
            NotificationStyle.important => Importance.high,
            NotificationStyle.urgent => Importance.max,
          },
        ),
      );
    }
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

    return NotificationEvent(
      action: switch (response.actionId) {
        'complete' => NotificationAction.complete,
        'snooze' => NotificationAction.snooze,
        _ => NotificationAction.open,
      },
      taskId: taskId,
      reminderId: payload['reminderId'] as String?,
      snoozeMinutes: (payload['snoozeMinutes'] as num?)?.toInt(),
    );
  }

  @override
  Future<bool> hasPermission() async {
    if (!supportsScheduling) return false;
    await initialise();
    final android = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
    // iOS and macOS expose no synchronous check through the plugin, so assume
    // granted and let the OS decide at delivery time.
    return android ?? true;
  }

  @override
  Future<bool> requestPermission() async {
    if (!supportsScheduling) return false;
    await initialise();

    final android = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final macos = await _plugin
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    return android ?? ios ?? macos ?? true;
  }

  /// Asks Android for permission to schedule exact alarms. Without it the OS
  /// may delay an alert under Doze; the app degrades rather than failing.
  Future<bool> requestExactAlarmPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return true;
    await initialise();
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestExactAlarmsPermission();
    return granted ?? false;
  }

  @override
  Future<void> schedule(PlannedNotification n, NotificationPreferences prefs) async {
    if (!supportsScheduling) return;
    await initialise();

    await _plugin.zonedSchedule(
      id: n.notificationId,
      title: n.title,
      body: n.body,
      scheduledDate: tz.TZDateTime.from(n.fireAt, tz.local),
      notificationDetails: _details(prefs),
      // Inexact is used deliberately: it needs no special permission and the
      // OS still delivers within a short window. Exact alarms are requested
      // separately and only if the user opts in.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({
        'taskId': n.taskId,
        'reminderId': n.reminderId,
        'scheduledFor': n.fireAt.toIso8601String(),
      }),
    );
  }

  NotificationDetails _details(NotificationPreferences prefs) {
    final actions = supportsActions
        ? const [
            AndroidNotificationAction('complete', 'Complete', showsUserInterface: false),
            AndroidNotificationAction('snooze', 'Snooze', showsUserInterface: false),
            AndroidNotificationAction('open', 'Open', showsUserInterface: true),
          ]
        : const <AndroidNotificationAction>[];

    final silent = prefs.sound != NotificationSound.defaultSound;
    final vibrate = prefs.vibration != VibrationPattern.none &&
        prefs.sound != NotificationSound.silent;
    final pattern = prefs.vibration.pattern;

    return NotificationDetails(
      android: AndroidNotificationDetails(
        prefs.style.channelId,
        prefs.style.channelName,
        channelDescription: 'Scheduled task and reminder alerts',
        importance: switch (prefs.style) {
          NotificationStyle.normal => Importance.defaultImportance,
          NotificationStyle.important => Importance.high,
          NotificationStyle.urgent => Importance.max,
        },
        priority: switch (prefs.style) {
          NotificationStyle.normal => Priority.defaultPriority,
          NotificationStyle.important => Priority.high,
          NotificationStyle.urgent => Priority.max,
        },
        playSound: prefs.sound == NotificationSound.defaultSound,
        enableVibration: vibrate,
        vibrationPattern: pattern == null ? null : Int64List.fromList(pattern),
        actions: actions,
      ),
      iOS: DarwinNotificationDetails(
        categoryIdentifier: categoryId,
        presentSound: !silent,
        interruptionLevel: switch (prefs.style) {
          NotificationStyle.urgent => InterruptionLevel.timeSensitive,
          _ => InterruptionLevel.active,
        },
      ),
      macOS: DarwinNotificationDetails(
        categoryIdentifier: categoryId,
        presentSound: !silent,
      ),
    );
  }

  @override
  Future<void> cancel(int notificationId) async {
    if (!supportsScheduling) return;
    await initialise();
    await _plugin.cancel(id: notificationId);
  }

  @override
  Future<void> cancelAll() async {
    if (!supportsScheduling) return;
    await initialise();
    await _plugin.cancelAll();
  }

  @override
  Future<Set<int>> pendingIds() async {
    if (!supportsScheduling) return {};
    await initialise();
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((p) => p.id).toSet();
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!supportsScheduling) return;
    await initialise();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details(const NotificationPreferences()),
      payload: payload,
    );
  }
}

/// Runs when an action is tapped while the app is not in the foreground.
/// Must be top-level and annotated or the OS cannot find it.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  // No UI and no authenticated Firestore in this isolate. The action is
  // replayed from getNotificationAppLaunchDetails on next launch, which keeps
  // every write on the main isolate where auth already exists.
}

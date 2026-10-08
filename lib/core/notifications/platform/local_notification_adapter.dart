import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/notification_preferences.dart';
import '../models/reminder_sound.dart';
import '../scheduling/reminder_calculator.dart';
import 'background_actions.dart';
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

  /// Whether Android will let this app set exact alarms. Cached because it is
  /// a platform channel call and scheduling happens in loops.
  bool? _canScheduleExact;

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
          DarwinNotificationAction.plain('snooze', 'Snooze'),
          DarwinNotificationAction.plain('open', 'Open',
              options: {DarwinNotificationActionOption.foreground}),
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
        appName: 'My Scheduler App',
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
      if (response != null) launchEvent = eventFromResponse(response);
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
    final event = eventFromResponse(response);
    if (event != null) _events.add(event);
  }

  /// Turns a raw platform response into an event, or null if it is not ours.
  /// Public because the background isolate parses responses the same way.
  static NotificationEvent? eventFromResponse(NotificationResponse response) {
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
      notificationId: response.id,
    );
  }

  @override
  Future<bool> hasPermission() async {
    if (!supportsScheduling) return false;
    await initialise();
    final android = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
    if (android != null) return android;
    // Asks iOS/macOS for the current authorisation without prompting, so a
    // denial made in Settings is noticed and explained.
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.checkPermissions();
    final macos = await _plugin
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
        ?.checkPermissions();
    return (ios ?? macos)?.isEnabled ?? true;
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
      notificationDetails: await _detailsFor(n, prefs),
      // A reminder is only useful at the minute it was set for, so use an
      // exact alarm whenever the OS allows one. Inexact alarms are batched and
      // can arrive minutes late, which was observed on a real device. The app
      // declares USE_EXACT_ALARM, which Android grants to alarm-driven apps at
      // install; where that is unavailable this falls back to inexact rather
      // than failing to schedule at all.
      androidScheduleMode: await _scheduleMode(),
      payload: jsonEncode({
        'taskId': n.taskId,
        'reminderId': n.reminderId,
        'scheduledFor': n.fireAt.toIso8601String(),
      }),
    );
  }

  /// Exact when permitted, inexact otherwise.
  Future<AndroidScheduleMode> _scheduleMode() async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    _canScheduleExact ??= await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.canScheduleExactNotifications() ??
        false;
    return _canScheduleExact!
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Channel ids already created this run, so each is created once.
  final Set<String> _channels = {};

  /// The platform behaviour for one planned notification.
  ///
  /// Android fixes a channel's sound, vibration and importance when it is
  /// created and ignores later changes, so each distinct combination gets its
  /// own channel, created on first use. That is why a different sound on a
  /// different reminder genuinely sounds different, instead of every reminder
  /// sharing whichever channel happened to be created first.
  Future<NotificationDetails> _detailsFor(
    PlannedNotification n,
    NotificationPreferences prefs,
  ) async {
    final alarm = n.isAlarm;

    // The legacy global switches still apply on top: a user who chose Silent
    // or Vibrate only in settings gets exactly that.
    final globallyMuted = prefs.sound != NotificationSound.defaultSound;
    final soundId = globallyMuted
        ? kSilentSoundId
        : ReminderSounds.resolve(n.soundId ?? ReminderSounds.defaultFor(n.alertMode));
    final silent = soundId == kSilentSoundId;
    final vibrate = (n.vibrate && prefs.vibration != VibrationPattern.none) ||
        prefs.sound == NotificationSound.vibrateOnly;
    final bundled = ReminderSounds.byId(soundId);

    final pattern = alarm
        ? Int64List.fromList(const [0, 800, 400, 800, 400, 800])
        : (prefs.vibration.pattern == null
            ? null
            : Int64List.fromList(prefs.vibration.pattern!));

    final importance = alarm
        ? Importance.max
        : switch (n.style) {
            NotificationStyle.normal => Importance.defaultImportance,
            NotificationStyle.important => Importance.high,
            NotificationStyle.urgent => Importance.max,
          };

    final channelId =
        'rem3_${alarm ? 'alarm' : n.style.name}_${silent ? 'silent' : soundId}_${vibrate ? 'v' : 'q'}';
    final channelName = alarm ? 'Alarms' : n.style.channelName;
    final sound =
        bundled == null ? null : RawResourceAndroidNotificationSound(bundled.androidRawName);

    await _ensureChannel(
      AndroidNotificationChannel(
        channelId,
        '$channelName · ${ReminderSounds.labelFor(soundId)}${vibrate ? '' : ' · no vibration'}',
        description: alarm
            ? 'Reminders you set to alarm. They repeat until you deal with them.'
            : 'Task reminders',
        importance: importance,
        playSound: !silent,
        sound: sound,
        enableVibration: vibrate,
        vibrationPattern: vibrate ? pattern : null,
        audioAttributesUsage:
            alarm ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
      ),
    );

    final actions = supportsActions
        ? [
            const AndroidNotificationAction('complete', 'Complete', showsUserInterface: false),
            AndroidNotificationAction('snooze', 'Snooze ${prefs.snoozeMinutes} min',
                showsUserInterface: false),
            const AndroidNotificationAction('open', 'Open', showsUserInterface: true),
          ]
        : const <AndroidNotificationAction>[];

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Scheduled task and reminder alerts',
        importance: importance,
        priority: alarm || n.style == NotificationStyle.urgent
            ? Priority.max
            : n.style == NotificationStyle.important
                ? Priority.high
                : Priority.defaultPriority,
        playSound: !silent,
        sound: sound,
        enableVibration: vibrate,
        vibrationPattern: vibrate ? pattern : null,
        audioAttributesUsage:
            alarm ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
        actions: actions,
        // The lock screen: public shows the task, private shows only that a
        // notification exists. The user chooses in settings.
        visibility: prefs.showContentOnLockScreen
            ? NotificationVisibility.public
            : NotificationVisibility.private,
        // What makes an alarm an alarm rather than a louder notification: the
        // alarm category, a full-screen intent (shown over the lock screen where
        // Android allows it), a sound that repeats until handled (the insistent
        // flag, value 4), and a notification that cannot be swiped away by
        // accident.
        category: alarm ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
        fullScreenIntent: alarm,
        ongoing: alarm,
        autoCancel: !alarm,
        additionalFlags: alarm ? Int32List.fromList(const [4]) : null,
      ),
      iOS: _darwin(n, silent, prefs),
      macOS: DarwinNotificationDetails(
        categoryIdentifier: categoryId,
        presentSound: !silent,
        presentBadge: prefs.badge,
      ),
    );
  }

  /// iOS cannot play a bundled custom sound here (see ReminderSounds), and has
  /// no unrestricted alarm: the strongest it permits a local notification is a
  /// time-sensitive one, which can break through Focus modes. That is what an
  /// alarm maps to on iOS, and the settings screen says so.
  DarwinNotificationDetails _darwin(
    PlannedNotification n,
    bool silent,
    NotificationPreferences prefs,
  ) =>
      DarwinNotificationDetails(
        categoryIdentifier: categoryId,
        presentSound: !silent,
        presentBadge: prefs.badge,
        interruptionLevel: n.isAlarm || n.style == NotificationStyle.urgent
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      );

  Future<void> _ensureChannel(AndroidNotificationChannel channel) async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return;
    if (!_channels.add(channel.id)) return;
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Asks Android to let alarms take over the screen. Android 14 made this a
  /// permission the user grants, and without it an alarm still sounds but shows
  /// as an ordinary heads-up notification.
  Future<bool> requestFullScreenIntentPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return true;
    await initialise();
    return await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestFullScreenIntentPermission() ??
        false;
  }

  /// Used for immediate notifications such as the daily summary, which carry no
  /// per-reminder settings.
  NotificationDetails _details(NotificationPreferences prefs) {
    final silent = prefs.sound != NotificationSound.defaultSound;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        prefs.style.channelId,
        prefs.style.channelName,
        channelDescription: 'Scheduled task and reminder alerts',
      ),
      iOS: DarwinNotificationDetails(categoryIdentifier: categoryId, presentSound: !silent),
      macOS: DarwinNotificationDetails(categoryIdentifier: categoryId, presentSound: !silent),
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
Future<void> notificationBackgroundHandler(NotificationResponse response) =>
    BackgroundActions.handle(response);

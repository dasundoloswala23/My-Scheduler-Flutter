/// How loudly a reminder should arrive. Maps to an Android channel and an
/// iOS/macOS interruption level.
enum NotificationStyle { normal, important, urgent }

extension NotificationStyleX on NotificationStyle {
  String get label => switch (this) {
        NotificationStyle.normal => 'Normal',
        NotificationStyle.important => 'Important',
        NotificationStyle.urgent => 'Urgent',
      };

  /// Android channel id. One channel per style, because a channel's importance
  /// cannot be changed after it is created.
  String get channelId => switch (this) {
        NotificationStyle.normal => 'reminders_normal',
        NotificationStyle.important => 'reminders_important',
        NotificationStyle.urgent => 'reminders_urgent',
      };

  String get channelName => switch (this) {
        NotificationStyle.normal => 'Reminders',
        NotificationStyle.important => 'Important reminders',
        NotificationStyle.urgent => 'Urgent reminders',
      };
}

enum NotificationSound { defaultSound, silent, vibrateOnly }

extension NotificationSoundX on NotificationSound {
  String get label => switch (this) {
        NotificationSound.defaultSound => 'Default',
        NotificationSound.silent => 'Silent',
        NotificationSound.vibrateOnly => 'Vibrate only',
      };
}

enum VibrationPattern { none, short, defaultPattern, long }

extension VibrationPatternX on VibrationPattern {
  String get label => switch (this) {
        VibrationPattern.none => 'Off',
        VibrationPattern.short => 'Short',
        VibrationPattern.defaultPattern => 'Default',
        VibrationPattern.long => 'Long',
      };

  /// Milliseconds, as wait/vibrate pairs. Null means the system default.
  List<int>? get pattern => switch (this) {
        VibrationPattern.none => null,
        VibrationPattern.short => [0, 150],
        VibrationPattern.defaultPattern => null,
        VibrationPattern.long => [0, 500, 200, 500],
      };
}

/// A time of day stored as minutes from midnight, so it survives JSON without
/// dragging a date along.
class DayTime {
  const DayTime(this.hour, this.minute);

  final int hour;
  final int minute;

  int get minutesFromMidnight => hour * 60 + minute;

  String format() {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = hour < 12 ? 'AM' : 'PM';
    return '$h:${minute.toString().padLeft(2, '0')} $suffix';
  }

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  factory DayTime.fromJson(Map<String, dynamic> json) => DayTime(
        (json['hour'] as num?)?.toInt() ?? 0,
        (json['minute'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is DayTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

/// Everything the user can turn on, off or tune about notifications.
///
/// This is consulted when scheduling, so a muted category or a quiet hour
/// prevents an alert from ever being registered with the OS rather than being
/// filtered after the fact.
class NotificationPreferences {
  const NotificationPreferences({
    this.masterEnabled = true,
    this.taskReminders = true,
    this.earlyReminders = true,
    this.overdueTasks = true,
    this.upcomingTasks = true,
    this.recurringTasks = true,
    this.subtaskReminders = false,
    this.focusTimer = true,
    this.assignments = true,
    this.dailySummary = false,
    this.dailySummaryTime = const DayTime(8, 0),
    this.weeklySummary = false,
    this.sound = NotificationSound.defaultSound,
    this.vibration = VibrationPattern.defaultPattern,
    this.style = NotificationStyle.normal,
    this.defaultReminderMinutes,
    this.quietHoursEnabled = false,
    this.quietHoursStart = const DayTime(22, 0),
    this.quietHoursEnd = const DayTime(7, 0),
    this.urgentIgnoresQuietHours = true,
    this.mutedCategoryIds = const {},
  });

  final bool masterEnabled;
  final bool taskReminders;
  final bool earlyReminders;
  final bool overdueTasks;
  final bool upcomingTasks;
  final bool recurringTasks;
  final bool subtaskReminders;
  final bool focusTimer;
  final bool assignments;

  final bool dailySummary;
  final DayTime dailySummaryTime;
  final bool weeklySummary;

  final NotificationSound sound;
  final VibrationPattern vibration;
  final NotificationStyle style;

  /// Applied to a newly created task. Null means no reminder by default.
  final int? defaultReminderMinutes;

  final bool quietHoursEnabled;
  final DayTime quietHoursStart;
  final DayTime quietHoursEnd;

  /// Urgent alerts may still arrive during quiet hours if the user allows it.
  final bool urgentIgnoresQuietHours;

  /// Categories the user has muted; tasks in them schedule nothing.
  final Set<String> mutedCategoryIds;

  /// True when [moment] falls inside the quiet window. Handles a window that
  /// wraps past midnight, which is the normal case (22:00 to 07:00).
  bool isQuietAt(DateTime moment) {
    if (!quietHoursEnabled) return false;
    final minutes = moment.hour * 60 + moment.minute;
    final start = quietHoursStart.minutesFromMidnight;
    final end = quietHoursEnd.minutesFromMidnight;
    if (start == end) return false;
    return start < end
        ? minutes >= start && minutes < end
        : minutes >= start || minutes < end;
  }

  NotificationPreferences copyWith({
    bool? masterEnabled,
    bool? taskReminders,
    bool? earlyReminders,
    bool? overdueTasks,
    bool? upcomingTasks,
    bool? recurringTasks,
    bool? subtaskReminders,
    bool? focusTimer,
    bool? assignments,
    bool? dailySummary,
    DayTime? dailySummaryTime,
    bool? weeklySummary,
    NotificationSound? sound,
    VibrationPattern? vibration,
    NotificationStyle? style,
    Object? defaultReminderMinutes = _keep,
    bool? quietHoursEnabled,
    DayTime? quietHoursStart,
    DayTime? quietHoursEnd,
    bool? urgentIgnoresQuietHours,
    Set<String>? mutedCategoryIds,
  }) =>
      NotificationPreferences(
        masterEnabled: masterEnabled ?? this.masterEnabled,
        taskReminders: taskReminders ?? this.taskReminders,
        earlyReminders: earlyReminders ?? this.earlyReminders,
        overdueTasks: overdueTasks ?? this.overdueTasks,
        upcomingTasks: upcomingTasks ?? this.upcomingTasks,
        recurringTasks: recurringTasks ?? this.recurringTasks,
        subtaskReminders: subtaskReminders ?? this.subtaskReminders,
        focusTimer: focusTimer ?? this.focusTimer,
        assignments: assignments ?? this.assignments,
        dailySummary: dailySummary ?? this.dailySummary,
        dailySummaryTime: dailySummaryTime ?? this.dailySummaryTime,
        weeklySummary: weeklySummary ?? this.weeklySummary,
        sound: sound ?? this.sound,
        vibration: vibration ?? this.vibration,
        style: style ?? this.style,
        defaultReminderMinutes: defaultReminderMinutes == _keep
            ? this.defaultReminderMinutes
            : defaultReminderMinutes as int?,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietHoursStart: quietHoursStart ?? this.quietHoursStart,
        quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
        urgentIgnoresQuietHours: urgentIgnoresQuietHours ?? this.urgentIgnoresQuietHours,
        mutedCategoryIds: mutedCategoryIds ?? this.mutedCategoryIds,
      );

  Map<String, dynamic> toJson() => {
        'masterEnabled': masterEnabled,
        'taskReminders': taskReminders,
        'earlyReminders': earlyReminders,
        'overdueTasks': overdueTasks,
        'upcomingTasks': upcomingTasks,
        'recurringTasks': recurringTasks,
        'subtaskReminders': subtaskReminders,
        'focusTimer': focusTimer,
        'assignments': assignments,
        'dailySummary': dailySummary,
        'dailySummaryTime': dailySummaryTime.toJson(),
        'weeklySummary': weeklySummary,
        'sound': sound.name,
        'vibration': vibration.name,
        'style': style.name,
        'defaultReminderMinutes': defaultReminderMinutes,
        'quietHoursEnabled': quietHoursEnabled,
        'quietHoursStart': quietHoursStart.toJson(),
        'quietHoursEnd': quietHoursEnd.toJson(),
        'urgentIgnoresQuietHours': urgentIgnoresQuietHours,
        'mutedCategoryIds': mutedCategoryIds.toList(),
      };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        masterEnabled: (json['masterEnabled'] ?? true) as bool,
        taskReminders: (json['taskReminders'] ?? true) as bool,
        earlyReminders: (json['earlyReminders'] ?? true) as bool,
        overdueTasks: (json['overdueTasks'] ?? true) as bool,
        upcomingTasks: (json['upcomingTasks'] ?? true) as bool,
        recurringTasks: (json['recurringTasks'] ?? true) as bool,
        subtaskReminders: (json['subtaskReminders'] ?? false) as bool,
        focusTimer: (json['focusTimer'] ?? true) as bool,
        assignments: (json['assignments'] ?? true) as bool,
        dailySummary: (json['dailySummary'] ?? false) as bool,
        dailySummaryTime: json['dailySummaryTime'] == null
            ? const DayTime(8, 0)
            : DayTime.fromJson(Map<String, dynamic>.from(json['dailySummaryTime'] as Map)),
        weeklySummary: (json['weeklySummary'] ?? false) as bool,
        sound: NotificationSound.values.firstWhere(
          (s) => s.name == json['sound'],
          orElse: () => NotificationSound.defaultSound,
        ),
        vibration: VibrationPattern.values.firstWhere(
          (v) => v.name == json['vibration'],
          orElse: () => VibrationPattern.defaultPattern,
        ),
        style: NotificationStyle.values.firstWhere(
          (s) => s.name == json['style'],
          orElse: () => NotificationStyle.normal,
        ),
        defaultReminderMinutes: (json['defaultReminderMinutes'] as num?)?.toInt(),
        quietHoursEnabled: (json['quietHoursEnabled'] ?? false) as bool,
        quietHoursStart: json['quietHoursStart'] == null
            ? const DayTime(22, 0)
            : DayTime.fromJson(Map<String, dynamic>.from(json['quietHoursStart'] as Map)),
        quietHoursEnd: json['quietHoursEnd'] == null
            ? const DayTime(7, 0)
            : DayTime.fromJson(Map<String, dynamic>.from(json['quietHoursEnd'] as Map)),
        urgentIgnoresQuietHours: (json['urgentIgnoresQuietHours'] ?? true) as bool,
        mutedCategoryIds: ((json['mutedCategoryIds'] ?? const []) as List).cast<String>().toSet(),
      );
}

const _keep = Object();

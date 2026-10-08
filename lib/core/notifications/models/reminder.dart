/// How a reminder decides when to fire.
enum ReminderType {
  /// Exactly at the task's start time.
  atTime,

  /// [Reminder.offsetMinutes] before the task's start time.
  beforeTask,

  /// At [Reminder.absoluteDateTime], independent of the task's start time.
  customTime,

  /// Follows the task's recurrence; the offset applies to each occurrence.
  recurring,
}

/// How a reminder gets the user's attention.
///
/// These are genuinely different behaviours, not a volume setting. A
/// notification arrives once, like any other, and is easy to miss. An alarm is
/// built to be hard to miss: it uses the alarm audio stream, repeats until it
/// is dealt with, and asks the OS to show it over the lock screen. Where a
/// platform does not allow that, the strongest permitted behaviour is used and
/// the settings screen says so.
enum AlertMode { notification, alarm }

extension AlertModeX on AlertMode {
  String get label => switch (this) {
        AlertMode.notification => 'Notification',
        AlertMode.alarm => 'Alarm',
      };
}

/// The unit a custom offset was entered in, so the UI can show it back the way
/// the user typed it rather than converting 2 days into 2880 minutes.
enum ReminderUnit { minutes, hours, days }

extension ReminderUnitX on ReminderUnit {
  int get multiplier => switch (this) {
        ReminderUnit.minutes => 1,
        ReminderUnit.hours => 60,
        ReminderUnit.days => 1440,
      };

  String get label => switch (this) {
        ReminderUnit.minutes => 'Minutes',
        ReminderUnit.hours => 'Hours',
        ReminderUnit.days => 'Days',
      };
}

/// One alert belonging to a task.
///
/// Every reminder carries its own id and the platform [notificationId] it was
/// scheduled with, so cancelling is exact: the app never has to guess which
/// alerts a task owns.
class Reminder {
  const Reminder({
    required this.id,
    required this.taskId,
    this.type = ReminderType.beforeTask,
    this.offsetMinutes = 0,
    this.absoluteDateTime,
    this.enabled = true,
    this.alertMode = AlertMode.notification,
    this.soundId,
    this.vibrate,
    this.notificationId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String taskId;
  final ReminderType type;

  /// Minutes before the task starts. Ignored for [ReminderType.customTime].
  final int offsetMinutes;

  /// Fixed moment for [ReminderType.customTime].
  final DateTime? absoluteDateTime;

  /// A disabled reminder is kept but never scheduled, so the user can switch
  /// one off without losing it.
  final bool enabled;

  /// Notification or alarm. Per reminder, so one task can have a gentle early
  /// nudge and a loud one at the start time.
  final AlertMode alertMode;

  /// Which sound to play, by id from the sound catalogue. Null means "use the
  /// default for this mode", which is how a reminder follows the settings
  /// screen until the user picks something specific for it.
  final String? soundId;

  /// Null follows the default for this mode.
  final bool? vibrate;

  /// The id this reminder was last scheduled under on the platform.
  final int? notificationId;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// When this reminder should fire for a task starting at [taskStart].
  /// Returns null when it cannot be placed.
  DateTime? fireTimeFor(DateTime? taskStart) {
    switch (type) {
      case ReminderType.customTime:
        return absoluteDateTime;
      case ReminderType.atTime:
        return taskStart;
      case ReminderType.beforeTask:
      case ReminderType.recurring:
        if (taskStart == null) return null;
        return taskStart.subtract(Duration(minutes: offsetMinutes));
    }
  }

  /// "15 minutes before", "At the time", "1 day before".
  String get label {
    if (type == ReminderType.customTime) {
      final when = absoluteDateTime;
      return when == null ? 'Custom time' : 'At a set time';
    }
    return describeOffset(offsetMinutes);
  }

  /// The same reminder attached to a different task.
  ///
  /// Used when a task is created together with its reminders: they are built
  /// before the task has an id, so they are re-keyed once it does.
  Reminder withTaskId(String newTaskId) => Reminder(
        id: id,
        taskId: newTaskId,
        type: type,
        offsetMinutes: offsetMinutes,
        absoluteDateTime: absoluteDateTime,
        enabled: enabled,
        alertMode: alertMode,
        soundId: soundId,
        vibrate: vibrate,
        notificationId: notificationId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Reminder copyWith({
    ReminderType? type,
    int? offsetMinutes,
    Object? absoluteDateTime = _keep,
    bool? enabled,
    AlertMode? alertMode,
    Object? soundId = _keep,
    Object? vibrate = _keep,
    Object? notificationId = _keep,
    DateTime? updatedAt,
  }) =>
      Reminder(
        id: id,
        taskId: taskId,
        type: type ?? this.type,
        offsetMinutes: offsetMinutes ?? this.offsetMinutes,
        absoluteDateTime:
            absoluteDateTime == _keep ? this.absoluteDateTime : absoluteDateTime as DateTime?,
        enabled: enabled ?? this.enabled,
        alertMode: alertMode ?? this.alertMode,
        soundId: soundId == _keep ? this.soundId : soundId as String?,
        vibrate: vibrate == _keep ? this.vibrate : vibrate as bool?,
        notificationId: notificationId == _keep ? this.notificationId : notificationId as int?,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'type': type.name,
        'offsetMinutes': offsetMinutes,
        'absoluteDateTime': absoluteDateTime?.toIso8601String(),
        'enabled': enabled,
        'alertMode': alertMode.name,
        'soundId': soundId,
        'vibrate': vibrate,
        'notificationId': notificationId,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: (json['id'] ?? '') as String,
        taskId: (json['taskId'] ?? '') as String,
        type: ReminderType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ReminderType.beforeTask,
        ),
        offsetMinutes: (json['offsetMinutes'] as num?)?.toInt() ?? 0,
        absoluteDateTime: json['absoluteDateTime'] == null
            ? null
            : DateTime.tryParse(json['absoluteDateTime'] as String),
        enabled: (json['enabled'] ?? true) as bool,
        // A document written before alarms existed has no alertMode, so it
        // stays the plain notification it always was.
        alertMode: AlertMode.values.firstWhere(
          (m) => m.name == json['alertMode'],
          orElse: () => AlertMode.notification,
        ),
        soundId: json['soundId'] as String?,
        vibrate: json['vibrate'] as bool?,
        notificationId: (json['notificationId'] as num?)?.toInt(),
        createdAt:
            json['createdAt'] == null ? null : DateTime.tryParse(json['createdAt'] as String),
        updatedAt:
            json['updatedAt'] == null ? null : DateTime.tryParse(json['updatedAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.id == id &&
      other.type == type &&
      other.offsetMinutes == offsetMinutes &&
      other.absoluteDateTime == absoluteDateTime &&
      other.enabled == enabled &&
      other.alertMode == alertMode &&
      other.soundId == soundId &&
      other.vibrate == vibrate;

  @override
  int get hashCode =>
      Object.hash(id, type, offsetMinutes, absoluteDateTime, enabled, alertMode, soundId, vibrate);
}

const _keep = Object();

/// Offsets offered in the picker, in minutes before the start time.
const List<int> kReminderPresets = [0, 5, 10, 15, 30, 45, 60, 120, 1440, 2880];

/// Human label for an offset, including values that are not presets.
String describeOffset(int minutes) {
  if (minutes == 0) return 'At the time';
  if (minutes % 1440 == 0) {
    final days = minutes ~/ 1440;
    return days == 1 ? '1 day before' : '$days days before';
  }
  if (minutes % 60 == 0) {
    final hours = minutes ~/ 60;
    return hours == 1 ? '1 hour before' : '$hours hours before';
  }
  return minutes == 1 ? '1 minute before' : '$minutes minutes before';
}

/// Splits an offset back into the largest whole unit, so "120" shows as
/// "2 Hours" in the editor rather than "120 Minutes".
(int value, ReminderUnit unit) splitOffset(int minutes) {
  if (minutes != 0 && minutes % 1440 == 0) return (minutes ~/ 1440, ReminderUnit.days);
  if (minutes != 0 && minutes % 60 == 0) return (minutes ~/ 60, ReminderUnit.hours);
  return (minutes, ReminderUnit.minutes);
}

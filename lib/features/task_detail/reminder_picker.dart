import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/notifications/models/reminder.dart';
import '../../core/notifications/platform/local_notification_adapter.dart';
import 'reminder_alert_options.dart';

/// Opens the editor for one reminder. Returns the edited reminder, or null if
/// the user backed out.
Future<Reminder?> showReminderEditor(
  BuildContext context, {
  required String taskId,
  Reminder? existing,
  bool defaultVibrate = true,
  AlertMode defaultMode = AlertMode.notification,
}) {
  return showModalBottomSheet<Reminder>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ReminderEditor(
      taskId: taskId,
      existing: existing,
      defaultVibrate: defaultVibrate,
      defaultMode: defaultMode,
    ),
  );
}

/// Where the user turns notifications back on after denying them.
String notificationSettingsHint() => switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'Open Settings > MyPlanScheduler > Notifications and turn on Allow Notifications.',
      TargetPlatform.macOS => 'Open System Settings > Notifications > My Scheduler App and turn on Allow Notifications.',
      TargetPlatform.android => 'Open Settings > Apps > MyPlanScheduler > Notifications.',
      _ => 'Enable notifications for MyPlanScheduler in your system settings.',
    };

/// Asks the OS for notification permission, explaining why first.
///
/// Called when the user adds their first reminder rather than at launch, so the
/// prompt arrives with context.
Future<bool> ensureNotificationPermission(BuildContext context) async {
  final adapter = LocalNotificationAdapter();
  if (!adapter.supportsScheduling) return true;
  if (await adapter.hasPermission()) return true;
  if (!context.mounted) return false;

  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Allow notifications?'),
      content: const Text(
        'My Scheduler App needs notification permission to alert you before a task '
        'starts. Without it, reminders are saved but never appear.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
      ],
    ),
  );
  if (proceed != true) return false;
  return adapter.requestPermission();
}

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({
    required this.taskId,
    this.existing,
    this.defaultVibrate = true,
    this.defaultMode = AlertMode.notification,
  });

  final String taskId;
  final Reminder? existing;
  final bool defaultVibrate;

  /// What a brand new reminder starts as, from the user's settings.
  final AlertMode defaultMode;

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late ReminderType _type = widget.existing?.type ?? ReminderType.beforeTask;
  late int _value;
  late ReminderUnit _unit;
  late DateTime _absolute =
      widget.existing?.absoluteDateTime ?? DateTime.now().add(const Duration(hours: 1));
  final _valueController = TextEditingController();

  late AlertMode _mode = widget.existing?.alertMode ?? widget.defaultMode;
  late String? _soundId = widget.existing?.soundId;
  late bool? _vibrate = widget.existing?.vibrate;

  @override
  void initState() {
    super.initState();
    final offset = widget.existing?.offsetMinutes ?? 15;
    final (value, unit) = splitOffset(offset);
    _value = value;
    _unit = unit;
    _valueController.text = '$value';
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  int get _offsetMinutes => _type == ReminderType.atTime ? 0 : _value * _unit.multiplier;

  void _save() {
    final reminder = Reminder(
      id: widget.existing?.id ?? const Uuid().v4(),
      taskId: widget.taskId,
      type: _type,
      offsetMinutes: _offsetMinutes,
      absoluteDateTime: _type == ReminderType.customTime ? _absolute : null,
      enabled: widget.existing?.enabled ?? true,
      alertMode: _mode,
      soundId: _soundId,
      vibrate: _vibrate,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    Navigator.pop(context, reminder);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final defaults = widget.defaultVibrate;

    // Header and footer stay put; only the middle scrolls. That keeps Save
    // reachable on a small screen and with the keyboard open, rather than
    // letting a long form push it off the bottom.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
              child: Text(
                widget.existing == null ? 'Add reminder' : 'Edit reminder',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('Reminders fire before the task starts.',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12.5)),
            ),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quick presets.
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final preset in kReminderPresets)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(describeOffset(preset)),
                                selected:
                                    _type != ReminderType.customTime && _offsetMinutes == preset,
                                onSelected: (_) {
                                  final (value, unit) = splitOffset(preset);
                                  setState(() {
                                    _type = preset == 0
                                        ? ReminderType.atTime
                                        : ReminderType.beforeTask;
                                    _value = value;
                                    _unit = unit;
                                    _valueController.text = '$value';
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    ),

                    const Divider(height: 24),

                    // Custom value and unit: "[30] [Minutes] before".
                    if (_type != ReminderType.customTime && _type != ReminderType.atTime)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: _valueController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(isDense: true),
                                onChanged: (v) => setState(() => _value = int.tryParse(v) ?? 0),
                              ),
                            ),
                            const SizedBox(width: 12),
                            DropdownButton<ReminderUnit>(
                              value: _unit,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final unit in ReminderUnit.values)
                                  DropdownMenuItem(value: unit, child: Text(unit.label)),
                              ],
                              onChanged: (unit) =>
                                  setState(() => _unit = unit ?? ReminderUnit.minutes),
                            ),
                            const SizedBox(width: 12),
                            Text('before', style: TextStyle(color: palette.textSecondary)),
                          ],
                        ),
                      ),

                    SwitchListTile(
                      title: const Text('At a specific time instead'),
                      subtitle: Text(
                        _type == ReminderType.customTime
                            ? '${_absolute.day}/${_absolute.month} at '
                                '${TimeOfDay.fromDateTime(_absolute).format(context)}'
                            : 'Independent of when the task starts',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _type == ReminderType.customTime,
                      onChanged: (on) => setState(
                        () => _type = on ? ReminderType.customTime : ReminderType.beforeTask,
                      ),
                    ),

                    if (_type == ReminderType.customTime)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _absolute,
                              firstDate: DateTime.now().subtract(const Duration(days: 1)),
                              lastDate: DateTime(2100),
                            );
                            if (date == null || !context.mounted) return;
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(_absolute),
                            );
                            if (time == null) return;
                            setState(() => _absolute = DateTime(
                                date.year, date.month, date.day, time.hour, time.minute));
                          },
                          icon: const Icon(Icons.schedule, size: 18),
                          label: const Text('Choose date and time'),
                        ),
                      ),

                    const Divider(height: 28),

                    // Notification or alarm, the sound, and vibration.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ReminderAlertOptions(
                        mode: _mode,
                        soundId: _soundId,
                        vibrate: _vibrate,
                        defaultVibrate: defaults,
                        onChanged: (mode, soundId, vibrate) => setState(() {
                          _mode = mode;
                          _soundId = soundId;
                          _vibrate = vibrate;
                        }),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _offsetMinutes < 0 ? null : _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Snooze durations offered on a notification and in the app.
const List<int> kSnoozeOptions = [5, 10, 15, 30, 60];

Future<int?> showSnoozePicker(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Snooze for', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          for (final minutes in kSnoozeOptions)
            ListTile(
              dense: true,
              title: Text(minutes < 60 ? '$minutes minutes' : '1 hour'),
              onTap: () => Navigator.pop(context, minutes),
            ),
        ],
      ),
    ),
  );
}

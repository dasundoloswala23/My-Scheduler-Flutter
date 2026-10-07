import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/notifications/models/notification_preferences.dart';
import '../../core/notifications/models/reminder.dart';
import '../../core/notifications/platform/local_notification_adapter.dart';
import '../task_detail/reminder_picker.dart';
import '../../core/providers.dart';
import 'more_page.dart';

/// Everything the user can turn on, off or tune about notifications.
///
/// Saving writes to the user document, so preferences follow the account to
/// every device rather than living on one phone.
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationPreferencesProvider);
    final supported = LocalNotificationAdapter().supportsScheduling;

    return SubPage(
      eyebrow: 'My Scheduler App',
      title: 'Notifications',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(onRetry: () => ref.invalidate(notificationPreferencesProvider)),
        data: (prefs) => _Form(prefs: prefs, supported: supported),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.prefs, required this.supported});

  final NotificationPreferences prefs;
  final bool supported;

  Future<void> _save(WidgetRef ref, NotificationPreferences next) =>
      ref.read(notificationPreferencesServiceProvider).save(next);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = prefs.masterEnabled;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        if (!supported)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'This platform cannot schedule notifications, so these settings '
              'are saved but have no effect here.',
              style: TextStyle(fontSize: 12.5, color: AppColors.amber),
            ),
          ),

        Card(
          child: SwitchListTile(
            title: const Text('All notifications', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Turn everything off in one place', style: TextStyle(fontSize: 12.5)),
            value: enabled,
            onChanged: (v) => _save(ref, prefs.copyWith(masterEnabled: v)),
          ),
        ),
        const SizedBox(height: 14),

        _SectionLabel('What to notify me about'),
        Card(
          child: Column(
            children: [
              _Toggle(
                label: 'Task reminders',
                value: prefs.taskReminders,
                enabled: enabled,
                onChanged: (v) => _save(ref, prefs.copyWith(taskReminders: v)),
              ),
              _Toggle(
                label: 'Early reminders',
                subtitle: 'Alerts before a task starts',
                value: prefs.earlyReminders,
                enabled: enabled,
                onChanged: (v) => _save(ref, prefs.copyWith(earlyReminders: v)),
              ),
              _Toggle(
                label: 'Overdue tasks',
                value: prefs.overdueTasks,
                enabled: enabled,
                onChanged: (v) => _save(ref, prefs.copyWith(overdueTasks: v)),
              ),
              _Toggle(
                label: 'Upcoming tasks',
                value: prefs.upcomingTasks,
                enabled: enabled,
                onChanged: (v) => _save(ref, prefs.copyWith(upcomingTasks: v)),
              ),
              _Toggle(
                label: 'Recurring tasks',
                value: prefs.recurringTasks,
                enabled: enabled,
                onChanged: (v) => _save(ref, prefs.copyWith(recurringTasks: v)),
              ),
              _Toggle(
                label: 'Subtask reminders',
                value: prefs.subtaskReminders,
                enabled: enabled,
                onChanged: (v) => _save(ref, prefs.copyWith(subtaskReminders: v)),
              ),
              _Toggle(
                label: 'Focus timer',
                value: prefs.focusTimer,
                enabled: enabled,
                onChanged: (v) => _save(ref, prefs.copyWith(focusTimer: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _SectionLabel('Default reminder'),
        Card(
          child: ListTile(
            enabled: enabled,
            leading: const Icon(Icons.notifications_none),
            title: const Text('New tasks start with', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              prefs.defaultReminderMinutes == null
                  ? 'No reminder'
                  : describeOffset(prefs.defaultReminderMinutes!),
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final chosen = await showModalBottomSheet<Object?>(
                context: context,
                builder: (context) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        title: const Text('No reminder'),
                        onTap: () => Navigator.pop(context, 'none'),
                      ),
                      for (final preset in kReminderPresets)
                        ListTile(
                          title: Text(describeOffset(preset)),
                          onTap: () => Navigator.pop(context, preset),
                        ),
                    ],
                  ),
                ),
              );
              if (chosen == null) return;
              await _save(
                ref,
                prefs.copyWith(defaultReminderMinutes: chosen == 'none' ? null : chosen as int),
              );
            },
          ),
        ),
        const SizedBox(height: 14),

        _SectionLabel('How they arrive'),
        Card(
          child: Column(
            children: [
              _Choice<NotificationStyle>(
                label: 'Style',
                enabled: enabled,
                value: prefs.style,
                options: NotificationStyle.values,
                labelFor: (s) => s.label,
                onChanged: (v) => _save(ref, prefs.copyWith(style: v)),
              ),
              _Choice<NotificationSound>(
                label: 'Sound',
                enabled: enabled,
                value: prefs.sound,
                options: NotificationSound.values,
                labelFor: (s) => s.label,
                onChanged: (v) => _save(ref, prefs.copyWith(sound: v)),
              ),
              _Choice<VibrationPattern>(
                label: 'Vibration',
                enabled: enabled,
                value: prefs.vibration,
                options: VibrationPattern.values,
                labelFor: (v) => v.label,
                onChanged: (v) => _save(ref, prefs.copyWith(vibration: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _SectionLabel('Quiet hours'),
        Card(
          child: Column(
            children: [
              _Toggle(
                label: 'Quiet hours',
                subtitle: 'Hold reminders overnight',
                value: prefs.quietHoursEnabled,
                enabled: enabled,
                onChanged: (v) => _save(ref, prefs.copyWith(quietHoursEnabled: v)),
              ),
              _TimeRow(
                label: 'From',
                time: prefs.quietHoursStart,
                enabled: enabled && prefs.quietHoursEnabled,
                onChanged: (t) => _save(ref, prefs.copyWith(quietHoursStart: t)),
              ),
              _TimeRow(
                label: 'Until',
                time: prefs.quietHoursEnd,
                enabled: enabled && prefs.quietHoursEnabled,
                onChanged: (t) => _save(ref, prefs.copyWith(quietHoursEnd: t)),
              ),
              _Toggle(
                label: 'Let urgent reminders through',
                value: prefs.urgentIgnoresQuietHours,
                enabled: enabled && prefs.quietHoursEnabled,
                onChanged: (v) => _save(ref, prefs.copyWith(urgentIgnoresQuietHours: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _SectionLabel('Summaries'),
        Card(
          child: Column(
            children: [
              _Toggle(
                label: 'Daily summary',
                subtitle: 'A morning note of what is on today',
                value: prefs.dailySummary,
                enabled: enabled,
                onChanged: (v) => _save(ref, prefs.copyWith(dailySummary: v)),
              ),
              _TimeRow(
                label: 'At',
                time: prefs.dailySummaryTime,
                enabled: enabled && prefs.dailySummary,
                onChanged: (t) => _save(ref, prefs.copyWith(dailySummaryTime: t)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Check permission', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Ask the system again if alerts are not arriving',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            onTap: () async {
              final adapter = LocalNotificationAdapter();
              final granted = await adapter.requestPermission();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(granted
                      ? 'Notifications are allowed.'
                      : 'Notifications are blocked. ${notificationSettingsHint()}'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 10, letterSpacing: 1.1, color: AppColors.muted)),
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      value: value && enabled,
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.labelFor,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T) labelFor;
  final bool enabled;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      enabled: enabled,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(labelFor(option))),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.time,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final DayTime time;
  final bool enabled;
  final ValueChanged<DayTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      enabled: enabled,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: Text(time.format(),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: enabled ? AppColors.primary : AppColors.muted,
          )),
      onTap: enabled
          ? () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: time.hour, minute: time.minute),
              );
              if (picked != null) onChanged(DayTime(picked.hour, picked.minute));
            }
          : null,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 36, color: AppColors.muted),
          const SizedBox(height: 12),
          const Text('Could not load your settings.',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

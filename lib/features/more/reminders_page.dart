import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/notifications/models/reminder.dart' as task_reminder;
import '../../core/notifications/models/reminder_sound.dart';
import '../../core/notifications/platform/local_notification_adapter.dart';
import '../../core/notifications/scheduling/upcoming_reminders.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../quick_add/quick_add_sheet.dart';
import '../task_detail/task_detail_sheet.dart';
import 'more_page.dart';

/// Every reminder, grouped by when it fires.
///
/// Two kinds appear. Reminders attached to a task come from the task itself, so
/// each one is the live reminder and tapping it opens that task. Stand-alone
/// reminders, made from Quick Add without a task, are listed below them.
class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standalone = ref.watch(remindersProvider).value ?? const <Reminder>[];
    final tasks = ref.watch(tasksProvider).value ?? const [];
    final groups = groupUpcomingReminders(tasks, DateTime.now());
    final hasTaskReminders = groups.values.any((g) => g.isNotEmpty);
    final empty = standalone.isEmpty && !hasTaskReminders;

    return SubPage(
      eyebrow: 'My Scheduler App',
      title: 'Reminders',
      floatingActionButton: empty
          ? null
          : FloatingActionButton(
              tooltip: 'Add reminder',
              onPressed: () => _add(context),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            ),
      child: empty
          ? EmptyState(
              icon: Icons.notifications_none,
              title: 'No reminders yet',
              actionLabel: 'Add Reminder',
              onAction: () => _add(context),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              children: [
                if (!LocalNotificationAdapter().supportsScheduling)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Notifications are not available on this platform, so reminders are shown here only.',
                      style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
                    ),
                  ),
                for (final bucket in ReminderBucket.values)
                  if (groups[bucket]!.isNotEmpty) ...[
                    _GroupLabel(bucket.label,
                        warning: bucket == ReminderBucket.missed),
                    for (final item in groups[bucket]!)
                      _TaskReminderCard(
                        item: item,
                        missed: bucket == ReminderBucket.missed,
                        onTap: () => showTaskDetailSheet(context, item.task),
                      ),
                  ],
                if (standalone.isNotEmpty) ...[
                  const _GroupLabel('Free-standing'),
                  for (final r in standalone) _StandaloneCard(reminder: r),
                ],
              ],
            ),
    );
  }

  /// Adding goes through Quick Add, which already handles the date, the time,
  /// notification versus alarm, and the sound. Keeping a second copy of that
  /// here is how the two would drift apart.
  void _add(BuildContext context) =>
      showQuickAddSheet(context, kind: QuickAddKind.reminder);
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {this.warning = false});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: warning ? context.palette.warning : context.palette.textSecondary,
          ),
        ),
      );
}

class _TaskReminderCard extends StatelessWidget {
  const _TaskReminderCard({required this.item, required this.onTap, this.missed = false});

  final UpcomingReminder item;
  final VoidCallback onTap;
  final bool missed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reminder = item.reminder;
    final alarm = reminder.alertMode == task_reminder.AlertMode.alarm;
    final sound = ReminderSounds.labelFor(
        reminder.soundId ?? ReminderSounds.defaultFor(reminder.alertMode));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        minVerticalPadding: 12,
        leading: Icon(
          alarm ? Icons.alarm : Icons.notifications_none,
          color: missed ? palette.warning : AppColors.primary,
        ),
        title: Text(item.task.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${DateFormat('EEE, MMM d · h:mm a').format(item.fireAt)}\n'
          '${reminder.label} · ${reminder.alertMode.label} · $sound',
          style: TextStyle(fontSize: 12, height: 1.4, color: palette.textSecondary),
        ),
        isThreeLine: true,
        trailing: Icon(Icons.chevron_right, color: palette.textSecondary),
      ),
    );
  }
}

class _StandaloneCard extends ConsumerWidget {
  const _StandaloneCard({required this.reminder});
  final Reminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = reminder;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: InkWell(
          customBorder: const CircleBorder(),
          onTap: () async {
            await ref.read(repoProvider).saveReminder(Reminder(
                  id: r.id,
                  title: r.title,
                  remindAt: r.remindAt,
                  done: !r.done,
                  notificationId: r.notificationId,
                ));
            if (!r.done && r.notificationId != null) {
              await LocalNotificationAdapter().cancel(r.notificationId!);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              r.done ? Icons.check_circle : Icons.notifications_none,
              color: r.done ? context.palette.success : context.palette.danger,
            ),
          ),
        ),
        title: Text(r.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              decoration: r.done ? TextDecoration.lineThrough : null,
              color: r.done ? context.palette.textSecondary : null,
            )),
        subtitle: Text(DateFormat('EEE, MMM d · h:mm a').format(r.remindAt),
            style: TextStyle(fontSize: 12, color: context.palette.textSecondary)),
        trailing: IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () async {
            if (r.notificationId != null) {
              await LocalNotificationAdapter().cancel(r.notificationId!);
            }
            await ref.read(repoProvider).deleteReminder(r.id);
          },
        ),
      ),
    );
  }
}

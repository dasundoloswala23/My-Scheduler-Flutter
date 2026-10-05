import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/notifications/models/notification_preferences.dart';
import '../../core/notifications/platform/local_notification_adapter.dart';
import '../../core/notifications/scheduling/reminder_calculator.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import 'more_page.dart';

/// Screenshot 7: reminders, each one backed by a real scheduled notification.
class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersProvider).value ?? const <Reminder>[];

    return SubPage(
      eyebrow: 'My scheduler',
      title: 'Reminders',
      floatingActionButton: reminders.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: () => _add(context, ref),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            ),
      child: reminders.isEmpty
          ? EmptyState(
              icon: Icons.notifications_none,
              title: 'Your reminders live here',
              actionLabel: 'Add Reminder',
              onAction: () => _add(context, ref),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              children: [
                if (!LocalNotificationAdapter().supportsScheduling)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Notifications are not available on this platform, so reminders are shown here only.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                for (final r in reminders)
                  Card(
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
                        child: Icon(
                          r.done ? Icons.check_circle : Icons.notifications_none,
                          color: r.done ? AppColors.success : AppColors.danger,
                        ),
                      ),
                      title: Text(r.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: r.done ? TextDecoration.lineThrough : null,
                            color: r.done ? AppColors.muted : null,
                          )),
                      subtitle: Text(DateFormat('EEE, MMM d · h:mm a').format(r.remindAt),
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          if (r.notificationId != null) {
                            await LocalNotificationAdapter().cancel(r.notificationId!);
                          }
                          await ref.read(repoProvider).deleteReminder(r.id);
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final title = await promptText(context, 'Remind me to…');
    if (title == null || !context.mounted) return;

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;

    final remindAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final notificationId = remindAt.millisecondsSinceEpoch ~/ 1000;

    await ref.read(repoProvider).addReminder(
          Reminder(id: 'new', title: title, remindAt: remindAt, notificationId: notificationId),
        );
    final adapter = LocalNotificationAdapter();
    await adapter.requestPermission();
    await adapter.schedule(
      PlannedNotification(
        notificationId: notificationId,
        reminderId: 'standalone',
        taskId: '',
        title: title,
        body: 'Reminder from My scheduler',
        fireAt: remindAt,
        style: NotificationStyle.normal,
      ),
      const NotificationPreferences(),
    );
  }
}

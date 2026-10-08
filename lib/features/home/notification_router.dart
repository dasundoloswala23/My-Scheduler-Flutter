import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/platform/local_notification_adapter.dart';
import '../../core/notifications/platform/notification_adapter.dart';
import '../../core/providers.dart';
import '../../models/task.dart';
import '../task_detail/task_detail_sheet.dart';

/// Listens for notification taps and action buttons, then acts on them:
///
///  - Open     opens the task's detail sheet (the deep link).
///  - Complete marks the task done without opening anything.
///  - Snooze   re-fires the reminder a few minutes later.
///
/// It wraps the app shell so a notification can be handled from anywhere.
class NotificationRouter extends ConsumerStatefulWidget {
  const NotificationRouter({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationRouter> createState() => _NotificationRouterState();
}

class _NotificationRouterState extends ConsumerState<NotificationRouter> {
  StreamSubscription<NotificationEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = LocalNotificationAdapter.events.listen(_handle);

    // A notification that launched the app is replayed once there is a UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launch = LocalNotificationAdapter.launchEvent;
      if (launch != null) {
        LocalNotificationAdapter.launchEvent = null;
        _handle(launch);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _handle(NotificationEvent event) async {
    // Wait for the task to arrive from Firestore; on a cold start the stream
    // may not have delivered yet.
    final task = await _findTask(event.taskId);
    if (task == null || !mounted) return;

    final repo = ref.read(repoProvider);

    // An alarm is an ongoing notification that keeps sounding until it is
    // cleared, so acting on it, even just opening it, has to clear it. The
    // Complete and Snooze buttons already cancel themselves; a tap on the body
    // does not, which would leave the alarm ringing under the open app.
    final id = event.notificationId;
    if (id != null) {
      await ref.read(notificationAdapterProvider).cancel(id);
    }

    switch (event.action) {
      case NotificationAction.complete:
        await repo.setTaskCompleted(task, true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Completed "${task.title}"')),
          );
        }
      case NotificationAction.snooze:
        final minutes = event.snoozeMinutes ??
            ref.read(notificationPreferencesProvider).value?.snoozeMinutes ??
            10;
        await repo.snoozeTask(task, minutes: minutes, reminderId: event.reminderId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reminder snoozed for $minutes minutes')),
          );
        }
      case NotificationAction.open:
        if (mounted) showTaskDetailSheet(context, task);
    }
  }

  /// Polls the task list briefly, because the notification can arrive before
  /// the first Firestore snapshot does.
  Future<Task?> _findTask(String taskId) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final tasks = ref.read(tasksProvider).value;
      final match = tasks?.where((t) => t.id == taskId).firstOrNull;
      if (match != null) return match;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

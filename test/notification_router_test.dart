import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/notifications/models/notification_preferences.dart';
import 'package:myschedule/core/notifications/platform/local_notification_adapter.dart';
import 'package:myschedule/core/notifications/platform/notification_adapter.dart';
import 'package:myschedule/core/attachment_service.dart';
import 'package:myschedule/core/providers.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/features/home/notification_router.dart';
import 'package:myschedule/models/attachment.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/task.dart';

class _Repo extends Fake implements Repo {
  final completed = <String>[];
  final snoozed = <String>[];

  @override
  Future<void> setTaskCompleted(Task task, bool done) async => completed.add(task.id);

  @override
  Future<DateTime?> snoozeTask(Task task, {int minutes = 10, String? reminderId}) async {
    snoozed.add('${task.id}:$minutes');
    return null;
  }
}

class _Attachments extends Fake implements AttachmentService {
  @override
  Stream<List<Attachment>> watch(String taskId) => Stream.value(const <Attachment>[]);
}

/// A tapped notification must act on the task it was scheduled for, and only
/// that one. The launch event is how Android hands a cold-start tap to the app.
Future<(_Repo, FakeNotificationAdapter)> _launch(
  WidgetTester tester,
  NotificationEvent event,
) async {
  final repo = _Repo();
  final adapter = FakeNotificationAdapter();
  LocalNotificationAdapter.launchEvent = event;
  addTearDown(() => LocalNotificationAdapter.launchEvent = null);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      repoProvider.overrideWithValue(repo),
      notificationAdapterProvider.overrideWithValue(adapter),
      attachmentServiceProvider.overrideWithValue(_Attachments()),
      notificationPreferencesProvider.overrideWith((ref) => Stream.value(const NotificationPreferences())),
      tasksProvider.overrideWithValue(const AsyncData([
        Task(id: 'a', title: 'First task'),
        Task(id: 'b', title: 'Second task'),
      ])),
      categoriesProvider.overrideWith((ref) => Stream.value(const <Category>[])),
      boardsProvider.overrideWith((ref) => Stream.value(const <Board>[])),
      listsProvider.overrideWith((ref) => Stream.value(const <TaskList>[])),
    ],
    child: const MaterialApp(
      home: Scaffold(body: NotificationRouter(child: Text('app'))),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return (repo, adapter);
}

void main() {
  testWidgets('tapping a notification opens that exact task', (tester) async {
    await _launch(tester,
        const NotificationEvent(action: NotificationAction.open, taskId: 'b'));
    await tester.pumpAndSettle();
    expect(find.text('Second task'), findsWidgets);
    expect(find.text('First task'), findsNothing);
  });

  testWidgets('the Complete action completes only that task and clears the alarm',
      (tester) async {
    final (repo, adapter) = await _launch(
      tester,
      const NotificationEvent(
          action: NotificationAction.complete, taskId: 'a', notificationId: 42),
    );
    await tester.pump();
    expect(repo.completed, ['a']);
    expect(find.textContaining('Completed "First task"'), findsOneWidget);
    expect(adapter.cancelled, contains(42));
  });

  testWidgets('the Snooze action snoozes that task by the requested minutes', (tester) async {
    final (repo, _) = await _launch(
      tester,
      const NotificationEvent(
          action: NotificationAction.snooze, taskId: 'b', snoozeMinutes: 15),
    );
    await tester.pump();
    expect(repo.snoozed, ['b:15']);
  });
}

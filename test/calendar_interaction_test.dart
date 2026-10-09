import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/notifications/models/reminder.dart' hide Reminder;
import 'package:myschedule/core/notifications/models/reminder.dart' as n show Reminder;
import 'package:myschedule/core/notifications/platform/notification_adapter.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/core/preferences/app_preferences.dart';
import 'package:myschedule/core/providers.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/features/calendar/calendar_page.dart';
import 'package:myschedule/features/dnd/drag_core.dart';
import 'package:myschedule/models/task.dart';

/// Dragging an event and resizing its bottom edge in the REAL calendar page,
/// against the real [Repo] on an in-memory Firestore and a fake notification
/// platform. After each gesture it checks what was stored, the version bump, and
/// that the reminder was rescheduled to match.
void main() {
  final now = DateTime.now();
  // Three days out, so the start and its reminder are in the future.
  final day = DateTime(now.year, now.month, now.day + 3);
  final start = DateTime(day.year, day.month, day.day, 10, 0);

  late FakeFirebaseFirestore db;
  late FakeNotificationAdapter adapter;
  late Repo repo;
  late String taskId;

  Future<Task> read() async =>
      Task.fromDoc(await db.collection('users/u1/tasks').doc(taskId).get());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1500);
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      db = FakeFirebaseFirestore();
      adapter = FakeNotificationAdapter();
      repo = Repo(db: db, uid: 'u1', notifications: NotificationService(adapter: adapter));
      taskId = await repo.createTask(Task(
        id: 'new',
        title: 'Drag me',
        startDateTime: start,
        endDateTime: start.add(const Duration(hours: 1)),
        reminders: [
          n.Reminder(
            id: 'r1',
            taskId: 'new',
            type: ReminderType.beforeTask,
            offsetMinutes: 30,
          ),
        ],
      ));
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        repoProvider.overrideWithValue(repo),
        appPreferencesProvider.overrideWithValue(const AppPreferences()),
        savePreferencesProvider.overrideWithValue((_) async {}),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            // Point the calendar at the day of the event, as the week strip does.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ref.read(calendarFocusProvider) == null) {
                ref.read(calendarFocusProvider.notifier).focus(day);
              }
            });
            return const CalendarPage();
          }),
        ),
      ),
    ));
    await settle(tester);
    await tester.tap(find.text('Day').first);
    await settle(tester);
  }

  DateTime? firesAt() => adapter.scheduled.values.singleOrNull?.fireAt;

  testWidgets('the event is on the calendar with its reminder scheduled', (tester) async {
    await mount(tester);
    expect(find.text('Drag me'), findsWidgets);
    expect(firesAt(), start.subtract(const Duration(minutes: 30)));
  });

  testWidgets('dragging the event to a later slot saves it and moves the reminder', (tester) async {
    await mount(tester);
    final before = await tester.runAsync(read) as Task;

    final event = find.byType(TaskDraggable).first;
    final rect = tester.getRect(event);
    // A long press then a move, the way a touch drag starts.
    final gesture = await tester.startGesture(rect.center);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(0, 8));
    await tester.pump(const Duration(milliseconds: 100));
    // Two hours down: the hour height is whatever the density says.
    final hourHeight = const AppPreferences().calendarDensity.hourHeight;
    await gesture.moveTo(rect.center + Offset(0, 2 * hourHeight));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await settle(tester);

    final after = await tester.runAsync(read) as Task;
    expect(after.startDateTime!.isAfter(before.startDateTime!), isTrue, reason: 'it moved later');
    expect(after.startDateTime!.hour, anyOf(11, 12), reason: 'about two hours later, snapped to a slot');
    expect(after.duration, before.duration, reason: 'a move keeps the length');
    expect(after.version, greaterThan(before.version));
    expect(adapter.scheduled, hasLength(1), reason: 'the old alert was replaced, not kept');
    expect(firesAt(), after.startDateTime!.subtract(const Duration(minutes: 30)),
        reason: 'the reminder follows the new time');
  });

  testWidgets('dragging the bottom edge changes the duration and keeps the start and reminder',
      (tester) async {
    await mount(tester);
    final before = await tester.runAsync(read) as Task;

    final rect = tester.getRect(find.byType(TaskDraggable).first);
    final handle = Offset(rect.center.dx, rect.bottom - 4);
    final gesture = await tester.startGesture(handle);
    await tester.pump(const Duration(milliseconds: 50));
    final hourHeight = const AppPreferences().calendarDensity.hourHeight;
    for (var i = 1; i <= 6; i++) {
      await gesture.moveBy(Offset(0, (hourHeight / 2 + kTouchSlop) / 6));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await settle(tester);

    final after = await tester.runAsync(read) as Task;
    expect(after.startDateTime, before.startDateTime, reason: 'resizing never moves the start');
    expect(after.duration, const Duration(minutes: 90), reason: 'one hour plus half an hour');
    expect(after.version, greaterThan(before.version));
    expect(firesAt(), before.startDateTime!.subtract(const Duration(minutes: 30)),
        reason: 'the start did not change, so the reminder stays where it was');
    expect(adapter.scheduled, hasLength(1));
  });
}

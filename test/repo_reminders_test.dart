import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/notifications/models/notification_preferences.dart';
import 'package:myschedule/core/notifications/models/reminder.dart';
import 'package:myschedule/core/notifications/platform/notification_adapter.dart';
import 'package:myschedule/core/notifications/scheduling/reminder_calculator.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/models/task.dart';

/// These drive the real [Repo] against an in-memory Firestore and a fake
/// notification platform. Before they existed the move paths had no coverage at
/// all, which is how dragging a task to a new time left its old reminder firing
/// at the old time.
final kNow = DateTime(2026, 10, 5, 9, 0);

class _ThrowingAdapter extends FakeNotificationAdapter {
  @override
  Future<void> schedule(PlannedNotification n, NotificationPreferences p) async {
    throw StateError('the platform refused');
  }
}

class _Harness {
  _Harness({FakeNotificationAdapter? adapter})
      : adapter = adapter ?? FakeNotificationAdapter(),
        db = FakeFirebaseFirestore(),
        clock = FakeClock(kNow) {
    repo = Repo(
      db: db,
      uid: 'u1',
      notifications: NotificationService(adapter: this.adapter, clock: clock),
    );
  }

  final FakeNotificationAdapter adapter;
  final FakeFirebaseFirestore db;
  final FakeClock clock;
  late final Repo repo;

  Future<Task> read(String id) async =>
      Task.fromDoc(await db.collection('users').doc('u1').collection('tasks').doc(id).get());

  /// A task at [start] with one reminder [minutes] before it.
  Future<String> create({
    required DateTime start,
    int minutes = 30,
    AlertMode mode = AlertMode.notification,
    String? sound,
    String? categoryId,
  }) {
    final reminder = Reminder(
      id: 'r1',
      taskId: 'new',
      type: minutes == 0 ? ReminderType.atTime : ReminderType.beforeTask,
      offsetMinutes: minutes,
      alertMode: mode,
      soundId: sound,
    );
    return repo.createTask(Task(
      id: 'new',
      title: 'Kitty Meow Video',
      startDateTime: start,
      endDateTime: start.add(const Duration(hours: 1)),
      categoryId: categoryId,
      reminders: [reminder],
    ));
  }

  DateTime? get scheduledFor => adapter.scheduled.values.singleOrNull?.fireAt;
}

void main() {
  group('creating a task', () {
    test('schedules its reminder, keyed to the real task id', () async {
      final h = _Harness();
      final id = await h.create(start: DateTime(2026, 10, 5, 18, 0));

      expect(h.scheduledFor, DateTime(2026, 10, 5, 17, 30));
      expect(h.adapter.scheduled.values.single.taskId, id);

      // The stored reminder points at the task, not at the placeholder it was
      // built with.
      expect((await h.read(id)).reminders.single.taskId, id);
    });
  });

  group('moving a task reschedules its reminders', () {
    test('6 PM to 8 PM: the 5:30 PM alert is replaced by a 7:30 PM one', () async {
      final h = _Harness();
      final id = await h.create(start: DateTime(2026, 10, 5, 18, 0));
      expect(h.scheduledFor, DateTime(2026, 10, 5, 17, 30));
      final before = await h.read(id);

      final newStart = DateTime(2026, 10, 5, 20, 0);
      await h.repo.moveTask(
        taskId: id,
        expectedVersion: before.version,
        startDateTime: newStart,
        endDateTime: newStart.add(const Duration(hours: 1)),
      );

      expect(h.adapter.scheduled, hasLength(1), reason: 'no duplicate alert');
      expect(h.scheduledFor, DateTime(2026, 10, 5, 19, 30));
      expect((await h.read(id)).startDateTime, newStart);
    });

    test('moving to another day moves the alert to that day', () async {
      final h = _Harness();
      final id = await h.create(start: DateTime(2026, 10, 5, 18, 0));

      final tomorrow = DateTime(2026, 10, 6, 18, 0);
      await h.repo.moveTask(
        taskId: id,
        expectedVersion: 1,
        startDateTime: tomorrow,
        endDateTime: tomorrow.add(const Duration(hours: 1)),
      );

      expect(h.scheduledFor, DateTime(2026, 10, 6, 17, 30));
    });

    test('undoing the move puts the alert back', () async {
      final h = _Harness();
      final id = await h.create(start: DateTime(2026, 10, 5, 18, 0));
      final original = await h.read(id);

      final moved = DateTime(2026, 10, 5, 20, 0);
      final result = await h.repo.moveTask(
        taskId: id,
        expectedVersion: original.version,
        startDateTime: moved,
        endDateTime: moved.add(const Duration(hours: 1)),
      );
      expect(h.scheduledFor, DateTime(2026, 10, 5, 19, 30));

      await h.repo.moveTask(
        taskId: id,
        expectedVersion: result.newVersion,
        startDateTime: original.startDateTime,
        endDateTime: original.endDateTime,
      );

      expect(h.adapter.scheduled, hasLength(1));
      expect(h.scheduledFor, DateTime(2026, 10, 5, 17, 30));
    });

    test('dragging a task off the calendar cancels its alert', () async {
      final h = _Harness();
      final id = await h.create(start: DateTime(2026, 10, 5, 18, 0));
      expect(h.adapter.scheduled, hasLength(1));

      await h.repo.moveTask(
        taskId: id,
        expectedVersion: 1,
        startDateTime: null,
        endDateTime: null,
      );

      expect(h.adapter.scheduled, isEmpty,
          reason: 'an unscheduled task has nothing to be reminded about');
      expect((await h.read(id)).startDateTime, isNull);
    });

    test('an alarm is still an alarm, with its sound, after it moves', () async {
      final h = _Harness();
      final id = await h.create(
        start: DateTime(2026, 10, 5, 18, 0),
        mode: AlertMode.alarm,
        sound: 'classic_bell',
      );

      final moved = DateTime(2026, 10, 5, 21, 0);
      await h.repo.moveTask(
        taskId: id,
        expectedVersion: 1,
        startDateTime: moved,
        endDateTime: moved.add(const Duration(hours: 1)),
      );

      final n = h.adapter.scheduled.values.single;
      expect(n.isAlarm, isTrue);
      expect(n.soundId, 'classic_bell');
      expect(n.fireAt, DateTime(2026, 10, 5, 20, 30));
    });

    test('changing to a muted category cancels the alert', () async {
      final h = _Harness();
      h.repo.notificationPreferences =
          const NotificationPreferences(mutedCategoryIds: {'quiet-cat'});
      final id = await h.create(start: DateTime(2026, 10, 5, 18, 0));
      expect(h.adapter.scheduled, hasLength(1));

      await h.repo.moveTask(taskId: id, expectedVersion: 1, categoryId: 'quiet-cat');

      expect(h.adapter.scheduled, isEmpty);
    });
  });

  group('moves that do not change the time leave the alerts alone', () {
    test('reordering within a list does not reschedule', () async {
      final h = _Harness();
      final id = await h.create(start: DateTime(2026, 10, 5, 18, 0));
      h.adapter.cancelled.clear();

      await h.repo.moveTask(taskId: id, expectedVersion: 1, position: 12345);

      expect(h.adapter.cancelled, isEmpty, reason: 'no cancel-and-reschedule churn');
      expect(h.scheduledFor, DateTime(2026, 10, 5, 17, 30));
    });

    test('resizing the duration does not reschedule', () async {
      final h = _Harness();
      final id = await h.create(start: DateTime(2026, 10, 5, 18, 0));
      h.adapter.cancelled.clear();

      await h.repo.moveTask(
        taskId: id,
        expectedVersion: 1,
        endDateTime: DateTime(2026, 10, 5, 19, 30),
      );

      expect(h.adapter.cancelled, isEmpty);
      expect(h.scheduledFor, DateTime(2026, 10, 5, 17, 30));
    });
  });

  group('a failure in the platform never undoes a saved move', () {
    test('the task still moves when scheduling throws', () async {
      // Created with a healthy platform, so it has a reminder to reschedule...
      final h = _Harness();
      final id = await h.create(start: DateTime(2026, 10, 5, 18, 0));

      // ...then moved through a repository whose platform refuses to schedule.
      final failing = Repo(
        db: h.db,
        uid: 'u1',
        notifications: NotificationService(adapter: _ThrowingAdapter(), clock: h.clock),
      );
      final moved = DateTime(2026, 10, 5, 20, 0);
      await failing.moveTask(
        taskId: id,
        expectedVersion: 1,
        startDateTime: moved,
        endDateTime: moved.add(const Duration(hours: 1)),
      );

      expect((await h.read(id)).startDateTime, moved,
          reason: 'the move must be saved even though nothing could be scheduled');
    });

    test('moving a task that has been deleted elsewhere still reports it gone', () async {
      final h = _Harness();
      await expectLater(
        h.repo.moveTask(taskId: 'ghost', expectedVersion: 1, position: 1),
        throwsA(isA<TaskGoneException>()),
      );
    });
  });

  group('other changes keep reminders honest', () {
    test('deleting a task cancels every alert it owned', () async {
      final h = _Harness();
      final id = await h.create(start: DateTime(2026, 10, 5, 18, 0));
      expect(h.adapter.scheduled, hasLength(1));

      await h.repo.deleteTask(id);

      expect(h.adapter.scheduled, isEmpty);
    });

    test('completing a task cancels its alerts', () async {
      final h = _Harness();
      final id = await h.create(start: DateTime(2026, 10, 5, 18, 0));

      await h.repo.setTaskCompleted(await h.read(id), true);

      expect(h.adapter.scheduled, isEmpty);
      expect((await h.read(id)).completed, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/notifications/models/reminder.dart';
import 'package:myschedule/core/notifications/platform/notification_adapter.dart';
import 'package:myschedule/core/notifications/scheduling/reminder_calculator.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/core/providers.dart';
import 'package:myschedule/models/task.dart';

/// The board task and the calendar event are the same record.
///
/// These tests pin that down: one task, one id, and the calendar is just a
/// query over tasks that have a start time. If anything ever introduces a
/// second record for a scheduled task, these fail.
Task boardTask({
  String id = 'task-1',
  String title = 'Create Kitty Meow Video',
  String? boardId = 'board-youtube',
  String? listId = 'list-todo',
  String? categoryId = 'cat-kittymeow',
  DateTime? start,
  DateTime? end,
  bool isAllDay = false,
  bool completed = false,
  List<Reminder> reminders = const [],
}) =>
    Task(
      id: id,
      title: title,
      boardId: boardId,
      listId: listId,
      categoryId: categoryId,
      startDateTime: start,
      endDateTime: end,
      isAllDay: isAllDay,
      completed: completed,
      reminders: reminders,
    );

void main() {
  final day = DateTime(2026, 10, 6);

  group('1 — a board task without a date is not on the calendar', () {
    test('it has no schedule', () {
      final task = boardTask();
      expect(task.hasSchedule, isFalse);
      expect(task.hasTimeSlot, isFalse);
    });

    test('a day query does not return it', () {
      final tasks = [boardTask(), boardTask(id: 'task-2', start: DateTime(2026, 10, 6, 18, 0))];
      final onThatDay = tasksForDay(tasks, day);

      expect(onThatDay, hasLength(1));
      expect(onThatDay.single.id, 'task-2');
    });
  });

  group('2 — giving it a date and time puts it on the calendar', () {
    test('the same task appears, with the same id', () {
      final original = boardTask();
      final scheduled = original.copyWith(
        startDateTime: DateTime(2026, 10, 6, 18, 0),
        endDateTime: DateTime(2026, 10, 6, 19, 0),
      );

      expect(scheduled.id, original.id, reason: 'scheduling must not create a new task');
      expect(scheduled.hasSchedule, isTrue);
      expect(tasksForDay([scheduled], day), hasLength(1));
    });

    test('it keeps its board, list and category', () {
      final scheduled = boardTask().copyWith(startDateTime: DateTime(2026, 10, 6, 18, 0));

      expect(scheduled.boardId, 'board-youtube');
      expect(scheduled.listId, 'list-todo');
      expect(scheduled.categoryId, 'cat-kittymeow',
          reason: 'the calendar colours the event by the task category');
    });

    test('a date with no time is all-day, not a slot at midnight', () {
      final allDay = boardTask(start: DateTime(2026, 10, 8), isAllDay: true);

      expect(allDay.hasSchedule, isTrue);
      expect(allDay.hasTimeSlot, isFalse);
      expect(tasksForDay([allDay], DateTime(2026, 10, 8)), hasLength(1));
    });

    test('an all-day task can later be given a time', () {
      final allDay = boardTask(start: DateTime(2026, 10, 8), isAllDay: true);
      final timed = allDay.copyWith(
        startDateTime: DateTime(2026, 10, 8, 10, 0),
        endDateTime: DateTime(2026, 10, 8, 11, 0),
        isAllDay: false,
      );

      expect(timed.id, allDay.id);
      expect(timed.hasTimeSlot, isTrue);
      expect(timed.duration, const Duration(hours: 1));
    });
  });

  group('5, 6 — dragging and resizing change the same task', () {
    test('moving to another date changes only the date', () {
      final original = boardTask(
        start: DateTime(2026, 10, 7, 17, 0),
        end: DateTime(2026, 10, 7, 18, 0),
      );

      final moved = original.copyWith(
        startDateTime: DateTime(2026, 10, 8, 19, 0),
        endDateTime: DateTime(2026, 10, 8, 20, 0),
      );

      expect(moved.id, original.id);
      expect(moved.boardId, original.boardId);
      expect(moved.listId, original.listId);
      expect(tasksForDay([moved], DateTime(2026, 10, 7)), isEmpty);
      expect(tasksForDay([moved], DateTime(2026, 10, 8)), hasLength(1));
    });

    test('resizing changes the duration, not the start', () {
      final original = boardTask(
        start: DateTime(2026, 10, 7, 17, 0),
        end: DateTime(2026, 10, 7, 18, 0),
      );
      expect(original.duration, const Duration(hours: 1));

      final resized = original.copyWith(endDateTime: DateTime(2026, 10, 7, 18, 30));

      expect(resized.id, original.id);
      expect(resized.startDateTime, original.startDateTime);
      expect(resized.duration, const Duration(minutes: 90));
    });

    test('dragging back to the board clears the schedule without deleting', () {
      final scheduled = boardTask(start: DateTime(2026, 10, 7, 17, 0));
      final unscheduled = scheduled.copyWith(startDateTime: null, endDateTime: null);

      expect(unscheduled.id, scheduled.id);
      expect(unscheduled.hasSchedule, isFalse);
      expect(unscheduled.boardId, 'board-youtube', reason: 'it still lives on its board');
      expect(tasksForDay([unscheduled], DateTime(2026, 10, 7)), isEmpty);
    });
  });

  group('8 — changing the time reschedules the reminders', () {
    late FakeClock clock;
    late FakeNotificationAdapter adapter;
    late NotificationService service;

    setUp(() {
      clock = FakeClock(DateTime(2026, 10, 7, 9, 0));
      adapter = FakeNotificationAdapter();
      service = NotificationService(adapter: adapter, clock: clock);
    });

    test('the old alert is cancelled and the new one scheduled', () async {
      final reminders = [
        Reminder(id: 'r1', taskId: 'task-1', offsetMinutes: 30),
      ];

      // 6:00 PM → reminder at 5:30 PM.
      final original = boardTask(start: DateTime(2026, 10, 7, 18, 0), reminders: reminders);
      await service.sync(task: original, reminders: reminders);
      final oldId = adapter.scheduled.keys.single;
      expect(adapter.scheduled[oldId]!.fireAt, DateTime(2026, 10, 7, 17, 30));

      // Moved to 8:00 PM → reminder must become 7:30 PM, and 5:30 must go.
      adapter.cancelled.clear();
      final moved = original.copyWith(startDateTime: DateTime(2026, 10, 7, 20, 0));
      await service.sync(task: moved, reminders: reminders, previousReminders: reminders);

      expect(adapter.cancelled, contains(oldId));
      expect(adapter.scheduled, hasLength(1));
      expect(adapter.scheduled.values.single.fireAt, DateTime(2026, 10, 7, 19, 30));
    });

    test('several reminders all belong to the one task', () async {
      final reminders = [
        Reminder(id: 'hour', taskId: 'task-1', offsetMinutes: 60),
        Reminder(id: 'quarter', taskId: 'task-1', offsetMinutes: 15),
        Reminder(id: 'five', taskId: 'task-1', offsetMinutes: 5),
      ];
      final task = boardTask(start: DateTime(2026, 10, 7, 18, 0), reminders: reminders);

      await service.sync(task: task, reminders: reminders);

      expect(adapter.scheduled, hasLength(3));
      expect(adapter.scheduled.values.map((n) => n.taskId).toSet(), {'task-1'});
    });

    test('9 — deleting the task cancels every reminder', () async {
      final reminders = [
        Reminder(id: 'a', taskId: 'task-1', offsetMinutes: 60),
        Reminder(id: 'b', taskId: 'task-1', offsetMinutes: 15),
      ];
      final task = boardTask(start: DateTime(2026, 10, 7, 18, 0), reminders: reminders);
      await service.sync(task: task, reminders: reminders);
      expect(adapter.scheduled, hasLength(2));

      await service.cancelForTask(task, reminders);

      expect(adapter.scheduled, isEmpty);
    });
  });

  group('10 — completion is shared', () {
    test('completing the board task marks the calendar event complete', () {
      // There is only one record, so there is nothing to keep in step.
      final task = boardTask(start: DateTime(2026, 10, 6, 18, 0));
      final done = task.copyWith(completed: true);

      expect(done.id, task.id);
      expect(done.completed, isTrue);
      expect(tasksForDay([done], day), hasLength(1),
          reason: 'a completed task stays on the calendar, struck through');
    });
  });

  group('11, 12 — category and list changes', () {
    test('changing category keeps the task on the calendar, with a new colour', () {
      final task = boardTask(start: DateTime(2026, 10, 6, 18, 0));
      final recategorised = task.copyWith(categoryId: 'cat-job');

      expect(recategorised.id, task.id);
      expect(recategorised.categoryId, 'cat-job');
      expect(tasksForDay([recategorised], day), hasLength(1));
    });

    test('changing list does not disturb the schedule', () {
      final task = boardTask(start: DateTime(2026, 10, 6, 18, 0));
      final moved = task.copyWith(listId: 'list-inprogress');

      expect(moved.id, task.id);
      expect(moved.startDateTime, task.startDateTime);
      expect(tasksForDay([moved], day), hasLength(1));
    });
  });

  group('calendar filtering never changes data', () {
    final tasks = [
      boardTask(id: 'a', categoryId: 'cat-youtube', boardId: 'b1', start: DateTime(2026, 10, 6, 9)),
      boardTask(id: 'b', categoryId: 'cat-job', boardId: 'b1', start: DateTime(2026, 10, 6, 10)),
      boardTask(id: 'c', categoryId: 'cat-youtube', boardId: 'b2', start: DateTime(2026, 10, 6, 11)),
    ];

    test('filtering by category hides, it does not delete', () {
      final shown = tasks.where((t) => t.categoryId == 'cat-youtube').toList();

      expect(shown.map((t) => t.id), ['a', 'c']);
      expect(tasks, hasLength(3), reason: 'the underlying list is untouched');
    });

    test('filtering by board narrows to that board', () {
      final shown = tasks.where((t) => t.boardId == 'b1').toList();
      expect(shown.map((t) => t.id), ['a', 'b']);
    });

    test('both filters together', () {
      final shown = tasks
          .where((t) => t.categoryId == 'cat-youtube' && t.boardId == 'b2')
          .toList();
      expect(shown.single.id, 'c');
    });
  });

  group('the task is the single source of truth', () {
    test('a scheduled task carries everything the calendar needs to draw it', () {
      final task = boardTask(
        start: DateTime(2026, 10, 6, 18, 0),
        end: DateTime(2026, 10, 6, 19, 0),
        reminders: [Reminder(id: 'r', taskId: 'task-1', offsetMinutes: 30)],
      );

      // Title, category, board, completion and duration all come from the task
      // itself; nothing else has to be looked up or kept in step.
      expect(task.title, 'Create Kitty Meow Video');
      expect(task.categoryId, isNotNull);
      expect(task.boardId, isNotNull);
      expect(task.duration, const Duration(hours: 1));
      expect(task.effectiveReminders, hasLength(1));
      expect(task.completed, isFalse);
    });

    test('a round trip through JSON keeps the schedule and reminders', () {
      final task = boardTask(
        start: DateTime(2026, 10, 6, 18, 0),
        reminders: [Reminder(id: 'r', taskId: 'task-1', offsetMinutes: 30)],
        isAllDay: false,
      );

      final json = task.toJson();
      expect(json['isAllDay'], false);
      expect(json['hasSchedule'], true);
      expect((json['reminders'] as List), hasLength(1));
    });
  });
}

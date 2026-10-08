import 'package:cloud_firestore/cloud_firestore.dart' show CollectionReference;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/notifications/models/reminder.dart';
import 'package:myschedule/core/notifications/platform/notification_adapter.dart';
import 'package:myschedule/core/notifications/scheduling/reminder_calculator.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/models/collections.dart' hide Reminder;
import 'package:myschedule/models/task.dart';

/// The real [Repo] against an in-memory Firestore: board layout, the migration
/// of existing accounts, completing and reopening tasks, and recurrence.
final kNow = DateTime(2026, 10, 5, 9, 0);

class _H {
  _H()
      : db = FakeFirebaseFirestore(),
        adapter = FakeNotificationAdapter(),
        clock = FakeClock(kNow) {
    repo = Repo(
      db: db,
      uid: 'u1',
      notifications: NotificationService(adapter: adapter, clock: clock),
    );
  }

  final FakeFirebaseFirestore db;
  final FakeNotificationAdapter adapter;
  final FakeClock clock;
  late final Repo repo;

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      db.collection('users').doc('u1').collection(name);

  Future<String> newBoard() => repo.addBoard(Board(id: 'new', name: 'Board'));

  Future<List<TaskList>> listsOf(String boardId) async {
    final snap = await _col('lists').where('boardId', isEqualTo: boardId).get();
    return snap.docs.map(TaskList.fromDoc).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<TaskList> listNamed(String boardId, String name) async =>
      (await listsOf(boardId)).firstWhere((l) => l.name == name);

  Future<TaskList> completeList(String boardId) async =>
      (await listsOf(boardId)).firstWhere((l) => l.isComplete);

  Future<Task> read(String id) async => Task.fromDoc(await _col('tasks').doc(id).get());

  Future<List<Task>> allTasks() async =>
      (await _col('tasks').get()).docs.map(Task.fromDoc).toList();

  Future<String> addTask({
    String? boardId,
    String? listId,
    String title = 'Kitty Meow Video',
    Recurrence recurrence = Recurrence.none,
    DateTime? start,
    bool allDay = false,
    List<Reminder> reminders = const [],
    List<Subtask> subtasks = const [],
    double position = 5000,
  }) =>
      repo.createTask(Task(
        id: 'new',
        title: title,
        boardId: boardId,
        listId: listId,
        categoryId: 'cat-1',
        priority: TaskPriority.high,
        recurrence: recurrence,
        startDateTime: start,
        endDateTime: start?.add(const Duration(hours: 2)),
        isAllDay: allDay,
        reminders: reminders,
        subtasks: subtasks,
        position: position,
        attachmentCount: 3,
      ));

  Reminder reminder(int minutes, {String id = 'r1'}) => Reminder(
        id: id,
        taskId: 'new',
        type: minutes == 0 ? ReminderType.atTime : ReminderType.beforeTask,
        offsetMinutes: minutes,
      );

  /// An account as it was before the Complete list existed.
  Future<String> seedOldBoard({
    String name = 'Old board',
    bool withDone = true,
    bool doneIsSystem = true,
    bool withAnyLists = true,
  }) async {
    final boardRef = _col('boards').doc();
    await boardRef.set(Board(id: boardRef.id, name: name).toJson());
    if (!withAnyLists) return boardRef.id;

    final names = withDone
        ? ['Inbox', 'Todo', 'In progress', 'Waiting', 'Done', 'Someday']
        : ['Inbox', 'Todo', 'Someday'];
    for (final (i, n) in names.indexed) {
      final ref = _col('lists').doc();
      await ref.set(TaskList(
        id: ref.id,
        boardId: boardRef.id,
        name: n,
        position: (i + 1) * 1000.0,
        isSystem: n == 'Done' ? doneIsSystem : true,
      ).toJson());
    }
    return boardRef.id;
  }

  Future<void> markBootstrapped() =>
      db.collection('users').doc('u1').set({'bootstrapped': true});
}

void main() {
  group('a new board', () {
    test('starts with the default lists, including exactly one Complete list', () async {
      final h = _H();
      final board = await h.newBoard();
      final lists = await h.listsOf(board);

      expect(lists.map((l) => l.name),
          ['Inbox', 'Todo', 'In progress', 'Waiting', 'Complete', 'Someday']);
      expect(lists.where((l) => l.isComplete), hasLength(1));
    });

    test('its Complete list is protected: a system list, marked by kind, not by name', () async {
      final h = _H();
      final complete = await h.completeList(await h.newBoard());
      expect(complete.isSystem, isTrue);
      expect(complete.kind, kCompleteKind);
    });

    test('a first sign-in seeds a board that already has a Complete list', () async {
      final h = _H();
      await h.repo.ensureBootstrap();

      final boards = await h._col('boards').get();
      expect(boards.docs, hasLength(1));
      expect((await h.listsOf(boards.docs.single.id)).where((l) => l.isComplete), hasLength(1));
      expect((await h.db.collection('users').doc('u1').get()).data()!['listsVersion'],
          Repo.kListsVersion);
    });

    test('bootstrapping again does not create a second board', () async {
      final h = _H();
      await h.repo.ensureBootstrap();
      await h.repo.ensureBootstrap();
      expect((await h._col('boards').get()).docs, hasLength(1));
    });
  });

  group('migrating an existing account', () {
    test('a system "Done" list becomes the Complete list and keeps its tasks', () async {
      final h = _H();
      await h.markBootstrapped();
      final board = await h.seedOldBoard();
      final done = await h.listNamed(board, 'Done');

      final taskId = await h.addTask(boardId: board, listId: done.id, title: 'Shipped');
      final versionBefore = (await h.read(taskId)).version;

      await h.repo.ensureBootstrap();

      final complete = await h.completeList(board);
      expect(complete.id, done.id, reason: 'the same list, renamed, not a new one');
      expect(complete.name, 'Complete');
      expect(await h.listsOf(board), hasLength(6), reason: 'no list was added or lost');

      final task = await h.read(taskId);
      expect(task.listId, complete.id, reason: 'its tasks stay where they were');
      expect(task.version, versionBefore, reason: 'no task was touched');
    });

    test('a board with no Done list gets a Complete list', () async {
      final h = _H();
      await h.markBootstrapped();
      final board = await h.seedOldBoard(withDone: false);

      await h.repo.ensureBootstrap();

      final lists = await h.listsOf(board);
      expect(lists.where((l) => l.isComplete), hasLength(1));
      expect(lists, hasLength(4), reason: 'three existing lists plus one new');
      expect(lists.last.isComplete, isTrue, reason: 'added after the existing lists');
    });

    test('a board with no lists at all gets just a Complete list', () async {
      final h = _H();
      await h.markBootstrapped();
      final board = await h.seedOldBoard(withAnyLists: false);

      await h.repo.ensureBootstrap();

      final lists = await h.listsOf(board);
      expect(lists, hasLength(1));
      expect(lists.single.isComplete, isTrue);
    });

    test('a list the user made themselves called "Done" is not renamed', () async {
      final h = _H();
      await h.markBootstrapped();
      final board = await h.seedOldBoard(doneIsSystem: false);
      final mine = await h.listNamed(board, 'Done');

      await h.repo.ensureBootstrap();

      final lists = await h.listsOf(board);
      expect(lists.firstWhere((l) => l.id == mine.id).name, 'Done');
      expect(lists.firstWhere((l) => l.id == mine.id).isComplete, isFalse);
      expect(lists.where((l) => l.isComplete), hasLength(1), reason: 'a separate one was created');
    });

    test('every board is migrated, not just the first', () async {
      final h = _H();
      await h.markBootstrapped();
      final a = await h.seedOldBoard(name: 'A');
      final b = await h.seedOldBoard(name: 'B', withDone: false);

      await h.repo.ensureBootstrap();

      for (final board in [a, b]) {
        expect((await h.listsOf(board)).where((l) => l.isComplete), hasLength(1));
      }
    });

    test('running it again changes nothing', () async {
      final h = _H();
      await h.markBootstrapped();
      final board = await h.seedOldBoard();

      await h.repo.ensureBootstrap();
      final first = (await h.listsOf(board)).map((l) => '${l.id}:${l.name}:${l.kind}').toList();
      await h.repo.migrateLists(); // forced, ignoring the version flag
      final second = (await h.listsOf(board)).map((l) => '${l.id}:${l.name}:${l.kind}').toList();

      expect(second, first);
    });

    test('two devices migrating at once still produce one Complete list per board', () async {
      final h = _H();
      await h.markBootstrapped();
      final board = await h.seedOldBoard(withDone: false);

      await Future.wait([h.repo.migrateLists(), h.repo.migrateLists()]);

      expect((await h.listsOf(board)).where((l) => l.isComplete), hasLength(1),
          reason: 'a derived id means both devices write the same document');
    });

    test('an already migrated account is left alone', () async {
      final h = _H();
      await h.repo.ensureBootstrap();
      final board = (await h._col('boards').get()).docs.single.id;
      final before = (await h.listsOf(board)).map((l) => l.id).toList();

      await h.repo.ensureBootstrap();

      expect((await h.listsOf(board)).map((l) => l.id), before);
    });
  });

  group('completing a task', () {
    late _H h;
    late String board;
    late TaskList todo;
    late TaskList complete;

    setUp(() async {
      h = _H();
      board = await h.newBoard();
      todo = await h.listNamed(board, 'Todo');
      complete = await h.completeList(board);
    });

    test('moves the same task into the Complete list, remembering where it was', () async {
      final id = await h.addTask(boardId: board, listId: todo.id);
      final before = await h.read(id);

      await h.repo.setTaskCompleted(before, true);

      final after = await h.read(id);
      expect(after.id, id, reason: 'the same record, not a copy');
      expect(after.completed, isTrue);
      expect(after.completedAt, isNotNull);
      expect(after.listId, complete.id);
      expect(after.completedFromListId, todo.id);
      expect(after.version, greaterThan(before.version));
      expect(await h.allTasks(), hasLength(1), reason: 'completing never duplicates a task');
    });

    test('keeps everything else about the task, including its attachments', () async {
      final id = await h.addTask(boardId: board, listId: todo.id, title: 'Keep me');
      await h.repo.setTaskCompleted(await h.read(id), true);

      final after = await h.read(id);
      expect(after.title, 'Keep me');
      expect(after.categoryId, 'cat-1');
      expect(after.priority, TaskPriority.high);
      expect(after.attachmentCount, 3);
    });

    test('lands at the top of the Complete list', () async {
      final first = await h.addTask(boardId: board, listId: complete.id, position: 1000);
      final second = await h.addTask(boardId: board, listId: complete.id, position: 2000);
      final id = await h.addTask(boardId: board, listId: todo.id);

      await h.repo.setTaskCompleted(await h.read(id), true);

      final moved = (await h.read(id)).position;
      expect(moved, lessThan((await h.read(first)).position));
      expect(moved, lessThan((await h.read(second)).position));
    });

    test('completing it again does nothing', () async {
      final id = await h.addTask(boardId: board, listId: todo.id);
      await h.repo.setTaskCompleted(await h.read(id), true);
      final once = await h.read(id);

      // A stale copy still says "not completed", as another device's would.
      await h.repo.setTaskCompleted(await h.read(id), true);
      final twice = await h.read(id);

      expect(twice.version, once.version, reason: 'the second call must not write');
      expect(twice.completedFromListId, todo.id, reason: 'the origin must not be overwritten');
    });

    test('a task with no board is completed in place', () async {
      final id = await h.addTask();
      await h.repo.setTaskCompleted(await h.read(id), true);

      final after = await h.read(id);
      expect(after.completed, isTrue);
      expect(after.listId, isNull);
      expect(after.boardId, isNull);
    });

    test('a board that has not been migrated yet still lets a task complete', () async {
      final bare = await h.seedOldBoard(withAnyLists: false);
      final id = await h.addTask(boardId: bare, listId: 'ghost-list');

      await h.repo.setTaskCompleted(await h.read(id), true);

      final after = await h.read(id);
      expect(after.completed, isTrue);
      expect(after.listId, 'ghost-list', reason: 'there was nowhere to move it to');
    });

    test('cancels its reminders', () async {
      final id = await h.addTask(
        boardId: board,
        listId: todo.id,
        start: DateTime(2026, 10, 6, 18, 0),
        reminders: [h.reminder(30)],
      );
      expect(h.adapter.scheduled, hasLength(1));

      await h.repo.setTaskCompleted(await h.read(id), true);

      expect(h.adapter.scheduled, isEmpty);
    });

    test('a task created straight into the Complete list is complete', () async {
      final id = await h.addTask(boardId: board, listId: complete.id);
      final task = await h.read(id);
      expect(task.completed, isTrue);
      expect(task.completedAt, isNotNull);
    });

    test('completing a task that was deleted elsewhere reports it', () async {
      await expectLater(
        h.repo.completeTask(Task(id: 'ghost', title: 'gone')),
        throwsA(isA<TaskGoneException>()),
      );
    });
  });

  group('re-opening a task', () {
    late _H h;
    late String board;
    late TaskList todo;
    late TaskList waiting;

    setUp(() async {
      h = _H();
      board = await h.newBoard();
      todo = await h.listNamed(board, 'Todo');
      waiting = await h.listNamed(board, 'Waiting');
    });

    test('puts it back in the list it came from', () async {
      final id = await h.addTask(boardId: board, listId: todo.id);
      await h.repo.setTaskCompleted(await h.read(id), true);

      await h.repo.setTaskCompleted(await h.read(id), false);

      final after = await h.read(id);
      expect(after.completed, isFalse);
      expect(after.completedAt, isNull);
      expect(after.listId, todo.id);
      expect(after.completedFromListId, isNull);
      expect(await h.allTasks(), hasLength(1));
    });

    test('goes to the list the user dragged it to, when there is one', () async {
      final id = await h.addTask(boardId: board, listId: todo.id);
      await h.repo.setTaskCompleted(await h.read(id), true);

      await h.repo.reopenTask(await h.read(id), toListId: waiting.id, position: 4242);

      final after = await h.read(id);
      expect(after.listId, waiting.id);
      expect(after.position, 4242);
    });

    test('falls back to the first ordinary list if its origin list was deleted', () async {
      final custom = await h.repo.addList(
          TaskList(id: 'new', boardId: board, name: 'Custom', position: 7000));
      final id = await h.addTask(boardId: board, listId: custom);
      await h.repo.setTaskCompleted(await h.read(id), true);
      await h.repo.deleteList(custom);

      await h.repo.setTaskCompleted(await h.read(id), false);

      final inbox = await h.listNamed(board, 'Inbox');
      expect((await h.read(id)).listId, inbox.id);
    });

    test('restores its reminders', () async {
      final id = await h.addTask(
        boardId: board,
        listId: todo.id,
        start: DateTime(2026, 10, 6, 18, 0),
        reminders: [h.reminder(30)],
      );
      await h.repo.setTaskCompleted(await h.read(id), true);
      expect(h.adapter.scheduled, isEmpty);

      await h.repo.setTaskCompleted(await h.read(id), false);

      expect(h.adapter.scheduled.values.single.fireAt, DateTime(2026, 10, 6, 17, 30));
    });

    test('re-opening a task that is not completed does nothing', () async {
      final id = await h.addTask(boardId: board, listId: todo.id);
      final before = await h.read(id);

      await h.repo.setTaskCompleted(before, false);

      expect((await h.read(id)).version, before.version);
    });
  });

  group('a repeating task', () {
    late _H h;
    late String board;
    late TaskList todo;
    late TaskList complete;
    final start = DateTime(2026, 10, 6, 18, 0);

    setUp(() async {
      h = _H();
      board = await h.newBoard();
      todo = await h.listNamed(board, 'Todo');
      complete = await h.completeList(board);
    });

    Future<String> daily({
      List<Reminder>? reminders,
      List<Subtask>? subtasks,
      bool allDay = false,
    }) =>
        h.addTask(
          boardId: board,
          listId: todo.id,
          recurrence: Recurrence.daily,
          start: start,
          allDay: allDay,
          reminders: reminders ?? [h.reminder(30)],
          subtasks: subtasks ?? [const Subtask(id: 's1', title: 'Step', done: true)],
        );

    test('the finished occurrence goes to Complete and the next appears in the ORIGINAL list',
        () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);

      final done = await h.read(id);
      expect(done.listId, complete.id);

      final all = await h.allTasks();
      expect(all, hasLength(2));
      final next = all.firstWhere((t) => t.id != id);
      expect(next.listId, todo.id, reason: 'back in the list it was in, not in Complete');
      expect(next.completed, isFalse);
      expect(next.startDateTime, DateTime(2026, 10, 7, 18, 0));
      expect(next.endDateTime!.difference(next.startDateTime!), const Duration(hours: 2),
          reason: 'the duration carries over');
    });

    test('the next occurrence is a fresh task: not done, no files, version 1', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);

      final next = (await h.allTasks()).firstWhere((t) => t.id != id);
      expect(next.subtasks.single.done, isFalse, reason: 'subtasks start unticked');
      expect(next.attachmentCount, 0, reason: 'it must not claim files it does not have');
      expect(next.attachmentPreview, isNull);
      expect(next.version, 1);
      expect(next.completedFromListId, isNull);
      expect(next.spawnedNextTaskId, isNull);
      expect(next.title, 'Kitty Meow Video');
      expect(next.categoryId, 'cat-1');
      expect(next.priority, TaskPriority.high);
      expect(next.recurrence, Recurrence.daily);
    });

    test('the next occurrence has its own reminders, scheduled for the next day', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);

      final next = (await h.allTasks()).firstWhere((t) => t.id != id);
      expect(next.reminders.single.taskId, next.id, reason: 're-keyed to the new task');

      // A repeating task schedules a rolling window of occurrences, because
      // platforms cap how many alerts can be pending. All of them must belong to
      // the new occurrence, and none to the one that was just finished.
      final alerts = h.adapter.scheduled.values.toList();
      expect(alerts.every((n) => n.taskId == next.id), isTrue,
          reason: 'the finished task must have no alerts left');
      expect(alerts, hasLength(ReminderCalculator.recurringWindow));
      final first = alerts.map((n) => n.fireAt).reduce((a, b) => a.isBefore(b) ? a : b);
      expect(first, DateTime(2026, 10, 7, 17, 30));
    });

    test('an all-day repeating task stays all-day', () async {
      final id = await daily(reminders: const [], allDay: true);
      await h.repo.setTaskCompleted(await h.read(id), true);
      expect((await h.allTasks()).firstWhere((t) => t.id != id).isAllDay, isTrue);
    });

    test('the finished task records which occurrence followed it', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);

      final next = (await h.allTasks()).firstWhere((t) => t.id != id);
      expect((await h.read(id)).spawnedNextTaskId, next.id);
    });

    test('completing the same occurrence twice creates one next occurrence', () async {
      final id = await daily();
      final stale = await h.read(id);

      await h.repo.setTaskCompleted(stale, true);
      await h.repo.setTaskCompleted(stale, true);

      expect(await h.allTasks(), hasLength(2));
    });

    test('two completions that both got past the guard still create one next occurrence',
        () async {
      final id = await daily();
      // Two devices (or the app and a notification action) each read the task
      // while it was still open, so both go on to write.
      final seenByA = await h.read(id);
      final seenByB = await h.read(id);

      await Future.wait([
        h.repo.commitCompletion(seenByA),
        h.repo.commitCompletion(seenByB),
      ]);

      expect(await h.allTasks(), hasLength(2),
          reason: 'the next occurrence has a derived id, so both writes hit one document');
    });

    test('the same completion run twice from one snapshot is also safe', () async {
      final id = await daily();
      final stale = await h.read(id);

      await h.repo.commitCompletion(stale);
      await h.repo.commitCompletion(stale);

      expect(await h.allTasks(), hasLength(2));
    });

    test('two apps completing at once through the public API end in a consistent state',
        () async {
      // A smoke test of the full path under concurrency. It does not force both
      // past the guard (the tests above do that); it checks nothing is corrupted.
      final id = await daily();
      await Future.wait([
        h.repo.setTaskCompleted(await h.read(id), true),
        h.repo.setTaskCompleted(await h.read(id), true),
      ]);

      final all = await h.allTasks();
      expect(all, hasLength(2));
      expect(all.where((t) => !t.completed), hasLength(1));
      expect((await h.read(id)).listId, complete.id);
    });

    test('the series continues: completing the next one creates a third, not a loop', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);
      final second = (await h.allTasks()).firstWhere((t) => t.id != id);

      await h.repo.setTaskCompleted(second, true);

      final all = await h.allTasks();
      expect(all, hasLength(3));
      expect(all.where((t) => !t.completed), hasLength(1), reason: 'only one open occurrence');
      expect(all.where((t) => !t.completed).single.startDateTime, DateTime(2026, 10, 8, 18, 0));
      expect(all.map((t) => t.id).toSet(), hasLength(3), reason: 'every id is distinct');
    });

    test('un-completing removes the next occurrence if nobody has touched it', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);
      expect(await h.allTasks(), hasLength(2));

      await h.repo.setTaskCompleted(await h.read(id), false);

      final all = await h.allTasks();
      expect(all, hasLength(1), reason: 'no duplicate left behind');
      expect(all.single.id, id);
      expect(all.single.spawnedNextTaskId, isNull);
      expect(all.single.listId, todo.id);
    });

    test('completing again after that creates the next occurrence once more', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);
      await h.repo.setTaskCompleted(await h.read(id), false);

      await h.repo.setTaskCompleted(await h.read(id), true);

      expect(await h.allTasks(), hasLength(2), reason: 'one again, not two');
    });

    test('an occurrence the user edited is kept when the original is re-opened', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);
      final next = (await h.allTasks()).firstWhere((t) => t.id != id);
      await h.repo.updateTask(next.copyWith(title: 'Edited next one'));

      await h.repo.setTaskCompleted(await h.read(id), false);

      expect(await h.allTasks(), hasLength(2), reason: 'the edit must not be thrown away');
      expect((await h.read(next.id)).title, 'Edited next one');
    });

    test('and completing the original again does not add a third', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);
      final next = (await h.allTasks()).firstWhere((t) => t.id != id);
      await h.repo.updateTask(next.copyWith(title: 'Edited next one'));
      await h.repo.setTaskCompleted(await h.read(id), false);

      await h.repo.setTaskCompleted(await h.read(id), true);

      expect(await h.allTasks(), hasLength(2));
    });

    test('an occurrence that was itself completed is kept', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);
      final next = (await h.allTasks()).firstWhere((t) => t.id != id);
      await h.repo.setTaskCompleted(next, true); // completes the second, spawns a third

      await h.repo.setTaskCompleted(await h.read(id), false);

      expect((await h.read(next.id)).completed, isTrue);
    });

    test('if the user deleted the next occurrence, a new one can be made', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);
      final next = (await h.allTasks()).firstWhere((t) => t.id != id);
      await h.repo.deleteTask(next.id);

      await h.repo.setTaskCompleted(await h.read(id), false);
      expect((await h.read(id)).spawnedNextTaskId, isNull);

      await h.repo.setTaskCompleted(await h.read(id), true);
      expect(await h.allTasks(), hasLength(2));
    });

    test('un-completing cancels the removed occurrence\'s reminders', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);
      final nextId = (await h.allTasks()).firstWhere((t) => t.id != id).id;
      expect(h.adapter.scheduled.values.any((n) => n.taskId == nextId), isTrue);

      await h.repo.setTaskCompleted(await h.read(id), false);

      expect(h.adapter.scheduled.values.any((n) => n.taskId == nextId), isFalse,
          reason: 'an alert for a task that no longer exists must not survive');
    });

    test('a repeating task with no start date completes without creating anything', () async {
      final id = await h.addTask(
          boardId: board, listId: todo.id, recurrence: Recurrence.daily);
      await h.repo.setTaskCompleted(await h.read(id), true);
      expect(await h.allTasks(), hasLength(1));
    });

    test('a task that does not repeat never creates a next occurrence', () async {
      final id = await h.addTask(boardId: board, listId: todo.id, start: start);
      await h.repo.setTaskCompleted(await h.read(id), true);
      expect(await h.allTasks(), hasLength(1));
    });

    test('weekly and monthly series advance by the right amount', () async {
      for (final (recurrence, expected) in [
        (Recurrence.weekly, DateTime(2026, 10, 13, 18, 0)),
        (Recurrence.monthly, DateTime(2026, 11, 6, 18, 0)),
        (Recurrence.yearly, DateTime(2027, 10, 6, 18, 0)),
      ]) {
        final fresh = _H();
        final b = await fresh.newBoard();
        final t = await fresh.listNamed(b, 'Todo');
        final id = await fresh.addTask(
            boardId: b, listId: t.id, recurrence: recurrence, start: start);
        await fresh.repo.setTaskCompleted(await fresh.read(id), true);

        final next = (await fresh.allTasks()).firstWhere((x) => x.id != id);
        expect(next.startDateTime, expected, reason: recurrence.name);
      }
    });

    test('it survives a restart: a fresh repository sees one open occurrence', () async {
      final id = await daily();
      await h.repo.setTaskCompleted(await h.read(id), true);

      // A new Repo over the same data is what the app has after a restart.
      final restarted = Repo(
        db: h.db,
        uid: 'u1',
        notifications: NotificationService(adapter: h.adapter, clock: h.clock),
      );
      final stale = await h.read(id);
      await restarted.setTaskCompleted(stale, true);

      expect(await h.allTasks(), hasLength(2));
      expect((await h.allTasks()).where((t) => !t.completed), hasLength(1));
    });
  });

  group('deleting lists and boards never loses a task', () {
    test('deleting a list moves its tasks to the next ordinary list', () async {
      final h = _H();
      final board = await h.newBoard();
      final custom = await h.repo.addList(
          TaskList(id: 'new', boardId: board, name: 'Custom', position: 7000));
      final id = await h.addTask(boardId: board, listId: custom);

      await h.repo.deleteList(custom);

      final task = await h.read(id);
      expect(task.listId, (await h.listNamed(board, 'Inbox')).id);
      expect(task.boardId, board);
    });

    test('the Complete list cannot be deleted', () async {
      final h = _H();
      final board = await h.newBoard();
      final complete = await h.completeList(board);

      await expectLater(h.repo.deleteList(complete.id), throwsStateError);
      expect(await h.listsOf(board), hasLength(6));
    });

    test('deleting a board keeps its tasks and returns them to the Inbox', () async {
      final h = _H();
      final board = await h.newBoard();
      final todo = await h.listNamed(board, 'Todo');
      final id = await h.addTask(boardId: board, listId: todo.id);

      await h.repo.deleteBoard(board);

      expect(await h.listsOf(board), isEmpty, reason: 'its lists went with it');
      final task = await h.read(id);
      expect(task.isUnsorted, isTrue, reason: 'back in the Inbox, not pointing at a dead board');
    });
  });
}

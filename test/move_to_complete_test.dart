import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/move_controller.dart';
import 'package:myschedule/core/notifications/platform/notification_adapter.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/core/providers.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/task.dart';

/// Dropping a card on the Complete list must complete it, and dragging a
/// completed card out must re-open it, with a correct Undo for each. These run
/// the real [MoveController] against the real [Repo].
class _World {
  _World() : db = FakeFirebaseFirestore() {
    repo = Repo(
      db: db,
      uid: 'u1',
      notifications: NotificationService(adapter: FakeNotificationAdapter()),
    );
  }

  final FakeFirebaseFirestore db;
  late final Repo repo;
  late String board;
  late TaskList todo;
  late TaskList waiting;
  late TaskList complete;

  Future<void> setUp() async {
    board = await repo.addBoard(Board(id: 'new', name: 'Board'));
    final snap = await db
        .collection('users')
        .doc('u1')
        .collection('lists')
        .where('boardId', isEqualTo: board)
        .get();
    final lists = snap.docs.map(TaskList.fromDoc).toList();
    todo = lists.firstWhere((l) => l.name == 'Todo');
    waiting = lists.firstWhere((l) => l.name == 'Waiting');
    complete = lists.firstWhere((l) => l.isComplete);
  }

  Future<Task> addTask({Recurrence recurrence = Recurrence.none, DateTime? start}) async {
    final id = await repo.createTask(Task(
      id: 'new',
      title: 'Drag me',
      boardId: board,
      listId: todo.id,
      position: 5000,
      recurrence: recurrence,
      startDateTime: start,
      endDateTime: start?.add(const Duration(hours: 1)),
    ));
    return read(id);
  }

  Future<Task> read(String id) async => Task.fromDoc(
      await db.collection('users').doc('u1').collection('tasks').doc(id).get());

  Future<int> taskCount() async =>
      (await db.collection('users').doc('u1').collection('tasks').get()).docs.length;
}

typedef _Host = ({WidgetRef ref, BuildContext context});

Future<_Host> _mount(WidgetTester tester, _World w) async {
  late WidgetRef capturedRef;
  late BuildContext capturedContext;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repoProvider.overrideWithValue(w.repo),
        listsProvider.overrideWith((ref) => w.repo.watchLists()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              // Watching keeps the lists stream alive, as the board does.
              ref.watch(listsProvider);
              capturedRef = ref;
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  // Let the lists stream deliver before the controller reads it.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  return (ref: capturedRef, context: capturedContext);
}

Future<void> _drop(WidgetTester tester, _Host host, Task task, TaskMove move) async {
  await tester.runAsync(() async {
    await MoveController(host.ref).run(
      context: host.context,
      task: task,
      move: move,
      description: 'moved',
    );
  });
  await tester.pump();
}

void main() {
  testWidgets('dropping a card on the Complete list completes it, in place of a plain move',
      (tester) async {
    await tester.runAsync(() async {});
    final w = _World();
    await tester.runAsync(w.setUp);
    final task = await tester.runAsync(() => w.addTask()) as Task;
    final host = await _mount(tester, w);

    await _drop(tester, host, task, TaskMove(listId: w.complete.id, boardId: w.board, position: 100));

    final after = await tester.runAsync(() => w.read(task.id)) as Task;
    expect(after.completed, isTrue, reason: 'a plain move would have left it unfinished');
    expect(after.listId, w.complete.id);
    expect(after.completedFromListId, w.todo.id);
    expect(after.position, 100, reason: 'it lands where it was dropped');
  });

  testWidgets('Undo after completing re-opens the task rather than just moving it back',
      (tester) async {
    final w = _World();
    await tester.runAsync(w.setUp);
    final task = await tester.runAsync(() => w.addTask()) as Task;
    final host = await _mount(tester, w);

    await _drop(tester, host, task, TaskMove(listId: w.complete.id, boardId: w.board, position: 100));
    // Let the snackbar finish sliding in, or the tap lands on empty space.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('UNDO'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    // The undo runs in the test's fake-async zone but its Firestore calls need
    // real time, so alternate between the two until it has finished.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }

    final after = await tester.runAsync(() => w.read(task.id)) as Task;
    expect(after.completed, isFalse,
        reason: 'moving it back without re-opening would leave it marked completed');
    expect(after.listId, w.todo.id);
  });

  testWidgets('dragging a completed card out of Complete re-opens it in the new list',
      (tester) async {
    final w = _World();
    await tester.runAsync(w.setUp);
    final task = await tester.runAsync(() => w.addTask()) as Task;
    await tester.runAsync(() => w.repo.setTaskCompleted(task, true));
    final completed = await tester.runAsync(() => w.read(task.id)) as Task;
    final host = await _mount(tester, w);

    await _drop(tester, host, completed, TaskMove(listId: w.waiting.id, boardId: w.board, position: 777));

    final after = await tester.runAsync(() => w.read(task.id)) as Task;
    expect(after.completed, isFalse);
    expect(after.listId, w.waiting.id);
    expect(after.position, 777);
  });

  testWidgets('an ordinary move between two normal lists leaves completion alone',
      (tester) async {
    final w = _World();
    await tester.runAsync(w.setUp);
    final task = await tester.runAsync(() => w.addTask()) as Task;
    final host = await _mount(tester, w);

    await _drop(tester, host, task, TaskMove(listId: w.waiting.id, boardId: w.board, position: 900));

    final after = await tester.runAsync(() => w.read(task.id)) as Task;
    expect(after.completed, isFalse);
    expect(after.listId, w.waiting.id);
    expect(after.completedFromListId, isNull);
  });

  testWidgets('completing a repeating task by drag creates the next occurrence once',
      (tester) async {
    final w = _World();
    await tester.runAsync(w.setUp);
    final task = await tester.runAsync(
            () => w.addTask(recurrence: Recurrence.daily, start: DateTime(2030, 1, 5, 9)))
        as Task;
    final host = await _mount(tester, w);

    await _drop(tester, host, task, TaskMove(listId: w.complete.id, boardId: w.board, position: 100));

    expect(await tester.runAsync(w.taskCount), 2, reason: 'the original and exactly one next');
    final after = await tester.runAsync(() => w.read(task.id)) as Task;
    expect(after.spawnedNextTaskId, isNotNull);
  });
}

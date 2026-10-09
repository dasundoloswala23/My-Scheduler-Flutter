// Completion, the Complete list and recurrence, against the real Firebase
// project, on a real device or the Windows desktop.
//
//   flutter test integration_test/completion_device_test.dart -d ZL8325W28X
//   flutter test integration_test/completion_device_test.dart -d windows
//
// The first test runs the account migration, so it renames the test account's
// existing "Done" list to "Complete". That is the intended behaviour for every
// account, and it is idempotent: running it again changes nothing.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:myschedule/core/repository.dart';
import 'package:myschedule/firebase_options.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/task.dart';

// Credentials come from the command line, never from the repository:
//   --dart-define=MYS_TEST_EMAIL=… --dart-define=MYS_TEST_PASSWORD=…
const email = String.fromEnvironment('MYS_TEST_EMAIL');
const password = String.fromEnvironment('MYS_TEST_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Repo repo;
  late String uid;
  late String boardId;
  late TaskList todo;
  late TaskList complete;
  final created = <String>[];

  CollectionReference<Map<String, dynamic>> col(String name) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection(name);

  Future<Task> read(String id) async => Task.fromDoc(await col('tasks').doc(id).get());

  Future<List<TaskList>> listsOf(String board) async =>
      (await col('lists').where('boardId', isEqualTo: board).get())
          .docs
          .map(TaskList.fromDoc)
          .toList();

  Future<String> addTask({
    required String title,
    Recurrence recurrence = Recurrence.none,
    DateTime? start,
  }) async {
    final id = await repo.createTask(Task(
      id: 'new',
      title: title,
      description: 'Created by the completion device test',
      boardId: boardId,
      listId: todo.id,
      position: 500000,
      recurrence: recurrence,
      startDateTime: start,
      endDateTime: start?.add(const Duration(hours: 1)),
    ));
    created.add(id);
    return id;
  }

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final credential =
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    uid = credential.user!.uid;
    repo = Repo(uid: uid);
  });

  tearDownAll(() async {
    // Leave the account as it was found: remove every task this run made,
    // including the next occurrences the repeating-task tests spawned.
    final spawned = <String>{};
    for (final id in created) {
      final snap = await col('tasks').doc(id).get();
      final next = snap.data()?['spawnedNextTaskId'] as String?;
      if (next != null) spawned.add(next);
    }
    for (final id in {...created, ...spawned}) {
      await repo.deleteTask(id);
    }
  });

  testWidgets('every board on the account has exactly one Complete list after bootstrap',
      (tester) async {
    await repo.ensureBootstrap();

    final boards = (await col('boards').get()).docs;
    expect(boards, isNotEmpty);
    for (final board in boards) {
      final lists = await listsOf(board.id);
      expect(lists.where((l) => l.isComplete), hasLength(1),
          reason: 'board "${board.data()['name']}" must have one Complete list');
    }

    // Use the first board that has the lists these tests need.
    boardId = boards.first.id;
    final lists = await listsOf(boardId);
    todo = lists.firstWhere((l) => l.name == 'Todo');
    complete = lists.firstWhere((l) => l.isComplete);
    expect(complete.name, 'Complete');
  });

  testWidgets('bootstrapping again changes nothing (idempotent on the live project)',
      (tester) async {
    final before = (await listsOf(boardId)).map((l) => '${l.id}:${l.name}:${l.kind}').toSet();
    await repo.ensureBootstrap();
    await repo.migrateLists();
    final after = (await listsOf(boardId)).map((l) => '${l.id}:${l.name}:${l.kind}').toSet();
    expect(after, before);
  });

  testWidgets('completing moves the same task to Complete and reopening restores it',
      (tester) async {
    final id = await addTask(title: 'Device test — complete and reopen');
    final before = await read(id);
    final taskCountBefore = (await col('tasks').get()).docs.length;

    await repo.setTaskCompleted(before, true);

    final done = await read(id);
    expect(done.completed, isTrue);
    expect(done.listId, complete.id, reason: 'it must have moved to the Complete list');
    expect(done.completedFromListId, todo.id);
    expect(done.version, greaterThan(before.version));
    expect((await col('tasks').get()).docs.length, taskCountBefore,
        reason: 'completing must not create a second record');

    await repo.setTaskCompleted(done, false);

    final back = await read(id);
    expect(back.completed, isFalse);
    expect(back.listId, todo.id);
    expect(back.completedAt, isNull);
  });

  testWidgets('a repeating task spawns one next occurrence in the original list, even twice',
      (tester) async {
    // A whole-minute start: Firestore stores timestamps to the millisecond, so a
    // start with microseconds would read back slightly different and make an
    // exact 24 hour comparison meaningless.
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day + 2, 9, 30);
    final id = await addTask(
      title: 'Device test — daily repeat',
      recurrence: Recurrence.daily,
      start: start,
    );
    final stale = await read(id);
    final before = (await col('tasks').get()).docs.length;

    await repo.setTaskCompleted(stale, true);
    await repo.setTaskCompleted(stale, true); // a second completion from stale state

    final all = await col('tasks').get();
    expect(all.docs.length, before + 1, reason: 'exactly one next occurrence, not two');

    final done = await read(id);
    expect(done.listId, complete.id);
    expect(done.spawnedNextTaskId, isNotNull);

    final next = await read(done.spawnedNextTaskId!);
    expect(next.listId, todo.id, reason: 'the next occurrence returns to the original list');
    expect(next.completed, isFalse);
    expect(next.startDateTime, DateTime(start.year, start.month, start.day + 1, 9, 30),
        reason: 'the same wall-clock time, one calendar day on');
    expect(next.version, 1);
  });

  testWidgets('re-opening a repeating task removes its untouched next occurrence',
      (tester) async {
    final id = await addTask(
      title: 'Device test — repeat then reopen',
      recurrence: Recurrence.daily,
      start: DateTime.now().add(const Duration(days: 3)),
    );
    await repo.setTaskCompleted(await read(id), true);
    final nextId = (await read(id)).spawnedNextTaskId!;
    expect((await col('tasks').doc(nextId).get()).exists, isTrue);

    await repo.setTaskCompleted(await read(id), false);

    expect((await col('tasks').doc(nextId).get()).exists, isFalse,
        reason: 'no duplicate may be left behind');
    expect((await read(id)).spawnedNextTaskId, isNull);
  });
}

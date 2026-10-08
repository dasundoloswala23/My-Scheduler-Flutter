import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/list_order.dart';
import 'package:myschedule/core/notifications/platform/notification_adapter.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/core/preferences/app_preferences.dart';
import 'package:myschedule/core/providers.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/features/boards/board_view.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/task.dart';

TaskList _l(String id, double pos) => TaskList(id: id, boardId: 'b', name: id, position: pos);

Repo _repo(FakeFirebaseFirestore db) => Repo(
      db: db,
      uid: 'u1',
      notifications: NotificationService(adapter: FakeNotificationAdapter()),
    );

Future<List<TaskList>> _boardLists(FakeFirebaseFirestore db, String board) async {
  final snap =
      await db.collection('users/u1/lists').where('boardId', isEqualTo: board).get();
  return snap.docs.map(TaskList.fromDoc).toList()
    ..sort((a, b) => a.position.compareTo(b.position));
}

void main() {
  group('planListMove', () {
    final abc = [_l('a', 1000), _l('b', 2000), _l('c', 3000)];

    test('moving right puts the list between its new neighbours', () {
      final plan = planListMove(abc, 'a', 1)!;
      expect(plan.position, 2500);
      expect(plan.reordered.map((l) => l.id), ['b', 'a', 'c']);
    });

    test('moving left to the front goes before the first list', () {
      final plan = planListMove(abc, 'b', -1)!;
      expect(plan.position, lessThan(1000));
      expect(plan.reordered.map((l) => l.id), ['b', 'a', 'c']);
    });

    test('moving right to the end goes after the last list', () {
      final plan = planListMove(abc, 'b', 1)!;
      expect(plan.position, greaterThan(3000));
      expect(plan.reordered.map((l) => l.id), ['a', 'c', 'b']);
    });

    test('cannot move past either end or an unknown list', () {
      expect(planListMove(abc, 'a', -1), isNull);
      expect(planListMove(abc, 'c', 1), isNull);
      expect(planListMove(abc, 'zzz', 1), isNull);
    });

    test('asks for a rebalance when the neighbours are too close', () {
      final tight = [_l('a', 1), _l('b', 1.00001), _l('c', 1.00002), _l('d', 5)];
      expect(planListMove(tight, 'a', 1)!.needsRebalance, isTrue);
    });
  });

  group('Repo.moveListBy', () {
    late FakeFirebaseFirestore db;
    late Repo repo;
    late String board;

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = _repo(db);
      board = await repo.addBoard(Board(id: 'new', name: 'B'));
    });

    Future<List<String>> names() async => (await _boardLists(db, board)).map((l) => l.name).toList();

    Future<String> idOf(String name) async =>
        (await _boardLists(db, board)).firstWhere((l) => l.name == name).id;

    test('moves a list right and the order persists', () async {
      final before = await names();
      await repo.moveListBy(await idOf(before[0]), 1);
      final after = await names();
      expect(after[0], before[1]);
      expect(after[1], before[0]);
      expect(after.skip(2), before.skip(2));
    });

    test('moving left then right restores the order', () async {
      final before = await names();
      final id = await idOf(before[2]);
      await repo.moveListBy(id, -1);
      expect(await names(), isNot(before));
      await repo.moveListBy(id, 1);
      expect(await names(), before);
    });

    test('at the edge nothing changes', () async {
      final before = await names();
      await repo.moveListBy(await idOf(before.first), -1);
      await repo.moveListBy(await idOf(before.last), 1);
      expect(await names(), before);
    });

    test('many moves back and forth never lose or duplicate a list', () async {
      final before = await names();
      final id = await idOf(before[1]);
      for (var i = 0; i < 40; i++) {
        await repo.moveListBy(id, i.isEven ? 1 : -1);
      }
      final after = await names();
      expect(after.toSet(), before.toSet());
      expect(after, hasLength(before.length));
    });
  });

  group('board drop zones', () {
    testWidgets('the top zone sits above the first card and inserts at the top', (tester) async {
      final db = FakeFirebaseFirestore();
      final repo = _repo(db);
      late String board;
      late TaskList todo;
      await tester.runAsync(() async {
        board = await repo.addBoard(Board(id: 'new', name: 'B'));
        final lists = await _boardLists(db, board);
        todo = lists.firstWhere((l) => l.name == 'Todo');
        for (final (i, title) in ['First', 'Second'].indexed) {
          await repo.createTask(Task(
            id: 'new',
            title: title,
            boardId: board,
            listId: todo.id,
            position: 1000.0 * (i + 1),
          ));
        }
        await repo.createTask(Task(
          id: 'new',
          title: 'Mover',
          boardId: board,
          listId: lists.firstWhere((l) => l.name == 'Waiting').id,
          position: 1000,
        ));
      });

      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          repoProvider.overrideWithValue(repo),
          appPreferencesProvider.overrideWithValue(const AppPreferences()),
        ],
        child: MaterialApp(home: Scaffold(body: BoardView(boardId: board))),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump();
      }

      // Nothing is being dragged, so the labelled zones are collapsed.
      expect(find.text('Drop task here'), findsNothing);

      final mover = find.text('Mover');
      expect(mover, findsOneWidget);
      final gesture = await tester.startGesture(tester.getCenter(mover));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 300));

      // The drag opened the zones, and one of them is above the first card.
      final firstTop = tester.getTopLeft(find.text('First')).dy;
      final zoneYs = [
        for (final e in find.text('Drop task here').evaluate())
          tester.getCenter(find.byElementPredicate((x) => x == e)).dy
      ].where((y) => y < firstTop).toList();
      expect(zoneYs, isNotEmpty, reason: 'a zone must exist above the first card');

      final firstX = tester.getCenter(find.text('First')).dx;
      await gesture.moveTo(Offset(firstX, zoneYs.first));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 300));

      final snap = await tester.runAsync(
          () => db.collection('users/u1/tasks').where('listId', isEqualTo: todo.id).get());
      final tasks = snap!.docs.map(Task.fromDoc).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      expect(tasks.map((t) => t.title).toList(), ['Mover', 'First', 'Second']);
    });
  });
}

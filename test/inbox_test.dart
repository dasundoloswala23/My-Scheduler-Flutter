import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/providers.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/features/inbox/inbox_page.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/task.dart';

class _Repo extends Fake implements Repo {
  final completed = <String>[];

  @override
  Future<void> setTaskCompleted(Task task, bool done) async => completed.add(task.id);
}

Future<_Repo> _mount(WidgetTester tester, List<Task> tasks) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 1200);
  addTearDown(tester.view.reset);
  final repo = _Repo();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      repoProvider.overrideWithValue(repo),
      tasksProvider.overrideWithValue(AsyncData(tasks)),
      categoriesProvider.overrideWith((ref) => Stream.value(const <Category>[])),
    ],
    child: const MaterialApp(home: Scaffold(body: InboxPage())),
  ));
  await tester.pump();
  return repo;
}

void main() {
  testWidgets('shows only tasks with no board and no list', (tester) async {
    await _mount(tester, [
      const Task(id: '1', title: 'Loose thought'),
      const Task(id: '2', title: 'On a board', boardId: 'b', listId: 'l'),
      const Task(id: '3', title: 'Already done', completed: true),
    ]);
    expect(find.text('Loose thought'), findsOneWidget);
    expect(find.text('On a board'), findsNothing);
    expect(find.text('Already done'), findsNothing);
  });

  testWidgets('a task given a board and list leaves the inbox', (tester) async {
    await _mount(tester, [const Task(id: '1', title: 'Loose thought', boardId: 'b', listId: 'l')]);
    expect(find.text('Loose thought'), findsNothing);
    expect(find.text('Your inbox is empty'), findsOneWidget);
  });

  testWidgets('an empty inbox explains itself', (tester) async {
    await _mount(tester, const []);
    expect(find.text('Your inbox is empty'), findsOneWidget);
  });

  testWidgets('completing from the inbox completes that one task', (tester) async {
    final repo = await _mount(tester, [
      const Task(id: '1', title: 'A'),
      const Task(id: '2', title: 'B'),
    ]);
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pump();
    expect(repo.completed, ['1']);
  });
}

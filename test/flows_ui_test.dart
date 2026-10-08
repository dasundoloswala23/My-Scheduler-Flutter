import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/flows/flow_advisor.dart';
import 'package:myschedule/core/flows/flow_engine.dart';
import 'package:myschedule/core/flows/flow_filters.dart';
import 'package:myschedule/core/notifications/platform/notification_adapter.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/core/providers.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/features/flows/flow_create_sheet.dart';
import 'package:myschedule/features/flows/flow_detail_page.dart';
import 'package:myschedule/features/flows/flows_page.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/project_flow.dart';
import 'package:myschedule/models/task.dart';

ProjectFlow _flow(String id, String name,
        {FlowStatus status = FlowStatus.active,
        DateTime? due,
        String? board,
        String? category}) =>
    ProjectFlow(
        id: id, name: name, status: status, dueDate: due, boardId: board, categoryId: category);

FlowStage _stage(String id, String flow, double pos, {ManualStageStatus? manual}) =>
    FlowStage(id: id, flowId: flow, title: id, position: pos, manualStatus: manual);

FlowResult _eval(ProjectFlow f, List<FlowStage> stages,
        [Map<String, TaskCounts> counts = const {}]) =>
    FlowEngine.evaluate(flow: f, stages: stages, counts: counts);

void main() {
  final now = DateTime(2026, 10, 8, 12);

  group('filtering flows', () {
    final a = _flow('a', 'Launch app', due: DateTime(2026, 10, 10), board: 'b1', category: 'c1');
    final b = _flow('b', 'Website', board: 'b2');
    final c = _flow('c', 'Old project');
    final d = _flow('d', 'Shelved', status: FlowStatus.archived);

    final results = {
      'a': _eval(a, [_stage('a1', 'a', 1)]),
      'b': _eval(b, [_stage('b1', 'b', 1, manual: ManualStageStatus.blocked)]),
      'c': _eval(c, [_stage('c1', 'c', 1, manual: ManualStageStatus.completed)]),
      'd': _eval(d, [_stage('d1', 'd', 1)]),
    };
    final all = [a, b, c, d];

    List<String> run(FlowFilter f, {String q = '', String? board, String? category}) =>
        filterFlows(
          flows: all,
          results: results,
          filter: f,
          search: q,
          boardId: board,
          categoryId: category,
          now: now,
        ).map((x) => x.id).toList();

    test('All includes everything, archived too', () => expect(run(FlowFilter.all), ['a', 'b', 'c', 'd']));
    test('Active leaves out finished, and archived', () => expect(run(FlowFilter.active), ['a', 'b']));
    test('Completed', () => expect(run(FlowFilter.completed), ['c']));
    test('Blocked finds the flow with a blocked stage', () => expect(run(FlowFilter.blocked), ['b']));
    test('Due soon finds a flow due within a week', () => expect(run(FlowFilter.dueSoon), ['a']));
    test('an overdue unfinished flow is due soon', () {
      final late = _flow('late', 'Late', due: DateTime(2026, 9, 1));
      final r = filterFlows(
        flows: [late],
        results: {'late': _eval(late, [_stage('l1', 'late', 1)])},
        filter: FlowFilter.dueSoon,
        now: now,
      );
      expect(r, hasLength(1));
    });
    test('a finished flow is never due soon', () {
      final done = _flow('done', 'Done', due: DateTime(2026, 10, 9));
      final r = filterFlows(
        flows: [done],
        results: {'done': _eval(done, [_stage('x', 'done', 1, manual: ManualStageStatus.completed)])},
        filter: FlowFilter.dueSoon,
        now: now,
      );
      expect(r, isEmpty);
    });
    test('search is case-insensitive', () => expect(run(FlowFilter.all, q: 'WEB'), ['b']));
    test('board filter', () => expect(run(FlowFilter.all, board: 'b1'), ['a']));
    test('category filter', () => expect(run(FlowFilter.all, category: 'c1'), ['a']));
    test('filters combine', () => expect(run(FlowFilter.active, q: 'launch', board: 'b2'), isEmpty));
  });

  group('Flow Advisor', () {
    const advisor = TemplateFlowAdvisor();

    test('"launch my Flutter app" suggests the mobile app stages, labelled as templates',
        () async {
      final s = await advisor.suggest('I want to launch my Flutter app');
      expect(s.stages.first, 'Planning');
      expect(s.stages, contains('Google Play'));
      expect(s.source.toLowerCase(), contains('not ai'));
    });

    test('a goal that matches nothing suggests nothing instead of inventing stages', () async {
      final s = await advisor.suggest('xyzzy');
      expect(s.isEmpty, isTrue);
    });

    testWidgets('Add all returns the stages; nothing else is created', (tester) async {
      FlowSuggestion? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => result = await showDialog<FlowSuggestion>(
                context: c, builder: (_) => const FlowAdvisorDialog()),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'I want to launch my Flutter app');
      await tester.tap(find.text('Suggest stages'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not AI'), findsOneWidget);
      expect(find.textContaining('Accepting creates these stages only'), findsOneWidget);

      await tester.tap(find.text('Add all'));
      await tester.pumpAndSettle();
      expect(result!.stages, hasLength(9));
    });

    testWidgets('Customize lets a stage be removed before accepting', (tester) async {
      FlowSuggestion? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => result = await showDialog<FlowSuggestion>(
                context: c, builder: (_) => const FlowAdvisorDialog()),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'launch my flutter app');
      await tester.tap(find.text('Suggest stages'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Customize'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove stage').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use these'));
      await tester.pumpAndSettle();

      expect(result!.stages, hasLength(8));
      expect(result!.stages, isNot(contains('Planning')));
    });

    testWidgets('Cancel returns nothing', (tester) async {
      FlowSuggestion? result = const FlowSuggestion(flowName: 'x', stages: [], source: '');
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => result = await showDialog<FlowSuggestion>(
                context: c, builder: (_) => const FlowAdvisorDialog()),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('screens against a real repo', () {
    late FakeFirebaseFirestore db;
    late Repo repo;
    late String flowId;
    late String taskId;

    Future<void> mount(WidgetTester tester, Widget home) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(500, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [repoProvider.overrideWithValue(repo)],
        child: MaterialApp(home: home),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump();
      }
    }

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = Repo(
        db: db,
        uid: 'u1',
        notifications: NotificationService(adapter: FakeNotificationAdapter()),
      );
    });

    Future<void> seed(WidgetTester tester) async {
      await tester.runAsync(() async {
        final board = await repo.addBoard(Board(id: 'new', name: 'B'));
        taskId = await repo.createTask(Task(id: 'new', title: 'Write plan', boardId: board));
        flowId = await repo.flows.createFlow(
          ProjectFlow(id: 'new', name: 'Launch app', boardId: board),
          stageTitles: ['Planning', 'Building'],
        );
        final stage = (await db.collection('users/u1/flowStages').get())
            .docs
            .map(FlowStage.fromDoc)
            .firstWhere((s) => s.title == 'Planning');
        await repo.flows.linkTask(flowId: flowId, stageId: stage.id, taskId: taskId);
      });
    }

    testWidgets('the flows page lists flows with their progress and narrows by filter',
        (tester) async {
      await seed(tester);
      await mount(tester, const ProjectFlowsPage());

      expect(find.text('Launch app'), findsOneWidget);
      expect(find.text('0/2 stages'), findsOneWidget);

      await tester.tap(find.text('Completed'));
      await tester.pump();
      expect(find.text('Launch app'), findsNothing);
      expect(find.text('No flows match.'), findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.pump();
      expect(find.text('Launch app'), findsOneWidget);
    });

    testWidgets('the detail page shows the timeline and ticking the task advances it',
        (tester) async {
      await seed(tester);
      await mount(tester, FlowDetailPage(flowId: flowId));

      expect(find.text('0/2 stages complete'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('0/1 tasks'), findsOneWidget);
      expect(find.text('Write plan'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump();
      }

      expect(find.text('1/2 stages complete'), findsOneWidget);
      expect(find.text('Completed'), findsWidgets);
    });

    testWidgets('an empty account shows the empty state with a way to start', (tester) async {
      await mount(tester, const ProjectFlowsPage());
      expect(find.text('Plan a project in stages'), findsOneWidget);
      expect(find.text('New flow'), findsWidgets);
    });
  });
}

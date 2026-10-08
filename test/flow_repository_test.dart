import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/flows/flow_templates.dart';
import 'package:myschedule/core/notifications/platform/notification_adapter.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/project_flow.dart';
import 'package:myschedule/models/task.dart';

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

  Future<void> setUp() async {
    board = await repo.addBoard(Board(id: 'new', name: 'Launch'));
    final snap = await db.collection('users/u1/lists').where('boardId', isEqualTo: board).get();
    todo = snap.docs.map(TaskList.fromDoc).firstWhere((l) => l.name == 'Todo');
  }

  Future<String> task(String title, {Recurrence recurrence = Recurrence.none, DateTime? start}) =>
      repo.createTask(Task(
        id: 'new',
        title: title,
        boardId: board,
        listId: todo.id,
        position: 1000,
        recurrence: recurrence,
        startDateTime: start,
        endDateTime: start?.add(const Duration(hours: 1)),
      ));

  Future<Task> readTask(String id) async =>
      Task.fromDoc(await db.collection('users/u1/tasks').doc(id).get());

  Future<int> taskCount() async => (await db.collection('users/u1/tasks').get()).docs.length;

  Future<ProjectFlow> readFlow(String id) async =>
      ProjectFlow.fromDoc(await db.collection('users/u1/projectFlows').doc(id).get());

  Future<List<FlowStage>> stages(String flowId) async =>
      (await db.collection('users/u1/flowStages').where('flowId', isEqualTo: flowId).get())
          .docs
          .map(FlowStage.fromDoc)
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));

  Future<String> flow({
    List<String> stageTitles = const ['Plan', 'Build', 'Ship'],
    FlowMode mode = FlowMode.sequential,
  }) =>
      repo.flows.createFlow(
        ProjectFlow(id: 'new', name: 'Launch app', boardId: board, mode: mode),
        stageTitles: stageTitles,
      );
}

void main() {
  late _World w;

  setUp(() async {
    w = _World();
    await w.setUp();
  });

  group('creating flows', () {
    test('a template creates its stages and no tasks', () async {
      final tasksBefore = await w.taskCount();
      final template = flowTemplateById('mobile_app_launch')!;

      final id = await w.flow(stageTitles: template.stages);

      final stages = await w.stages(id);
      expect(stages.map((s) => s.title), [
        'Planning',
        'Development',
        'Internal QA',
        'Beta Testing',
        'Store Preparation',
        'Google Play',
        'App Store',
        'Marketing',
        'Post Launch',
      ]);
      expect(await w.taskCount(), tasksBefore, reason: 'a template never creates tasks');
    });

    test('every template has stages, except Custom which starts empty', () {
      for (final t in kFlowTemplates) {
        if (t.id == 'custom') {
          expect(t.stages, isEmpty);
        } else {
          expect(t.stages, isNotEmpty, reason: t.name);
        }
      }
      expect(kFlowTemplates.map((t) => t.name), containsAll([
        'Mobile App Launch',
        'Website Launch',
        'Client Project',
        'Product Launch',
        'YouTube Channel Launch',
        'Custom',
      ]));
    });

    test('the first stage is active at once and the flow caches it', () async {
      final id = await w.flow();
      final stages = await w.stages(id);
      final flow = await w.readFlow(id);
      expect(stages.first.state, StageState.active);
      expect(flow.currentStageId, stages.first.id);
      expect(flow.progress, 0);
    });
  });

  group('linking existing tasks', () {
    test('linking points at the real task and creates no second one', () async {
      final taskId = await w.task('Implement Google Sign-In');
      final id = await w.flow();
      final stage = (await w.stages(id))[1];
      final before = await w.taskCount();

      await w.repo.flows.linkTask(flowId: id, stageId: stage.id, taskId: taskId);

      expect(await w.taskCount(), before);
      final link = await w.db.collection('users/u1/flowTaskLinks').doc(taskId).get();
      expect(link.exists, isTrue);
      expect(link.data()!['stageId'], stage.id);
      // The task itself is untouched: same board, same list.
      final t = await w.readTask(taskId);
      expect(t.boardId, w.board);
      expect(t.listId, w.todo.id);
    });

    test('linking a task again moves it instead of linking it twice', () async {
      final taskId = await w.task('Task');
      final id = await w.flow();
      final stages = await w.stages(id);

      await w.repo.flows.linkTask(flowId: id, stageId: stages[0].id, taskId: taskId);
      await w.repo.flows.linkTask(flowId: id, stageId: stages[2].id, taskId: taskId);

      final links = await w.db.collection('users/u1/flowTaskLinks').get();
      expect(links.docs, hasLength(1));
      expect(links.docs.single.data()['stageId'], stages[2].id);
    });

    test('a stage from another flow is refused', () async {
      final taskId = await w.task('Task');
      final a = await w.flow();
      final b = await w.flow();
      final foreign = (await w.stages(b)).first;

      expect(
        () => w.repo.flows.linkTask(flowId: a, stageId: foreign.id, taskId: taskId),
        throwsStateError,
      );
    });

    test('a task that does not exist is refused', () async {
      final id = await w.flow();
      final stage = (await w.stages(id)).first;
      expect(
        () => w.repo.flows.linkTask(flowId: id, stageId: stage.id, taskId: 'ghost'),
        throwsStateError,
      );
    });

    test('unlinking leaves the task alone', () async {
      final taskId = await w.task('Task');
      final id = await w.flow();
      final stage = (await w.stages(id)).first;
      await w.repo.flows.linkTask(flowId: id, stageId: stage.id, taskId: taskId);

      await w.repo.flows.unlinkTask(taskId);

      expect((await w.db.collection('users/u1/flowTaskLinks').get()).docs, isEmpty);
      expect((await w.readTask(taskId)).title, 'Task');
    });
  });

  group('completing a linked task drives the flow', () {
    test('finishing the only task of stage 1 completes it and unlocks stage 2', () async {
      final taskId = await w.task('Write the plan');
      final id = await w.flow();
      final stages = await w.stages(id);
      await w.repo.flows.linkTask(flowId: id, stageId: stages[0].id, taskId: taskId);

      await w.repo.setTaskCompleted(await w.readTask(taskId), true);

      final after = await w.stages(id);
      expect(after[0].state, StageState.completed);
      expect(after[1].state, StageState.active);
      final flow = await w.readFlow(id);
      expect(flow.currentStageId, after[1].id);
      expect(flow.progress, closeTo(1 / 3, 1e-9));
    });

    test('re-opening the task locks stage 2 again', () async {
      final taskId = await w.task('Write the plan');
      final id = await w.flow();
      final stages = await w.stages(id);
      await w.repo.flows.linkTask(flowId: id, stageId: stages[0].id, taskId: taskId);
      await w.repo.setTaskCompleted(await w.readTask(taskId), true);

      await w.repo.setTaskCompleted(await w.readTask(taskId), false);

      final after = await w.stages(id);
      expect(after[0].state, StageState.active);
      expect(after[1].state, StageState.upcoming);
      expect((await w.readFlow(id)).progress, 0);
    });

    test('a stage with two tasks needs both', () async {
      final a = await w.task('A');
      final b = await w.task('B');
      final id = await w.flow();
      final stage = (await w.stages(id))[0];
      await w.repo.flows.linkTask(flowId: id, stageId: stage.id, taskId: a);
      await w.repo.flows.linkTask(flowId: id, stageId: stage.id, taskId: b);

      await w.repo.setTaskCompleted(await w.readTask(a), true);
      expect((await w.stages(id))[0].state, StageState.active, reason: 'one of two is not enough');

      await w.repo.setTaskCompleted(await w.readTask(b), true);
      expect((await w.stages(id))[0].state, StageState.completed);
    });

    test('finishing every stage completes the flow', () async {
      final id = await w.flow(stageTitles: ['One', 'Two']);
      final stages = await w.stages(id);
      for (final s in stages) {
        final t = await w.task('Task for ${s.title}');
        await w.repo.flows.linkTask(flowId: id, stageId: s.id, taskId: t);
        await w.repo.setTaskCompleted(await w.readTask(t), true);
      }

      final flow = await w.readFlow(id);
      expect(flow.status, FlowStatus.completed);
      expect(flow.completedAt, isNotNull);
      expect(flow.progress, 1);
    });

    test('deleting a linked task unlinks it and the stage counts what is left', () async {
      final a = await w.task('A');
      final b = await w.task('B');
      final id = await w.flow();
      final stage = (await w.stages(id))[0];
      await w.repo.flows.linkTask(flowId: id, stageId: stage.id, taskId: a);
      await w.repo.flows.linkTask(flowId: id, stageId: stage.id, taskId: b);
      await w.repo.setTaskCompleted(await w.readTask(a), true);

      await w.repo.deleteTask(b);

      expect((await w.db.collection('users/u1/flowTaskLinks').doc(b).get()).exists, isFalse);
      expect((await w.stages(id))[0].state, StageState.completed,
          reason: 'its only remaining task is done');
    });

    test('completing a repeating linked task completes its stage; the next one is not linked',
        () async {
      final taskId = await w.task('Weekly report',
          recurrence: Recurrence.weekly, start: DateTime(2030, 1, 7, 9));
      final id = await w.flow(stageTitles: ['Reporting', 'Wrap up']);
      final stage = (await w.stages(id))[0];
      await w.repo.flows.linkTask(flowId: id, stageId: stage.id, taskId: taskId);

      await w.repo.setTaskCompleted(await w.readTask(taskId), true);

      expect((await w.stages(id))[0].state, StageState.completed);
      expect((await w.db.collection('users/u1/flowTaskLinks').get()).docs, hasLength(1));
      expect(await w.taskCount(), 2, reason: 'the original and exactly one next occurrence');
    });
  });

  group('editing flows', () {
    test('a dependency cycle is refused', () async {
      final id = await w.flow(mode: FlowMode.dependency);
      final s = await w.stages(id);
      await w.repo.flows.updateStage(s[1].copyWith(dependencyStageIds: [s[0].id]));

      expect(
        () => w.repo.flows.updateStage(s[0].copyWith(dependencyStageIds: [s[1].id])),
        throwsStateError,
      );
    });

    test('dependency mode unlocks a stage only when its dependencies finish', () async {
      final id = await w.flow(mode: FlowMode.dependency, stageTitles: ['A', 'B', 'C']);
      final s = await w.stages(id);
      await w.repo.flows.updateStage(s[2].copyWith(dependencyStageIds: [s[0].id, s[1].id]));
      final ta = await w.task('ta');
      final tb = await w.task('tb');
      await w.repo.flows.linkTask(flowId: id, stageId: s[0].id, taskId: ta);
      await w.repo.flows.linkTask(flowId: id, stageId: s[1].id, taskId: tb);

      await w.repo.setTaskCompleted(await w.readTask(ta), true);
      expect((await w.stages(id))[2].state, isNot(StageState.active));

      await w.repo.setTaskCompleted(await w.readTask(tb), true);
      expect((await w.stages(id))[2].state, StageState.active);
    });

    test('deleting a stage unlinks its tasks, keeps them, and clears dependencies on it',
        () async {
      final id = await w.flow(mode: FlowMode.dependency, stageTitles: ['A', 'B']);
      final s = await w.stages(id);
      await w.repo.flows.updateStage(s[1].copyWith(dependencyStageIds: [s[0].id]));
      final t = await w.task('kept');
      await w.repo.flows.linkTask(flowId: id, stageId: s[0].id, taskId: t);

      await w.repo.flows.deleteStage(s[0]);

      expect((await w.readTask(t)).title, 'kept');
      expect((await w.db.collection('users/u1/flowTaskLinks').get()).docs, isEmpty);
      final left = await w.stages(id);
      expect(left, hasLength(1));
      expect(left.single.dependencyStageIds, isEmpty);
      expect(left.single.state, StageState.active);
    });

    test('deleting a flow removes its stages and links but never the tasks', () async {
      final t = await w.task('survivor');
      final id = await w.flow();
      await w.repo.flows.linkTask(flowId: id, stageId: (await w.stages(id)).first.id, taskId: t);

      await w.repo.flows.deleteFlow(id);

      expect((await w.db.collection('users/u1/projectFlows').get()).docs, isEmpty);
      expect((await w.db.collection('users/u1/flowStages').get()).docs, isEmpty);
      expect((await w.db.collection('users/u1/flowTaskLinks').get()).docs, isEmpty);
      expect((await w.readTask(t)).title, 'survivor');
    });

    test('pausing a flow is kept even when its stages are all done', () async {
      final id = await w.flow(stageTitles: ['Only']);
      await w.repo.flows.updateFlow((await w.readFlow(id)).copyWith(status: FlowStatus.paused));
      final t = await w.task('t');
      await w.repo.flows.linkTask(flowId: id, stageId: (await w.stages(id)).first.id, taskId: t);
      await w.repo.setTaskCompleted(await w.readTask(t), true);

      expect((await w.readFlow(id)).status, FlowStatus.paused);
    });

    test('reordering stages changes which one is first', () async {
      final id = await w.flow(stageTitles: ['A', 'B', 'C']);
      final s = await w.stages(id);

      await w.repo.flows.reorderStages(id, [s[2].id, s[0].id, s[1].id]);

      final after = await w.stages(id);
      expect(after.map((x) => x.title), ['C', 'A', 'B']);
      expect(after.first.state, StageState.active);
    });

    test('recomputing twice gives the same answer', () async {
      final id = await w.flow();
      final first = await w.repo.flows.recompute(id);
      final second = await w.repo.flows.recompute(id);
      expect(second!.progress, first!.progress);
      expect(second.currentStageId, first.currentStageId);
    });
  });
}

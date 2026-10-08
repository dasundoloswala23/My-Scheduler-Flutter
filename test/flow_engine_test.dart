import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/flows/flow_engine.dart';
import 'package:myschedule/models/project_flow.dart';

FlowStage _s(
  String id,
  double pos, {
  bool required = true,
  List<String> deps = const [],
  ManualStageStatus? manual,
  bool auto = true,
}) =>
    FlowStage(
      id: id,
      flowId: 'f',
      title: id,
      position: pos,
      isRequired: required,
      dependencyStageIds: deps,
      manualStatus: manual,
      autoCompleteWhenTasksDone: auto,
    );

ProjectFlow _flow(FlowMode mode, {FlowStatus status = FlowStatus.active}) =>
    ProjectFlow(id: 'f', name: 'Flow', mode: mode, status: status);

Map<String, StageState> _states(FlowResult r) => {for (final s in r.stages) s.stage.id: s.state};

FlowResult _run(
  FlowMode mode,
  List<FlowStage> stages, {
  Map<String, TaskCounts> counts = const {},
  FlowStatus status = FlowStatus.active,
}) =>
    FlowEngine.evaluate(flow: _flow(mode, status: status), stages: stages, counts: counts);

void main() {
  const done = TaskCounts(2, 2);
  const half = TaskCounts(1, 2);

  group('sequential', () {
    final stages = [_s('a', 1), _s('b', 2), _s('c', 3), _s('d', 4)];

    test('only the first stage is active; the next is up next; the rest are locked', () {
      final r = _run(FlowMode.sequential, stages);
      expect(_states(r), {
        'a': StageState.active,
        'b': StageState.upcoming,
        'c': StageState.locked,
        'd': StageState.locked,
      });
      expect(r.currentStageId, 'a');
    });

    test('finishing stage 1 unlocks stage 2', () {
      final r = _run(FlowMode.sequential, stages, counts: {'a': done});
      expect(_states(r)['a'], StageState.completed);
      expect(_states(r)['b'], StageState.active);
      expect(_states(r)['c'], StageState.upcoming);
      expect(r.currentStageId, 'b');
    });

    test('a half-finished stage does not unlock the next', () {
      final r = _run(FlowMode.sequential, stages, counts: {'a': half});
      expect(_states(r)['a'], StageState.active);
      expect(_states(r)['b'], StageState.upcoming);
    });

    test('order follows position, not the order the stages were stored', () {
      final r = _run(FlowMode.sequential, [_s('c', 3), _s('a', 1), _s('b', 2)]);
      expect(r.stages.map((s) => s.stage.id), ['a', 'b', 'c']);
      expect(_states(r)['a'], StageState.active);
    });

    test('an optional stage that is not finished does not hold up the next', () {
      final r = _run(FlowMode.sequential, [_s('a', 1), _s('opt', 2, required: false), _s('c', 3)],
          counts: {'a': done});
      expect(_states(r)['c'], StageState.active);
    });

    test('a blocked stage shows the stages behind it as blocked, not just locked', () {
      final r = _run(FlowMode.sequential, [_s('a', 1, manual: ManualStageStatus.blocked), _s('b', 2)]);
      expect(_states(r), {'a': StageState.blocked, 'b': StageState.blocked});
    });
  });

  group('flexible', () {
    test('every unfinished stage is active at once', () {
      final r = _run(FlowMode.flexible, [_s('a', 1), _s('b', 2), _s('c', 3)], counts: {'b': done});
      expect(_states(r), {
        'a': StageState.active,
        'b': StageState.completed,
        'c': StageState.active,
      });
    });

    test('currentStageId is the first active stage by position', () {
      final r = _run(FlowMode.flexible, [_s('a', 1), _s('b', 2)], counts: {'a': done});
      expect(r.currentStageId, 'b');
    });
  });

  group('dependency', () {
    test('a stage unlocks only when everything it depends on is complete', () {
      final stages = [
        _s('design', 1),
        _s('build', 2),
        _s('test', 3, deps: ['design', 'build']),
      ];
      var r = _run(FlowMode.dependency, stages, counts: {'design': done});
      expect(_states(r)['test'], StageState.upcoming, reason: 'build is still active');
      expect(_states(r)['build'], StageState.active, reason: 'no dependencies');

      r = _run(FlowMode.dependency, stages, counts: {'design': done, 'build': done});
      expect(_states(r)['test'], StageState.active);
    });

    test('a stage waiting on something locked is locked', () {
      final stages = [_s('a', 1), _s('b', 2, deps: ['a']), _s('c', 3, deps: ['b'])];
      final r = _run(FlowMode.dependency, stages);
      expect(_states(r), {
        'a': StageState.active,
        'b': StageState.upcoming,
        'c': StageState.locked,
      });
    });

    test('a dependency on a stage that no longer exists is ignored', () {
      final r = _run(FlowMode.dependency, [_s('a', 1, deps: ['gone'])]);
      expect(_states(r)['a'], StageState.active);
    });

    test('a cycle is detected and its stages are blocked, not silently ignored', () {
      final stages = [_s('a', 1, deps: ['b']), _s('b', 2, deps: ['a']), _s('c', 3)];
      final r = _run(FlowMode.dependency, stages);
      expect(r.hasCycle, isTrue);
      expect(r.cycleStageIds, {'a', 'b'});
      expect(_states(r)['a'], StageState.blocked);
      expect(_states(r)['b'], StageState.blocked);
      expect(_states(r)['c'], StageState.active, reason: 'unrelated stages are unaffected');
    });

    test('a stage that depends on itself is a cycle', () {
      expect(FlowEngine.findCycle([_s('a', 1, deps: ['a'])]), {'a'});
    });

    test('wouldCreateCycle says no before the edit that would make one', () {
      final stages = [_s('a', 1), _s('b', 2, deps: ['a']), _s('c', 3, deps: ['b'])];
      expect(FlowEngine.wouldCreateCycle(stages, 'a', 'c'), isTrue);
      expect(FlowEngine.wouldCreateCycle(stages, 'c', 'a'), isFalse);
      expect(FlowEngine.wouldCreateCycle(stages, 'b', 'b'), isTrue);
    });

    test('a blocked prerequisite blocks what depends on it', () {
      final stages = [_s('a', 1, manual: ManualStageStatus.blocked), _s('b', 2, deps: ['a'])];
      expect(_states(_run(FlowMode.dependency, stages))['b'], StageState.blocked);
    });
  });

  group('completion of a stage', () {
    test('finishing every linked task completes the stage', () {
      final r = _run(FlowMode.flexible, [_s('a', 1)], counts: {'a': done});
      expect(_states(r)['a'], StageState.completed);
    });

    test('a stage with no tasks is not complete by itself', () {
      final r = _run(FlowMode.flexible, [_s('a', 1)]);
      expect(_states(r)['a'], StageState.active);
    });

    test('with auto-complete off, finished tasks leave the stage for the user to close', () {
      final r = _run(FlowMode.flexible, [_s('a', 1, auto: false)], counts: {'a': done});
      expect(_states(r)['a'], StageState.active);
    });

    test('marking a stage complete by hand completes it without tasks', () {
      final r = _run(FlowMode.flexible, [_s('a', 1, manual: ManualStageStatus.completed)]);
      expect(_states(r)['a'], StageState.completed);
    });

    test('reopening one task of a finished stage reopens the stage', () {
      final stages = [_s('a', 1), _s('b', 2)];
      var r = _run(FlowMode.sequential, stages, counts: {'a': done});
      expect(_states(r)['b'], StageState.active);
      r = _run(FlowMode.sequential, stages, counts: {'a': half});
      expect(_states(r)['a'], StageState.active);
      expect(_states(r)['b'], StageState.upcoming, reason: 'b locks again');
    });
  });

  group('progress and flow status', () {
    test('progress is completed stages over all stages', () {
      final stages = [for (var i = 0; i < 9; i++) _s('s$i', i.toDouble())];
      final counts = {for (var i = 0; i < 4; i++) 's$i': done};
      final r = _run(FlowMode.sequential, stages, counts: counts);
      expect(r.completedStages, 4);
      expect(r.totalStages, 9);
      expect(r.progress, closeTo(4 / 9, 1e-9));
    });

    test('an empty flow has no progress and is not complete', () {
      final r = _run(FlowMode.sequential, const []);
      expect(r.progress, 0);
      expect(r.status, FlowStatus.active);
    });

    test('the flow completes when every required stage is complete', () {
      final r = _run(FlowMode.sequential, [_s('a', 1), _s('opt', 2, required: false)],
          counts: {'a': done});
      expect(r.status, FlowStatus.completed);
    });

    test('an unfinished required stage keeps the flow active', () {
      final r = _run(FlowMode.flexible, [_s('a', 1), _s('b', 2)], counts: {'a': done});
      expect(r.status, FlowStatus.active);
    });

    test('paused and archived are the user\'s choice and are kept', () {
      final stages = [_s('a', 1)];
      expect(_run(FlowMode.flexible, stages, counts: {'a': done}, status: FlowStatus.paused).status,
          FlowStatus.paused);
      expect(_run(FlowMode.flexible, stages, status: FlowStatus.archived).status,
          FlowStatus.archived);
    });
  });
}

import '../../models/project_flow.dart';

/// How many of a stage's linked tasks are finished.
class TaskCounts {
  const TaskCounts(this.done, this.total);
  final int done;
  final int total;

  static const none = TaskCounts(0, 0);
}

/// What the engine worked out for one stage.
class StageResult {
  const StageResult({required this.stage, required this.state, required this.tasks});

  final FlowStage stage;
  final StageState state;
  final TaskCounts tasks;
}

/// What the engine worked out for a whole flow.
class FlowResult {
  const FlowResult({
    required this.stages,
    required this.status,
    required this.completedStages,
    required this.totalStages,
    required this.currentStageId,
    required this.cycleStageIds,
  });

  /// In position order.
  final List<StageResult> stages;

  /// The flow's status after taking its stages into account.
  final FlowStatus status;

  final int completedStages;
  final int totalStages;

  /// The first active stage, or null when none is.
  final String? currentStageId;

  /// Stages caught in a dependency cycle. Empty when the dependencies are sound.
  final Set<String> cycleStageIds;

  /// Completed stages over all stages, 0 to 1.
  double get progress => totalStages == 0 ? 0 : completedStages / totalStages;

  bool get hasCycle => cycleStageIds.isNotEmpty;

  StageResult? stage(String id) => stages.where((s) => s.stage.id == id).firstOrNull;
}

/// The rules of a Project Flow, with no Firebase in them.
///
/// Given a flow, its stages and how many of each stage's tasks are done, it
/// decides every stage's state, the flow's progress and status. Because it is
/// a pure function of those inputs, a screen can call it on every rebuild and
/// two devices always agree, whatever order their writes arrived in.
class FlowEngine {
  const FlowEngine._();

  static FlowResult evaluate({
    required ProjectFlow flow,
    required List<FlowStage> stages,
    Map<String, TaskCounts> counts = const {},
  }) {
    final ordered = [...stages]..sort((a, b) => a.position.compareTo(b.position));
    final byId = {for (final s in ordered) s.id: s};

    final cycle = flow.mode == FlowMode.dependency ? findCycle(ordered) : <String>{};

    bool isDone(FlowStage s) {
      if (s.manualStatus == ManualStageStatus.completed) return true;
      final c = counts[s.id] ?? TaskCounts.none;
      return s.autoCompleteWhenTasksDone && c.total > 0 && c.done == c.total;
    }

    final states = <String, StageState>{};

    // Completed stages first: every other state depends on which are complete.
    for (final s in ordered) {
      if (isDone(s)) states[s.id] = StageState.completed;
    }

    // The prerequisites a stage is waiting on, by mode.
    List<String> prerequisites(FlowStage s, int index) => switch (flow.mode) {
          FlowMode.flexible => const [],
          FlowMode.sequential => [
              for (var i = 0; i < index; i++)
                if (ordered[i].isRequired) ordered[i].id,
            ],
          FlowMode.dependency => [
              for (final d in s.dependencyStageIds)
                if (byId.containsKey(d)) d,
            ],
        };

    // A stage's state can depend on earlier stages' states, so resolve in an
    // order where prerequisites come first. Sequential and flexible are
    // already in order. Dependency mode needs a pass until nothing changes,
    // which is bounded by the number of stages (cycles are handled apart).
    for (var pass = 0; pass <= ordered.length; pass++) {
      var changed = false;
      for (final (i, s) in ordered.indexed) {
        if (states[s.id] == StageState.completed) continue;

        final next = _stateFor(
          s,
          prerequisites(s, i),
          states,
          inCycle: cycle.contains(s.id),
        );
        if (states[s.id] != next) {
          states[s.id] = next;
          changed = true;
        }
      }
      if (!changed) break;
    }

    final results = [
      for (final s in ordered)
        StageResult(
          stage: s,
          state: states[s.id] ?? StageState.locked,
          tasks: counts[s.id] ?? TaskCounts.none,
        ),
    ];

    final completed = results.where((r) => r.state == StageState.completed).length;
    final required = results.where((r) => r.stage.isRequired);
    final allRequiredDone =
        results.isNotEmpty && required.every((r) => r.state == StageState.completed);

    // The user's pause or archive wins over anything derived.
    final status = switch (flow.status) {
      FlowStatus.paused || FlowStatus.archived => flow.status,
      _ => allRequiredDone ? FlowStatus.completed : FlowStatus.active,
    };

    return FlowResult(
      stages: results,
      status: status,
      completedStages: completed,
      totalStages: results.length,
      currentStageId:
          results.where((r) => r.state == StageState.active).firstOrNull?.stage.id,
      cycleStageIds: cycle,
    );
  }

  static StageState _stateFor(
    FlowStage s,
    List<String> prerequisites,
    Map<String, StageState> states, {
    required bool inCycle,
  }) {
    if (s.manualStatus == ManualStageStatus.blocked) return StageState.blocked;
    // A stage in a dependency cycle can never unlock, and the cycle is shown.
    if (inCycle) return StageState.blocked;

    final unmet = [
      for (final p in prerequisites)
        if (states[p] != StageState.completed) p,
    ];
    if (unmet.isEmpty) return StageState.active;

    // Waiting on something that is itself blocked: this is blocked too, so the
    // cause is visible rather than the whole chain looking merely locked.
    if (unmet.any((p) => states[p] == StageState.blocked)) return StageState.blocked;

    // Waiting only on stages that are in progress right now: this one is next.
    if (unmet.every((p) => states[p] == StageState.active)) return StageState.upcoming;

    return StageState.locked;
  }

  /// The stages that sit on a dependency cycle (including a stage that depends
  /// on itself). Empty when there is none.
  static Set<String> findCycle(List<FlowStage> stages) {
    final ids = {for (final s in stages) s.id};
    final deps = {
      for (final s in stages) s.id: s.dependencyStageIds.where(ids.contains).toList(),
    };

    // A stage is on a cycle exactly when it can reach itself.
    bool reaches(String from, String target) {
      final seen = <String>{};
      final stack = [...deps[from]!];
      while (stack.isNotEmpty) {
        final n = stack.removeLast();
        if (n == target) return true;
        if (seen.add(n)) stack.addAll(deps[n]!);
      }
      return false;
    }

    return {for (final s in stages) if (reaches(s.id, s.id)) s.id};
  }

  /// Whether making [stageId] depend on [dependsOnId] would create a cycle.
  static bool wouldCreateCycle(
    List<FlowStage> stages,
    String stageId,
    String dependsOnId,
  ) {
    if (stageId == dependsOnId) return true;
    final changed = [
      for (final s in stages)
        if (s.id == stageId)
          s.copyWith(dependencyStageIds: {...s.dependencyStageIds, dependsOnId}.toList())
        else
          s,
    ];
    return findCycle(changed).isNotEmpty;
  }
}

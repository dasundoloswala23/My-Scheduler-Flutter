import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/project_flow.dart';
import '../providers.dart';
import 'flow_engine.dart';

final flowsProvider =
    StreamProvider<List<ProjectFlow>>((ref) => ref.watch(repoProvider).flows.watchFlows());

final flowStagesProvider =
    StreamProvider<List<FlowStage>>((ref) => ref.watch(repoProvider).flows.watchStages());

final flowLinksProvider =
    StreamProvider<List<FlowTaskLink>>((ref) => ref.watch(repoProvider).flows.watchLinks());

/// Each flow evaluated by the engine against the live tasks.
///
/// Screens read this rather than the stored copy, so what they show is always
/// consistent with the tasks on screen, even for the instant before a
/// recompute has been written.
final flowResultsProvider = Provider<Map<String, FlowResult>>((ref) {
  final flows = ref.watch(flowsProvider).value ?? const <ProjectFlow>[];
  final stages = ref.watch(flowStagesProvider).value ?? const <FlowStage>[];
  final links = ref.watch(flowLinksProvider).value ?? const <FlowTaskLink>[];
  final tasks = ref.watch(tasksProvider).value ?? const [];
  final completed = {for (final t in tasks) t.id: t.completed};

  return {
    for (final flow in flows)
      flow.id: FlowEngine.evaluate(
        flow: flow,
        stages: [for (final s in stages) if (s.flowId == flow.id) s],
        counts: _countsFor(flow.id, links, completed),
      ),
  };
});

Map<String, TaskCounts> _countsFor(
  String flowId,
  List<FlowTaskLink> links,
  Map<String, bool> completed,
) {
  final counts = <String, TaskCounts>{};
  for (final link in links) {
    if (link.flowId != flowId) continue;
    final done = completed[link.taskId];
    if (done == null) continue; // the task is gone; the link counts for nothing
    final c = counts[link.stageId] ?? TaskCounts.none;
    counts[link.stageId] = TaskCounts(c.done + (done ? 1 : 0), c.total + 1);
  }
  return counts;
}

/// For every linked task, its flow's progress as (stages done, stages in all),
/// which is what the small "Flow 4/9" badge on a board card shows.
final taskFlowBadgeProvider = Provider<Map<String, ({int done, int total})>>((ref) {
  final links = ref.watch(flowLinksProvider).value ?? const <FlowTaskLink>[];
  final results = ref.watch(flowResultsProvider);
  return {
    for (final l in links)
      if (results[l.flowId] != null)
        l.taskId: (
          done: results[l.flowId]!.completedStages,
          total: results[l.flowId]!.totalStages,
        ),
  };
});

/// The tasks linked to each stage, so a stage can list them.
final stageTaskIdsProvider = Provider<Map<String, List<String>>>((ref) {
  final links = ref.watch(flowLinksProvider).value ?? const <FlowTaskLink>[];
  final byStage = <String, List<String>>{};
  for (final l in [...links]..sort((a, b) => a.position.compareTo(b.position))) {
    byStage.putIfAbsent(l.stageId, () => []).add(l.taskId);
  }
  return byStage;
});

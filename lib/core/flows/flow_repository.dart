import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/project_flow.dart';
import '../../models/task.dart';
import 'flow_engine.dart';

/// Stores Project Flows under `users/{uid}`, so the same owner-only rule that
/// protects tasks protects them.
///
///   projectFlows/{flowId}   the flow
///   flowStages/{stageId}    its stages (each carries `flowId`)
///   flowTaskLinks/{taskId}  which stage a task belongs to; the id is the task
///                           id, so a task has at most one link
///
/// Tasks are never copied here. A link only points at the real task.
class FlowRepo {
  FlowRepo({required FirebaseFirestore db, required String uid})
      : _db = db,
        _user = db.collection('users').doc(uid);

  final FirebaseFirestore _db;
  final DocumentReference<Map<String, dynamic>> _user;

  static const flowsCollection = 'projectFlows';
  static const stagesCollection = 'flowStages';
  static const linksCollection = 'flowTaskLinks';

  CollectionReference<Map<String, dynamic>> get _flows => _user.collection(flowsCollection);
  CollectionReference<Map<String, dynamic>> get _stages => _user.collection(stagesCollection);
  CollectionReference<Map<String, dynamic>> get _links => _user.collection(linksCollection);
  CollectionReference<Map<String, dynamic>> get _tasks => _user.collection('tasks');

  Stream<List<ProjectFlow>> watchFlows() => _flows.snapshots().map((s) =>
      s.docs.map(ProjectFlow.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0))));

  Stream<List<FlowStage>> watchStages() => _stages.snapshots().map((s) =>
      s.docs.map(FlowStage.fromDoc).toList()..sort((a, b) => a.position.compareTo(b.position)));

  Stream<List<FlowTaskLink>> watchLinks() =>
      _links.snapshots().map((s) => s.docs.map(FlowTaskLink.fromDoc).toList());

  // ---- Flows -------------------------------------------------------------

  /// Creates a flow with one stage per title, in one batch. No tasks are made.
  Future<String> createFlow(ProjectFlow flow, {List<String> stageTitles = const []}) async {
    final ref = _flows.doc();
    final batch = _db.batch();
    batch.set(ref, {
      ...flow.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final (i, title) in stageTitles.indexed) {
      batch.set(_stages.doc(), {
        ...FlowStage(id: '', flowId: ref.id, title: title.trim(), position: (i + 1) * 1000.0)
            .toJson(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await recompute(ref.id);
    return ref.id;
  }

  Future<void> updateFlow(ProjectFlow flow) async {
    await _flows.doc(flow.id).update({
      ...flow.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await recompute(flow.id);
  }

  /// Deletes the flow, its stages and its links. The linked tasks are not
  /// touched: they simply stop belonging to a flow.
  Future<void> deleteFlow(String flowId) async {
    final stages = await _stages.where('flowId', isEqualTo: flowId).get();
    final links = await _links.where('flowId', isEqualTo: flowId).get();
    final batch = _db.batch();
    for (final d in [...stages.docs, ...links.docs]) {
      batch.delete(d.reference);
    }
    batch.delete(_flows.doc(flowId));
    await batch.commit();
  }

  // ---- Stages ------------------------------------------------------------

  Future<String> addStage(String flowId, String title, {double? position}) async {
    final existing = await _stages.where('flowId', isEqualTo: flowId).get();
    final last = existing.docs
        .map((d) => (d.data()['position'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final ref = _stages.doc();
    await ref.set({
      ...FlowStage(id: '', flowId: flowId, title: title.trim(), position: position ?? last + 1000)
          .toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await recompute(flowId);
    return ref.id;
  }

  /// Saves a stage. In dependency mode, an edit that would make the stages
  /// depend on each other in a circle is refused.
  Future<void> updateStage(FlowStage stage) async {
    final flow = ProjectFlow.fromDoc(await _flows.doc(stage.flowId).get());
    if (flow.mode == FlowMode.dependency) {
      final siblings = (await _stages.where('flowId', isEqualTo: stage.flowId).get())
          .docs
          .map(FlowStage.fromDoc)
          .map((s) => s.id == stage.id ? stage : s)
          .toList();
      if (FlowEngine.findCycle(siblings).isNotEmpty) {
        throw StateError('Those dependencies would make the stages wait on each other.');
      }
    }
    await _stages.doc(stage.id).update({
      ...stage.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await recompute(stage.flowId);
  }

  /// Removes a stage, unlinks its tasks (the tasks stay), and takes it out of
  /// the other stages' dependencies.
  Future<void> deleteStage(FlowStage stage) async {
    final links = await _links.where('stageId', isEqualTo: stage.id).get();
    final siblings = await _stages.where('flowId', isEqualTo: stage.flowId).get();

    final batch = _db.batch();
    for (final l in links.docs) {
      batch.delete(l.reference);
    }
    for (final doc in siblings.docs) {
      final s = FlowStage.fromDoc(doc);
      if (s.dependencyStageIds.contains(stage.id)) {
        batch.update(doc.reference, {
          'dependencyStageIds': s.dependencyStageIds.where((d) => d != stage.id).toList(),
        });
      }
    }
    batch.delete(_stages.doc(stage.id));
    await batch.commit();
    await recompute(stage.flowId);
  }

  /// Renumbers a flow's stages to match [orderedIds].
  Future<void> reorderStages(String flowId, List<String> orderedIds) async {
    final batch = _db.batch();
    for (final (i, id) in orderedIds.indexed) {
      batch.update(_stages.doc(id), {'position': (i + 1) * 1000.0});
    }
    await batch.commit();
    await recompute(flowId);
  }

  // ---- Links -------------------------------------------------------------

  /// Links an existing task to a stage. Linking a task that is already linked
  /// moves it, because the link's id is the task's id.
  Future<void> linkTask({
    required String flowId,
    required String stageId,
    required String taskId,
  }) async {
    final stage = await _stages.doc(stageId).get();
    if (!stage.exists || stage.data()?['flowId'] != flowId) {
      throw StateError('That stage does not belong to this flow.');
    }
    if (!(await _tasks.doc(taskId).get()).exists) {
      throw StateError('That task no longer exists.');
    }

    final previous = await _links.doc(taskId).get();
    final previousFlow = previous.data()?['flowId'] as String?;

    await _links.doc(taskId).set({
      ...FlowTaskLink(taskId: taskId, flowId: flowId, stageId: stageId).toJson(),
      'createdAt': previous.exists
          ? (previous.data()?['createdAt'] ?? FieldValue.serverTimestamp())
          : FieldValue.serverTimestamp(),
    });

    await recompute(flowId);
    if (previousFlow != null && previousFlow != flowId) await recompute(previousFlow);
  }

  Future<void> unlinkTask(String taskId) async {
    final link = await _links.doc(taskId).get();
    if (!link.exists) return;
    final flowId = link.data()?['flowId'] as String?;
    await link.reference.delete();
    if (flowId != null) await recompute(flowId);
  }

  // ---- Derived state -----------------------------------------------------

  /// Evaluates a flow from its stages and its tasks, and stores the result
  /// where it differs from what is stored. Writes nothing when nothing changed,
  /// so running it twice is harmless and cannot loop.
  ///
  /// The engine is the source of truth and the screens evaluate it live, so the
  /// stored copy only serves queries and other devices. Two recomputes racing
  /// therefore cannot leave a wrong answer on screen, and the next one repairs
  /// the stored copy; a transaction would add nothing but contention.
  Future<FlowResult?> recompute(String flowId) async {
    final flowDoc = await _flows.doc(flowId).get();
    if (!flowDoc.exists) return null;
    final flow = ProjectFlow.fromDoc(flowDoc);

    final stages = (await _stages.where('flowId', isEqualTo: flowId).get())
        .docs
        .map(FlowStage.fromDoc)
        .toList();
    final links = (await _links.where('flowId', isEqualTo: flowId).get())
        .docs
        .map(FlowTaskLink.fromDoc)
        .toList();

    final counts = <String, TaskCounts>{};
    for (final link in links) {
      final task = await _tasks.doc(link.taskId).get();
      // A link whose task is gone counts for nothing.
      if (!task.exists) continue;
      final done = Task.fromDoc(task).completed;
      final c = counts[link.stageId] ?? TaskCounts.none;
      counts[link.stageId] = TaskCounts(c.done + (done ? 1 : 0), c.total + 1);
    }

    final result = FlowEngine.evaluate(flow: flow, stages: stages, counts: counts);

    final batch = _db.batch();
    var writes = 0;

    for (final r in result.stages) {
      final shouldBeDone = r.state == StageState.completed;
      if (r.stage.state != r.state || (r.stage.completedAt != null) != shouldBeDone) {
        batch.update(_stages.doc(r.stage.id), {
          'status': r.state.name,
          'completedAt': shouldBeDone ? (r.stage.completedAt ?? Timestamp.now()) : null,
        });
        writes++;
      }
    }

    final finished = result.status == FlowStatus.completed;
    final flowChanged = flow.currentStageId != result.currentStageId ||
        (flow.progress - result.progress).abs() > 1e-9 ||
        flow.status != result.status ||
        (flow.completedAt != null) != finished;
    if (flowChanged) {
      batch.update(_flows.doc(flowId), {
        'currentStageId': result.currentStageId,
        'progress': result.progress,
        'status': result.status.name,
        'completedAt': finished ? (flow.completedAt ?? Timestamp.now()) : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      writes++;
    }

    if (writes > 0) await batch.commit();
    return result;
  }

  /// Recomputes the flow a task belongs to, if any. Called after a task is
  /// completed, re-opened or deleted.
  Future<void> recomputeForTask(String taskId) async {
    final link = await _links.doc(taskId).get();
    final flowId = link.data()?['flowId'] as String?;
    if (flowId != null) await recompute(flowId);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/flows/flow_engine.dart';
import '../../core/flows/flow_providers.dart';
import '../../core/providers.dart';
import '../../models/project_flow.dart';
import '../../models/task.dart';
import '../more/more_page.dart';
import '../task_detail/task_detail_sheet.dart';

/// One flow as a vertical timeline of stages.
class FlowDetailPage extends ConsumerWidget {
  const FlowDetailPage({super.key, required this.flowId});

  final String flowId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = (ref.watch(flowsProvider).value ?? const <ProjectFlow>[])
        .where((f) => f.id == flowId)
        .firstOrNull;
    final result = ref.watch(flowResultsProvider)[flowId];

    // The flow was deleted (here or on another device).
    if (flow == null || result == null) {
      return const SubPage(eyebrow: 'Project Flow', title: 'Flow', child: SizedBox.shrink());
    }

    final palette = context.palette;
    final flows = ref.read(repoProvider).flows;

    return SubPage(
      eyebrow: 'Project Flow',
      title: flow.name,
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'rename':
                final name = await _promptText(context, 'Rename flow', flow.name);
                if (name != null) await flows.updateFlow(flow.copyWith(name: name));
              case 'pause':
                await flows.updateFlow(flow.copyWith(
                    status: flow.status == FlowStatus.paused
                        ? FlowStatus.active
                        : FlowStatus.paused));
              case 'archive':
                await flows.updateFlow(flow.copyWith(
                    status: flow.status == FlowStatus.archived
                        ? FlowStatus.active
                        : FlowStatus.archived));
              case 'delete':
                if (await _confirm(context, 'Delete this flow?',
                    'Its stages and links are removed. Your tasks are not deleted.')) {
                  await flows.deleteFlow(flow.id);
                  if (context.mounted) Navigator.of(context).pop();
                }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(
                value: 'pause',
                child: Text(flow.status == FlowStatus.paused ? 'Resume' : 'Pause')),
            PopupMenuItem(
                value: 'archive',
                child: Text(flow.status == FlowStatus.archived ? 'Unarchive' : 'Archive')),
            const PopupMenuItem(value: 'delete', child: Text('Delete flow')),
          ],
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final title = await _promptText(context, 'New stage', '');
          if (title != null) await flows.addStage(flow.id, title);
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add stage'),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          Text('${result.completedStages}/${result.totalStages} stages complete',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: result.progress, minHeight: 8),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('${flow.status.label}${result.status != flow.status ? ' → ${result.status.label}' : ''}',
                  style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
              const Spacer(),
              DropdownButton<FlowMode>(
                value: flow.mode,
                underline: const SizedBox.shrink(),
                items: [
                  for (final m in FlowMode.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) async {
                  if (m != null) await flows.updateFlow(flow.copyWith(mode: m));
                },
              ),
            ],
          ),
          Text(flow.mode.description,
              style: TextStyle(fontSize: 12, color: palette.textSecondary)),
          if (result.hasCycle)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Some stages depend on each other in a circle, so they can never unlock. '
                'Edit their dependencies.',
                style: TextStyle(color: palette.danger, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 18),
          if (result.stages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text('No stages yet. Add the first one.',
                    style: TextStyle(color: palette.textSecondary)),
              ),
            ),
          for (final (i, s) in result.stages.indexed)
            _StageTile(
              flow: flow,
              result: result,
              stage: s,
              isLast: i == result.stages.length - 1,
            ),
        ],
      ),
    );
  }
}

class _StageTile extends ConsumerWidget {
  const _StageTile({
    required this.flow,
    required this.result,
    required this.stage,
    required this.isLast,
  });

  final ProjectFlow flow;
  final FlowResult result;
  final StageResult stage;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final s = stage.stage;
    final state = stage.state;
    final repo = ref.read(repoProvider);
    final flows = repo.flows;
    final allTasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final taskIds = ref.watch(stageTaskIdsProvider)[s.id] ?? const <String>[];
    final linked = [
      for (final id in taskIds)
        ?allTasks.where((t) => t.id == id).firstOrNull,
    ];

    final (IconData icon, Color color) = switch (state) {
      StageState.completed => (Icons.check_circle, palette.success),
      StageState.active => (Icons.radio_button_checked, AppColors.primary),
      StageState.upcoming => (Icons.radio_button_unchecked, AppColors.primary),
      StageState.blocked => (Icons.block, palette.danger),
      StageState.locked => (Icons.lock_outline, palette.textDisabled),
    };
    final dim = state == StageState.locked;
    final highlighted = state == StageState.active;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Icon(icon, color: color, size: 24),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: palette.border)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Opacity(
                opacity: dim ? 0.6 : 1,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                  decoration: BoxDecoration(
                    color: highlighted ? palette.selected : Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: highlighted
                          ? AppColors.primary
                          : (state == StageState.blocked ? palette.danger : Colors.transparent),
                      width: highlighted || state == StageState.blocked ? 1.5 : 0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(s.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                          Text(state.label,
                              style: TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
                          PopupMenuButton<String>(
                            onSelected: (v) => _menu(context, ref, v, linked),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'link', child: Text('Link a task')),
                              const PopupMenuItem(value: 'rename', child: Text('Rename')),
                              if (flow.mode == FlowMode.dependency)
                                const PopupMenuItem(
                                    value: 'deps', child: Text('Dependencies')),
                              PopupMenuItem(
                                  value: 'required',
                                  child: Text(s.isRequired
                                      ? 'Make optional'
                                      : 'Make required')),
                              PopupMenuItem(
                                  value: 'complete',
                                  child: Text(s.manualStatus == ManualStageStatus.completed
                                      ? 'Reopen stage'
                                      : 'Mark complete')),
                              PopupMenuItem(
                                  value: 'block',
                                  child: Text(s.manualStatus == ManualStageStatus.blocked
                                      ? 'Unblock'
                                      : 'Mark blocked')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete stage')),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        stage.tasks.total == 0
                            ? 'No tasks linked'
                            : '${stage.tasks.done}/${stage.tasks.total} tasks',
                        style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
                      ),
                      if (s.dueDate != null)
                        Text('Due ${DateFormat('MMM d').format(s.dueDate!)}',
                            style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                      for (final t in linked)
                        InkWell(
                          onTap: () => showTaskDetailSheet(context, t),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: t.completed,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (v) => repo.setTaskCompleted(t, v == true),
                                ),
                                Expanded(
                                  child: Text(
                                    t.title,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      decoration:
                                          t.completed ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Unlink task',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.link_off, size: 18),
                                  onPressed: () => flows.unlinkTask(t.id),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _menu(
      BuildContext context, WidgetRef ref, String action, List<Task> linked) async {
    final flows = ref.read(repoProvider).flows;
    final s = stage.stage;
    try {
      switch (action) {
        case 'link':
          final id = await _pickTask(context, ref, flow);
          if (id != null) {
            await flows.linkTask(flowId: flow.id, stageId: s.id, taskId: id);
          }
        case 'rename':
          final title = await _promptText(context, 'Rename stage', s.title);
          if (title != null) await flows.updateStage(s.copyWith(title: title));
        case 'deps':
          final ids = await _pickDependencies(context, result, s);
          if (ids != null) await flows.updateStage(s.copyWith(dependencyStageIds: ids));
        case 'required':
          await flows.updateStage(s.copyWith(isRequired: !s.isRequired));
        case 'complete':
          await flows.updateStage(s.copyWith(
              manualStatus: s.manualStatus == ManualStageStatus.completed
                  ? null
                  : ManualStageStatus.completed));
        case 'block':
          await flows.updateStage(s.copyWith(
              manualStatus: s.manualStatus == ManualStageStatus.blocked
                  ? null
                  : ManualStageStatus.blocked));
        case 'delete':
          if (await _confirm(context, 'Delete "${s.title}"?',
              'Its tasks stay where they are and are just unlinked.')) {
            await flows.deleteStage(s);
          }
      }
    } on StateError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

Future<String?> _promptText(BuildContext context, String title, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(c, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(c, controller.text.trim().isEmpty ? null : controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(BuildContext context, String title, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
      ],
    ),
  );
  return ok == true;
}

/// Lists existing tasks that are not already in a flow, so linking can never
/// put one task in two places. Tasks from the flow's board come first.
Future<String?> _pickTask(BuildContext context, WidgetRef ref, ProjectFlow flow) {
  final linkedIds = {
    for (final l in ref.read(flowLinksProvider).value ?? const <FlowTaskLink>[]) l.taskId,
  };
  final tasks = [
    for (final t in ref.read(tasksProvider).value ?? const <Task>[])
      if (!linkedIds.contains(t.id) && t.parentTaskId == null) t,
  ]..sort((a, b) {
      final ab = a.boardId == flow.boardId ? 0 : 1;
      final bb = b.boardId == flow.boardId ? 0 : 1;
      return ab != bb ? ab - bb : a.title.compareTo(b.title);
    });

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (c, controller) => tasks.isEmpty
          ? const Center(child: Text('Every task is already in a flow.'))
          : ListView(
              controller: controller,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Link an existing task',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                for (final t in tasks)
                  ListTile(
                    title: Text(t.title),
                    subtitle: t.completed ? const Text('Completed') : null,
                    onTap: () => Navigator.pop(c, t.id),
                  ),
              ],
            ),
    ),
  );
}

Future<List<String>?> _pickDependencies(
    BuildContext context, FlowResult result, FlowStage stage) {
  final selected = {...stage.dependencyStageIds};
  final others = [for (final r in result.stages) if (r.stage.id != stage.id) r.stage];

  return showDialog<List<String>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Depends on'),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final o in others)
                CheckboxListTile(
                  value: selected.contains(o.id),
                  title: Text(o.title),
                  onChanged: (v) => setState(() {
                    v == true ? selected.add(o.id) : selected.remove(o.id);
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, selected.toList()), child: const Text('Save')),
        ],
      ),
    ),
  );
}

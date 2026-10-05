import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/position.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import '../../core/reminder_scheduler.dart';
import '../attachments/attachment_section.dart';
import 'reminder_picker.dart';

Future<void> showTaskDetailSheet(BuildContext context, Task task) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TaskDetailSheet(taskId: task.id),
  );
}

/// The detail sheet from screenshots 14–15: header, four info tiles, the
/// subtask checklist with drag-reorder and progress, attachments, and the
/// Complete button.
class TaskDetailSheet extends ConsumerWidget {
  const TaskDetailSheet({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final task = tasks.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return const SizedBox.shrink();

    final repo = ref.read(repoProvider);
    final category = ref.watch(categoryByIdProvider)[task.categoryId];
    final lists = ref.watch(listsProvider).value ?? const <TaskList>[];
    final boards = ref.watch(boardsProvider).value ?? const <Board>[];
    final list = lists.where((l) => l.id == task.listId).firstOrNull;
    final board = boards.where((b) => b.id == task.boardId).firstOrNull;
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  Row(
                    children: [
                      if (category != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Color(category.colorValue).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(category.name,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(category.colorValue))),
                        ),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _EditableTitle(task: task),
                  if (task.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(task.description, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: _InfoTile(label: 'BOARD', value: board?.name ?? '—', icon: Icons.view_week_outlined)),
                    const SizedBox(width: 12),
                    Expanded(child: _InfoTile(label: 'LIST', value: list?.name ?? 'Inbox', icon: Icons.list)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _InfoTile(label: 'PRIORITY', value: task.priority.label, icon: Icons.flag_outlined)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _InfoTile(
                        label: 'DUE DATE',
                        value: task.startDateTime == null
                            ? 'Not set'
                            : DateFormat('MMM d, h:mm a').format(task.startDateTime!),
                        icon: Icons.calendar_today_outlined,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  _SubtaskSection(task: task),
                  const SizedBox(height: 20),
                  _ReminderRow(task: task),
                  const SizedBox(height: 24),
                  AttachmentSection(
                    taskId: task.id,
                    service: ref.watch(attachmentServiceProvider),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: () => showTaskDetailMore(context, ref, task),
                        icon: const Icon(Icons.more_horiz),
                        label: const Text('More'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        onPressed: () async {
                          await repo.setTaskCompleted(task, !task.completed);
                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check),
                        label: Text(task.completed ? 'Completed' : 'Complete task'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showTaskDetailMore(BuildContext context, WidgetRef ref, Task task) async {
  final repo = ref.read(repoProvider);
  await showModalBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('Repeat'),
            subtitle: Text(task.recurrence.name),
            onTap: () async {
              final chosen = await showModalBottomSheet<Recurrence>(
                context: sheetContext,
                builder: (c) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final r in Recurrence.values)
                        ListTile(title: Text(r.name), onTap: () => Navigator.pop(c, r)),
                    ],
                  ),
                ),
              );
              if (chosen != null) {
                await repo.updateTask(task.copyWith(recurrence: chosen));
              }
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
          if (task.recurrence != Recurrence.none) ...[
            ListTile(
              leading: const Icon(Icons.skip_next),
              title: const Text('Skip this occurrence'),
              subtitle: const Text('Move to the next date without completing'),
              onTap: () async {
                await repo.skipOccurrence(task);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_busy),
              title: const Text('Stop repeating'),
              subtitle: const Text('Keep the task, end the series'),
              onTap: () async {
                await repo.stopSeries(task);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete task'),
            onTap: () async {
              await repo.deleteTask(task.id);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
        ],
      ),
    ),
  );
}

/// Shows the task's reminders and opens the picker. Reminders need a start
/// time to fire, so the row says so when there is none.
class _ReminderRow extends ConsumerWidget {
  const _ReminderRow({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offsets = task.reminderOffsets;
    final summary = offsets.isEmpty
        ? 'None'
        : offsets.map(ReminderOffset.labelFor).join(', ');

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final chosen = await showReminderPicker(context, selected: offsets);
        if (chosen == null) return;
        await ref.read(repoProvider).updateTask(task.copyWith(reminderOffsets: chosen));
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications_none, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('REMINDERS',
                      style: TextStyle(fontSize: 10, letterSpacing: 0.8, color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text(summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (offsets.isNotEmpty && task.startDateTime == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Text('Set a date and time for these to fire',
                          style: TextStyle(fontSize: 11.5, color: AppColors.amber)),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _EditableTitle extends ConsumerStatefulWidget {
  const _EditableTitle({required this.task});
  final Task task;

  @override
  ConsumerState<_EditableTitle> createState() => _EditableTitleState();
}

class _EditableTitleState extends ConsumerState<_EditableTitle> {
  late final _controller = TextEditingController(text: widget.task.title);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: null,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      decoration: const InputDecoration(border: InputBorder.none, filled: false, isDense: true),
      onSubmitted: (value) {
        if (value.trim().isEmpty) return;
        ref.read(repoProvider).updateTask(widget.task.copyWith(title: value.trim()));
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 0.8, color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Unlimited subtasks: add, check, drag to reorder, rename, promote to a task.
class _SubtaskSection extends ConsumerStatefulWidget {
  const _SubtaskSection({required this.task});
  final Task task;

  @override
  ConsumerState<_SubtaskSection> createState() => _SubtaskSectionState();
}

class _SubtaskSectionState extends ConsumerState<_SubtaskSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(List<Subtask> subtasks) =>
      ref.read(repoProvider).updateTask(widget.task.copyWith(subtasks: subtasks));

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final subtasks = [...task.subtasks];
    final progress = subtasks.isEmpty ? 0.0 : task.doneSubtasks / subtasks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Subtasks', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('${task.doneSubtasks} of ${subtasks.length}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const Spacer(),
            Text('${(progress * 100).round()}%',
                style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: AppColors.primarySoft,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
        const SizedBox(height: 12),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) {
            // onReorderItem already accounts for the removed item.
            final item = subtasks.removeAt(oldIndex);
            subtasks.insert(newIndex, item);
            final positions = Position.rebalanced(subtasks.length);
            _save([
              for (var i = 0; i < subtasks.length; i++) subtasks[i].copyWith(position: positions[i]),
            ]);
          },
          children: [
            for (var i = 0; i < subtasks.length; i++)
              _SubtaskTile(
                key: ValueKey(subtasks[i].id),
                index: i,
                subtask: subtasks[i],
                onToggle: () {
                  final next = [...subtasks];
                  next[i] = next[i].copyWith(done: !next[i].done);
                  _save(next);
                },
                onDelete: () {
                  final next = [...subtasks]..removeAt(i);
                  _save(next);
                },
                onPromote: () async {
                  final sub = subtasks[i];
                  final tasks = ref.read(tasksProvider).value ?? const <Task>[];
                  final siblings = task.listId == null ? <Task>[] : tasksForList(tasks, task.listId!);
                  await ref.read(repoProvider).createTask(Task(
                        id: 'new',
                        title: sub.title,
                        listId: task.listId,
                        boardId: task.boardId,
                        categoryId: task.categoryId,
                        completed: sub.done,
                        position: Position.between(siblings.lastOrNull?.position, null),
                      ));
                  await _save([...subtasks]..removeAt(i));
                },
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(hintText: 'Add a subtask', isDense: true),
                onSubmitted: (_) => _add(subtasks),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: () => _add(subtasks), icon: const Icon(Icons.add)),
          ],
        ),
      ],
    );
  }

  void _add(List<Subtask> subtasks) {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    _save([
      ...subtasks,
      Subtask(
        id: const Uuid().v4(),
        title: title,
        position: Position.between(subtasks.lastOrNull?.position, null),
      ),
    ]);
    _controller.clear();
  }
}

class _SubtaskTile extends StatelessWidget {
  const _SubtaskTile({
    super.key,
    required this.index,
    required this.subtask,
    required this.onToggle,
    required this.onDelete,
    required this.onPromote,
  });

  final int index;
  final Subtask subtask;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onPromote;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                subtask.done ? Icons.check_circle : Icons.circle_outlined,
                color: subtask.done ? AppColors.success : AppColors.muted,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtask.title,
              style: TextStyle(
                decoration: subtask.done ? TextDecoration.lineThrough : null,
                color: subtask.done ? AppColors.muted : null,
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, size: 18),
            onSelected: (v) => v == 'promote' ? onPromote() : onDelete(),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'promote', child: Text('Convert to task')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_handle, size: 18, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

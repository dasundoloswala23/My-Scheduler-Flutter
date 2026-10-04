import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/move_controller.dart';
import '../../core/position.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import '../task_detail/task_detail_sheet.dart';

/// The `...` menu on every card.
///
/// This is the accessibility requirement: everything drag-and-drop can do is
/// also reachable here, for keyboard, screen-reader and one-handed use.
class TaskMenuButton extends ConsumerWidget {
  const TaskMenuButton({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Task actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      onSelected: (value) => _handle(context, ref, value),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit task'))),
        PopupMenuItem(value: 'list', child: ListTile(leading: Icon(Icons.view_week_outlined), title: Text('Change list'))),
        PopupMenuItem(value: 'category', child: ListTile(leading: Icon(Icons.label_outline), title: Text('Change category'))),
        PopupMenuItem(value: 'date', child: ListTile(leading: Icon(Icons.calendar_today_outlined), title: Text('Change date'))),
        PopupMenuItem(value: 'time', child: ListTile(leading: Icon(Icons.schedule), title: Text('Change time'))),
        PopupMenuItem(value: 'priority', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('Change priority'))),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete task'))),
      ],
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, String value) async {
    switch (value) {
      case 'edit':
        showTaskDetailSheet(context, task);
      case 'list':
        await _changeList(context, ref);
      case 'category':
        await _changeCategory(context, ref);
      case 'date':
        await _changeDate(context, ref);
      case 'time':
        await _changeTime(context, ref);
      case 'priority':
        await _changePriority(context, ref);
      case 'delete':
        await _confirmDelete(context, ref);
    }
  }

  Future<void> _changeList(BuildContext context, WidgetRef ref) async {
    final lists = ref.read(listsProvider).value ?? const <TaskList>[];
    final tasks = ref.read(tasksProvider).value ?? const <Task>[];
    final chosen = await showModalBottomSheet<TaskList>(
      context: context,
      builder: (context) => _PickerSheet(
        title: 'Move to list',
        children: [
          for (final l in lists)
            ListTile(
              leading: Icon(Icons.circle, size: 12, color: Color(l.colorValue)),
              title: Text(l.name),
              selected: l.id == task.listId,
              onTap: () => Navigator.pop(context, l),
            ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;

    final last = tasksForList(tasks, chosen.id).lastOrNull;
    await MoveController(ref).run(
      context: context,
      task: task,
      move: TaskMove(
        listId: chosen.id,
        boardId: chosen.boardId,
        position: Position.between(last?.position, null),
      ),
      description: 'Task moved to ${chosen.name}',
    );
  }

  Future<void> _changeCategory(BuildContext context, WidgetRef ref) async {
    final cats = ref.read(categoriesProvider).value ?? const <Category>[];
    final chosen = await showModalBottomSheet<Category>(
      context: context,
      builder: (context) => _PickerSheet(
        title: 'Move to category',
        children: [
          for (final c in cats)
            ListTile(
              leading: Icon(Icons.circle, size: 12, color: Color(c.colorValue)),
              title: Text(c.name),
              selected: c.id == task.categoryId,
              onTap: () => Navigator.pop(context, c),
            ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    await MoveController(ref).run(
      context: context,
      task: task,
      move: TaskMove(categoryId: chosen.id),
      description: 'Task moved to ${chosen.name}',
    );
  }

  Future<void> _changeDate(BuildContext context, WidgetRef ref) async {
    final base = task.startDateTime ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !context.mounted) return;

    final start = DateTime(picked.year, picked.month, picked.day, base.hour, base.minute);
    await MoveController(ref).run(
      context: context,
      task: task,
      move: TaskMove(startDateTime: start, endDateTime: start.add(task.duration)),
      description: 'Task moved to ${picked.day}/${picked.month}',
    );
  }

  Future<void> _changeTime(BuildContext context, WidgetRef ref) async {
    final base = task.startDateTime ?? DateTime.now();
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (picked == null || !context.mounted) return;

    final start = DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
    await MoveController(ref).run(
      context: context,
      task: task,
      move: TaskMove(startDateTime: start, endDateTime: start.add(task.duration)),
      description: 'Task moved to ${picked.format(context)}',
    );
  }

  Future<void> _changePriority(BuildContext context, WidgetRef ref) async {
    final chosen = await showModalBottomSheet<TaskPriority>(
      context: context,
      builder: (context) => _PickerSheet(
        title: 'Priority',
        children: [
          for (final p in TaskPriority.values)
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(p.label),
              selected: p == task.priority,
              onTap: () => Navigator.pop(context, p),
            ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    await MoveController(ref).run(
      context: context,
      task: task,
      move: TaskMove(priority: chosen),
      description: 'Priority set to ${chosen.label}',
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('"${task.title}" will be removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ref.read(repoProvider).deleteTask(task.id);
  }
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Flexible(child: ListView(shrinkWrap: true, children: children)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

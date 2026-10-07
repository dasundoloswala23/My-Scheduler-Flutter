import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/move_controller.dart';
import '../../core/providers.dart';
import '../../models/task.dart';
import '../boards/task_card.dart';
import '../dnd/drag_core.dart';
import 'more_page.dart';

/// Screenshot 8: the Eisenhower matrix.
///
/// Each quadrant maps to a priority, so dragging a card between quadrants is a
/// priority change written straight to Firestore, with the same undo as the
/// board.
class MatrixPage extends ConsumerWidget {
  const MatrixPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = (ref.watch(tasksProvider).value ?? const <Task>[])
        .where((t) => !t.completed)
        .toList();

    if (tasks.isEmpty) {
      return SubPage(
        eyebrow: 'My Scheduler App',
        title: 'Matrix',
        child: EmptyState(
          icon: Icons.grid_view,
          title: 'Your matrix lives here',
          actionLabel: 'Add Task',
          onAction: () => Navigator.pop(context),
        ),
      );
    }

    return SubPage(
      eyebrow: 'My Scheduler App',
      title: 'Matrix',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _Quadrant(
                      title: 'Do first',
                      subtitle: 'Urgent & important',
                      color: AppColors.danger,
                      priority: TaskPriority.high,
                      tasks: tasks.where((t) => t.priority == TaskPriority.high).toList(),
                    ),
                  ),
                  Expanded(
                    child: _Quadrant(
                      title: 'Schedule',
                      subtitle: 'Important, not urgent',
                      color: AppColors.blue,
                      priority: TaskPriority.medium,
                      tasks: tasks.where((t) => t.priority == TaskPriority.medium).toList(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _Quadrant(
                      title: 'Delegate',
                      subtitle: 'Urgent, not important',
                      color: AppColors.amber,
                      priority: TaskPriority.low,
                      tasks: tasks.where((t) => t.priority == TaskPriority.low).toList(),
                    ),
                  ),
                  Expanded(
                    child: _Quadrant(
                      title: 'Later',
                      subtitle: 'Neither',
                      color: AppColors.muted,
                      priority: TaskPriority.none,
                      tasks: tasks.where((t) => t.priority == TaskPriority.none).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Quadrant extends ConsumerStatefulWidget {
  const _Quadrant({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.priority,
    required this.tasks,
  });

  final String title;
  final String subtitle;
  final Color color;
  final TaskPriority priority;
  final List<Task> tasks;

  @override
  ConsumerState<_Quadrant> createState() => _QuadrantState();
}

class _QuadrantState extends ConsumerState<_Quadrant> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskDragData>(
      onWillAcceptWithDetails: (details) {
        final different = details.data.task.priority != widget.priority;
        if (different) setState(() => _hovering = true);
        return different;
      },
      onLeave: (_) => setState(() => _hovering = false),
      onAcceptWithDetails: (details) async {
        setState(() => _hovering = false);
        await MoveController(ref).run(
          context: context,
          task: details.data.task,
          move: TaskMove(priority: widget.priority),
          description: 'Moved to ${widget.title}',
        );
      },
      builder: (context, candidate, rejected) => Container(
        margin: const EdgeInsets.all(5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _hovering ? widget.color.withValues(alpha: 0.10) : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovering ? widget.color : widget.color.withValues(alpha: 0.25),
            width: _hovering ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 9, color: widget.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(widget.title,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: widget.color)),
                ),
                Text('${widget.tasks.length}',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
            Text(widget.subtitle, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final task in widget.tasks)
                    TaskDraggable(
                      data: TaskDragData(task),
                      feedbackWidth: 220,
                      child: TaskCard(task: task, showMenu: false),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

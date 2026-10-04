import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/move_controller.dart';
import '../../core/position.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import '../dnd/drag_core.dart';
import '../quick_add/quick_add_sheet.dart';
import 'task_card.dart';

/// A Trello-style board: horizontally scrolling lists, each holding draggable
/// cards. Cards can be reordered inside a list and moved between lists.
class BoardView extends ConsumerStatefulWidget {
  const BoardView({super.key, required this.boardId});

  final String boardId;

  @override
  ConsumerState<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends ConsumerState<BoardView> {
  final _horizontal = ScrollController();
  late final _autoScroller = EdgeAutoScroller(_horizontal);
  String? _filterCategoryId;

  @override
  void dispose() {
    _autoScroller.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lists = (ref.watch(listsProvider).value ?? const <TaskList>[])
        .where((l) => l.boardId == widget.boardId)
        .toList();
    final allTasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final boards = ref.watch(boardsProvider).value ?? const <Board>[];
    final board = boards.where((b) => b.id == widget.boardId).firstOrNull;

    // Filtering only hides cards; it never touches the stored data.
    final tasks = _filterCategoryId == null
        ? allTasks
        : allTasks.where((t) => t.categoryId == _filterCategoryId).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (board?.workspace ?? 'PERSONAL WORKSPACE').toUpperCase(),
                      style: const TextStyle(fontSize: 10, letterSpacing: 1.2, color: AppColors.muted),
                    ),
                    Text(board?.name ?? 'Board',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              _FilterButton(
                selectedId: _filterCategoryId,
                onChanged: (id) => setState(() => _filterCategoryId = id),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              for (final list in lists)
                _ListColumn(
                  list: list,
                  tasks: tasksForList(tasks, list.id),
                  onDragUpdate: _onDragUpdate,
                  onDragEnd: _autoScroller.stop,
                ),
              _AddListButton(boardId: widget.boardId),
            ],
          ),
        ),
      ],
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final size = MediaQuery.sizeOf(context);
    _autoScroller.update(details.globalPosition, size);
  }
}

class _ListColumn extends ConsumerStatefulWidget {
  const _ListColumn({
    required this.list,
    required this.tasks,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final TaskList list;
  final List<Task> tasks;
  final void Function(DragUpdateDetails) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  ConsumerState<_ListColumn> createState() => _ListColumnState();
}

class _ListColumnState extends ConsumerState<_ListColumn> {
  final _vertical = ScrollController();
  late final _autoScroller = EdgeAutoScroller(_vertical, axis: Axis.vertical, edge: 70);

  @override
  void dispose() {
    _autoScroller.dispose();
    _vertical.dispose();
    super.dispose();
  }

  /// Moves [data]'s task into this list at slot [index].
  Future<void> _drop(TaskDragData data, int index) async {
    final task = data.task;

    // Neighbours, ignoring the card being dragged so a move inside the same
    // list lands where the indicator showed.
    final others = widget.tasks.where((t) => t.id != task.id).toList();
    final clamped = index.clamp(0, others.length);
    final prev = clamped > 0 ? others[clamped - 1].position : null;
    final next = clamped < others.length ? others[clamped].position : null;

    if (Position.needsRebalance(prev, next)) {
      await _rebalance(others);
      return;
    }

    final movedLists = task.listId != widget.list.id;
    await MoveController(ref).run(
      context: context,
      task: task,
      move: TaskMove(
        position: Position.between(prev, next),
        listId: widget.list.id,
        boardId: widget.list.boardId,
      ),
      description: movedLists ? 'Task moved to ${widget.list.name}' : 'Task reordered',
      allowUndo: movedLists,
    );
  }

  /// Renumbers a list when two neighbours get too close to split again.
  Future<void> _rebalance(List<Task> items) async {
    final repo = ref.read(repoProvider);
    final positions = Position.rebalanced(items.length);
    for (var i = 0; i < items.length; i++) {
      await repo.moveTask(
        taskId: items[i].id,
        expectedVersion: items[i].version,
        position: positions[i],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 320,
      margin: const EdgeInsets.only(right: 14),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? const Color(0xFF17181D) : const Color(0xFFEDEFF3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 0, 8),
            child: Row(
              children: [
                Icon(Icons.circle, size: 9, color: Color(widget.list.colorValue)),
                const SizedBox(width: 8),
                Text(widget.list.name,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${widget.tasks.length}', style: const TextStyle(fontSize: 11)),
                ),
                const Spacer(),
                _ListMenu(list: widget.list),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _vertical,
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < widget.tasks.length; i++) ...[
                  DropGap(onAccept: (data) => _drop(data, i)),
                  TaskDraggable(
                    data: TaskDragData(widget.tasks[i], fromListId: widget.list.id),
                    onDragUpdate: (d) {
                      widget.onDragUpdate(d);
                      _autoScroller.update(d.globalPosition, MediaQuery.sizeOf(context));
                    },
                    onDragEnd: () {
                      widget.onDragEnd();
                      _autoScroller.stop();
                    },
                    child: TaskCard(task: widget.tasks[i]),
                  ),
                ],
                // The trailing zone is the big dashed "Drop task here" target.
                _TailDropZone(onAccept: (data) => _drop(data, widget.tasks.length)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => showQuickAddSheet(
              context,
              listId: widget.list.id,
              boardId: widget.list.boardId,
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add task'),
          ),
        ],
      ),
    );
  }
}

class _TailDropZone extends StatefulWidget {
  const _TailDropZone({required this.onAccept});
  final void Function(TaskDragData) onAccept;

  @override
  State<_TailDropZone> createState() => _TailDropZoneState();
}

class _TailDropZoneState extends State<_TailDropZone> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskDragData>(
      onWillAcceptWithDetails: (_) {
        setState(() => _hovering = true);
        return true;
      },
      onLeave: (_) => setState(() => _hovering = false),
      onAcceptWithDetails: (details) {
        setState(() => _hovering = false);
        widget.onAccept(details.data);
      },
      builder: (context, candidate, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: _hovering ? 64 : 46,
        margin: const EdgeInsets.only(top: 6, bottom: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _hovering ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovering ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
            width: _hovering ? 2 : 1.4,
          ),
        ),
        child: Text(
          'Drop task here',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.primary.withValues(alpha: _hovering ? 1 : 0.7),
          ),
        ),
      ),
    );
  }
}

class _ListMenu extends ConsumerWidget {
  const _ListMenu({required this.list});
  final TaskList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) async {
        final repo = ref.read(repoProvider);
        if (value == 'rename') {
          final name = await _promptName(context, list.name);
          if (name != null) await repo.saveList(list.copyWith(name: name));
        } else if (value == 'delete') {
          await repo.deleteList(list.id);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text('Rename list')),
        if (!list.isSystem) const PopupMenuItem(value: 'delete', child: Text('Delete list')),
      ],
    );
  }
}

class _AddListButton extends ConsumerWidget {
  const _AddListButton({required this.boardId});
  final String boardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 14),
      child: OutlinedButton.icon(
        onPressed: () async {
          final name = await _promptName(context, '');
          if (name == null) return;
          final lists = ref.read(listsProvider).value ?? const <TaskList>[];
          final last = lists.where((l) => l.boardId == boardId).lastOrNull;
          await ref.read(repoProvider).addList(TaskList(
                id: 'new',
                boardId: boardId,
                name: name,
                position: Position.between(last?.position, null),
              ));
        },
        icon: const Icon(Icons.add),
        label: const Text('Add another list'),
      ),
    );
  }
}

class _FilterButton extends ConsumerWidget {
  const _FilterButton({required this.selectedId, required this.onChanged});

  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    return PopupMenuButton<String?>(
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('All categories')),
        for (final c in categories) PopupMenuItem(value: c.id, child: Text(c.name)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.filter_list, size: 16, color: selectedId == null ? AppColors.muted : AppColors.primary),
          const SizedBox(width: 6),
          const Text('Filter', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
    );
  }
}

Future<String?> _promptName(BuildContext context, String initial) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('List name'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return (result == null || result.isEmpty) ? null : result;
}

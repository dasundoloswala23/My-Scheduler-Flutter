import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
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

  /// True while any card is being dragged; the drop zones open up for it.
  final _dragging = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _dragging.dispose();
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
                      style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: context.palette.textSecondary),
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
          // Columns are top-aligned and sized to their cards, so a board of
          // short lists reads as a row of cards rather than a row of tall
          // empty panels.
          child: ListView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              for (final list in lists)
                _ListColumn(
                  list: list,
                  boardLists: lists,
                  tasks: tasksForList(tasks, list.id),
                  dragging: _dragging,
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
    required this.boardLists,
    required this.tasks,
    required this.dragging,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final TaskList list;

  /// Every list on the board, in order, for the Move left / right menu.
  final List<TaskList> boardLists;
  final List<Task> tasks;
  final ValueNotifier<bool> dragging;
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
    final palette = context.palette;
    final isEmpty = widget.tasks.isEmpty;

    // The column sizes to its cards instead of filling the viewport, which is
    // what removes the tall empty black area under a short list (section 2).
    // `Flexible` still caps it at the available height, so a long list scrolls
    // rather than overflowing.
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        width: _columnWidth(MediaQuery.sizeOf(context).width),
        margin: const EdgeInsets.only(right: 14),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
        decoration: BoxDecoration(
          color: palette.surfaceVariant,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 0, 8),
              child: Row(
                children: [
                  Icon(Icons.circle,
                      size: 9, color: palette.onTint(Color(widget.list.colorValue))),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: palette.hover,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${widget.tasks.length}',
                        style: TextStyle(fontSize: 11, color: palette.textSecondary)),
                  ),
                  const Spacer(),
                  _ListMenu(list: widget.list, boardLists: widget.boardLists),
                ],
              ),
            ),
            if (isEmpty)
              // An empty list still needs a comfortable drop target, just not
              // a viewport-tall one.
              _DropZone(
                dragging: widget.dragging,
                onAccept: (data) => _drop(data, 0),
                label: 'No tasks yet',
                sublabel: 'Drop a task here',
                restingHeight: 92,
                draggingHeight: 92,
                alwaysShowLabel: true,
              )
            else
              Flexible(
                child: ListView(
                  controller: _vertical,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (var i = 0; i < widget.tasks.length; i++) ...[
                      if (i == 0)
                        _DropZone(
                          dragging: widget.dragging,
                          onAccept: (data) => _drop(data, 0),
                          label: 'Drop task here',
                        )
                      else
                        DropGap(onAccept: (data) => _drop(data, i)),
                      TaskDraggable(
                        data: TaskDragData(widget.tasks[i], fromListId: widget.list.id),
                        onDragStarted: () => widget.dragging.value = true,
                        onDragUpdate: (d) {
                          widget.onDragUpdate(d);
                          _autoScroller.update(d.globalPosition, MediaQuery.sizeOf(context));
                        },
                        onDragEnd: () {
                          widget.dragging.value = false;
                          widget.onDragEnd();
                          _autoScroller.stop();
                        },
                        child: TaskCard(task: widget.tasks[i]),
                      ),
                    ],
                    _DropZone(
                      dragging: widget.dragging,
                      onAccept: (data) => _drop(data, widget.tasks.length),
                      label: 'Drop at the end',
                      restingHeight: 24,
                    ),
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
      ),
    );
  }

  /// Narrower columns on a small laptop so three still fit without the board
  /// clipping, wider on a large display where there is room to read.
  double _columnWidth(double screenWidth) {
    if (screenWidth < 420) return screenWidth - 48;
    if (screenWidth < 1400) return 300;
    return 330;
  }
}

/// A labelled drop target that is only prominent while a card is being dragged.
///
/// While nothing is being dragged it collapses to a thin strip, so a list is not
/// carrying permanent empty boxes. As soon as a drag starts it opens up and
/// says what it is, and while a card hovers over it it grows further with a
/// violet outline. The same widget serves as the top zone, the between-card
/// gaps' bigger sibling at the end, and the whole target of an empty list.
class _DropZone extends StatefulWidget {
  const _DropZone({
    required this.dragging,
    required this.onAccept,
    required this.label,
    this.sublabel,
    this.restingHeight = 8,
    this.draggingHeight = 40,
    this.alwaysShowLabel = false,
  });

  final ValueListenable<bool> dragging;
  final void Function(TaskDragData) onAccept;
  final String label;
  final String? sublabel;

  /// Height when nothing is being dragged. Never zero: the zone must stay a
  /// valid target the instant a drag begins.
  final double restingHeight;
  final double draggingHeight;

  /// True for an empty list, whose zone is its only content.
  final bool alwaysShowLabel;

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ValueListenableBuilder<bool>(
      valueListenable: widget.dragging,
      builder: (context, isDragging, _) {
        final open = isDragging || _hovering || widget.alwaysShowLabel;

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
            curve: Curves.easeOut,
            height: _hovering
                ? widget.draggingHeight + 16
                : (open ? widget.draggingHeight : widget.restingHeight),
            margin: EdgeInsets.symmetric(vertical: open ? 4 : 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovering ? palette.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: open
                  ? Border.all(
                      color: _hovering ? AppColors.primary : palette.border,
                      width: _hovering ? 2 : 1.4,
                    )
                  : null,
            ),
            // Clipped, not laid out at its natural size: while the zone animates
            // open its height is smaller than its text, which would overflow.
            child: open
                ? ClipRect(
                    child: OverflowBox(
                      maxHeight: double.infinity,
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _hovering ? 'Drop task here' : widget.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _hovering ? AppColors.primary : palette.textSecondary,
                        ),
                      ),
                      if (widget.sublabel != null && !_hovering) ...[
                        const SizedBox(height: 3),
                        Text(widget.sublabel!,
                            style: TextStyle(fontSize: 11.5, color: palette.textDisabled)),
                      ],
                    ],
                    ),
                  ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _ListMenu extends ConsumerWidget {
  const _ListMenu({required this.list, required this.boardLists});
  final TaskList list;
  final List<TaskList> boardLists;

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
        } else if (value == 'left') {
          await repo.moveListBy(list.id, -1);
        } else if (value == 'right') {
          await repo.moveListBy(list.id, 1);
        }
      },
      itemBuilder: (context) {
        final index = boardLists.indexWhere((l) => l.id == list.id);
        return [
        const PopupMenuItem(value: 'rename', child: Text('Rename list')),
        PopupMenuItem(value: 'left', enabled: index > 0, child: const Text('Move left')),
        PopupMenuItem(
            value: 'right',
            enabled: index >= 0 && index < boardLists.length - 1,
            child: const Text('Move right')),
        if (!list.isSystem) const PopupMenuItem(value: 'delete', child: Text('Delete list')),
        ];
      },
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
    final palette = context.palette;
    final selected = categories.where((c) => c.id == selectedId).firstOrNull;

    return PopupMenuButton<String?>(
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        _item(null, 'All categories', null),
        for (final c in categories)
          _item(c.id, c.name, palette.onTint(Color(c.colorValue))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selectedId == null ? palette.border : AppColors.primary),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.filter_list,
              size: 16, color: selectedId == null ? palette.textSecondary : AppColors.primary),
          const SizedBox(width: 6),
          // Showing the active category, not just "Filter", so it is obvious
          // why cards are missing from the board.
          Text(selected?.name ?? 'All categories',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: selectedId == null ? palette.textPrimary : AppColors.primary,
              )),
        ]),
      ),
    );
  }

  PopupMenuItem<String?> _item(String? value, String label, Color? dot) {
    return PopupMenuItem<String?>(
      value: value,
      child: Row(
        children: [
          if (dot != null) ...[
            Icon(Icons.circle, size: 9, color: dot),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(label)),
          if (value == selectedId)
            const Icon(Icons.check, size: 16, color: AppColors.primary),
        ],
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

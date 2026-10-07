import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/position.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import 'board_view.dart';

/// Screenshot 20: the list of boards, opening into the drag-and-drop board.
class BoardsPage extends ConsumerStatefulWidget {
  const BoardsPage({super.key});

  @override
  ConsumerState<BoardsPage> createState() => _BoardsPageState();
}

class _BoardsPageState extends ConsumerState<BoardsPage> {
  String? _openBoardId;

  @override
  Widget build(BuildContext context) {
    final boards = ref.watch(boardsProvider).value ?? const <Board>[];
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final lists = ref.watch(listsProvider).value ?? const <TaskList>[];

    if (_openBoardId != null && boards.any((b) => b.id == _openBoardId)) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _openBoardId = null),
              icon: const Icon(Icons.chevron_left),
              label: const Text('All boards'),
            ),
          ),
          Expanded(child: BoardView(boardId: _openBoardId!)),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${boards.length} WORKSPACES',
                      style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: context.palette.textSecondary)),
                  Text('Boards',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            IconButton(onPressed: () => _createBoard(context), icon: const Icon(Icons.add)),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Your boards', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),
        for (final board in boards)
          _BoardTile(
            board: board,
            taskCount: tasks.where((t) => t.boardId == board.id).length,
            listCount: lists.where((l) => l.boardId == board.id).length,
            onTap: () => setState(() => _openBoardId = board.id),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _createBoard(context),
          icon: const Icon(Icons.add),
          label: const Text('Create board'),
        ),
      ],
    );
  }

  Future<void> _createBoard(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New board'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Board name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    final repo = ref.read(repoProvider);
    final boards = ref.read(boardsProvider).value ?? const <Board>[];
    final boardId = await repo.addBoard(
      Board(id: 'new', name: name, position: Position.between(boards.lastOrNull?.position, null)),
    );
    // A new board starts with the same default columns as the first one.
    const names = ['Inbox', 'Todo', 'In progress', 'Waiting', 'Done'];
    for (var i = 0; i < names.length; i++) {
      await repo.addList(TaskList(id: 'new', boardId: boardId, name: names[i], position: (i + 1) * 1000));
    }
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({
    required this.board,
    required this.taskCount,
    required this.listCount,
    required this.onTap,
  });

  final Board board;
  final int taskCount;
  final int listCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Color(board.colorValue).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.view_week, color: Color(board.colorValue)),
        ),
        title: Text(board.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$taskCount tasks · $listCount lists',
            style: TextStyle(color: context.palette.textSecondary, fontSize: 12.5)),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

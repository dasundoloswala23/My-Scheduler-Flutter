import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collections.dart' show TaskList;
import '../models/task.dart';
import 'providers.dart';
import 'repository.dart';

/// Describes one drag-and-drop move. Fields left null are unchanged, except
/// the three `clear*` flags, which exist so a move can explicitly unset a value
/// (dragging a scheduled task back to the board clears its times).
class TaskMove {
  const TaskMove({
    this.position,
    this.listId,
    this.boardId,
    this.categoryId,
    this.startDateTime,
    this.endDateTime,
    this.priority,
    this.clearSchedule = false,
    this.clearList = false,
  });

  final double? position;
  final String? listId;
  final String? boardId;
  final String? categoryId;
  final DateTime? startDateTime;
  final DateTime? endDateTime;
  final TaskPriority? priority;
  final bool clearSchedule;
  final bool clearList;

  /// The task as it will look once this move is applied.
  Task applyTo(Task t) => t.copyWith(
        position: position,
        listId: clearList ? null : (listId ?? t.listId),
        boardId: boardId ?? t.boardId,
        categoryId: categoryId ?? t.categoryId,
        startDateTime: clearSchedule ? null : (startDateTime ?? t.startDateTime),
        endDateTime: clearSchedule ? null : (endDateTime ?? t.endDateTime),
        priority: priority,
      );
}

/// Runs every drag-and-drop move: optimistic update first, Firestore second,
/// rollback plus an error on failure, and an Undo snackbar on success.
///
/// A move never deletes a task. If a drop lands somewhere invalid the caller
/// simply does not call this, and the card animates back by itself.
class MoveController {
  const MoveController(this.ref);

  final WidgetRef ref;

  Future<void> run({
    required BuildContext context,
    required Task task,
    required TaskMove move,
    required String description,
    bool allowUndo = true,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final overrides = ref.read(taskOverridesProvider.notifier);
    final repo = ref.read(repoProvider);

    // Dropping a card onto the Complete list completes it, and dragging a
    // completed card out of that list re-opens it. Both go through the same code
    // as ticking the circle, so a task ends up in the same state either way: its
    // reminders cancelled or restored, and a repeating task's next occurrence
    // created or removed.
    final lists = ref.read(listsProvider).value ?? const <TaskList>[];
    TaskList? listById(String? id) => lists.where((l) => l.id == id).firstOrNull;
    final target = move.clearList ? null : listById(move.listId);
    final source = listById(task.listId);
    final completing = !task.completed && target != null && target.isComplete;
    final reopening =
        task.completed && source != null && source.isComplete && target != null && !target.isComplete;

    // 1. Move it on screen straight away.
    var optimistic = move.applyTo(task);
    if (completing) optimistic = optimistic.copyWith(completed: true);
    if (reopening) optimistic = optimistic.copyWith(completed: false);
    overrides.put(optimistic);

    try {
      // 2. Write it.
      if (completing) {
        await repo.completeTask(task, position: move.position);
      } else if (reopening) {
        await repo.reopenTask(task, toListId: move.listId, position: move.position);
      } else {
        // An ordinary move, in a transaction that bumps `version`.
        await repo.moveTask(
          taskId: task.id,
          expectedVersion: task.version,
          position: move.position,
          listId: move.clearList ? null : (move.listId ?? task.listId),
          boardId: move.boardId ?? task.boardId,
          categoryId: move.categoryId ?? task.categoryId,
          startDateTime: move.clearSchedule ? null : (move.startDateTime ?? task.startDateTime),
          endDateTime: move.clearSchedule ? null : (move.endDateTime ?? task.endDateTime),
          priority: move.priority,
        );
      }

      // The server stream now carries the change, so drop the override.
      overrides.clear(task.id);

      if (allowUndo && context.mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(description),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () => _undo(task, wasCompleting: completing, wasReopening: reopening),
            ),
          ),
        );
      }
    } catch (e) {
      // 3. Put it back where it was and say why.
      overrides.clear(task.id);
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text(e is TaskGoneException
              ? 'That task no longer exists.'
              : 'Could not save the move. Check your connection.'),
        ),
      );
    }
  }

  /// Puts the task back as it was.
  ///
  /// Undoing a completion has to re-open the task, not just move it: moving it
  /// back to its old list would leave it marked completed.
  Future<void> _undo(
    Task previous, {
    bool wasCompleting = false,
    bool wasReopening = false,
  }) async {
    try {
      final repo = ref.read(repoProvider);
      if (wasCompleting) {
        await repo.reopenTask(previous, toListId: previous.listId, position: previous.position);
        return;
      }
      if (wasReopening) {
        await repo.completeTask(previous, position: previous.position);
        return;
      }
      await repo.moveTask(
            taskId: previous.id,
            expectedVersion: previous.version,
            position: previous.position,
            listId: previous.listId,
            boardId: previous.boardId,
            categoryId: previous.categoryId,
            startDateTime: previous.startDateTime,
            endDateTime: previous.endDateTime,
            priority: previous.priority,
          );
    } catch (_) {
      // Undo is best effort; the live stream still shows the truth.
    }
  }
}

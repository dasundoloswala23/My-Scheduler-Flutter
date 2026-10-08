import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../models/collections.dart';
import '../models/task.dart';
import 'attachment_service.dart';
import 'flows/flow_repository.dart';
import 'list_order.dart';
import 'position.dart';
import 'recurrence.dart';
import 'notifications/models/notification_preferences.dart';
import 'notifications/platform/local_notification_adapter.dart';
import 'notifications/services/notification_service.dart';

// Re-exported so code that imported it from here keeps working.
export 'recurrence.dart' show nextOccurrence;

typedef Json = Map<String, dynamic>;

/// All reads and writes for the signed-in user. Every document lives under
/// `users/{uid}/…`, which is exactly what firestore.rules allows.
class Repo {
  Repo({FirebaseFirestore? db, String? uid, NotificationService? notifications})
      : _db = db ?? FirebaseFirestore.instance,
        _uid = uid ?? FirebaseAuth.instance.currentUser?.uid ?? '_anon',
        _injectedNotifications = notifications;

  /// Supplied by tests, so the repository can be exercised without a platform
  /// notification plugin. In the app it is null and a real one is used.
  final NotificationService? _injectedNotifications;

  final FirebaseFirestore _db;
  final String _uid;

  DocumentReference<Json> get _user => _db.collection('users').doc(_uid);

  /// Project Flows: stages and the links between them and this repo's tasks.
  late final FlowRepo flows = FlowRepo(db: _db, uid: _uid);

  /// Brings the flow a task belongs to up to date after the task changed.
  /// Failure is isolated: a flow that cannot be refreshed now is refreshed by
  /// the next change, and the screens derive their state live anyway.
  Future<void> _syncFlowFor(String taskId) async {
    try {
      await flows.recomputeForTask(taskId);
    } catch (e) {
      debugPrint('Could not update the flow for task $taskId: $e');
    }
  }

  CollectionReference<Json> get tasks => _user.collection('tasks');
  CollectionReference<Json> get boards => _user.collection('boards');
  CollectionReference<Json> get lists => _user.collection('lists');
  CollectionReference<Json> get categories => _user.collection('categories');
  CollectionReference<Json> get notes => _user.collection('notes');
  CollectionReference<Json> get reminders => _user.collection('reminders');
  CollectionReference<Json> get holidays => _user.collection('holidays');
  CollectionReference<Json> get focusSessions => _user.collection('focusSessions');

  // ---------------------------------------------------------------- streams

  Stream<List<Task>> watchTasks() => tasks.snapshots().map(
      (s) => s.docs.map(Task.fromDoc).toList()..sort((a, b) => a.position.compareTo(b.position)));

  Stream<List<Board>> watchBoards() => boards.snapshots().map(
      (s) => s.docs.map(Board.fromDoc).toList()..sort((a, b) => a.position.compareTo(b.position)));

  Stream<List<TaskList>> watchLists() => lists.snapshots().map(
      (s) => s.docs.map(TaskList.fromDoc).toList()..sort((a, b) => a.position.compareTo(b.position)));

  Stream<List<Category>> watchCategories() => categories.snapshots().map(
      (s) => s.docs.map(Category.fromDoc).toList()..sort((a, b) => a.position.compareTo(b.position)));

  Stream<List<Note>> watchNotes() => notes.snapshots().map((s) => s.docs.map(Note.fromDoc).toList());

  Stream<List<Reminder>> watchReminders() => reminders.snapshots().map(
      (s) => s.docs.map(Reminder.fromDoc).toList()..sort((a, b) => a.remindAt.compareTo(b.remindAt)));

  Stream<List<Holiday>> watchHolidays() => holidays.snapshots().map(
      (s) => s.docs.map(Holiday.fromDoc).toList()..sort((a, b) => a.date.compareTo(b.date)));

  Stream<List<FocusSession>> watchFocusSessions() => focusSessions.snapshots().map(
      (s) => s.docs.map(FocusSession.fromDoc).toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt)));

  // ----------------------------------------------------------------- writes

  /// Notification work goes through one service so scheduling rules live in a
  /// single, tested place rather than being scattered through the repository.
  NotificationService get _notifications =>
      _injectedNotifications ?? NotificationService(adapter: LocalNotificationAdapter());

  NotificationPreferences _preferences = const NotificationPreferences();

  /// The repository schedules against the user's current preferences; the UI
  /// pushes them in whenever they change.
  set notificationPreferences(NotificationPreferences value) => _preferences = value;

  Future<String> createTask(Task task) async {
    final doc = tasks.doc();

    // A task created directly in the Complete list is a completed task. Without
    // this, "Add task" on that column would leave an unfinished task sitting
    // among the finished ones.
    var toWrite = task;
    if (task.listId != null && !task.completed) {
      final list = await lists.doc(task.listId!).get();
      if (list.exists && TaskList.fromDoc(list).isComplete) {
        toWrite = task.copyWith(completed: true, completedAt: DateTime.now());
      }
    }

    // The id is known before the write, so the reminders are stored against the
    // real task rather than the placeholder they were built with.
    final keyed = toWrite.copyWith(
      reminders: [for (final r in toWrite.reminders) r.withTaskId(doc.id)],
    );
    await doc.set({...keyed.toJson(), 'createdAt': FieldValue.serverTimestamp()});

    final saved = keyed.copyWithId(doc.id);
    await _notifications.sync(
      task: saved,
      reminders: saved.effectiveReminders,
      preferences: _preferences,
    );
    return doc.id;
  }

  /// [previous] is the task as it was before the edit. Passing it lets the
  /// service cancel alerts for reminders that have just been removed or had
  /// their offset changed, which is what prevents a stale notification after
  /// the task's time is moved.
  Future<void> updateTask(Task task, {Task? previous}) async {
    await tasks.doc(task.id).update({...task.toJson(), 'version': FieldValue.increment(1)});
    await _notifications.sync(
      task: task,
      reminders: task.effectiveReminders,
      previousReminders: previous?.effectiveReminders ?? const [],
      preferences: _preferences,
    );
  }

  /// Deletes the task and everything hanging off it.
  ///
  /// Attachment metadata and the stored files go first, so deleting a task
  /// never leaves orphaned objects in Storage paying rent.
  Future<void> deleteTask(String id) async {
    // Cancel the alerts first, while the task is still readable. Otherwise a
    // deleted task can still fire a reminder for something that no longer
    // exists, and nothing is left that knows which ids to cancel.
    try {
      final snap = await tasks.doc(id).get();
      if (snap.exists) {
        final task = Task.fromDoc(snap);
        await _notifications.cancelForTask(task, task.effectiveReminders);
      }
    } catch (_) {
      // Best effort: a scheduling failure must not block the delete.
    }

    try {
      await AttachmentService(db: _db, uid: _uid).deleteAllFor(id);
    } catch (_) {
      // A storage failure must not strand the task itself; the file clean-up
      // can be retried, an undeletable task cannot be worked around.
    }
    await tasks.doc(id).delete();

    // A deleted task leaves its flow; the stage then counts the tasks it has.
    try {
      await flows.unlinkTask(id);
    } catch (e) {
      debugPrint('Could not unlink deleted task $id from its flow: $e');
    }
  }

  /// Applies a drag-and-drop move in a transaction.
  ///
  /// Only the fields that actually changed are written. [expectedVersion] is the
  /// version the dragged card was showing; if another device has written since,
  /// the move still applies but the caller is told via [MoveResult.hadConflict]
  /// so it can refresh. Throws [TaskGoneException] if the task was deleted
  /// elsewhere, so the UI can roll back instead of recreating a dead task.
  Future<MoveResult> moveTask({
    required String taskId,
    required int expectedVersion,
    double? position,
    Object? listId = _unset,
    Object? boardId = _unset,
    Object? categoryId = _unset,
    Object? startDateTime = _unset,
    Object? endDateTime = _unset,
    TaskPriority? priority,
  }) async {
    final ref = tasks.doc(taskId);
    final result = await _db.runTransaction<MoveResult>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw const TaskGoneException();

      final current = (snap.data()?['version'] as num?)?.toInt() ?? 1;
      final data = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'version': current + 1,
      };
      if (position != null) data['position'] = position;
      if (listId != _unset) data['listId'] = listId;
      if (boardId != _unset) data['boardId'] = boardId;
      if (categoryId != _unset) data['categoryId'] = categoryId;
      if (startDateTime != _unset) {
        final value = startDateTime as DateTime?;
        data['startDateTime'] = value == null ? null : Timestamp.fromDate(value);
        data['hasSchedule'] = value != null;
      }
      if (endDateTime != _unset) {
        final value = endDateTime as DateTime?;
        data['endDateTime'] = value == null ? null : Timestamp.fromDate(value);
      }
      if (priority != null) data['priority'] = priority.name;

      tx.update(ref, data);
      return MoveResult(hadConflict: current != expectedVersion, newVersion: current + 1);
    });

    // A reminder is counted from the task's start, so moving the task has to
    // move its alerts. Without this the old alert still fires at the old time
    // and nothing fires at the new one. Only a change to the start (or to the
    // category, which can be muted) affects scheduling; a plain reorder does not.
    if (startDateTime != _unset || categoryId != _unset) {
      await _resyncReminders(taskId);
    }
    return result;
  }

  /// Brings the platform's alerts in line with the task as it is now in
  /// Firestore. A failure here must not undo a move that has already been saved,
  /// so it is reported rather than thrown.
  Future<void> _resyncReminders(String taskId) async {
    try {
      final snap = await tasks.doc(taskId).get();
      if (!snap.exists) return;
      final task = Task.fromDoc(snap);
      await _notifications.sync(
        task: task,
        reminders: task.effectiveReminders,
        preferences: _preferences,
      );
    } catch (e) {
      debugPrint('Could not reschedule reminders for task $taskId: $e');
    }
  }

  /// Completes or re-opens a task. The one entry point the UI, notifications and
  /// drag-and-drop all use, so a task behaves the same however it was finished.
  Future<void> setTaskCompleted(Task task, bool completed) =>
      completed ? completeTask(task) : reopenTask(task);

  /// Completes a task.
  ///
  /// The task is **moved** to its board's Complete list, never copied: it keeps
  /// its id, its history and its attachments. Where it came from is remembered so
  /// it can be put back. Future reminders are cancelled.
  ///
  /// A repeating task also gets its next occurrence, in the list the task came
  /// from. That next occurrence has a **deterministic id** derived from the task
  /// and the occurrence being completed, so completing the same occurrence twice
  /// (a double tap, two devices, the notification and the app at once) writes the
  /// same document twice instead of creating two. The two writes happen in one
  /// atomic batch.
  ///
  /// It is a batch and not a transaction on purpose: transactions fail when the
  /// device is offline, and ticking a task off on a phone with no signal has to
  /// keep working. The batch is queued and sent on reconnect.
  Future<void> completeTask(Task task, {double? position}) async {
    final taskRef = tasks.doc(task.id);
    final snap = await taskRef.get();
    if (!snap.exists) throw const TaskGoneException();
    final current = Task.fromDoc(snap);
    if (current.completed) return; // already done: nothing to move, nothing to spawn
    await commitCompletion(current, position: position);
  }

  /// The write half of [completeTask], from a snapshot already known to be open.
  ///
  /// It is separate so a test can run it twice from the same stale snapshot. That
  /// is exactly what two devices (or the app and a notification action) do when
  /// they both pass the "already completed?" check before either has written, and
  /// it is the case the deterministic next-occurrence id exists to survive.
  @visibleForTesting
  Future<void> commitCompletion(Task current, {double? position}) async {
    final taskRef = tasks.doc(current.id);
    final completeList =
        current.boardId == null ? null : await _completeListFor(current.boardId!);

    // Where the task was, so reopening can restore it. If it is somehow already
    // in the Complete list, keep whatever origin was recorded.
    final origin =
        current.listId != completeList?.id ? current.listId : current.completedFromListId;

    final update = <String, dynamic>{
      'completed': true,
      'completedAt': Timestamp.fromDate(DateTime.now()),
      'updatedAt': FieldValue.serverTimestamp(),
      'version': FieldValue.increment(1),
    };
    if (completeList != null) {
      update['listId'] = completeList.id;
      update['position'] = position ?? await _topPositionIn(completeList.id, except: current.id);
      update['completedFromListId'] = origin;
    }

    final batch = _db.batch();

    Task? next;
    if (current.recurrence != Recurrence.none &&
        current.startDateTime != null &&
        current.spawnedNextTaskId == null) {
      final nextStart = nextOccurrence(current.startDateTime!, current.recurrence);
      if (nextStart != null) {
        final nextId = _nextOccurrenceId(current);
        final span = current.endDateTime?.difference(current.startDateTime!);
        final base = current.copyWith(
          listId: origin,
          // The next occurrence is a fresh task: not done, no files, no history.
          completed: false,
          completedAt: null,
          completedFromListId: null,
          spawnedNextTaskId: null,
          startDateTime: nextStart,
          endDateTime: span == null ? null : nextStart.add(span),
          subtasks: [for (final s in current.subtasks) s.copyWith(done: false)],
          attachments: const [],
          attachmentCount: 0,
          attachmentPreview: null,
          version: 1,
        );
        next = base.copyWithId(nextId);
        // Its reminders belong to it, not to the task it was copied from.
        next = next.copyWith(
          reminders: [for (final r in next.reminders) r.withTaskId(nextId)],
        );
        batch.set(tasks.doc(nextId), {...next.toJson(), 'createdAt': FieldValue.serverTimestamp()});
        update['spawnedNextTaskId'] = nextId;
      }
    }

    batch.update(taskRef, update);
    await batch.commit();
    await _syncFlowFor(current.id);

    // After the commit, so a platform failure never undoes the completion.
    try {
      await _notifications.cancelForTask(current, current.effectiveReminders);
      if (next != null) {
        await _notifications.sync(
          task: next,
          reminders: next.effectiveReminders,
          preferences: _preferences,
        );
      }
    } catch (e) {
      debugPrint('Could not update reminders after completing ${current.id}: $e');
    }
  }

  /// Re-opens a completed task, putting it back in the list it came from (or
  /// [toListId] when the user dragged it somewhere specific).
  ///
  /// For a repeating task, the next occurrence created when it was completed is
  /// removed again **if nobody has touched it**, so completing and un-completing
  /// does not leave a duplicate behind. An occurrence that has been edited or
  /// completed is left alone.
  Future<void> reopenTask(Task task, {String? toListId, double? position}) async {
    final taskRef = tasks.doc(task.id);
    final snap = await taskRef.get();
    if (!snap.exists) throw const TaskGoneException();
    final current = Task.fromDoc(snap);
    if (!current.completed) return;

    // Where it goes: the list asked for, else where it came from if that list
    // still exists, else the first ordinary list on the board.
    String? targetListId = toListId;
    if (targetListId == null && current.completedFromListId != null) {
      final origin = await lists.doc(current.completedFromListId!).get();
      if (origin.exists && !TaskList.fromDoc(origin).isComplete) {
        targetListId = origin.id;
      }
    }
    if (targetListId == null && current.boardId != null) {
      targetListId = (await _firstOrdinaryListFor(current.boardId!))?.id;
    }

    final update = <String, dynamic>{
      'completed': false,
      'completedAt': null,
      'completedFromListId': null,
      'updatedAt': FieldValue.serverTimestamp(),
      'version': FieldValue.increment(1),
    };
    if (targetListId != null) {
      update['listId'] = targetListId;
      update['position'] = position ?? await _topPositionIn(targetListId, except: task.id);
    }

    final batch = _db.batch();

    // Remove the next occurrence only if it is exactly as it was created.
    Task? removed;
    final spawnedId = current.spawnedNextTaskId;
    if (spawnedId != null) {
      final spawnedSnap = await tasks.doc(spawnedId).get();
      if (spawnedSnap.exists) {
        final spawned = Task.fromDoc(spawnedSnap);
        if (!spawned.completed && spawned.version <= 1) {
          batch.delete(spawnedSnap.reference);
          update['spawnedNextTaskId'] = null;
          removed = spawned;
        }
        // A touched occurrence is kept, and spawnedNextTaskId stays set so that
        // completing this task again does not create another.
      } else {
        // It was deleted by the user: forget it, so a new one can be made.
        update['spawnedNextTaskId'] = null;
      }
    }

    batch.update(taskRef, update);
    await batch.commit();
    await _syncFlowFor(task.id);

    try {
      if (removed != null) {
        await _notifications.cancelForTask(removed, removed.effectiveReminders);
      }
      final revived = current.copyWith(completed: false, completedAt: null);
      await _notifications.sync(
        task: revived,
        reminders: revived.effectiveReminders,
        preferences: _preferences,
      );
    } catch (e) {
      debugPrint('Could not update reminders after reopening ${task.id}: $e');
    }
  }

  /// The id of the occurrence that follows [task].
  ///
  /// Derived from the task and from when it was due, so it is the same on every
  /// device and every attempt. That sameness is the entire idempotency guarantee.
  static String _nextOccurrenceId(Task task) =>
      '${task.id}-next-${task.startDateTime!.millisecondsSinceEpoch}';

  /// The board's Complete list, or null if the board has none yet.
  Future<TaskList?> _completeListFor(String boardId) async {
    final snap = await lists.where('boardId', isEqualTo: boardId).get();
    final complete = snap.docs.map(TaskList.fromDoc).where((l) => l.isComplete).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return complete.firstOrNull;
  }

  Future<TaskList?> _firstOrdinaryListFor(String boardId) async {
    final snap = await lists.where('boardId', isEqualTo: boardId).get();
    final ordinary = snap.docs.map(TaskList.fromDoc).where((l) => !l.isComplete).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return ordinary.firstOrNull;
  }

  /// A position that sorts before every card now in [listId].
  ///
  /// Sorted here and not by the query: asking Firestore for `where listId ==`
  /// plus `orderBy position` needs a composite index, and lists are small.
  Future<double> _topPositionIn(String listId, {String? except}) async {
    final snap = await tasks.where('listId', isEqualTo: listId).get();
    final positions = [
      for (final d in snap.docs)
        if (d.id != except) (d.data()['position'] as num?)?.toDouble() ?? 0.0,
    ];
    if (positions.isEmpty) return Position.between(null, null);
    return Position.between(null, positions.reduce((a, b) => a < b ? a : b));
  }

  /// Moves a repeating task to its next occurrence without completing it.
  ///
  /// Skipping edits the one task in place rather than spawning a new document,
  /// which is what keeps a daily task from multiplying into hundreds of rows.
  Future<void> skipOccurrence(Task task) async {
    if (task.recurrence == Recurrence.none || task.startDateTime == null) return;
    final next = nextOccurrence(task.startDateTime!, task.recurrence);
    if (next == null) return;

    final span = task.endDateTime?.difference(task.startDateTime!);
    final updated = task.copyWith(
      startDateTime: next,
      endDateTime: span == null ? null : next.add(span),
      subtasks: task.subtasks.map((s) => s.copyWith(done: false)).toList(),
    );
    await updateTask(updated);
  }

  /// Ends the series: the task stays, but stops repeating.
  Future<void> stopSeries(Task task) => updateTask(task.copyWith(recurrence: Recurrence.none));

  /// Pushes a task's reminders back by [minutes].
  ///
  /// Snoozes the reminder the notification came from when it is known, so a
  /// task with several reminders only moves the one that just fired.
  Future<DateTime?> snoozeTask(Task task, {int minutes = 10, String? reminderId}) async {
    final reminders = task.effectiveReminders;
    if (reminders.isEmpty) return null;

    final reminder = reminders.firstWhere(
      (r) => r.id == reminderId,
      orElse: () => reminders.first,
    );
    return _notifications.snooze(
      task: task,
      reminder: reminder,
      minutes: minutes,
      preferences: _preferences,
    );
  }

  Future<void> saveList(TaskList list) => lists.doc(list.id).set(list.toJson());
  Future<String> addList(TaskList list) async {
    final doc = lists.doc();
    await doc.set(list.toJson());
    return doc.id;
  }

  /// Deletes a list without losing its tasks.
  ///
  /// Deleting only the list document, as this used to, left every task in it
  /// pointing at a list that no longer exists, so they vanished from the board
  /// while still counting everywhere else. Its tasks are moved to the board's
  /// first remaining ordinary list, or back to the Inbox if there is none.
  ///
  /// The Complete list is the place finished work goes, so it cannot be deleted.
  Future<void> deleteList(String id) async {
    final listRef = lists.doc(id);
    final snap = await listRef.get();
    if (!snap.exists) return;
    final list = TaskList.fromDoc(snap);
    if (list.isComplete) {
      throw StateError('The Complete list cannot be deleted.');
    }

    final inList = await tasks.where('listId', isEqualTo: id).get();
    final batch = _db.batch();

    if (inList.docs.isNotEmpty) {
      final siblings = await lists.where('boardId', isEqualTo: list.boardId).get();
      final fallback = (siblings.docs.map(TaskList.fromDoc).where((l) => l.id != id && !l.isComplete).toList()
            ..sort((a, b) => a.position.compareTo(b.position)))
          .firstOrNull;

      for (final doc in inList.docs) {
        batch.update(doc.reference, {
          'listId': fallback?.id,
          // With nowhere on the board to go, the task returns to the Inbox.
          if (fallback == null) 'boardId': null,
          'updatedAt': FieldValue.serverTimestamp(),
          'version': FieldValue.increment(1),
        });
      }
    }

    batch.delete(listRef);
    await batch.commit();
  }

  /// Moves a list one place left (`delta` -1) or right (+1) on its board.
  ///
  /// This is the accessible way to reorder lists: a menu action rather than a
  /// drag, so it works with a keyboard and a screen reader and cannot be
  /// confused with dragging a card. It writes only the moved list's position,
  /// unless its neighbours have become too close to split, in which case the
  /// board's lists are renumbered.
  Future<void> moveListBy(String listId, int delta) async {
    final snap = await lists.doc(listId).get();
    if (!snap.exists) return;
    final list = TaskList.fromDoc(snap);

    final siblings = (await lists.where('boardId', isEqualTo: list.boardId).get())
        .docs
        .map(TaskList.fromDoc)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    final plan = planListMove(siblings, listId, delta);
    if (plan == null) return;

    if (!plan.needsRebalance) {
      await lists.doc(listId).update({
        'position': plan.position,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final batch = _db.batch();
    final positions = Position.rebalanced(plan.reordered.length);
    for (final (i, l) in plan.reordered.indexed) {
      batch.update(lists.doc(l.id), {
        'position': positions[i],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Creates a board together with its default lists, in one atomic write.
  ///
  /// A board used to be created empty, so it had no Complete list and nowhere
  /// for a finished task to go until the user built lists by hand.
  Future<String> addBoard(Board board) async {
    final ref = boards.doc();
    final batch = _db.batch();
    _addBoardWithLists(batch, ref, board);
    await batch.commit();
    return ref.id;
  }

  /// Deletes a board and tidies up after it. Its lists go with it; its tasks are
  /// kept and return to the Inbox rather than being deleted or left pointing at
  /// a board that is gone.
  Future<void> deleteBoard(String id) async {
    final boardLists = await lists.where('boardId', isEqualTo: id).get();
    final boardTasks = await tasks.where('boardId', isEqualTo: id).get();

    final batch = _db.batch();
    for (final doc in boardTasks.docs) {
      batch.update(doc.reference, {
        'boardId': null,
        'listId': null,
        'updatedAt': FieldValue.serverTimestamp(),
        'version': FieldValue.increment(1),
      });
    }
    for (final doc in boardLists.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(boards.doc(id));
    await batch.commit();
  }

  Future<String> addCategory(Category c) async {
    final doc = categories.doc();
    await doc.set(c.toJson());
    return doc.id;
  }

  Future<void> saveCategory(Category c) => categories.doc(c.id).set(c.toJson());
  Future<void> deleteCategory(String id) => categories.doc(id).delete();

  Future<String> addNote(Note n) async {
    final doc = notes.doc();
    await doc.set(n.toJson());
    return doc.id;
  }

  Future<void> saveNote(Note n) => notes.doc(n.id).set(n.toJson());
  Future<void> deleteNote(String id) => notes.doc(id).delete();

  Future<String> addReminder(Reminder r) async {
    final doc = reminders.doc();
    await doc.set(r.toJson());
    return doc.id;
  }

  Future<void> saveReminder(Reminder r) => reminders.doc(r.id).set(r.toJson());
  Future<void> deleteReminder(String id) => reminders.doc(id).delete();

  Future<String> addHoliday(Holiday h) async {
    final doc = holidays.doc();
    await doc.set(h.toJson());
    return doc.id;
  }

  Future<void> deleteHoliday(String id) => holidays.doc(id).delete();

  Future<void> addFocusSession(FocusSession s) => focusSessions.doc().set(s.toJson());

  // -------------------------------------------------------------- bootstrap

  /// The lists every board starts with. The fifth is the Complete list, marked by
  /// its `kind` and not its name.
  static const List<(String name, int color, String? kind)> defaultLists = [
    ('Inbox', 0xFF9CA3AF, null),
    ('Todo', 0xFF6C5CE7, null),
    ('In progress', 0xFFE8A33D, null),
    ('Waiting', 0xFF3B82F6, null),
    ('Complete', 0xFF30A46C, kCompleteKind),
    ('Someday', 0xFFA78BFA, null),
  ];

  /// Bumped when the shape of the default lists changes, so an existing account
  /// is migrated exactly once. Version 2 introduced the Complete list.
  static const int kListsVersion = 2;

  /// Adds [board] and its default lists to [batch].
  void _addBoardWithLists(WriteBatch batch, DocumentReference<Json> boardRef, Board board) {
    batch.set(boardRef, board.toJson());
    for (final (i, spec) in defaultLists.indexed) {
      final ref = lists.doc();
      batch.set(
        ref,
        TaskList(
          id: ref.id,
          boardId: boardRef.id,
          name: spec.$1,
          position: (i + 1) * 1000.0,
          isSystem: true,
          colorValue: spec.$2,
          kind: spec.$3,
        ).toJson(),
      );
    }
  }

  /// Creates the default board, lists and categories the first time a user
  /// signs in, and migrates an existing account to the current list layout.
  /// Safe to call on every launch: it checks flags first.
  Future<void> ensureBootstrap() async {
    final flag = await _user.get();
    final data = flag.data() ?? const <String, dynamic>{};

    if (data['bootstrapped'] != true) {
      final batch = _db.batch();
      final boardRef = boards.doc();
      _addBoardWithLists(
        batch,
        boardRef,
        Board(id: boardRef.id, name: 'Personal Board', position: 1000),
      );

      for (var i = 0; i < defaultCategories.length; i++) {
        final ref = categories.doc();
        final (name, color) = defaultCategories[i];
        batch.set(
            ref, Category(id: ref.id, name: name, colorValue: color, position: (i + 1) * 1000).toJson());
      }

      batch.set(
        _user,
        {
          'bootstrapped': true,
          'listsVersion': kListsVersion,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
      return;
    }

    if (((data['listsVersion'] as num?)?.toInt() ?? 1) < kListsVersion) {
      await migrateLists();
    }
  }

  /// Gives every board a Complete list.
  ///
  /// Where a board has a system list called "Done" it **becomes** the Complete
  /// list: it is renamed and marked, and keeps every task in it. Where there is
  /// none, a Complete list is created. Nothing is copied and no task is touched.
  ///
  /// It is safe to run twice, and safe to run on two devices at once: a created
  /// Complete list has an id derived from its board, so two devices write the
  /// same document rather than two lists.
  Future<void> migrateLists() async {
    final boardDocs = await boards.get();
    final listDocs = await lists.get();

    final batch = _db.batch();
    for (final board in boardDocs.docs) {
      final boardLists = listDocs.docs.where((d) => d.data()['boardId'] == board.id).toList();

      // Already has one: nothing to do.
      if (boardLists.any((d) => d.data()['kind'] == kCompleteKind)) continue;

      final done = boardLists
          .where((d) =>
              d.data()['isSystem'] == true &&
              ((d.data()['name'] as String?) ?? '').trim().toLowerCase() == 'done')
          .firstOrNull;

      if (done != null) {
        batch.update(done.reference, {
          'kind': kCompleteKind,
          'name': 'Complete',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final lastPosition = boardLists
            .map((d) => (d.data()['position'] as num?)?.toDouble() ?? 0.0)
            .fold<double>(0, (a, b) => a > b ? a : b);
        final ref = lists.doc('complete-${board.id}');
        batch.set(
          ref,
          TaskList(
            id: ref.id,
            boardId: board.id,
            name: 'Complete',
            position: lastPosition + 1000,
            isSystem: true,
            colorValue: defaultLists[4].$2,
            kind: kCompleteKind,
          ).toJson(),
        );
      }
    }

    batch.set(_user, {'listsVersion': kListsVersion}, SetOptions(merge: true));
    await batch.commit();
  }


  static const List<(String, int)> defaultCategories = [
    ('Job', 0xFF3B82F6),
    ('Personal', 0xFF30A46C),
    ('Company', 0xFF6C5CE7),
    ('Apps', 0xFF8B5CF6),
    ('YouTube', 0xFFE5484D),
    ('TikTok', 0xFF111827),
    ('Facebook', 0xFF1877F2),
    ('Nail Art', 0xFFEC4899),
    ('Hair Style', 0xFFE8A33D),
    ('Kitty Meow', 0xFFF59E0B),
    ('Pirith', 0xFF14B8A6),
    ('Other', 0xFF6B7280),
  ];
}

class MoveResult {
  const MoveResult({required this.hadConflict, required this.newVersion});
  final bool hadConflict;
  final int newVersion;
}

class TaskGoneException implements Exception {
  const TaskGoneException();
  @override
  String toString() => 'That task no longer exists.';
}


const _unset = Object();

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/collections.dart';
import '../models/task.dart';
import 'attachment_service.dart';
import 'reminder_scheduler.dart';

typedef Json = Map<String, dynamic>;

/// All reads and writes for the signed-in user. Every document lives under
/// `users/{uid}/…`, which is exactly what firestore.rules allows.
class Repo {
  Repo({FirebaseFirestore? db, String? uid})
      : _db = db ?? FirebaseFirestore.instance,
        _uid = uid ?? FirebaseAuth.instance.currentUser?.uid ?? '_anon';

  final FirebaseFirestore _db;
  final String _uid;

  DocumentReference<Json> get _user => _db.collection('users').doc(_uid);

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

  Future<String> createTask(Task task) async {
    final doc = tasks.doc();
    await doc.set({...task.toJson(), 'createdAt': FieldValue.serverTimestamp()});
    // The new document has a real id now, so reminders can be keyed to it.
    await const ReminderScheduler().sync(task.copyWithId(doc.id));
    return doc.id;
  }

  Future<void> updateTask(Task task) async {
    await tasks.doc(task.id).update({...task.toJson(), 'version': FieldValue.increment(1)});
    await const ReminderScheduler().sync(task);
  }

  /// Deletes the task and everything hanging off it.
  ///
  /// Attachment metadata and the stored files go first, so deleting a task
  /// never leaves orphaned objects in Storage paying rent.
  Future<void> deleteTask(String id) async {
    try {
      await AttachmentService(db: _db, uid: _uid).deleteAllFor(id);
    } catch (_) {
      // A storage failure must not strand the task itself; the file clean-up
      // can be retried, an undeletable task cannot be worked around.
    }
    await tasks.doc(id).delete();
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
    return _db.runTransaction<MoveResult>((tx) async {
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
  }

  Future<void> setTaskCompleted(Task task, bool completed) async {
    await tasks.doc(task.id).update({
      'completed': completed,
      'completedAt': completed ? Timestamp.fromDate(DateTime.now()) : null,
      'updatedAt': FieldValue.serverTimestamp(),
      'version': FieldValue.increment(1),
    });

    // A finished task should stop nagging; an un-finished one gets its
    // reminders back.
    const scheduler = ReminderScheduler();
    if (completed) {
      await scheduler.cancelFor(task);
    } else {
      await scheduler.sync(task.copyWith(completed: false));
    }

    // A repeating task spawns its next instance instead of just closing.
    if (completed && task.recurrence != Recurrence.none && task.startDateTime != null) {
      final next = nextOccurrence(task.startDateTime!, task.recurrence);
      if (next != null) {
        final span = task.endDateTime?.difference(task.startDateTime!);
        await createTask(task.copyWith(
          completed: false,
          completedAt: null,
          startDateTime: next,
          endDateTime: span == null ? null : next.add(span),
          subtasks: task.subtasks.map((s) => s.copyWith(done: false)).toList(),
          version: 1,
        ));
      }
    }
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

  /// Pushes a task's reminder back by the snooze interval.
  Future<void> snoozeTask(Task task) => const ReminderScheduler().snoozeTask(task);

  Future<void> saveList(TaskList list) => lists.doc(list.id).set(list.toJson());
  Future<void> deleteList(String id) => lists.doc(id).delete();
  Future<String> addList(TaskList list) async {
    final doc = lists.doc();
    await doc.set(list.toJson());
    return doc.id;
  }

  Future<String> addBoard(Board board) async {
    final doc = boards.doc();
    await doc.set(board.toJson());
    return doc.id;
  }

  Future<void> deleteBoard(String id) => boards.doc(id).delete();

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

  /// Creates the default board, lists and categories the first time a user
  /// signs in. Safe to call on every launch: it checks a flag first.
  Future<void> ensureBootstrap() async {
    final flag = await _user.get();
    if ((flag.data()?['bootstrapped'] ?? false) == true) return;

    final batch = _db.batch();
    final boardRef = boards.doc();
    batch.set(boardRef, Board(id: boardRef.id, name: 'Personal Board', position: 1000).toJson());

    const listNames = ['Inbox', 'Todo', 'In progress', 'Waiting', 'Done', 'Someday'];
    for (var i = 0; i < listNames.length; i++) {
      final ref = lists.doc();
      batch.set(
        ref,
        TaskList(
          id: ref.id,
          boardId: boardRef.id,
          name: listNames[i],
          position: (i + 1) * 1000,
          isSystem: true,
          colorValue: _listColors[i],
        ).toJson(),
      );
    }

    for (var i = 0; i < defaultCategories.length; i++) {
      final ref = categories.doc();
      final (name, color) = defaultCategories[i];
      batch.set(ref, Category(id: ref.id, name: name, colorValue: color, position: (i + 1) * 1000).toJson());
    }

    batch.set(_user, {'bootstrapped': true, 'createdAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true));
    await batch.commit();
  }

  static const _listColors = [
    0xFF9CA3AF,
    0xFF6C5CE7,
    0xFFE8A33D,
    0xFF3B82F6,
    0xFF30A46C,
    0xFFA78BFA,
  ];

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

/// Next date for a repeating task, or null when it does not repeat.
DateTime? nextOccurrence(DateTime from, Recurrence r) {
  switch (r) {
    case Recurrence.none:
      return null;
    case Recurrence.daily:
      return from.add(const Duration(days: 1));
    case Recurrence.weekdays:
      var next = from.add(const Duration(days: 1));
      while (next.weekday == DateTime.saturday || next.weekday == DateTime.sunday) {
        next = next.add(const Duration(days: 1));
      }
      return next;
    case Recurrence.weekly:
      return from.add(const Duration(days: 7));
    case Recurrence.monthly:
      return DateTime(from.year, from.month + 1, from.day, from.hour, from.minute);
    case Recurrence.yearly:
      return DateTime(from.year + 1, from.month, from.day, from.hour, from.minute);
  }
}

const _unset = Object();

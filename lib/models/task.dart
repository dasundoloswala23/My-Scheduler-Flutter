import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskPriority { none, low, medium, high }

extension TaskPriorityX on TaskPriority {
  String get label => switch (this) {
        TaskPriority.none => 'None',
        TaskPriority.low => 'Low',
        TaskPriority.medium => 'Medium',
        TaskPriority.high => 'High',
      };
}

/// How often a task repeats. `none` means it does not.
enum Recurrence { none, daily, weekdays, weekly, monthly, yearly }

class Subtask {
  const Subtask({
    required this.id,
    required this.title,
    this.done = false,
    this.position = 0,
  });

  final String id;
  final String title;
  final bool done;
  final double position;

  Subtask copyWith({String? title, bool? done, double? position}) => Subtask(
        id: id,
        title: title ?? this.title,
        done: done ?? this.done,
        position: position ?? this.position,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'done': done, 'position': position};

  factory Subtask.fromJson(Map<String, dynamic> json) => Subtask(
        id: json['id'] as String,
        title: (json['title'] ?? '') as String,
        done: (json['done'] ?? false) as bool,
        position: (json['position'] as num?)?.toDouble() ?? 0,
      );
}

class Task {
  const Task({
    required this.id,
    required this.title,
    this.description = '',
    this.boardId,
    this.listId,
    this.categoryId,
    this.parentTaskId,
    this.position = 0,
    this.completed = false,
    this.priority = TaskPriority.none,
    this.startDateTime,
    this.endDateTime,
    this.recurrence = Recurrence.none,
    this.reminderMinutesBefore,
    this.reminderOffsets = const [],
    this.subtasks = const [],
    this.attachments = const [],
    this.attachmentCount = 0,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.version = 1,
  });

  final String id;
  final String title;
  final String description;
  final String? boardId;
  final String? listId;
  final String? categoryId;
  final String? parentTaskId;
  final double position;
  final bool completed;
  final TaskPriority priority;
  final DateTime? startDateTime;
  final DateTime? endDateTime;
  final Recurrence recurrence;
  final int? reminderMinutesBefore;

  /// Minutes before [startDateTime] to fire a reminder. A task can have
  /// several; 0 means at the start time itself.
  final List<int> reminderOffsets;

  final List<Subtask> subtasks;

  /// Legacy field: plain filenames from before real uploads existed. Kept so
  /// older documents still render; new attachments use the subcollection and
  /// [attachmentCount].
  final List<String> attachments;

  /// Number of real attachments, denormalised so the board does not have to
  /// query each task's subcollection to draw the paperclip badge.
  final int attachmentCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  /// Bumped on every write so another device's concurrent edit is detectable.
  final int version;

  /// A task shows on the calendar once it has a start time.
  bool get hasSchedule => startDateTime != null;

  bool get isUnsorted => listId == null && boardId == null;

  int get doneSubtasks => subtasks.where((s) => s.done).length;

  Duration get duration => (startDateTime != null && endDateTime != null)
      ? endDateTime!.difference(startDateTime!)
      : const Duration(hours: 1);

  Task copyWith({
    String? title,
    String? description,
    Object? boardId = _sentinel,
    Object? listId = _sentinel,
    Object? categoryId = _sentinel,
    Object? parentTaskId = _sentinel,
    double? position,
    bool? completed,
    TaskPriority? priority,
    Object? startDateTime = _sentinel,
    Object? endDateTime = _sentinel,
    Recurrence? recurrence,
    Object? reminderMinutesBefore = _sentinel,
    List<int>? reminderOffsets,
    List<Subtask>? subtasks,
    List<String>? attachments,
    int? attachmentCount,
    DateTime? updatedAt,
    Object? completedAt = _sentinel,
    int? version,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      boardId: boardId == _sentinel ? this.boardId : boardId as String?,
      listId: listId == _sentinel ? this.listId : listId as String?,
      categoryId: categoryId == _sentinel ? this.categoryId : categoryId as String?,
      parentTaskId:
          parentTaskId == _sentinel ? this.parentTaskId : parentTaskId as String?,
      position: position ?? this.position,
      completed: completed ?? this.completed,
      priority: priority ?? this.priority,
      startDateTime:
          startDateTime == _sentinel ? this.startDateTime : startDateTime as DateTime?,
      endDateTime: endDateTime == _sentinel ? this.endDateTime : endDateTime as DateTime?,
      recurrence: recurrence ?? this.recurrence,
      reminderMinutesBefore: reminderMinutesBefore == _sentinel
          ? this.reminderMinutesBefore
          : reminderMinutesBefore as int?,
      reminderOffsets: reminderOffsets ?? this.reminderOffsets,
      subtasks: subtasks ?? this.subtasks,
      attachments: attachments ?? this.attachments,
      attachmentCount: attachmentCount ?? this.attachmentCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt == _sentinel ? this.completedAt : completedAt as DateTime?,
      version: version ?? this.version,
    );
  }

  /// The same task under a different id, used right after a create when the
  /// Firestore id is finally known.
  Task copyWithId(String newId) => Task(
        id: newId,
        title: title,
        description: description,
        boardId: boardId,
        listId: listId,
        categoryId: categoryId,
        parentTaskId: parentTaskId,
        position: position,
        completed: completed,
        priority: priority,
        startDateTime: startDateTime,
        endDateTime: endDateTime,
        recurrence: recurrence,
        reminderMinutesBefore: reminderMinutesBefore,
        reminderOffsets: reminderOffsets,
        subtasks: subtasks,
        attachments: attachments,
        attachmentCount: attachmentCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
        completedAt: completedAt,
        version: version,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'boardId': boardId,
        'listId': listId,
        'categoryId': categoryId,
        'parentTaskId': parentTaskId,
        'position': position,
        'completed': completed,
        'priority': priority.name,
        'startDateTime': startDateTime == null ? null : Timestamp.fromDate(startDateTime!),
        'endDateTime': endDateTime == null ? null : Timestamp.fromDate(endDateTime!),
        'hasSchedule': hasSchedule,
        'recurrence': recurrence.name,
        'reminderMinutesBefore': reminderMinutesBefore,
        'reminderOffsets': reminderOffsets,
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'attachments': attachments,
        'attachmentCount': attachmentCount,
        'createdAt': createdAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(createdAt!),
        'updatedAt': FieldValue.serverTimestamp(),
        'completedAt': completedAt == null ? null : Timestamp.fromDate(completedAt!),
        'version': version,
      };

  factory Task.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data() ?? const {};
    return Task(
      id: doc.id,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      boardId: json['boardId'] as String?,
      listId: json['listId'] as String?,
      categoryId: json['categoryId'] as String?,
      parentTaskId: json['parentTaskId'] as String?,
      position: (json['position'] as num?)?.toDouble() ?? 0,
      completed: (json['completed'] ?? false) as bool,
      priority: TaskPriority.values.firstWhere(
        (p) => p.name == json['priority'],
        orElse: () => TaskPriority.none,
      ),
      startDateTime: (json['startDateTime'] as Timestamp?)?.toDate(),
      endDateTime: (json['endDateTime'] as Timestamp?)?.toDate(),
      recurrence: Recurrence.values.firstWhere(
        (r) => r.name == json['recurrence'],
        orElse: () => Recurrence.none,
      ),
      reminderMinutesBefore: (json['reminderMinutesBefore'] as num?)?.toInt(),
      reminderOffsets: ((json['reminderOffsets'] ?? const []) as List)
          .map((e) => (e as num).toInt())
          .toList(),
      subtasks: ((json['subtasks'] ?? const []) as List)
          .map((e) => Subtask.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position)),
      attachments: ((json['attachments'] ?? const []) as List).cast<String>(),
      attachmentCount: (json['attachmentCount'] as num?)?.toInt() ?? 0,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
      completedAt: (json['completedAt'] as Timestamp?)?.toDate(),
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

const _sentinel = Object();

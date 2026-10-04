import 'package:cloud_firestore/cloud_firestore.dart';

/// A board holds lists, which hold tasks. Matches the "Boards" screen.
class Board {
  const Board({
    required this.id,
    required this.name,
    this.colorValue = 0xFF6C5CE7,
    this.position = 0,
    this.workspace = 'Personal workspace',
  });

  final String id;
  final String name;
  final int colorValue;
  final double position;
  final String workspace;

  Map<String, dynamic> toJson() => {
        'name': name,
        'colorValue': colorValue,
        'position': position,
        'workspace': workspace,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory Board.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data() ?? const {};
    return Board(
      id: doc.id,
      name: (json['name'] ?? 'Board') as String,
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF6C5CE7,
      position: (json['position'] as num?)?.toDouble() ?? 0,
      workspace: (json['workspace'] ?? 'Personal workspace') as String,
    );
  }
}

/// A column on a board: Inbox, Todo, In progress, Waiting, Done, Someday, …
class TaskList {
  const TaskList({
    required this.id,
    required this.boardId,
    required this.name,
    this.position = 0,
    this.colorValue = 0xFF9CA3AF,
    this.isSystem = false,
  });

  final String id;
  final String boardId;
  final String name;
  final double position;
  final int colorValue;
  final bool isSystem;

  TaskList copyWith({String? name, double? position, int? colorValue}) => TaskList(
        id: id,
        boardId: boardId,
        name: name ?? this.name,
        position: position ?? this.position,
        colorValue: colorValue ?? this.colorValue,
        isSystem: isSystem,
      );

  Map<String, dynamic> toJson() => {
        'boardId': boardId,
        'name': name,
        'position': position,
        'colorValue': colorValue,
        'isSystem': isSystem,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory TaskList.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data() ?? const {};
    return TaskList(
      id: doc.id,
      boardId: (json['boardId'] ?? '') as String,
      name: (json['name'] ?? 'List') as String,
      position: (json['position'] as num?)?.toDouble() ?? 0,
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF9CA3AF,
      isSystem: (json['isSystem'] ?? false) as bool,
    );
  }
}

/// An area of life. Shown as the coloured chip on every task card.
class Category {
  const Category({
    required this.id,
    required this.name,
    this.colorValue = 0xFF6C5CE7,
    this.position = 0,
    this.iconCode = 0xe3af,
  });

  final String id;
  final String name;
  final int colorValue;
  final double position;
  final int iconCode;

  Map<String, dynamic> toJson() => {
        'name': name,
        'colorValue': colorValue,
        'position': position,
        'iconCode': iconCode,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory Category.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data() ?? const {};
    return Category(
      id: doc.id,
      name: (json['name'] ?? 'Category') as String,
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF6C5CE7,
      position: (json['position'] as num?)?.toDouble() ?? 0,
      iconCode: (json['iconCode'] as num?)?.toInt() ?? 0xe3af,
    );
  }
}

class Note {
  const Note({
    required this.id,
    required this.title,
    this.body = '',
    this.categoryId,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final String? categoryId;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'categoryId': categoryId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory Note.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data() ?? const {};
    return Note(
      id: doc.id,
      title: (json['title'] ?? '') as String,
      body: (json['body'] ?? '') as String,
      categoryId: json['categoryId'] as String?,
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.remindAt,
    this.done = false,
    this.notificationId,
  });

  final String id;
  final String title;
  final DateTime remindAt;
  final bool done;
  final int? notificationId;

  Map<String, dynamic> toJson() => {
        'title': title,
        'remindAt': Timestamp.fromDate(remindAt),
        'done': done,
        'notificationId': notificationId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory Reminder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data() ?? const {};
    return Reminder(
      id: doc.id,
      title: (json['title'] ?? '') as String,
      remindAt: (json['remindAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      done: (json['done'] ?? false) as bool,
      notificationId: (json['notificationId'] as num?)?.toInt(),
    );
  }
}

class Holiday {
  const Holiday({
    required this.id,
    required this.name,
    required this.date,
    this.region = 'Sri Lanka',
  });

  final String id;
  final String name;
  final DateTime date;
  final String region;

  Map<String, dynamic> toJson() => {
        'name': name,
        'date': Timestamp.fromDate(date),
        'region': region,
      };

  factory Holiday.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data() ?? const {};
    return Holiday(
      id: doc.id,
      name: (json['name'] ?? '') as String,
      date: (json['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      region: (json['region'] ?? 'Sri Lanka') as String,
    );
  }
}

/// One completed Pomodoro, used by the Focus screen and the statistics.
class FocusSession {
  const FocusSession({
    required this.id,
    required this.startedAt,
    required this.minutes,
    this.taskId,
    this.taskTitle = '',
  });

  final String id;
  final DateTime startedAt;
  final int minutes;
  final String? taskId;
  final String taskTitle;

  Map<String, dynamic> toJson() => {
        'startedAt': Timestamp.fromDate(startedAt),
        'minutes': minutes,
        'taskId': taskId,
        'taskTitle': taskTitle,
      };

  factory FocusSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data() ?? const {};
    return FocusSession(
      id: doc.id,
      startedAt: (json['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      minutes: (json['minutes'] as num?)?.toInt() ?? 25,
      taskId: json['taskId'] as String?,
      taskTitle: (json['taskTitle'] ?? '') as String,
    );
  }
}

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

/// The `kind` of the list every board must have, where finished tasks go.
///
/// It is identified by this marker and not by its name, so renaming the list, or
/// a user making their own list called "Complete", never changes which one is
/// the real one.
const String kCompleteKind = 'complete';

/// A column on a board: Inbox, Todo, In progress, Waiting, Complete, Someday, …
class TaskList {
  const TaskList({
    required this.id,
    required this.boardId,
    required this.name,
    this.position = 0,
    this.colorValue = 0xFF9CA3AF,
    this.isSystem = false,
    this.kind,
  });

  final String id;
  final String boardId;
  final String name;
  final double position;
  final int colorValue;
  final bool isSystem;

  /// Null for an ordinary list; [kCompleteKind] for the board's Complete list.
  final String? kind;

  bool get isComplete => kind == kCompleteKind;

  TaskList copyWith({String? name, double? position, int? colorValue}) => TaskList(
        id: id,
        boardId: boardId,
        name: name ?? this.name,
        position: position ?? this.position,
        colorValue: colorValue ?? this.colorValue,
        isSystem: isSystem,
        kind: kind,
      );

  Map<String, dynamic> toJson() => {
        'boardId': boardId,
        'name': name,
        'position': position,
        'colorValue': colorValue,
        'isSystem': isSystem,
        'kind': kind,
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
      kind: json['kind'] as String?,
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

/// A holiday the user added by hand.
///
/// Built-in holidays are not stored: they are generated from
/// `HolidayData`, so only the user's own entries ever reach Firestore.
class Holiday {
  const Holiday({
    required this.id,
    required this.name,
    required this.date,
    this.region = '',
    this.countryCode = '',
    this.category = 'public',
  });

  final String id;
  final String name;
  final DateTime date;

  /// Free-text label kept for documents written before [countryCode] existed.
  final String region;

  /// ISO 3166-1 alpha-2, or empty for a holiday not tied to a country.
  final String countryCode;

  /// A [HolidayCategory] id. Stored as a string so an unknown value from a
  /// newer build degrades instead of failing to parse.
  final String category;

  Holiday copyWith({String? name, DateTime? date, String? countryCode, String? category}) =>
      Holiday(
        id: id,
        name: name ?? this.name,
        date: date ?? this.date,
        region: region,
        countryCode: countryCode ?? this.countryCode,
        category: category ?? this.category,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'date': Timestamp.fromDate(date),
        'region': region,
        'countryCode': countryCode,
        'category': category,
      };

  factory Holiday.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data() ?? const {};
    return Holiday(
      id: doc.id,
      name: (json['name'] ?? '') as String,
      date: (json['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      region: (json['region'] ?? '') as String,
      countryCode: (json['countryCode'] ?? '') as String,
      category: (json['category'] ?? 'public') as String,
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

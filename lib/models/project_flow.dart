import 'package:cloud_firestore/cloud_firestore.dart';

/// Project Flow is a planning layer over real tasks. It holds stages and links
/// to tasks; it never holds tasks of its own, so a task lives once, on its
/// board and on the calendar, and a flow only points at it.

enum FlowStatus { active, completed, paused, archived }

enum FlowMode { sequential, flexible, dependency }

/// Where a stage stands. Always derived by the flow engine from the stage's
/// own settings, its tasks and its prerequisites; never trusted from storage.
enum StageState { locked, upcoming, active, completed, blocked }

/// A stage the user has settled by hand. Everything else is derived.
enum ManualStageStatus { completed, blocked }

extension FlowStatusX on FlowStatus {
  String get label => switch (this) {
        FlowStatus.active => 'Active',
        FlowStatus.completed => 'Completed',
        FlowStatus.paused => 'Paused',
        FlowStatus.archived => 'Archived',
      };
}

extension FlowModeX on FlowMode {
  String get label => switch (this) {
        FlowMode.sequential => 'Sequential',
        FlowMode.flexible => 'Flexible',
        FlowMode.dependency => 'Dependency',
      };

  String get description => switch (this) {
        FlowMode.sequential => 'Each stage unlocks when the one before it is complete.',
        FlowMode.flexible => 'Any stage can be worked on at any time.',
        FlowMode.dependency => 'A stage unlocks when the stages it depends on are complete.',
      };
}

extension StageStateX on StageState {
  String get label => switch (this) {
        StageState.locked => 'Locked',
        StageState.upcoming => 'Up next',
        StageState.active => 'Active',
        StageState.completed => 'Completed',
        StageState.blocked => 'Blocked',
      };
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((v) => v.name == raw).firstOrNull ?? fallback;

DateTime? _date(Object? raw) => raw is Timestamp ? raw.toDate() : null;

class ProjectFlow {
  const ProjectFlow({
    required this.id,
    required this.name,
    this.description = '',
    this.icon = 'rocket_launch',
    this.colorValue = 0xFF7C5CFC,
    this.boardId,
    this.categoryId,
    this.mode = FlowMode.sequential,
    this.status = FlowStatus.active,
    this.currentStageId,
    this.progress = 0,
    this.startDate,
    this.dueDate,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  final String id;
  final String name;
  final String description;
  final String icon;
  final int colorValue;
  final String? boardId;
  final String? categoryId;
  final FlowMode mode;

  /// What the user chose (active, paused, archived) or what the engine found
  /// (completed). Stored so lists can be filtered and sorted without loading
  /// every stage.
  final FlowStatus status;

  /// Cached by the last recompute. The screens derive these live from the
  /// engine; the cache serves queries and other devices.
  final String? currentStageId;
  final double progress;

  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  ProjectFlow copyWith({
    String? name,
    String? description,
    String? icon,
    int? colorValue,
    Object? boardId = _keep,
    Object? categoryId = _keep,
    FlowMode? mode,
    FlowStatus? status,
    Object? currentStageId = _keep,
    double? progress,
    Object? startDate = _keep,
    Object? dueDate = _keep,
    Object? completedAt = _keep,
  }) =>
      ProjectFlow(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        icon: icon ?? this.icon,
        colorValue: colorValue ?? this.colorValue,
        boardId: identical(boardId, _keep) ? this.boardId : boardId as String?,
        categoryId: identical(categoryId, _keep) ? this.categoryId : categoryId as String?,
        mode: mode ?? this.mode,
        status: status ?? this.status,
        currentStageId:
            identical(currentStageId, _keep) ? this.currentStageId : currentStageId as String?,
        progress: progress ?? this.progress,
        startDate: identical(startDate, _keep) ? this.startDate : startDate as DateTime?,
        dueDate: identical(dueDate, _keep) ? this.dueDate : dueDate as DateTime?,
        createdAt: createdAt,
        updatedAt: updatedAt,
        completedAt: identical(completedAt, _keep) ? this.completedAt : completedAt as DateTime?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'icon': icon,
        'colorValue': colorValue,
        'boardId': boardId,
        'categoryId': categoryId,
        'mode': mode.name,
        'status': status.name,
        'currentStageId': currentStageId,
        'progress': progress,
        'startDate': startDate == null ? null : Timestamp.fromDate(startDate!),
        'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
        'completedAt': completedAt == null ? null : Timestamp.fromDate(completedAt!),
      };

  static ProjectFlow fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ProjectFlow(
      id: doc.id,
      name: d['name'] as String? ?? 'Untitled flow',
      description: d['description'] as String? ?? '',
      icon: d['icon'] as String? ?? 'rocket_launch',
      colorValue: (d['colorValue'] as num?)?.toInt() ?? 0xFF7C5CFC,
      boardId: d['boardId'] as String?,
      categoryId: d['categoryId'] as String?,
      mode: _enumByName(FlowMode.values, d['mode'], FlowMode.sequential),
      status: _enumByName(FlowStatus.values, d['status'], FlowStatus.active),
      currentStageId: d['currentStageId'] as String?,
      progress: (d['progress'] as num?)?.toDouble() ?? 0,
      startDate: _date(d['startDate']),
      dueDate: _date(d['dueDate']),
      createdAt: _date(d['createdAt']),
      updatedAt: _date(d['updatedAt']),
      completedAt: _date(d['completedAt']),
    );
  }
}

class FlowStage {
  const FlowStage({
    required this.id,
    required this.flowId,
    required this.title,
    this.description = '',
    this.position = 0,
    this.startDate,
    this.dueDate,
    this.priority = 'medium',
    this.colorValue,
    this.isRequired = true,
    this.dependencyStageIds = const [],
    this.autoCompleteWhenTasksDone = true,
    this.manualStatus,
    this.state = StageState.locked,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  final String id;
  final String flowId;
  final String title;
  final String description;
  final double position;
  final DateTime? startDate;
  final DateTime? dueDate;
  final String priority;
  final int? colorValue;

  /// A required stage must be completed for the flow to be completed, and
  /// gates the stages after it in sequential mode.
  final bool isRequired;

  /// Used in dependency mode.
  final List<String> dependencyStageIds;

  /// When true, finishing every linked task completes the stage on its own.
  final bool autoCompleteWhenTasksDone;

  /// A decision made by hand: mark complete, or mark blocked.
  final ManualStageStatus? manualStatus;

  /// The state at the last recompute. Cached for other devices and queries;
  /// the screens use the engine's answer instead.
  final StageState state;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  FlowStage copyWith({
    String? title,
    String? description,
    double? position,
    Object? startDate = _keep,
    Object? dueDate = _keep,
    String? priority,
    Object? colorValue = _keep,
    bool? isRequired,
    List<String>? dependencyStageIds,
    bool? autoCompleteWhenTasksDone,
    Object? manualStatus = _keep,
    StageState? state,
    Object? completedAt = _keep,
  }) =>
      FlowStage(
        id: id,
        flowId: flowId,
        title: title ?? this.title,
        description: description ?? this.description,
        position: position ?? this.position,
        startDate: identical(startDate, _keep) ? this.startDate : startDate as DateTime?,
        dueDate: identical(dueDate, _keep) ? this.dueDate : dueDate as DateTime?,
        priority: priority ?? this.priority,
        colorValue: identical(colorValue, _keep) ? this.colorValue : colorValue as int?,
        isRequired: isRequired ?? this.isRequired,
        dependencyStageIds: dependencyStageIds ?? this.dependencyStageIds,
        autoCompleteWhenTasksDone: autoCompleteWhenTasksDone ?? this.autoCompleteWhenTasksDone,
        manualStatus:
            identical(manualStatus, _keep) ? this.manualStatus : manualStatus as ManualStageStatus?,
        state: state ?? this.state,
        createdAt: createdAt,
        updatedAt: updatedAt,
        completedAt: identical(completedAt, _keep) ? this.completedAt : completedAt as DateTime?,
      );

  Map<String, dynamic> toJson() => {
        'flowId': flowId,
        'title': title,
        'description': description,
        'position': position,
        'startDate': startDate == null ? null : Timestamp.fromDate(startDate!),
        'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
        'priority': priority,
        'colorValue': colorValue,
        'isRequired': isRequired,
        'dependencyStageIds': dependencyStageIds,
        'autoCompleteWhenTasksDone': autoCompleteWhenTasksDone,
        'manualStatus': manualStatus?.name,
        'status': state.name,
        'completedAt': completedAt == null ? null : Timestamp.fromDate(completedAt!),
      };

  static FlowStage fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return FlowStage(
      id: doc.id,
      flowId: d['flowId'] as String? ?? '',
      title: d['title'] as String? ?? 'Stage',
      description: d['description'] as String? ?? '',
      position: (d['position'] as num?)?.toDouble() ?? 0,
      startDate: _date(d['startDate']),
      dueDate: _date(d['dueDate']),
      priority: d['priority'] as String? ?? 'medium',
      colorValue: (d['colorValue'] as num?)?.toInt(),
      isRequired: d['isRequired'] as bool? ?? true,
      dependencyStageIds:
          (d['dependencyStageIds'] as List?)?.whereType<String>().toList() ?? const [],
      autoCompleteWhenTasksDone: d['autoCompleteWhenTasksDone'] as bool? ?? true,
      manualStatus: ManualStageStatus.values.where((m) => m.name == d['manualStatus']).firstOrNull,
      state: _enumByName(StageState.values, d['status'], StageState.locked),
      createdAt: _date(d['createdAt']),
      updatedAt: _date(d['updatedAt']),
      completedAt: _date(d['completedAt']),
    );
  }
}

/// Says that a task belongs to a stage of a flow. The document id is the task
/// id, so a task has at most one link and linking twice only moves it.
class FlowTaskLink {
  const FlowTaskLink({
    required this.taskId,
    required this.flowId,
    required this.stageId,
    this.position = 0,
    this.createdAt,
  });

  final String taskId;
  final String flowId;
  final String stageId;
  final double position;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
        'flowId': flowId,
        'stageId': stageId,
        'taskId': taskId,
        'position': position,
      };

  static FlowTaskLink fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return FlowTaskLink(
      taskId: doc.id,
      flowId: d['flowId'] as String? ?? '',
      stageId: d['stageId'] as String? ?? '',
      position: (d['position'] as num?)?.toDouble() ?? 0,
      createdAt: _date(d['createdAt']),
    );
  }
}

const Object _keep = Object();

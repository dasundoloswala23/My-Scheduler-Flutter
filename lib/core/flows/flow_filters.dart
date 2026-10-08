import '../../models/project_flow.dart';
import 'flow_engine.dart';

enum FlowFilter { all, active, blocked, completed, dueSoon }

extension FlowFilterX on FlowFilter {
  String get label => switch (this) {
        FlowFilter.all => 'All',
        FlowFilter.active => 'Active',
        FlowFilter.blocked => 'Blocked',
        FlowFilter.completed => 'Completed',
        FlowFilter.dueSoon => 'Due soon',
      };
}

/// How many days ahead "due soon" looks. A flow already past its due date and
/// not finished counts too: it is the most urgent kind of due soon.
const int kDueSoonDays = 7;

/// A flow with at least one blocked stage, which has not finished.
bool isBlocked(FlowResult r) =>
    r.status == FlowStatus.active && r.stages.any((s) => s.state == StageState.blocked);

bool isDueSoon(ProjectFlow flow, FlowResult r, DateTime now) {
  final due = flow.dueDate;
  if (due == null || r.status != FlowStatus.active) return false;
  final cutoff = DateTime(now.year, now.month, now.day + kDueSoonDays + 1);
  return due.isBefore(cutoff);
}

/// The flows that pass [filter], the search text and the board and category
/// choices, in the order given. Archived flows only appear under All.
List<ProjectFlow> filterFlows({
  required List<ProjectFlow> flows,
  required Map<String, FlowResult> results,
  required FlowFilter filter,
  String search = '',
  String? boardId,
  String? categoryId,
  required DateTime now,
}) {
  final q = search.trim().toLowerCase();
  return [
    for (final f in flows)
      if (_passes(f, results[f.id], filter, now) &&
          (boardId == null || f.boardId == boardId) &&
          (categoryId == null || f.categoryId == categoryId) &&
          (q.isEmpty ||
              f.name.toLowerCase().contains(q) ||
              f.description.toLowerCase().contains(q)))
        f,
  ];
}

bool _passes(ProjectFlow f, FlowResult? r, FlowFilter filter, DateTime now) {
  // Before its stages have loaded a flow is treated by its stored status.
  final status = r?.status ?? f.status;
  return switch (filter) {
    FlowFilter.all => true,
    FlowFilter.active => status == FlowStatus.active,
    FlowFilter.completed => status == FlowStatus.completed,
    FlowFilter.blocked => r != null && isBlocked(r),
    FlowFilter.dueSoon => r != null && isDueSoon(f, r, now),
  };
}

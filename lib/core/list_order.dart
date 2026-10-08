import '../models/collections.dart';
import 'position.dart';

/// What moving a list one step would do.
class ListMovePlan {
  const ListMovePlan({
    required this.position,
    required this.reordered,
    required this.needsRebalance,
  });

  /// The new `position` for the list that moved. Only meaningful when
  /// [needsRebalance] is false.
  final double position;

  /// The lists in their new order, which is what a renumbering needs.
  final List<TaskList> reordered;

  /// True when the two neighbours have become too close to split again, so the
  /// whole board's lists should be renumbered instead.
  final bool needsRebalance;
}

/// Works out the result of moving list [listId] by [delta] places (-1 is left,
/// +1 is right) among [ordered], which must already be sorted by position.
///
/// Returns null when the list cannot move that way: it is already at that end,
/// or it is not in [ordered] at all.
///
/// Moving a list changes only the moved list's own `position`, by taking the
/// midpoint of its new neighbours (the same scheme cards use), so it is one
/// small write rather than a renumbering of the whole board.
ListMovePlan? planListMove(List<TaskList> ordered, String listId, int delta) {
  final from = ordered.indexWhere((l) => l.id == listId);
  if (from < 0) return null;

  final to = from + delta;
  if (to < 0 || to >= ordered.length) return null;

  final others = [...ordered]..removeAt(from);
  final moved = ordered[from];
  final reordered = [...others]..insert(to, moved);

  final prev = to > 0 ? others[to - 1] : null;
  final next = to < others.length ? others[to] : null;

  return ListMovePlan(
    position: Position.between(prev?.position, next?.position),
    reordered: reordered,
    needsRebalance: Position.needsRebalance(prev?.position, next?.position),
  );
}

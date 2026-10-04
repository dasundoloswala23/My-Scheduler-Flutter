/// Fractional ordering for drag-and-drop.
///
/// A card's `position` is a double. Dropping between two cards writes the
/// midpoint of their positions, so a single drop only ever writes one document.
/// Doubles run out of precision after roughly 50 subdivisions in the same gap,
/// so [needsRebalance] tells the caller when to renumber a list.
class Position {
  static const double step = 1000;

  /// Position for an item dropped between [prev] and [next] (either may be null
  /// at the start or end of a list).
  static double between(double? prev, double? next) {
    if (prev == null && next == null) return step;
    if (prev == null) return next! - step;
    if (next == null) return prev + step;
    return (prev + next) / 2;
  }

  /// True when two neighbours have become too close to split again.
  static bool needsRebalance(double? prev, double? next) {
    if (prev == null || next == null) return false;
    return (next - prev).abs() < 0.0001;
  }

  /// Evenly spaced positions used when renumbering a whole list.
  static List<double> rebalanced(int count) =>
      List.generate(count, (i) => (i + 1) * step);
}

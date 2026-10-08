import 'package:flutter/material.dart';

/// An [IndexedStack] that builds each child the first time it is shown and then
/// keeps it alive.
///
/// This is what makes switching tabs feel like switching tabs rather than
/// reloading a page: the Board keeps its horizontal and vertical scroll
/// position, the Calendar keeps its selected date and view, and a half-typed
/// search is still there when you come back.
///
/// Children that have never been shown are not built at all, so start-up does
/// not pay for five screens when one is visible.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int index;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  final Set<int> _visited = {};

  @override
  void initState() {
    super.initState();
    _visited.add(widget.index);
  }

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.itemCount; i++)
          _visited.contains(i) ? widget.itemBuilder(context, i) : const SizedBox.shrink(),
      ],
    );
  }
}

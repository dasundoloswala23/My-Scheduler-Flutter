import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../models/task.dart';

/// What travels with a dragged card.
class TaskDragData {
  const TaskDragData(this.task, {this.fromListId});
  final Task task;
  final String? fromListId;
}

/// Touch platforms need a long press to start a drag so the board can still be
/// scrolled with a finger; mouse and trackpad start on press.
bool get usesLongPressDrag =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Wraps a card so it can be dragged on every platform with the right gesture.
class TaskDraggable extends StatelessWidget {
  const TaskDraggable({
    super.key,
    required this.data,
    required this.child,
    this.feedbackWidth = 300,
    this.onDragStarted,
    this.onDragEnd,
    this.onDragUpdate,
  });

  final TaskDragData data;
  final Widget child;
  final double feedbackWidth;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;
  final void Function(DragUpdateDetails)? onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final feedback = _DragFeedback(width: feedbackWidth, child: child);
    // The gap left behind stays visible but faded, like Trello.
    final placeholder = Opacity(opacity: 0.35, child: child);

    void started() {
      HapticFeedback.mediumImpact();
      onDragStarted?.call();
    }

    if (usesLongPressDrag) {
      return LongPressDraggable<TaskDragData>(
        data: data,
        feedback: feedback,
        childWhenDragging: placeholder,
        onDragStarted: started,
        onDragUpdate: onDragUpdate,
        onDragEnd: (_) => onDragEnd?.call(),
        onDraggableCanceled: (_, _) => onDragEnd?.call(),
        child: child,
      );
    }
    return Draggable<TaskDragData>(
      data: data,
      feedback: feedback,
      childWhenDragging: placeholder,
      onDragStarted: started,
      onDragUpdate: onDragUpdate,
      onDragEnd: (_) => onDragEnd?.call(),
      onDraggableCanceled: (_, _) => onDragEnd?.call(),
      child: child,
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Transform.rotate(
        angle: 0.02,
        child: SizedBox(
          width: width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A drop zone between two cards. Grows and shows a violet line while a card
/// hovers over it, which is the visual drop indicator.
class DropGap extends StatefulWidget {
  const DropGap({
    super.key,
    required this.onAccept,
    this.canAccept,
    this.height = 8,
  });

  final void Function(TaskDragData data) onAccept;
  final bool Function(TaskDragData data)? canAccept;
  final double height;

  @override
  State<DropGap> createState() => _DropGapState();
}

class _DropGapState extends State<DropGap> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskDragData>(
      onWillAcceptWithDetails: (details) {
        final ok = widget.canAccept?.call(details.data) ?? true;
        if (ok) setState(() => _hovering = true);
        return ok;
      },
      onLeave: (_) => setState(() => _hovering = false),
      onAcceptWithDetails: (details) {
        setState(() => _hovering = false);
        HapticFeedback.selectionClick();
        widget.onAccept(details.data);
      },
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: _hovering ? 44 : widget.height,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: _hovering ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: _hovering
                ? Border.all(color: AppColors.primary, width: 2, strokeAlign: BorderSide.strokeAlignInside)
                : null,
          ),
        );
      },
    );
  }
}

/// Scrolls a list while a drag hovers near its edges.
///
/// Call [update] with the pointer's global position during a drag and [stop]
/// when the drag ends.
class EdgeAutoScroller {
  EdgeAutoScroller(this.controller, {this.axis = Axis.horizontal, this.edge = 90});

  final ScrollController controller;
  final Axis axis;
  final double edge;
  Timer? _timer;

  void update(Offset globalPosition, Size viewport) {
    final pos = axis == Axis.horizontal ? globalPosition.dx : globalPosition.dy;
    final extent = axis == Axis.horizontal ? viewport.width : viewport.height;

    double delta = 0;
    if (pos < edge) {
      delta = -((edge - pos) / edge) * 24;
    } else if (pos > extent - edge) {
      delta = ((pos - (extent - edge)) / edge) * 24;
    }

    if (delta == 0) {
      stop();
      return;
    }
    _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _scrollBy(delta));
  }

  void _scrollBy(double delta) {
    if (!controller.hasClients) return;
    final target = (controller.offset + delta)
        .clamp(controller.position.minScrollExtent, controller.position.maxScrollExtent);
    controller.jumpTo(target);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}

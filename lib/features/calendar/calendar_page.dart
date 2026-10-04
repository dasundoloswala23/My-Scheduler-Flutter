import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/move_controller.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import '../dnd/drag_core.dart';
import '../quick_add/quick_add_sheet.dart';
import '../task_detail/task_detail_sheet.dart';

enum CalendarView { day, week, month, agenda }

const double kHourHeight = 64;
const int kSlotMinutes = 15;

/// The calendar from screenshots 3 and 26–27.
///
/// Tasks with a start time appear here. They can be dragged to another time or
/// day, resized to change duration, dragged in from the unscheduled panel, and
/// dragged back out to clear their schedule. Every drop writes to Firestore.
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  CalendarView _view = CalendarView.week;
  DateTime _anchor = DateTime.now();
  final _gridScroll = ScrollController(initialScrollOffset: kHourHeight * 7);

  @override
  void dispose() {
    _gridScroll.dispose();
    super.dispose();
  }

  List<DateTime> get _weekDays {
    final monday = _anchor.subtract(Duration(days: _anchor.weekday - 1));
    return [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final unscheduled = tasks.where((t) => t.startDateTime == null && !t.completed).toList();
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          anchor: _anchor,
          view: _view,
          onView: (v) => setState(() => _view = v),
          onToday: () => setState(() => _anchor = DateTime.now()),
          onShift: (days) => setState(() => _anchor = _anchor.add(Duration(days: days))),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide && _view != CalendarView.month)
                SizedBox(width: 260, child: _UnscheduledPanel(tasks: unscheduled)),
              Expanded(child: _buildView(tasks)),
            ],
          ),
        ),
        if (!isWide && _view != CalendarView.month && unscheduled.isNotEmpty)
          SizedBox(height: 132, child: _UnscheduledPanel(tasks: unscheduled, horizontal: true)),
      ],
    );
  }

  Widget _buildView(List<Task> tasks) => switch (_view) {
        CalendarView.day => _TimeGrid(days: [_anchor], tasks: tasks, scrollController: _gridScroll),
        CalendarView.week => _TimeGrid(days: _weekDays, tasks: tasks, scrollController: _gridScroll),
        CalendarView.month => _MonthGrid(
            anchor: _anchor,
            tasks: tasks,
            onPickDay: (d) => setState(() {
              _anchor = d;
              _view = CalendarView.day;
            }),
          ),
        CalendarView.agenda => _AgendaList(tasks: tasks, from: _anchor),
      };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.anchor,
    required this.view,
    required this.onView,
    required this.onToday,
    required this.onShift,
  });

  final DateTime anchor;
  final CalendarView view;
  final ValueChanged<CalendarView> onView;
  final VoidCallback onToday;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CALENDAR',
                        style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: AppColors.muted)),
                    Text(DateFormat('MMMM y').format(anchor),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              IconButton(onPressed: () => onShift(-7), icon: const Icon(Icons.chevron_left)),
              TextButton(onPressed: onToday, child: const Text('Today')),
              IconButton(onPressed: () => onShift(7), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<CalendarView>(
            segments: const [
              ButtonSegment(value: CalendarView.day, label: Text('Day')),
              ButtonSegment(value: CalendarView.week, label: Text('Week')),
              ButtonSegment(value: CalendarView.month, label: Text('Month')),
              ButtonSegment(value: CalendarView.agenda, label: Text('Agenda')),
            ],
            selected: {view},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onView(s.first),
          ),
        ],
      ),
    );
  }
}

/// Day and week views. Each 15-minute slot is a drop target.
class _TimeGrid extends ConsumerWidget {
  const _TimeGrid({required this.days, required this.tasks, required this.scrollController});

  final List<DateTime> days;
  final List<Task> tasks;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 56),
            for (final day in days)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Text(DateFormat('EEE').format(day).toUpperCase(),
                          style: const TextStyle(fontSize: 10, color: AppColors.muted, letterSpacing: 1)),
                      const SizedBox(height: 2),
                      _DayNumber(day: day),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            child: SizedBox(
              height: kHourHeight * 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Column(
                      children: [
                        for (var h = 0; h < 24; h++)
                          SizedBox(
                            height: kHourHeight,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8, top: 2),
                                child: Text(
                                  DateFormat('h a').format(DateTime(2020, 1, 1, h)),
                                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final day in days)
                    Expanded(child: _DayColumn(day: day, tasks: tasksForDay(tasks, day))),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isToday ? AppColors.primary : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Text('${day.day}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isToday ? Colors.white : null,
          )),
    );
  }
}

class _DayColumn extends ConsumerWidget {
  const _DayColumn({required this.day, required this.tasks});

  final DateTime day;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const slotsPerDay = 24 * 60 ~/ kSlotMinutes;
    const slotHeight = kHourHeight * kSlotMinutes / 60;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
      ),
      child: Stack(
        children: [
          // Hour lines.
          Column(
            children: [
              for (var h = 0; h < 24; h++)
                Container(
                  height: kHourHeight,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
                  ),
                ),
            ],
          ),
          // One drop target per 15 minutes.
          Column(
            children: [
              for (var s = 0; s < slotsPerDay; s++)
                _SlotTarget(
                  height: slotHeight,
                  slotTime: DateTime(day.year, day.month, day.day)
                      .add(Duration(minutes: s * kSlotMinutes)),
                ),
            ],
          ),
          // Events on top.
          for (final task in tasks) _PositionedEvent(task: task, day: day),
        ],
      ),
    );
  }
}

class _SlotTarget extends ConsumerStatefulWidget {
  const _SlotTarget({required this.height, required this.slotTime});

  final double height;
  final DateTime slotTime;

  @override
  ConsumerState<_SlotTarget> createState() => _SlotTargetState();
}

class _SlotTargetState extends ConsumerState<_SlotTarget> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskDragData>(
      onWillAcceptWithDetails: (_) {
        setState(() => _hovering = true);
        return true;
      },
      onLeave: (_) => setState(() => _hovering = false),
      onAcceptWithDetails: (details) async {
        setState(() => _hovering = false);
        final task = details.data.task;
        final start = widget.slotTime;
        await MoveController(ref).run(
          context: context,
          task: task,
          move: TaskMove(startDateTime: start, endDateTime: start.add(task.duration)),
          description: 'Task moved to ${DateFormat('MMM d, h:mm a').format(start)}',
        );
      },
      builder: (context, candidate, rejected) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: _hovering ? AppColors.primary.withValues(alpha: 0.18) : Colors.transparent,
          border: _hovering ? const Border(top: BorderSide(color: AppColors.primary, width: 2)) : null,
        ),
      ),
    );
  }
}

/// An event placed by time, draggable to move and resizable at the bottom edge.
class _PositionedEvent extends ConsumerStatefulWidget {
  const _PositionedEvent({required this.task, required this.day});

  final Task task;
  final DateTime day;

  @override
  ConsumerState<_PositionedEvent> createState() => _PositionedEventState();
}

class _PositionedEventState extends ConsumerState<_PositionedEvent> {
  double? _resizeDelta;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final start = task.startDateTime!;
    final top = (start.hour * 60 + start.minute) / 60 * kHourHeight;
    final baseHeight = task.duration.inMinutes / 60 * kHourHeight;
    final height = ((_resizeDelta ?? 0) + baseHeight).clamp(22.0, kHourHeight * 24 - top);

    final category = ref.watch(categoryByIdProvider)[task.categoryId];
    final color = category == null ? AppColors.primary : Color(category.colorValue);

    final card = _EventCard(task: task, color: color, height: height);

    return Positioned(
      top: top,
      left: 2,
      right: 2,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: TaskDraggable(
              data: TaskDragData(task),
              feedbackWidth: 180,
              child: GestureDetector(
                onTap: () => showTaskDetailSheet(context, task),
                child: card,
              ),
            ),
          ),
          // Bottom edge resize handle: drag to change the end time.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 10,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) => setState(() => _resizeDelta = (_resizeDelta ?? 0) + d.delta.dy),
                onVerticalDragEnd: (_) => _commitResize(baseHeight),
                child: Center(
                  child: Container(
                    width: 30,
                    height: 3,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _commitResize(double baseHeight) async {
    final delta = _resizeDelta;
    setState(() => _resizeDelta = null);
    if (delta == null || delta.abs() < 4) return;

    final task = widget.task;
    final newMinutes = ((baseHeight + delta) / kHourHeight * 60)
        .round()
        .clamp(kSlotMinutes, 24 * 60);
    // Snap to the nearest 15 minutes, like the drop slots.
    final snapped = (newMinutes / kSlotMinutes).round() * kSlotMinutes;
    final end = task.startDateTime!.add(Duration(minutes: snapped));

    await MoveController(ref).run(
      context: context,
      task: task,
      move: TaskMove(endDateTime: end),
      description: 'Duration set to ${snapped ~/ 60}h ${snapped % 60}m',
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.task, required this.color, required this.height});

  final Task task;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            maxLines: height > 40 ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
          if (height > 44)
            Text(
              '${DateFormat('h:mm').format(task.startDateTime!)} – '
              '${DateFormat('h:mm a').format(task.startDateTime!.add(task.duration))}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: color.withValues(alpha: 0.9)),
            ),
        ],
      ),
    );
  }
}

/// Screenshot 26: "Drag to schedule" panel. Also accepts events dragged back
/// out of the grid, which clears their schedule rather than deleting them.
class _UnscheduledPanel extends ConsumerStatefulWidget {
  const _UnscheduledPanel({required this.tasks, this.horizontal = false});

  final List<Task> tasks;
  final bool horizontal;

  @override
  ConsumerState<_UnscheduledPanel> createState() => _UnscheduledPanelState();
}

class _UnscheduledPanelState extends ConsumerState<_UnscheduledPanel> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskDragData>(
      onWillAcceptWithDetails: (details) {
        final scheduled = details.data.task.startDateTime != null;
        if (scheduled) setState(() => _hovering = true);
        return scheduled;
      },
      onLeave: (_) => setState(() => _hovering = false),
      onAcceptWithDetails: (details) async {
        setState(() => _hovering = false);
        await MoveController(ref).run(
          context: context,
          task: details.data.task,
          move: const TaskMove(clearSchedule: true),
          description: 'Task unscheduled',
        );
      },
      builder: (context, candidate, rejected) {
        final items = [
          for (final t in widget.tasks)
            SizedBox(
              width: widget.horizontal ? 210 : null,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                child: TaskDraggable(
                  data: TaskDragData(t),
                  feedbackWidth: 200,
                  child: _UnscheduledCard(task: t),
                ),
              ),
            ),
        ];

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 8, 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovering ? AppColors.primarySoft : Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            border: _hovering ? Border.all(color: AppColors.primary, width: 2) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('DRAG TO SCHEDULE',
                        style: TextStyle(fontSize: 10, letterSpacing: 1.1, color: AppColors.muted)),
                  ),
                  Text('${widget.tasks.length}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Unscheduled', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 10),
              Expanded(
                child: widget.horizontal
                    ? ListView(scrollDirection: Axis.horizontal, children: items)
                    : ListView(children: items),
              ),
              if (!widget.horizontal)
                TextButton.icon(
                  onPressed: () => showQuickAddSheet(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add unscheduled task'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _UnscheduledCard extends ConsumerWidget {
  const _UnscheduledCard({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(categoryByIdProvider)[task.categoryId];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (category != null)
                  Text(category.name,
                      style: TextStyle(fontSize: 11, color: Color(category.colorValue))),
              ],
            ),
          ),
          const Icon(Icons.schedule, size: 15, color: AppColors.muted),
        ],
      ),
    );
  }
}

/// Month grid (screenshot 3). Each day accepts a dropped task, keeping its time.
class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({required this.anchor, required this.tasks, required this.onPickDay});

  final DateTime anchor;
  final List<Task> tasks;
  final ValueChanged<DateTime> onPickDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = DateTime(anchor.year, anchor.month, 1);
    final leading = first.weekday - 1;
    final daysInMonth = DateTime(anchor.year, anchor.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(anchor.year, anchor.month, d),
    ];
    final holidays = ref.watch(holidaysProvider).value ?? const <Holiday>[];

    return Column(
      children: [
        Row(
          children: [
            for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.85),
            itemCount: cells.length,
            itemBuilder: (context, i) {
              final day = cells[i];
              if (day == null) return const SizedBox.shrink();
              final dayTasks = tasksForDay(tasks, day);
              final isHoliday = holidays.any((h) =>
                  h.date.year == day.year && h.date.month == day.month && h.date.day == day.day);
              return _MonthCell(
                day: day,
                tasks: dayTasks,
                isHoliday: isHoliday,
                onTap: () => onPickDay(day),
              );
            },
          ),
        ),
        Expanded(child: _AgendaList(tasks: tasks, from: anchor, limitDays: 1)),
      ],
    );
  }
}

class _MonthCell extends ConsumerStatefulWidget {
  const _MonthCell({
    required this.day,
    required this.tasks,
    required this.isHoliday,
    required this.onTap,
  });

  final DateTime day;
  final List<Task> tasks;
  final bool isHoliday;
  final VoidCallback onTap;

  @override
  ConsumerState<_MonthCell> createState() => _MonthCellState();
}

class _MonthCellState extends ConsumerState<_MonthCell> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = widget.day.year == now.year &&
        widget.day.month == now.month &&
        widget.day.day == now.day;

    return DragTarget<TaskDragData>(
      onWillAcceptWithDetails: (_) {
        setState(() => _hovering = true);
        return true;
      },
      onLeave: (_) => setState(() => _hovering = false),
      onAcceptWithDetails: (details) async {
        setState(() => _hovering = false);
        final task = details.data.task;
        final base = task.startDateTime ?? DateTime(widget.day.year, widget.day.month, widget.day.day, 9);
        final start = DateTime(widget.day.year, widget.day.month, widget.day.day, base.hour, base.minute);
        await MoveController(ref).run(
          context: context,
          task: task,
          move: TaskMove(startDateTime: start, endDateTime: start.add(task.duration)),
          description: 'Task moved to ${DateFormat('MMM d').format(start)}',
        );
      },
      builder: (context, candidate, rejected) => InkWell(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: _hovering ? AppColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: _hovering ? Border.all(color: AppColors.primary, width: 1.6) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text('${widget.day.day}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isToday
                          ? Colors.white
                          : widget.isHoliday
                              ? AppColors.danger
                              : null,
                    )),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final t in widget.tasks.take(3))
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: t.completed ? AppColors.success : AppColors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgendaList extends ConsumerWidget {
  const _AgendaList({required this.tasks, required this.from, this.limitDays = 14});

  final List<Task> tasks;
  final DateTime from;
  final int limitDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = [for (var i = 0; i < limitDays; i++) from.add(Duration(days: i))];
    final holidays = ref.watch(holidaysProvider).value ?? const <Holiday>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
      children: [
        for (final day in days) ...[
          if (tasksForDay(tasks, day).isNotEmpty || _holidaysOn(holidays, day).isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Text(DateFormat('EEEE, MMMM d').format(day),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final h in _holidaysOn(holidays, day))
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.celebration_outlined, size: 18, color: AppColors.amber),
                  const SizedBox(width: 10),
                  Expanded(child: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  const Text('Public holiday', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                ]),
              ),
            for (final t in tasksForDay(tasks, day))
              ListTile(
                onTap: () => showTaskDetailSheet(context, t),
                contentPadding: EdgeInsets.zero,
                leading: Text(DateFormat('HH:mm').format(t.startDateTime!),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(
                  '${t.duration.inMinutes} min',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
          ],
        ],
      ],
    );
  }

  List<Holiday> _holidaysOn(List<Holiday> holidays, DateTime day) => holidays
      .where((h) => h.date.year == day.year && h.date.month == day.month && h.date.day == day.day)
      .toList();
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/holidays/holiday_data.dart';
import '../../core/holidays/holiday_service.dart';
import '../../core/move_controller.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/holiday_entry.dart';
import '../../models/task.dart';
import '../dnd/drag_core.dart';
import '../quick_add/quick_add_sheet.dart';
import '../task_detail/task_detail_sheet.dart';

enum CalendarView { day, threeDay, week, month, agenda }

extension CalendarViewX on CalendarView {
  String get label => switch (this) {
        CalendarView.day => 'Day',
        CalendarView.threeDay => '3 days',
        CalendarView.week => 'Week',
        CalendarView.month => 'Month',
        CalendarView.agenda => 'Agenda',
      };

  IconData get icon => switch (this) {
        CalendarView.day => Icons.calendar_view_day,
        CalendarView.threeDay => Icons.view_column_outlined,
        CalendarView.week => Icons.calendar_view_week,
        CalendarView.month => Icons.calendar_view_month,
        CalendarView.agenda => Icons.view_agenda_outlined,
      };

  /// Views that lay tasks out on a time grid, as opposed to month and agenda.
  bool get isTimeGrid =>
      this == CalendarView.day || this == CalendarView.threeDay || this == CalendarView.week;
}

/// Fallback hour height. The grid actually uses the height for the user's
/// chosen [CalendarDensity]; this is the comfortable value and is kept as the
/// default for anything constructed without one.
const double kHourHeight = 64;
const int kSlotMinutes = 15;

/// Maps the stored preference onto the view enum the page works in.
CalendarView _viewFor(CalendarViewPref pref) => switch (pref) {
      CalendarViewPref.day => CalendarView.day,
      CalendarViewPref.threeDay => CalendarView.threeDay,
      CalendarViewPref.week => CalendarView.week,
      CalendarViewPref.month => CalendarView.month,
      CalendarViewPref.agenda => CalendarView.agenda,
    };

CalendarViewPref _prefFor(CalendarView view) => switch (view) {
      CalendarView.day => CalendarViewPref.day,
      CalendarView.threeDay => CalendarViewPref.threeDay,
      CalendarView.week => CalendarViewPref.week,
      CalendarView.month => CalendarViewPref.month,
      CalendarView.agenda => CalendarViewPref.agenda,
    };

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
  /// The view the user picked during this visit. Null means "use the saved
  /// default", so the page honours the preference on open without fighting a
  /// change made while it is on screen.
  CalendarView? _view;
  DateTime _anchor = DateTime.now();
  final _gridScroll = ScrollController();

  /// What the grid is currently scrolled for, so the jump to the preferred
  /// hour happens on open and whenever the preference or density changes —
  /// and not on every rebuild, which would fight the user's own scrolling.
  double? _appliedScrollOffset;

  @override
  void dispose() {
    _gridScroll.dispose();
    super.dispose();
  }

  CalendarView _currentView(AppPreferences prefs) =>
      _view ?? _viewFor(prefs.calendarDefaultView);

  /// Records the choice both locally and in the user's preferences, so the
  /// selected view survives leaving the tab and reopening the app.
  void _selectView(CalendarView view, AppPreferences prefs) {
    setState(() => _view = view);
    if (_prefFor(view) != prefs.calendarDefaultView) {
      ref.read(savePreferencesProvider)(
          prefs.copyWith(calendarDefaultView: _prefFor(view)));
    }
  }

  /// How far the arrows move, in days, for the current view.
  int _viewSpanDays(CalendarView view) => switch (view) {
        CalendarView.day => 1,
        CalendarView.threeDay => 3,
        CalendarView.week => 7,
        CalendarView.month => 30,
        CalendarView.agenda => 7,
      };

  /// Three days starting at the anchor — the comfortable middle ground between
  /// a single day and a full week on a phone.
  List<DateTime> get _threeDays => [
        for (var i = 0; i < 3; i++)
          DateTime(_anchor.year, _anchor.month, _anchor.day + i),
      ];

  List<DateTime> _weekDays(AppPreferences prefs) {
    // The first day of the week follows the preference, so a Sunday-start
    // week is a real week and not Monday's grid relabelled.
    final firstWeekday = prefs.weekStartsOnMonday ? DateTime.monday : DateTime.sunday;
    final back = (_anchor.weekday - firstWeekday + 7) % 7;
    final start = DateTime(_anchor.year, _anchor.month, _anchor.day - back);
    final days = [
      for (var i = 0; i < 7; i++) DateTime(start.year, start.month, start.day + i),
    ];
    if (prefs.showWeekends) return days;
    return days
        .where((d) => d.weekday != DateTime.saturday && d.weekday != DateTime.sunday)
        .toList();
  }

  /// Category and board filters. These only hide events; they never change the
  /// task data, so filtering can't lose anything.
  String? _filterCategoryId;
  String? _filterBoardId;

  /// Puts the grid's viewport at the user's preferred starting hour. Earlier
  /// hours stay above it, reachable by scrolling up.
  void _applyPreferredScroll(AppPreferences prefs, double hourHeight) {
    final offset = prefs.calendarScrollHour * hourHeight;
    if (_appliedScrollOffset == offset) return;
    _appliedScrollOffset = offset;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_gridScroll.hasClients) return;
      _gridScroll.jumpTo(offset.clamp(0, _gridScroll.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final allTasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final prefs = ref.watch(appPreferencesProvider);
    final view = _currentView(prefs);
    final hourHeight = prefs.calendarDensity.hourHeight;

    if (view.isTimeGrid) _applyPreferredScroll(prefs, hourHeight);

    // Another screen can send the user here for a specific day, such as the
    // week strip on Today.
    final focus = ref.watch(calendarFocusProvider);
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _anchor = focus;
          if (_view == CalendarView.month) _view = CalendarView.day;
        });
        ref.read(calendarFocusProvider.notifier).clear();
      });
    }

    final tasks = allTasks.where((t) {
      if (_filterCategoryId != null && t.categoryId != _filterCategoryId) return false;
      if (_filterBoardId != null && t.boardId != _filterBoardId) return false;
      return true;
    }).toList();

    final unscheduled = tasks.where((t) => t.startDateTime == null && !t.completed).toList();
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          anchor: _anchor,
          view: view,
          density: prefs.calendarDensity,
          onView: (v) => _selectView(v, prefs),
          onDensity: (d) => ref
              .read(savePreferencesProvider)(prefs.copyWith(calendarDensity: d)),
          onToday: () => setState(() => _anchor = DateTime.now()),
          // The arrows move by whatever the current view shows, so Week jumps a
          // week and 3 days jumps three.
          onShift: (direction) => setState(
            () => _anchor = _anchor.add(Duration(days: direction * _viewSpanDays(view))),
          ),
        ),
        _FilterBar(
          categoryId: _filterCategoryId,
          boardId: _filterBoardId,
          onCategory: (id) => setState(() => _filterCategoryId = id),
          onBoard: (id) => setState(() => _filterBoardId = id),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide && view.isTimeGrid)
                SizedBox(width: 260, child: _UnscheduledPanel(tasks: unscheduled)),
              Expanded(child: _buildView(tasks, view, prefs, hourHeight)),
            ],
          ),
        ),
        if (!isWide && view.isTimeGrid && unscheduled.isNotEmpty)
          SizedBox(height: 152, child: _UnscheduledPanel(tasks: unscheduled, horizontal: true)),
      ],
    );
  }

  Widget _buildView(
    List<Task> tasks,
    CalendarView view,
    AppPreferences prefs,
    double hourHeight,
  ) {
    _TimeGrid grid(List<DateTime> days) => _TimeGrid(
          days: days,
          tasks: tasks,
          scrollController: _gridScroll,
          hourHeight: hourHeight,
          density: prefs.calendarDensity,
        );

    return switch (view) {
      CalendarView.day => grid([_anchor]),
      CalendarView.threeDay => grid(_threeDays),
      CalendarView.week => grid(_weekDays(prefs)),
      CalendarView.month => _MonthGrid(
          anchor: _anchor,
          tasks: tasks,
          weekStartsOnMonday: prefs.weekStartsOnMonday,
          onPickDay: (d) => setState(() {
            _anchor = d;
            _view = CalendarView.day;
          }),
        ),
      CalendarView.agenda => _AgendaList(tasks: tasks, from: _anchor),
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.anchor,
    required this.view,
    required this.density,
    required this.onView,
    required this.onDensity,
    required this.onToday,
    required this.onShift,
  });

  final DateTime anchor;
  final CalendarView view;
  final CalendarDensity density;
  final ValueChanged<CalendarView> onView;
  final ValueChanged<CalendarDensity> onDensity;
  final VoidCallback onToday;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
                    Text('CALENDAR',
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: palette.textSecondary)),
                    Text(DateFormat('MMMM y').format(anchor),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              IconButton(onPressed: () => onShift(-1), icon: const Icon(Icons.chevron_left)),
              TextButton(onPressed: onToday, child: const Text('Today')),
              IconButton(onPressed: () => onShift(1), icon: const Icon(Icons.chevron_right)),
              // Layout sits beside the view switcher because they are the same
              // kind of choice: how the calendar presents itself.
              PopupMenuButton<CalendarDensity>(
                tooltip: 'Calendar layout',
                position: PopupMenuPosition.under,
                onSelected: onDensity,
                icon: const Icon(Icons.tune, size: 19),
                itemBuilder: (context) => [
                  for (final option in CalendarDensity.values)
                    PopupMenuItem(
                      value: option,
                      child: Row(
                        children: [
                          Expanded(child: Text(option.label)),
                          if (option == density)
                            Icon(Icons.check, size: 16, color: context.palette.accent),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // A scrolling row rather than a segmented button: five views do not
          // fit across a phone, and a segmented button would squeeze or clip
          // them instead of letting the row scroll.
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final option in CalendarView.values)
                  _ViewButton(
                    view: option,
                    selected: option == view,
                    onTap: () => onView(option),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One calendar view option: Day, 3 days, Week, Month or Agenda.
class _ViewButton extends StatelessWidget {
  const _ViewButton({required this.view, required this.selected, required this.onTap});

  final CalendarView view;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final foreground = selected ? Colors.white : palette.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: selected ? null : Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(view.icon, size: 15, color: foreground),
              const SizedBox(width: 6),
              Text(
                view.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filters the calendar by category and board. Both only hide events; the
/// underlying tasks are untouched.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.categoryId,
    required this.boardId,
    required this.onCategory,
    required this.onBoard,
  });

  final String? categoryId;
  final String? boardId;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onBoard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final boards = ref.watch(boardsProvider).value ?? const <Board>[];
    final selectedCategory = categories.where((c) => c.id == categoryId).firstOrNull;
    final selectedBoard = boards.where((b) => b.id == boardId).firstOrNull;

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        children: [
          PopupMenuButton<String?>(
            onSelected: (v) => onCategory(v),
            position: PopupMenuPosition.under,
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('All categories')),
              for (final c in categories) PopupMenuItem(value: c.id, child: Text(c.name)),
            ],
            child: _FilterChip(
              label: selectedCategory?.name ?? 'Category',
              active: categoryId != null,
              color: selectedCategory == null ? null : Color(selectedCategory.colorValue),
            ),
          ),
          PopupMenuButton<String?>(
            onSelected: (v) => onBoard(v),
            position: PopupMenuPosition.under,
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('All boards')),
              for (final b in boards) PopupMenuItem(value: b.id, child: Text(b.name)),
            ],
            child: _FilterChip(
              label: selectedBoard?.name ?? 'Board',
              active: boardId != null,
            ),
          ),
          if (categoryId != null || boardId != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextButton(
                onPressed: () {
                  onCategory(null);
                  onBoard(null);
                },
                child: const Text('Clear'),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, this.color});

  final String label;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? tint.withValues(alpha: 0.12) : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: active ? Border.all(color: tint) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.filter_list, size: 14, color: active ? tint : context.palette.textSecondary),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: active ? tint : context.palette.textSecondary,
            )),
      ]),
    );
  }
}

/// Day and week views. Each 15-minute slot is a drop target.
class _TimeGrid extends ConsumerWidget {
  const _TimeGrid({
    required this.days,
    required this.tasks,
    required this.scrollController,
    required this.hourHeight,
    required this.density,
  });

  final List<DateTime> days;
  final List<Task> tasks;
  final ScrollController scrollController;
  final double hourHeight;
  final CalendarDensity density;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

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
                          style: TextStyle(
                              fontSize: 10,
                              color: palette.textSecondary,
                              letterSpacing: 1)),
                      const SizedBox(height: 2),
                      _DayNumber(day: day),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Divider(height: 1, color: palette.divider),

        // Tasks given a date but no time sit here rather than at an arbitrary
        // place in the grid. Holidays share the row, so a day can show both.
        _AllDayRow(days: days, tasks: tasks),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            child: SizedBox(
              height: hourHeight * 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Column(
                      children: [
                        for (var h = 0; h < 24; h++)
                          SizedBox(
                            height: hourHeight,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8, top: 2),
                                child: Text(
                                  DateFormat('h a').format(DateTime(2020, 1, 1, h)),
                                  style: TextStyle(
                                      fontSize: 10.5, color: palette.textSecondary),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final day in days)
                    Expanded(
                      child: _DayColumn(
                        day: day,
                        hourHeight: hourHeight,
                        density: density,
                        // All-day tasks are drawn in the row above, not in the
                        // time grid.
                        tasks: tasksForDay(tasks, day).where((t) => !t.isAllDay).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The all-day strip above the time grid. A task with a date but no time
/// lands here, and can be dropped onto a time slot later to get one.
class _AllDayRow extends ConsumerWidget {
  const _AllDayRow({required this.days, required this.tasks});

  final List<DateTime> days;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final categories = ref.watch(categoryByIdProvider);
    final holidaysByDay = ref.watch(holidayServiceProvider).entriesByDay(days);

    final hasAnything = days.any((day) =>
        tasksForDay(tasks, day).any((t) => t.isAllDay) || holidaysByDay.on(day).isNotEmpty);

    if (!hasAnything) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 8),
              child: Text('all-day',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 10, color: palette.textSecondary)),
            ),
          ),
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Column(
                  children: [
                    // Holidays first, then the day's all-day tasks. Both are
                    // drawn: a holiday never hides a task.
                    for (final holiday in holidaysByDay.on(day))
                      _HolidayPill(holiday: holiday),
                    for (final task in tasksForDay(tasks, day).where((t) => t.isAllDay))
                      _AllDayChip(task: task, categories: categories),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A holiday on the calendar. It is metadata, not a task: it has no drag
/// handle and no drop behaviour, so it cannot interfere with scheduling.
class _HolidayPill extends StatelessWidget {
  const _HolidayPill({required this.holiday});
  final HolidayEntry holiday;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final flag = HolidayData.country(holiday.countryCode)?.flag ?? '';

    return Tooltip(
      message: '${holiday.name} · ${holiday.category.label}',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: palette.tint(palette.warning),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          flag.isEmpty ? holiday.name : '$flag ${holiday.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: palette.warning, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.task, required this.categories});

  final Task task;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context) {
    final category = task.categoryId == null ? null : categories[task.categoryId];
    final color = category == null ? AppColors.primary : Color(category.colorValue);

    return TaskDraggable(
      data: TaskDragData(task),
      feedbackWidth: 180,
      child: GestureDetector(
        onTap: () => showTaskDetailSheet(context, task),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(5),
            border: Border(left: BorderSide(color: color, width: 2.5)),
          ),
          child: Text(
            task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
              decoration: task.completed ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
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
  const _DayColumn({
    required this.day,
    required this.tasks,
    required this.hourHeight,
    required this.density,
  });

  final DateTime day;
  final List<Task> tasks;
  final double hourHeight;
  final CalendarDensity density;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const slotsPerDay = 24 * 60 ~/ kSlotMinutes;
    final slotHeight = hourHeight * kSlotMinutes / 60;
    final palette = context.palette;
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: palette.gridLine)),
      ),
      child: Stack(
        children: [
          // Hour lines.
          Column(
            children: [
              for (var h = 0; h < 24; h++)
                Container(
                  height: hourHeight,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: palette.gridLine)),
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
          for (final task in tasks)
            _PositionedEvent(
              task: task,
              day: day,
              hourHeight: hourHeight,
              density: density,
            ),
          // The current-time line, drawn last so it reads over an event.
          if (isToday)
            Positioned(
              top: (now.hour * 60 + now.minute) / 60 * hourHeight,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: palette.danger, shape: BoxShape.circle),
                    ),
                    Expanded(child: Container(height: 1.4, color: palette.danger)),
                  ],
                ),
              ),
            ),
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
  const _PositionedEvent({
    required this.task,
    required this.day,
    required this.hourHeight,
    required this.density,
  });

  final Task task;
  final DateTime day;
  final double hourHeight;
  final CalendarDensity density;

  @override
  ConsumerState<_PositionedEvent> createState() => _PositionedEventState();
}

class _PositionedEventState extends ConsumerState<_PositionedEvent> {
  double? _resizeDelta;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final hourHeight = widget.hourHeight;
    final start = task.startDateTime!;
    final top = (start.hour * 60 + start.minute) / 60 * hourHeight;
    final baseHeight = task.duration.inMinutes / 60 * hourHeight;
    final height = ((_resizeDelta ?? 0) + baseHeight).clamp(22.0, hourHeight * 24 - top);

    final category = ref.watch(categoryByIdProvider)[task.categoryId];
    // The event takes the category's colour, lifted for dark mode so a colour
    // chosen in light mode is still readable here.
    final color = context.palette
        .onTint(category == null ? AppColors.primary : Color(category.colorValue));

    final card = _EventCard(
      task: task,
      color: color,
      height: height,
      showDetail: widget.density.showEventDetail,
    );

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
    final newMinutes = ((baseHeight + delta) / widget.hourHeight * 60)
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
  const _EventCard({
    required this.task,
    required this.color,
    required this.height,
    this.showDetail = true,
  });

  final Task task;
  final Color color;
  final double height;

  /// False in the compact layout, where only the title fits.
  final bool showDetail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
      decoration: BoxDecoration(
        color: context.palette.tint(color),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (task.completed) ...[
                Icon(Icons.check_circle, size: 11, color: color),
                const SizedBox(width: 3),
              ],
              Expanded(
                child: Text(
                  task.title,
                  maxLines: height > 40 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                    // A finished task stays on the calendar, struck through,
                    // rather than vanishing from the day's history.
                    decoration: task.completed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
          if (showDetail && height > 44)
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
            color: _hovering ? context.palette.selected : Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            border: _hovering ? Border.all(color: AppColors.primary, width: 2) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('DRAG TO SCHEDULE',
                        style: TextStyle(fontSize: 10, letterSpacing: 1.1, color: context.palette.textSecondary)),
                  ),
                  Text('${widget.tasks.length}', style: TextStyle(fontSize: 11, color: context.palette.textSecondary)),
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
          Icon(Icons.drag_indicator, size: 16, color: context.palette.textSecondary),
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
                      style: TextStyle(fontSize: 11, color: context.palette.onTint(Color(category.colorValue)))),
              ],
            ),
          ),
          Icon(Icons.schedule, size: 15, color: context.palette.textSecondary),
        ],
      ),
    );
  }
}

/// Month grid (screenshot 3). Each day accepts a dropped task, keeping its time.
class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({
    required this.anchor,
    required this.tasks,
    required this.onPickDay,
    this.weekStartsOnMonday = true,
  });

  final DateTime anchor;
  final List<Task> tasks;
  final ValueChanged<DateTime> onPickDay;
  final bool weekStartsOnMonday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final first = DateTime(anchor.year, anchor.month, 1);
    final firstWeekday = weekStartsOnMonday ? DateTime.monday : DateTime.sunday;
    final leading = (first.weekday - firstWeekday + 7) % 7;
    final daysInMonth = DateTime(anchor.year, anchor.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(anchor.year, anchor.month, d),
    ];

    final holidaysByDay = ref
        .watch(holidayServiceProvider)
        .entriesByDay(cells.whereType<DateTime>());

    const mondayFirst = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final headers = weekStartsOnMonday
        ? mondayFirst
        : [mondayFirst.last, ...mondayFirst.take(6)];

    return Column(
      children: [
        Row(
          children: [
            for (final label in headers)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(label,
                        style: TextStyle(fontSize: 11, color: palette.textSecondary)),
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
              return _MonthCell(
                day: day,
                tasks: tasksForDay(tasks, day),
                holidays: holidaysByDay.on(day),
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
    required this.holidays,
    required this.onTap,
  });

  final DateTime day;
  final List<Task> tasks;
  final List<HolidayEntry> holidays;
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
      builder: (context, candidate, rejected) {
        final palette = context.palette;
        final holiday = widget.holidays.firstOrNull;

        return InkWell(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _hovering ? palette.selected : Colors.transparent,
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
                            : holiday != null
                                ? palette.warning
                                : palette.textPrimary,
                      )),
                ),
                // The holiday's name, not just a coloured number, so the day
                // says what it is without opening it.
                if (holiday != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text(
                      holiday.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 8.5, color: palette.warning, fontWeight: FontWeight.w600),
                    ),
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
                          color: t.completed ? palette.success : palette.warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
    final palette = context.palette;
    final days = [for (var i = 0; i < limitDays; i++) from.add(Duration(days: i))];
    final holidaysByDay = ref.watch(holidayServiceProvider).entriesByDay(days);
    final categories = ref.watch(categoryByIdProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
      children: [
        for (final day in days) ...[
          if (tasksForDay(tasks, day).isNotEmpty || holidaysByDay.on(day).isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Text(DateFormat('EEEE, MMMM d').format(day),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final h in holidaysByDay.on(day))
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: palette.tint(palette.warning),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.celebration_outlined, size: 18, color: palette.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      HolidayData.country(h.countryCode) == null
                          ? h.name
                          : '${HolidayData.country(h.countryCode)!.flag} ${h.name}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(h.category.label,
                      style: TextStyle(fontSize: 11, color: palette.textSecondary)),
                ]),
              ),
            // Tasks are listed whether or not the day is a holiday.
            for (final t in tasksForDay(tasks, day))
              ListTile(
                onTap: () => showTaskDetailSheet(context, t),
                contentPadding: EdgeInsets.zero,
                leading: Text(
                  t.isAllDay ? 'all-day' : DateFormat('HH:mm').format(t.startDateTime!),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
                title: Text(t.title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(
                  [
                    if (categories[t.categoryId] != null) categories[t.categoryId]!.name,
                    '${t.duration.inMinutes} min',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ),
          ],
        ],
      ],
    );
  }
}

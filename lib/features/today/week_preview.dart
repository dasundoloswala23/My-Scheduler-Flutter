import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';

/// A week strip on the home screen: the seven days around today, each showing
/// how busy it is. Tapping a day opens the full Calendar on that date.
///
/// It reads the same scheduled tasks the Calendar does, so the two can never
/// disagree.
class WeekPreview extends ConsumerWidget {
  const WeekPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final holidays = ref.watch(holidaysProvider).value ?? const <Holiday>[];
    final categories = ref.watch(categoryByIdProvider);

    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];

    void openCalendar(DateTime day) {
      ref.read(calendarFocusProvider.notifier).focus(day);
      ref.read(homeTabProvider.notifier).go(2);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.muted),
                const SizedBox(width: 8),
                Text(
                  DateFormat('MMMM y').format(now),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => openCalendar(now),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(children: [
                      Text('Open calendar',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                      Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (final day in days)
                Expanded(
                  child: _DayCell(
                    day: day,
                    tasks: tasksForDay(tasks, day),
                    isHoliday: holidays.any((h) =>
                        h.date.year == day.year &&
                        h.date.month == day.month &&
                        h.date.day == day.day),
                    categories: categories,
                    onTap: () => openCalendar(day),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.tasks,
    required this.isHoliday,
    required this.categories,
    required this.onTap,
  });

  final DateTime day;
  final List<Task> tasks;
  final bool isHoliday;
  final Map<String, Category> categories;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Text(
              DateFormat('E').format(day).substring(0, 1),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isHoliday ? AppColors.danger : AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: isToday
                      ? Colors.white
                      : isHoliday
                          ? AppColors.danger
                          : null,
                ),
              ),
            ),
            const SizedBox(height: 5),
            // A dot per task, coloured by its category, so the week reads at a
            // glance. Four is enough to show "busy" without crowding the cell.
            SizedBox(
              height: 5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final task in tasks.take(4))
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: task.completed
                            ? AppColors.success
                            : task.categoryId != null && categories[task.categoryId] != null
                                ? Color(categories[task.categoryId]!.colorValue)
                                : AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

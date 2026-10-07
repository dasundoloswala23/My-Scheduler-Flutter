import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import 'more_page.dart';

/// Screenshot 10 and 35: real numbers aggregated from tasks and focus sessions.
class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final sessions = ref.watch(focusSessionsProvider).value ?? const <FocusSession>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];

    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));

    final completedThisWeek =
        tasks.where((t) => t.completedAt != null && !t.completedAt!.isBefore(weekStart)).toList();
    final overdue = tasks
        .where((t) => !t.completed && t.startDateTime != null && t.startDateTime!.isBefore(now))
        .length;
    final completionRate = tasks.isEmpty
        ? 0
        : (tasks.where((t) => t.completed).length / tasks.length * 100).round();
    final focusMinutes = sessions
        .where((s) => !s.startedAt.isBefore(weekStart))
        .fold<int>(0, (sum, s) => sum + s.minutes);

    // Completions per weekday, Monday first.
    final perDay = List<int>.filled(7, 0);
    for (final t in completedThisWeek) {
      perDay[t.completedAt!.weekday - 1]++;
    }
    final maxPerDay = perDay.fold<int>(1, (m, v) => v > m ? v : m);

    // Share of active tasks by category.
    final counts = activeTaskCountByCategory(tasks);
    final totalCounted = counts.values.fold<int>(0, (a, b) => a + b);

    return SubPage(
      eyebrow: 'Your insights',
      title: 'Productivity',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This week', style: TextStyle(color: context.palette.textSecondary, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Text('${completedThisWeek.length}',
                      style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700, height: 1)),
                  Text('tasks completed', style: TextStyle(color: context.palette.textSecondary, fontSize: 12.5)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 120,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    height: (perDay[i] / maxPerDay) * 90 + 4,
                                    decoration: BoxDecoration(
                                      color: i == now.weekday - 1
                                          ? AppColors.primary
                                          : context.palette.selected,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                                      style: TextStyle(fontSize: 11, color: context.palette.textSecondary)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.track_changes,
                  value: '${focusMinutes ~/ 60}h ${focusMinutes % 60}m',
                  label: 'Focus time',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.check,
                  value: '$completionRate%',
                  label: 'Completion',
                  color: context.palette.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.flag_outlined,
                  value: '$overdue',
                  label: 'Overdue',
                  color: context.palette.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.list_alt,
                  value: '${tasks.where((t) => !t.completed).length}',
                  label: 'Remaining',
                  color: AppColors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text('Category activity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          if (totalCounted == 0)
            Text('No active tasks yet.', style: TextStyle(color: context.palette.textSecondary, fontSize: 13))
          else
            for (final c in categories.where((c) => (counts[c.id] ?? 0) > 0))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 9, color: Color(c.colorValue)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 110,
                      child: Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (counts[c.id] ?? 0) / totalCounted,
                          minHeight: 7,
                          backgroundColor: Colors.black.withValues(alpha: 0.06),
                          valueColor: AlwaysStoppedAnimation(Color(c.colorValue)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${(((counts[c.id] ?? 0) / totalCounted) * 100).round()}%',
                        style: TextStyle(fontSize: 12, color: context.palette.textSecondary)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(label, style: TextStyle(fontSize: 11.5, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

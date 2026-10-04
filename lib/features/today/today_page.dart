import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/task.dart';
import '../task_detail/task_detail_sheet.dart';

/// Screenshots 12–13: greeting, progress ring, today's timeline, coming up.
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final now = DateTime.now();
    final today = tasksForDay(tasks, now);
    final done = today.where((t) => t.completed).length;
    final goal = today.isEmpty ? 8 : today.length;
    final name = FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ?? 'there';
    final upcoming = tasks
        .where((t) => t.startDateTime != null && t.startDateTime!.isAfter(now) && !_isSameDay(t.startDateTime!, now))
        .toList()
      ..sort((a, b) => a.startDateTime!.compareTo(b.startDateTime!));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
      children: [
        Text(DateFormat('EEEE, MMMM d').format(now),
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 2),
        Text('${_greeting(now)}, $name',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        _ProgressCard(done: done, goal: goal),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YOUR DAY', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: AppColors.muted)),
                  Text('Scheduled', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19)),
                ],
              ),
            ),
            Text(DateFormat('MMM d').format(now),
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        if (today.isEmpty)
          const _EmptyHint(text: 'Nothing scheduled today. Add a task to get started.')
        else
          for (final task in today) _TimelineRow(task: task),
        const SizedBox(height: 24),
        const Text('Coming up', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        const SizedBox(height: 10),
        if (upcoming.isEmpty)
          const _EmptyHint(text: 'Nothing coming up yet.')
        else
          for (final task in upcoming.take(5)) _UpcomingCard(task: task),
      ],
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.done, required this.goal});

  final int done;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final progress = goal == 0 ? 0.0 : (done / goal).clamp(0.0, 1.0);
    final remaining = (goal - done).clamp(0, goal);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$done', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                    TextSpan(text: '/$goal', style: const TextStyle(fontSize: 11)),
                  ]),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("TODAY'S PROGRESS",
                    style: TextStyle(fontSize: 9.5, letterSpacing: 1.2, color: Colors.white70)),
                const SizedBox(height: 4),
                Text(
                  remaining == 0 ? 'All done for today.' : "You're in a good flow.",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
                ),
                const SizedBox(height: 2),
                Text(
                  remaining == 0
                      ? 'Enjoy the rest of your day.'
                      : '$remaining more ${remaining == 1 ? 'task' : 'tasks'} to reach your daily goal.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends ConsumerWidget {
  const _TimelineRow({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(categoryByIdProvider)[task.categoryId];
    final color = category == null ? AppColors.primary : Color(category.colorValue);

    return InkWell(
      onTap: () => showTaskDetailSheet(context, task),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(DateFormat('HH:mm').format(task.startDateTime!),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 10),
              child: Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => ref.read(repoProvider).setTaskCompleted(task, !task.completed),
              child: Icon(
                task.completed ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: task.completed ? AppColors.success : AppColors.muted,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: task.completed ? TextDecoration.lineThrough : null,
                        color: task.completed ? AppColors.muted : null,
                      )),
                  if (category != null)
                    Text(
                      category.name +
                          (task.priority == TaskPriority.high ? ' · High priority' : ''),
                      style: TextStyle(fontSize: 12, color: color),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => showTaskDetailSheet(context, task),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(DateFormat('dd').format(task.startDateTime!),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text(DateFormat('MMM').format(task.startDateTime!).toUpperCase(),
                style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          ],
        ),
        title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${task.subtasks.length} subtasks · ${DateFormat('h:mm a').format(task.startDateTime!)}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
    );
  }
}

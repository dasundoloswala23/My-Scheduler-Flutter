import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/task.dart';
import '../task_detail/task_detail_sheet.dart';
import 'week_preview.dart';

/// Screenshots 12–13: greeting, progress ring, today's timeline, coming up.
class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  /// The day being looked at, as a local calendar date (no time of day).
  DateTime _day = dateOnly(DateTime.now());

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(_day.year - 5),
      lastDate: DateTime(_day.year + 10),
    );
    if (picked != null) setState(() => _day = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final now = DateTime.now();
    final isToday = _isSameDay(_day, now);
    final today = tasksForDay(tasks, _day);
    final done = today.where((t) => t.completed).length;
    final goal = today.isEmpty ? 8 : today.length;
    final name = _firstName();
    final upcoming = tasks
        .where((t) =>
            t.startDateTime != null &&
            !t.startDateTime!.isBefore(shiftDay(_day, 1)))
        .toList()
      ..sort((a, b) => a.startDateTime!.compareTo(b.startDateTime!));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
      children: [
        Row(children: [
          IconButton(
            tooltip: 'Previous day',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _day = shiftDay(_day, -1)),
          ),
          Flexible(
            child: InkWell(
            onTap: _pickDay,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(DateFormat('EEEE, MMMM d').format(_day),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: context.palette.textSecondary)),
            ),
          ),
          ),
          IconButton(
            tooltip: 'Next day',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => _day = shiftDay(_day, 1)),
          ),
          if (!isToday)
            TextButton(
              onPressed: () => setState(() => _day = dateOnly(DateTime.now())),
              child: const Text('Today'),
            ),
        ]),
        const SizedBox(height: 2),
        Text('${_greeting(now)}, $name',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        _ProgressCard(done: done, goal: goal, isToday: isToday),
        const SizedBox(height: 16),
        const WeekPreview(),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YOUR DAY', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: context.palette.textSecondary)),
                  Text('Scheduled', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19)),
                ],
              ),
            ),
            Text(DateFormat('MMM d').format(_day),
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        if (today.isEmpty)
          _EmptyHint(
              text: isToday
                  ? 'Nothing scheduled today. Add a task to get started.'
                  : 'Nothing scheduled on ${DateFormat('MMM d').format(_day)}.')
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

  /// The signed-in user's first name. Falls back to a neutral word when there is
  /// no user, or Firebase is not available (as in a widget test).
  static String _firstName() {
    try {
      return FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ?? 'there';
    } catch (_) {
      return 'there';
    }
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
  const _ProgressCard({required this.done, required this.goal, required this.isToday});

  final int done;
  final int goal;
  final bool isToday;

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
                Text(isToday ? "TODAY'S PROGRESS" : 'PROGRESS',
                    style: TextStyle(fontSize: 9.5, letterSpacing: 1.2, color: Colors.white70)),
                const SizedBox(height: 4),
                Text(
                  remaining == 0 ? (isToday ? 'All done for today.' : 'All done.') : "You're in a good flow.",
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
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.palette.textSecondary)),
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
                color: task.completed ? context.palette.success : context.palette.textSecondary,
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
                        color: task.completed ? context.palette.textSecondary : null,
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
            Icon(Icons.chevron_right, size: 18, color: context.palette.textSecondary),
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
                style: TextStyle(fontSize: 10, color: context.palette.textSecondary)),
          ],
        ),
        title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${task.subtasks.length} subtasks · ${DateFormat('h:mm a').format(task.startDateTime!)}',
          style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
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
      child: Text(text, style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/task.dart';
import '../boards/task_menu.dart';
import '../task_detail/task_detail_sheet.dart';

/// Screenshot 4: quick capture. Anything without a board or list waits here
/// until it is given a board, date or category.
class InboxPage extends ConsumerWidget {
  const InboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final unsorted = tasks.where((t) => t.isUnsorted && !t.completed).toList();
    final categories = ref.watch(categoryByIdProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
      children: [
        Text('QUICK CAPTURE',
            style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: context.palette.textSecondary)),
        Text('Inbox', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.palette.selected,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Clear your mind',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                    SizedBox(height: 2),
                    Text('Capture it now, organize it later.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.primary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(child: Text('Unsorted', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${unsorted.length}', style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (unsorted.isEmpty)
          const _InboxEmpty()
        else
          for (final task in unsorted)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                onTap: () => showTaskDetailSheet(context, task),
                leading: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => ref.read(repoProvider).setTaskCompleted(task, true),
                  child: Icon(Icons.circle_outlined, color: context.palette.textSecondary),
                ),
                title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                subtitle: Text(
                  [
                    categories[task.categoryId]?.name ?? 'No category',
                    if (task.startDateTime != null)
                      DateFormat(task.isAllDay ? 'MMM d' : 'MMM d, h:mm a')
                          .format(task.startDateTime!),
                    task.priority.label,
                  ].join('  ·  '),
                  style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
                ),
                trailing: TaskMenuButton(task: task),
              ),
            ),
        const SizedBox(height: 16),
        if (unsorted.isNotEmpty) const _InboxZero(),
      ],
    );
  }
}

class _InboxEmpty extends StatelessWidget {
  const _InboxEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: context.palette.textSecondary),
          const SizedBox(height: 10),
          const Text('Your inbox is empty',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text('Tasks you capture without a board or list land here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: context.palette.textSecondary)),
        ],
      ),
    );
  }
}

class _InboxZero extends StatelessWidget {
  const _InboxZero();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.inbox_outlined, size: 18, color: context.palette.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Inbox zero feels good.',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text('Assign a board, date, or category to move items out of your inbox.',
                  style: TextStyle(fontSize: 12, color: context.palette.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

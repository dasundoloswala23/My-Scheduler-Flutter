import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        const Text('QUICK CAPTURE',
            style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: AppColors.muted)),
        Text('Inbox', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
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
          _InboxZero()
        else
          for (final task in unsorted)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                onTap: () => showTaskDetailSheet(context, task),
                leading: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => ref.read(repoProvider).setTaskCompleted(task, true),
                  child: const Icon(Icons.circle_outlined, color: AppColors.muted),
                ),
                title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                subtitle: Text(
                  categories[task.categoryId]?.name ?? 'Unsorted',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                trailing: TaskMenuButton(task: task),
              ),
            ),
        const SizedBox(height: 16),
        if (unsorted.isNotEmpty) _InboxZero(),
      ],
    );
  }
}

class _InboxZero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.inbox_outlined, size: 18, color: AppColors.muted),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Inbox zero feels good.',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              SizedBox(height: 2),
              Text('Assign a board, date, or category to move items out of your inbox.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

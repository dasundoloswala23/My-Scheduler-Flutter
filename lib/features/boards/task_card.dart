import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import '../task_detail/task_detail_sheet.dart';
import 'task_menu.dart';

/// The card from the screenshots: category chip, title, description,
/// then priority, date, subtask progress and attachment count.
class TaskCard extends ConsumerWidget {
  const TaskCard({super.key, required this.task, this.showMenu = true});

  final Task task;
  final bool showMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(categoryByIdProvider)[task.categoryId];
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showTaskDetailSheet(context, task),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (category != null) _CategoryChip(category: category),
                  const Spacer(),
                  if (showMenu)
                    TaskMenuButton(task: task)
                  else
                    const SizedBox(height: 24),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CompleteCircle(task: task),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              decoration: task.completed ? TextDecoration.lineThrough : null,
                              color: task.completed ? AppColors.muted : null,
                            ),
                          ),
                          if (task.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              task.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_hasMeta) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _MetaRow(task: task),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasMeta =>
      task.priority != TaskPriority.none ||
      task.startDateTime != null ||
      task.subtasks.isNotEmpty ||
      task.attachments.isNotEmpty ||
      task.attachmentCount > 0;
}

class _CompleteCircle extends ConsumerWidget {
  const _CompleteCircle({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => ref.read(repoProvider).setTaskCompleted(task, !task.completed),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          task.completed ? Icons.check_circle : Icons.circle_outlined,
          size: 20,
          color: task.completed ? AppColors.success : AppColors.muted,
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        category.name,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    if (task.priority != TaskPriority.none) {
      final color = switch (task.priority) {
        TaskPriority.high => AppColors.danger,
        TaskPriority.medium => AppColors.amber,
        _ => AppColors.muted,
      };
      items.add(_Meta(icon: Icons.flag_outlined, label: task.priority.label, color: color));
    }
    if (task.startDateTime != null) {
      items.add(_Meta(
        icon: Icons.calendar_today_outlined,
        label: DateFormat('MMM d').format(task.startDateTime!),
      ));
    }
    if (task.subtasks.isNotEmpty) {
      items.add(_Meta(
        icon: Icons.check,
        label: '${task.doneSubtasks}/${task.subtasks.length}',
      ));
    }
    // Real uploads keep a count on the task; the legacy string list is the
    // fallback for documents written before attachments were real files.
    final attachmentCount =
        task.attachmentCount > 0 ? task.attachmentCount : task.attachments.length;
    if (attachmentCount > 0) {
      items.add(_Meta(icon: Icons.attach_file, label: '$attachmentCount'));
    }

    return Wrap(spacing: 14, runSpacing: 6, children: items);
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
      ],
    );
  }
}

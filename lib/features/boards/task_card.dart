import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/link_preview.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import '../task_detail/task_detail_sheet.dart';
import 'task_menu.dart';

/// A board card: category chip, title, the schedule and reminder meta, an
/// attachment or link preview, and the subtask checklist.
///
/// The card is compact by default. A long checklist collapses behind
/// "+N more" rather than stretching the card, so one task cannot make the
/// board unusable (section 6 of the brief).
class TaskCard extends ConsumerStatefulWidget {
  const TaskCard({super.key, required this.task, this.showMenu = true});

  final Task task;
  final bool showMenu;

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  /// Per-card, not persisted: expanding one card's checklist is a glance, not
  /// a preference.
  bool _subtasksExpanded = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final theme = Theme.of(context);
    final palette = context.palette;
    final prefs = ref.watch(appPreferencesProvider);
    final category = ref.watch(categoryByIdProvider)[task.categoryId];

    final link = LinkPreview.firstIn('${task.description} ${task.title}');

    return Card(
      margin: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showTaskDetailSheet(context, task),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (category != null || widget.showMenu)
                Row(
                  children: [
                    if (category != null) _CategoryChip(category: category),
                    const Spacer(),
                    if (widget.showMenu)
                      TaskMenuButton(task: task)
                    else
                      const SizedBox(height: 22),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 2),
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
                              decoration:
                                  task.completed ? TextDecoration.lineThrough : null,
                              color: task.completed ? palette.textSecondary : null,
                            ),
                          ),
                          if (task.description.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              task.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (task.attachmentPreview != null) ...[
                const SizedBox(height: 8),
                _AttachmentPreviewTile(
                  preview: task.attachmentPreview!,
                  count: task.attachmentCount,
                ),
              ] else if (link != null) ...[
                const SizedBox(height: 8),
                _LinkPreviewTile(link: link),
              ],
              if (_hasMeta) ...[
                const SizedBox(height: 9),
                Divider(height: 1, color: palette.divider),
                const SizedBox(height: 7),
                _MetaRow(task: task),
              ],
              if (task.subtasks.isNotEmpty && prefs.showSubtasksOnCards) ...[
                const SizedBox(height: 8),
                _SubtaskChecklist(
                  task: task,
                  previewCount: prefs.subtaskPreviewCount,
                  expanded: _subtasksExpanded,
                  onToggleExpanded: () =>
                      setState(() => _subtasksExpanded = !_subtasksExpanded),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasMeta =>
      widget.task.priority != TaskPriority.none ||
      widget.task.startDateTime != null ||
      widget.task.subtasks.isNotEmpty ||
      widget.task.attachments.isNotEmpty ||
      widget.task.attachmentCount > 0 ||
      widget.task.effectiveReminders.isNotEmpty;
}

class _CompleteCircle extends ConsumerWidget {
  const _CompleteCircle({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => ref.read(repoProvider).setTaskCompleted(task, !task.completed),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          task.completed ? Icons.check_circle : Icons.circle_outlined,
          size: 20,
          color: task.completed ? palette.success : palette.textSecondary,
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
    final palette = context.palette;
    // The stored colour is lifted for dark mode so a category picked in light
    // mode is still legible, rather than a dark colour on a dark chip.
    final color = palette.onTint(Color(category.colorValue));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.tint(color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        category.name,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// The subtask checklist on the front of the card.
///
/// Ticking a box writes straight to the task and deliberately does not open
/// the detail sheet, which is what makes the checklist usable from the board.
class _SubtaskChecklist extends ConsumerWidget {
  const _SubtaskChecklist({
    required this.task,
    required this.previewCount,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final Task task;
  final int previewCount;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final subtasks = task.subtasks;
    final done = task.doneSubtasks;
    final shown = expanded ? subtasks : subtasks.take(previewCount).toList();
    final hidden = subtasks.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: subtasks.isEmpty ? 0 : done / subtasks.length,
                  minHeight: 4,
                  backgroundColor: palette.divider,
                  valueColor: AlwaysStoppedAnimation(
                    done == subtasks.length ? palette.success : AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$done/${subtasks.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final subtask in shown)
          _SubtaskRow(
            task: task,
            subtask: subtask,
            onToggle: () => _toggle(ref, subtask),
          ),
        if (hidden > 0 || expanded)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Text(
                  expanded ? 'Show less' : '+ $hidden more',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _toggle(WidgetRef ref, Subtask subtask) async {
    final updated = [
      for (final s in task.subtasks)
        if (s.id == subtask.id) s.copyWith(done: !s.done) else s,
    ];
    await ref.read(repoProvider).updateTask(task.copyWith(subtasks: updated));
  }
}

class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({required this.task, required this.subtask, required this.onToggle});

  final Task task;
  final Subtask subtask;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      // Stops the tap reaching the card, so ticking a box never opens the
      // detail sheet.
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              subtask.done ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: subtask.done ? palette.success : palette.textSecondary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                subtask.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  color: subtask.done ? palette.textDisabled : palette.textPrimary,
                  decoration: subtask.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A thumbnail for an image attachment, or a typed icon for anything else.
class _AttachmentPreviewTile extends StatelessWidget {
  const _AttachmentPreviewTile({required this.preview, required this.count});

  final AttachmentPreview preview;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final thumbnail = preview.thumbnailUrl;

    if (preview.isImage && thumbnail != null && thumbnail.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: thumbnail,
              height: 112,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: (context, _) => Container(height: 112, color: palette.surfaceVariant),
              // A preview that will not load must never break the card.
              errorWidget: (context, _, _) =>
                  _FileChip(icon: Icons.image_outlined, label: preview.fileName, count: count),
            ),
            if (count > 1)
              Positioned(
                right: 6,
                top: 6,
                child: _CountBadge(count: count),
              ),
          ],
        ),
      );
    }

    final (icon, label) = switch (preview) {
      final p when p.isPdf => (Icons.picture_as_pdf_outlined, 'PDF'),
      final p when p.isVideo => (Icons.videocam_outlined, 'Video'),
      final p when p.isAudio => (Icons.audiotrack_outlined, 'Audio'),
      final p when p.isImage => (Icons.image_outlined, 'Image'),
      _ => (Icons.insert_drive_file_outlined, 'File'),
    };
    return _FileChip(
      icon: icon,
      label: preview.fileName.isEmpty ? label : preview.fileName,
      count: count,
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.icon, required this.label, required this.count});

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: palette.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.textPrimary),
            ),
          ),
          if (count > 1) _CountBadge(count: count),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file, size: 11, color: palette.textSecondary),
          const SizedBox(width: 2),
          Text('$count',
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: palette.textSecondary)),
        ],
      ),
    );
  }
}

/// A link found in the task text. Shows a thumbnail when one is derivable
/// from the URL, and the domain alone otherwise.
class _LinkPreviewTile extends StatelessWidget {
  const _LinkPreviewTile({required this.link});
  final LinkPreview link;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (link.hasThumbnail)
            CachedNetworkImage(
              imageUrl: link.thumbnailUrl!,
              height: 96,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: (context, _) => Container(height: 96, color: palette.surfaceSunken),
              // Falling back to the domain row below is the documented
              // behaviour when a preview cannot be produced.
              errorWidget: (context, _, _) => const SizedBox.shrink(),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(Icons.link, size: 14, color: palette.textSecondary),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (link.siteName != null)
                        Text(link.siteName!,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            )),
                      Text(
                        link.domain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = <Widget>[];

    if (task.priority != TaskPriority.none) {
      final color = switch (task.priority) {
        TaskPriority.high => palette.danger,
        TaskPriority.medium => palette.warning,
        _ => palette.textSecondary,
      };
      items.add(_Meta(icon: Icons.flag_outlined, label: task.priority.label, color: color));
    }
    // Schedule and reminders are shown on the card, so a board task reads the
    // same way whether you meet it here or on the calendar.
    if (task.startDateTime != null) {
      items.add(_Meta(
        icon: Icons.calendar_today_outlined,
        label: DateFormat('MMM d').format(task.startDateTime!),
      ));

      if (task.isAllDay) {
        items.add(const _Meta(icon: Icons.schedule, label: 'All day'));
      } else {
        final start = DateFormat('h:mm a').format(task.startDateTime!);
        final end = task.endDateTime == null
            ? null
            : DateFormat('h:mm a').format(task.endDateTime!);
        items.add(_Meta(
          icon: Icons.schedule,
          label: end == null ? start : '$start – $end',
        ));
      }
    }

    final reminders = task.effectiveReminders.where((r) => r.enabled).toList();
    if (reminders.isNotEmpty) {
      items.add(_Meta(
        icon: Icons.notifications_none,
        label: reminders.length == 1
            ? reminders.single.label
            : '${reminders.length} reminders',
      ));
    }
    if (task.subtasks.isNotEmpty) {
      items.add(_Meta(
        icon: Icons.checklist,
        label: '${task.doneSubtasks}/${task.subtasks.length} subtasks',
      ));
    }
    // Real uploads keep a count on the task; the legacy string list is the
    // fallback for documents written before attachments were real files.
    final attachmentCount =
        task.attachmentCount > 0 ? task.attachmentCount : task.attachments.length;
    if (attachmentCount > 0) {
      items.add(_Meta(icon: Icons.attach_file, label: '$attachmentCount'));
    }

    return Wrap(spacing: 12, runSpacing: 5, children: items);
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.textSecondary;
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

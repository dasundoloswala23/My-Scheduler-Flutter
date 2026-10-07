import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/notifications/models/notification_preferences.dart';
import '../../core/notifications/platform/local_notification_adapter.dart';
import '../../core/notifications/scheduling/reminder_calculator.dart';
import '../../core/position.dart';
import '../../core/providers.dart';
import '../../core/notifications/models/reminder.dart' as task_reminder;
import '../../models/collections.dart';
import '../../models/task.dart';

enum QuickAddKind { task, note, reminder, event }

Future<void> showQuickAddSheet(
  BuildContext context, {
  String? listId,
  String? boardId,
  DateTime? date,
  QuickAddKind kind = QuickAddKind.task,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => QuickAddSheet(listId: listId, boardId: boardId, date: date, initialKind: kind),
  );
}

/// "Create something" from screenshots 16–19: a segmented type picker, a title,
/// then category, date, time and reminder rows.
class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({
    super.key,
    this.listId,
    this.boardId,
    this.date,
    this.initialKind = QuickAddKind.task,
  });

  final String? listId;
  final String? boardId;
  final DateTime? date;
  final QuickAddKind initialKind;

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  late QuickAddKind _kind = widget.initialKind;
  final _title = TextEditingController();
  String? _categoryId;
  late DateTime _date = widget.date ?? DateTime.now();
  TimeOfDay? _time;
  int? _reminderMinutes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Start from the user's default category, if they set one and it still
    // exists. They can still change it before saving.
    final defaultCategoryId = ref.read(appPreferencesProvider).defaultCategoryId;
    if (defaultCategoryId != null) _categoryId = defaultCategoryId;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _noun => switch (_kind) {
        QuickAddKind.task => 'Task',
        QuickAddKind.note => 'Note',
        QuickAddKind.reminder => 'Reminder',
        QuickAddKind.event => 'Event',
      };

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _busy = true);

    final repo = ref.read(repoProvider);
    final when = _time == null
        ? null
        : DateTime(_date.year, _date.month, _date.day, _time!.hour, _time!.minute);

    try {
      switch (_kind) {
        case QuickAddKind.task:
        case QuickAddKind.event:
          final tasks = ref.read(tasksProvider).value ?? const <Task>[];
          final siblings = widget.listId == null ? <Task>[] : tasksForList(tasks, widget.listId!);
          await repo.createTask(Task(
            id: 'new',
            title: title,
            listId: widget.listId,
            boardId: widget.boardId,
            categoryId: _categoryId,
            priority: ref.read(appPreferencesProvider).defaultPriority,
            position: Position.between(siblings.lastOrNull?.position, null),
            startDateTime: when,
            endDateTime: when?.add(const Duration(hours: 1)),
            // createTask schedules the reminders itself, so the sheet only has
            // to say which ones the task should have.
            reminders: _reminderMinutes == null
                ? const []
                : [
                    task_reminder.Reminder(
                      id: const Uuid().v4(),
                      taskId: 'new',
                      type: _reminderMinutes == 0
                          ? task_reminder.ReminderType.atTime
                          : task_reminder.ReminderType.beforeTask,
                      offsetMinutes: _reminderMinutes!,
                      createdAt: DateTime.now(),
                    ),
                  ],
          ));
        case QuickAddKind.note:
          await repo.addNote(Note(id: 'new', title: title, categoryId: _categoryId));
        case QuickAddKind.reminder:
          final remindAt = when ?? DateTime(_date.year, _date.month, _date.day, 9);
          final id = await repo.addReminder(Reminder(
            id: 'new',
            title: title,
            remindAt: remindAt,
            notificationId: remindAt.millisecondsSinceEpoch ~/ 1000,
          ));
          // A standalone reminder is not attached to a task, so it is
          // scheduled directly rather than through the task scheduler.
          await LocalNotificationAdapter().schedule(
            PlannedNotification(
              notificationId: remindAt.millisecondsSinceEpoch ~/ 1000,
              reminderId: id,
              taskId: '',
              title: title,
              body: 'Reminder',
              fireAt: remindAt,
              style: NotificationStyle.normal,
            ),
            const NotificationPreferences(),
          );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save. $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final categoryName =
        categories.where((c) => c.id == _categoryId).firstOrNull?.name ?? 'Inbox';
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('QUICK ADD',
                              style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: context.palette.textSecondary)),
                          Text('Create something',
                              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    for (final k in QuickAddKind.values) ...[
                      Expanded(
                        child: _KindButton(
                          kind: k,
                          selected: k == _kind,
                          onTap: () => setState(() => _kind = k),
                        ),
                      ),
                      if (k != QuickAddKind.values.last) const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WHAT DO YOU NEED TO DO?',
                        style: TextStyle(fontSize: 10, letterSpacing: 1, color: context.palette.textSecondary)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _title,
                      autofocus: true,
                      decoration: InputDecoration(hintText: 'New ${_noun.toLowerCase()} title'),
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                ),
              ),
              _Row(
                icon: Icons.label_outline,
                label: 'Category',
                value: categoryName,
                onTap: () async {
                  final chosen = await showModalBottomSheet<Category>(
                    context: context,
                    builder: (c) => SafeArea(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final cat in categories)
                            ListTile(
                              leading: Icon(Icons.circle, size: 12, color: Color(cat.colorValue)),
                              title: Text(cat.name),
                              onTap: () => Navigator.pop(c, cat),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (chosen != null) setState(() => _categoryId = chosen.id);
                },
              ),
              _Row(
                icon: Icons.calendar_today_outlined,
                label: 'Date',
                value: DateFormat('MMM d, y').format(_date),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              _Row(
                icon: Icons.schedule,
                label: 'Time',
                value: _time == null ? 'No time' : _time!.format(context),
                onTap: () async {
                  final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                  if (picked != null) setState(() => _time = picked);
                },
              ),
              _Row(
                icon: Icons.notifications_none,
                label: 'Reminder',
                value: _reminderMinutes == null ? 'None' : '$_reminderMinutes min before',
                onTap: () async {
                  final picked = await showModalBottomSheet<int?>(
                    context: context,
                    builder: (c) => SafeArea(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          ListTile(title: const Text('None'), onTap: () => Navigator.pop(c, null)),
                          for (final m in [5, 10, 15, 30, 60])
                            ListTile(title: Text('$m minutes before'), onTap: () => Navigator.pop(c, m)),
                        ],
                      ),
                    ),
                  );
                  setState(() => _reminderMinutes = picked);
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.add),
                  label: Text('Add $_noun'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({required this.kind, required this.selected, required this.onTap});

  final QuickAddKind kind;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (kind) {
        QuickAddKind.task => Icons.check,
        QuickAddKind.note => Icons.sticky_note_2_outlined,
        QuickAddKind.reminder => Icons.notifications_none,
        QuickAddKind.event => Icons.calendar_today_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final label = kind.name[0].toUpperCase() + kind.name.substring(1);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? context.palette.selected : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          border: selected ? Border.all(color: AppColors.primary, width: 1.4) : null,
        ),
        child: Column(
          children: [
            Icon(_icon, size: 20, color: selected ? AppColors.primary : context.palette.textSecondary),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.primary : context.palette.textSecondary,
                )),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value, required this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 20, color: context.palette.textSecondary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(value, style: TextStyle(color: context.palette.textSecondary, fontSize: 12.5)),
      trailing: Icon(Icons.chevron_right, size: 20, color: context.palette.textSecondary),
    );
  }
}

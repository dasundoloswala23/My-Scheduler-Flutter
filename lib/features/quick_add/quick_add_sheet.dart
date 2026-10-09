import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/flows/flow_providers.dart';
import '../../core/notifications/models/notification_preferences.dart';
import '../../core/notifications/models/reminder.dart' as task_reminder;
import '../../core/notifications/models/reminder_sound.dart';
import '../../core/notifications/platform/local_notification_adapter.dart';
import '../../core/notifications/scheduling/reminder_calculator.dart';
import '../../core/position.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/project_flow.dart';
import '../../models/task.dart';
import '../task_detail/reminder_alert_options.dart';
import '../task_detail/reminder_picker.dart';
import 'quick_add_logic.dart';

enum QuickAddKind { task, note, reminder, event }

/// Opens Quick Add as a modal sheet.
///
/// `useSafeArea` keeps the sheet clear of the status bar and notch, and
/// `isScrollControlled` lets it use the full height. The sheet itself handles
/// the keyboard: the header and the Save button stay pinned and only the middle
/// scrolls, so neither can be pushed off screen.
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
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => QuickAddSheet(listId: listId, boardId: boardId, date: date, initialKind: kind),
  );
}

class _PendingFile {
  _PendingFile({required this.name, this.file, this.bytes});
  final String name;
  final File? file;
  final Uint8List? bytes;
}

/// Create a task, note, reminder or event.
///
/// Everything is saved in one operation: the task, its schedule, its reminders,
/// its subtasks and its attachments all belong to the single task record that
/// the Board and the Calendar both read. Nothing is created twice.
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
  final _notes = TextEditingController();
  final _url = TextEditingController();
  final _subtask = TextEditingController();

  /// Checked and set synchronously, so a double tap cannot create two tasks.
  final _guard = SubmitGuard();
  bool _busy = false;

  String? _categoryId;
  String? _boardId;
  String? _listId;

  late DateTime _date = widget.date ?? DateTime.now();

  /// True once the user has picked a date (or Quick Add was opened from a
  /// specific day). A date that merely defaulted to today must not turn every
  /// task into an all-day task.
  late bool _dateChosen = widget.date != null;

  TimeOfDay? _time;
  int _durationMinutes = kDefaultDurationMinutes;
  TaskPriority? _priority;
  Recurrence _recurrence = Recurrence.none;

  /// The Project Flow stage this task will be linked to, if the user picked one.
  FlowStage? _flowStage;
  String? _flowName;

  final List<task_reminder.Reminder> _reminders = [];
  bool _defaultReminderApplied = false;

  final List<String> _subtasks = [];
  final List<_PendingFile> _files = [];

  // Alert settings for a stand-alone reminder, which has no reminder list.
  task_reminder.AlertMode? _alertMode;
  String? _soundId;
  bool? _vibrate;

  @override
  void initState() {
    super.initState();
    _boardId = widget.boardId;
    _listId = widget.listId;
    // Start from the user's default category, if they set one.
    _categoryId = ref.read(appPreferencesProvider).defaultCategoryId;
    // The Save button and its message depend on these, so rebuild as they change.
    _title.addListener(_changed);
    _url.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _url.dispose();
    _subtask.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------- derived

  bool get _isTaskLike => _kind == QuickAddKind.task || _kind == QuickAddKind.event;

  NotificationPreferences get _notificationPrefs =>
      ref.read(notificationPreferencesProvider).value ?? const NotificationPreferences();

  QuickAddSchedule get _schedule =>
      scheduleFor(date: _date, dateChosen: _dateChosen, time: _time);

  QuickAddValidation get _validation => validateQuickAdd(
        title: _title.text,
        url: _url.text,
        // Reminders count from a clock time, so only a chosen time counts here.
        start: combineDateAndTime(_date, _time),
        durationMinutes: _durationMinutes,
        reminderCount: _isTaskLike ? _reminders.length : 0,
        now: DateTime.now(),
      );

  String get _noun => switch (_kind) {
        QuickAddKind.task => 'Task',
        QuickAddKind.note => 'Note',
        QuickAddKind.reminder => 'Reminder',
        QuickAddKind.event => 'Event',
      };

  // ------------------------------------------------------------------- actions

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _dateChosen = true;
      });
    }
  }

  Future<void> _pickTime() async {
    // A native picker that follows the device's 12 or 24 hour setting and
    // locale. It opens on the next full hour rather than the current minute.
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? defaultTimeAfter(DateTime.now()),
    );
    if (picked == null) return;
    setState(() {
      _time = picked;
      _applyDefaultReminder();
    });
  }

  /// The first time a time is chosen, add the user's default reminder, once. It
  /// shows in the list and can be removed, so it is a head start, not a surprise.
  void _applyDefaultReminder() {
    if (_defaultReminderApplied || !_isTaskLike || _reminders.isNotEmpty) return;
    final prefs = _notificationPrefs;
    final minutes = prefs.defaultReminderMinutes;
    _defaultReminderApplied = true;
    if (minutes == null) return;
    _reminders.add(task_reminder.Reminder(
      id: const Uuid().v4(),
      taskId: 'new',
      type: minutes == 0
          ? task_reminder.ReminderType.atTime
          : task_reminder.ReminderType.beforeTask,
      offsetMinutes: minutes,
      alertMode: prefs.defaultAlertMode,
      createdAt: DateTime.now(),
    ));
  }

  Future<void> _pickFlowStage() async {
    final flows = (ref.read(flowsProvider).value ?? const <ProjectFlow>[])
        .where((f) => f.status == FlowStatus.active || f.status == FlowStatus.paused)
        .toList();
    final stages = ref.read(flowStagesProvider).value ?? const <FlowStage>[];

    final chosen = await showModalBottomSheet<(FlowStage?, String?)>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('None'),
              onTap: () => Navigator.pop(c, (null, null)),
            ),
            for (final f in flows) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              for (final s in stages.where((s) => s.flowId == f.id))
                ListTile(
                  dense: true,
                  title: Text(s.title),
                  onTap: () => Navigator.pop(c, (s, f.name)),
                ),
            ],
          ],
        ),
      ),
    );
    if (chosen != null) {
      setState(() {
        _flowStage = chosen.$1;
        _flowName = chosen.$2;
      });
    }
  }

  Future<void> _pickRecurrence() async {
    final chosen = await showModalBottomSheet<Recurrence>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in Recurrence.values)
              ListTile(
                title: Text(r.label),
                trailing: r == _recurrence ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(c, r),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => _recurrence = chosen);
  }

  Future<void> _pickDuration() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in kDurationPresets)
              ListTile(
                title: Text(describeDuration(m)),
                trailing: m == _durationMinutes ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(c, m),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Custom…'),
              onTap: () async {
                final custom = await _askCustomDuration(c);
                if (c.mounted && custom != null) Navigator.pop(c, custom);
              },
            ),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => _durationMinutes = chosen);
  }

  Future<int?> _askCustomDuration(BuildContext sheetContext) {
    final controller = TextEditingController(text: '$_durationMinutes');
    return showDialog<int>(
      context: sheetContext,
      builder: (c) => AlertDialog(
        title: const Text('Duration in minutes'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'minutes'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(c, v != null && v >= 1 ? v : null);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _pickList() async {
    final boards = ref.read(boardsProvider).value ?? const <Board>[];
    final lists = ref.read(listsProvider).value ?? const <TaskList>[];

    final chosen = await showModalBottomSheet<(String?, String?)>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Inbox'),
              subtitle: const Text('Not on a board yet'),
              onTap: () => Navigator.pop(c, (null, null)),
            ),
            for (final board in boards) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(board.name.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                        color: context.palette.textSecondary)),
              ),
              for (final list in lists.where((l) => l.boardId == board.id))
                ListTile(
                  leading: Icon(Icons.circle, size: 12, color: Color(list.colorValue)),
                  title: Text(list.name),
                  onTap: () => Navigator.pop(c, (board.id, list.id)),
                ),
            ],
          ],
        ),
      ),
    );
    if (chosen != null) {
      setState(() {
        _boardId = chosen.$1;
        _listId = chosen.$2;
      });
    }
  }

  Future<void> _addReminder() async {
    // Permission is asked for here, when the first reminder is added, with an
    // explanation, rather than at launch.
    if (_reminders.isEmpty && !await ensureNotificationPermission(context)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reminders are saved, but will not appear until notifications '
                'are allowed. ${notificationSettingsHint()}'),
          ),
        );
      }
    }
    if (!mounted) return;
    final prefs = _notificationPrefs;
    final added = await showReminderEditor(
      context,
      taskId: 'new',
      defaultVibrate: prefs.vibration != VibrationPattern.none,
      defaultMode: prefs.defaultAlertMode,
    );
    if (added != null) setState(() => _reminders.add(added));
  }

  Future<void> _editReminder(task_reminder.Reminder existing) async {
    final prefs = _notificationPrefs;
    final edited = await showReminderEditor(
      context,
      taskId: 'new',
      existing: existing,
      defaultVibrate: prefs.vibration != VibrationPattern.none,
      defaultMode: prefs.defaultAlertMode,
    );
    if (edited == null) return;
    setState(() {
      final i = _reminders.indexWhere((r) => r.id == existing.id);
      if (i >= 0) _reminders[i] = edited;
    });
  }

  Future<void> _pickFiles() async {
    final picked = await FilePicker.pickFiles();
    for (final f in picked) {
      final path = f.path;
      _files.add(_PendingFile(
        name: f.name,
        // A path lets Storage stream from disk; the web has none, so read bytes.
        file: path == null ? null : File(path),
        bytes: path == null ? await f.readAsBytes() : null,
      ));
    }
    if (mounted) setState(() {});
  }

  void _addSubtask() {
    final text = _subtask.text.trim();
    if (text.isEmpty) return;
    setState(() => _subtasks.add(text));
    _subtask.clear();
  }

  // -------------------------------------------------------------------- submit

  Future<void> _submit() async {
    final validation = _validation;
    if (!validation.canSave) return;

    // Captured before any await: the sheet closes, and the confirmation has to
    // appear on the screen underneath it.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // A trailing subtask typed but not yet added is still the user's intent.
    _addSubtask();

    await _guard.run(() async {
      if (mounted) setState(() => _busy = true);
      var failedUploads = 0;
      String summary;

      try {
        final repo = ref.read(repoProvider);
        final title = _title.text.trim();
        final url = normalizeUrl(_url.text);
        final description = composeDescription(notes: _notes.text, url: url);

        switch (_kind) {
          case QuickAddKind.task:
          case QuickAddKind.event:
            final schedule = _schedule;
            final tasks = ref.read(tasksProvider).value ?? const <Task>[];
            final siblings = _listId == null ? <Task>[] : tasksForList(tasks, _listId!);

            final id = await repo.createTask(Task(
              id: 'new',
              title: title,
              description: description,
              listId: _listId,
              boardId: _boardId,
              categoryId: _categoryId,
              priority: _priority ?? ref.read(appPreferencesProvider).defaultPriority,
              position: Position.between(siblings.lastOrNull?.position, null),
              startDateTime: schedule.start,
              endDateTime: schedule.isAllDay ? null : endFor(schedule.start, _durationMinutes),
              isAllDay: schedule.isAllDay,
              // A repeat needs a date to repeat from; without one it is ignored.
              recurrence: schedule.isScheduled ? _recurrence : Recurrence.none,
              subtasks: [
                for (final (i, text) in _subtasks.indexed)
                  Subtask(id: const Uuid().v4(), title: text, position: i.toDouble()),
              ],
              // createTask re-keys these to the new task and schedules them.
              reminders: List.of(_reminders),
            ));

            // A flow link needs the task to exist too. A failed link must not undo
            // the task, which is already saved.
            final stage = _flowStage;
            if (stage != null) {
              try {
                await repo.flows
                    .linkTask(flowId: stage.flowId, stageId: stage.id, taskId: id);
              } catch (e) {
                debugPrint('Could not link new task to its flow: $e');
              }
            }

            // Attachments need the task to exist, so they follow it. A failed
            // upload must not undo the task, so each is tried on its own.
            for (final f in _files) {
              try {
                await ref.read(attachmentServiceProvider).upload(
                      taskId: id,
                      originalFileName: f.name,
                      file: f.file,
                      bytes: f.bytes,
                    );
              } catch (_) {
                failedUploads++;
              }
            }
            summary = schedule.start == null
                ? 'Added "$title"'
                : schedule.isAllDay
                    ? 'Added "$title" · ${DateFormat('MMM d').format(schedule.start!)}'
                    : 'Added "$title" · ${DateFormat('MMM d, h:mm a').format(schedule.start!)}';

          case QuickAddKind.note:
            await repo.addNote(Note(
              id: 'new',
              title: title,
              body: description,
              categoryId: _categoryId,
            ));
            summary = 'Note added';

          case QuickAddKind.reminder:
            final remindAt = combineDateAndTime(_date, _time) ??
                DateTime(_date.year, _date.month, _date.day, 9);
            final prefs = _notificationPrefs;
            final mode = _alertMode ?? prefs.defaultAlertMode;
            final reminderId = await repo.addReminder(Reminder(
              id: 'new',
              title: title,
              remindAt: remindAt,
              notificationId: remindAt.millisecondsSinceEpoch ~/ 1000,
            ));
            // A stand-alone reminder is not attached to a task, so it is
            // scheduled directly. One already in the past would be rejected.
            if (remindAt.isAfter(DateTime.now())) {
              await LocalNotificationAdapter().schedule(
                PlannedNotification(
                  notificationId: remindAt.millisecondsSinceEpoch ~/ 1000,
                  reminderId: reminderId,
                  taskId: '',
                  title: title,
                  body: 'Reminder',
                  fireAt: remindAt,
                  style: prefs.style,
                  alertMode: prefs.alarmsEnabled ? mode : task_reminder.AlertMode.notification,
                  soundId: _soundId,
                  vibrate: _vibrate ?? prefs.vibration != VibrationPattern.none,
                ),
                prefs,
              );
            }
            summary = 'Reminder set for ${DateFormat('MMM d, h:mm a').format(remindAt)}';
        }

        if (failedUploads > 0) {
          summary = '$summary. $failedUploads attachment${failedUploads == 1 ? '' : 's'} '
              'could not be uploaded; add ${failedUploads == 1 ? 'it' : 'them'} from the task.';
        }

        navigator.pop();
        messenger.showSnackBar(SnackBar(content: Text(summary)));
      } catch (e) {
        if (mounted) {
          setState(() => _busy = false);
          messenger.showSnackBar(SnackBar(content: Text('Could not save. $e')));
        }
      }
    });
  }

  // --------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;

    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final boards = ref.watch(boardsProvider).value ?? const <Board>[];
    final lists = ref.watch(listsProvider).value ?? const <TaskList>[];

    final categoryName =
        categories.where((c) => c.id == _categoryId).firstOrNull?.name ?? 'None';
    final list = lists.where((l) => l.id == _listId).firstOrNull;
    final board = boards.where((b) => b.id == (list?.boardId ?? _boardId)).firstOrNull;
    final listName = list == null
        ? (board?.name ?? 'Inbox')
        : (board == null ? list.name : '${board.name} · ${list.name}');

    final validation = _validation;
    final timeLabel = _time == null ? 'No time' : _time!.format(context);

    return Padding(
      // Lifts the whole sheet above the keyboard.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      // A Material, not a coloured DecoratedBox: ListTile paints its tap ripple
      // on the nearest Material, and a DecoratedBox in between hides it, which
      // left every row in the form with no visible tap feedback.
      child: Material(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----- pinned header
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration:
                    BoxDecoration(color: palette.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('New ${_noun.toLowerCase()}',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // ----- scrolling body
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
                            if (k != QuickAddKind.values.last) const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: TextField(
                        controller: _title,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(hintText: '$_noun title'),
                        // Done on the keyboard saves. The guard makes a stray
                        // double press harmless.
                        onSubmitted: (_) => _submit(),
                      ),
                    ),

                    if (_isTaskLike || _kind == QuickAddKind.reminder) ...[
                      const _SectionHeader('Schedule'),
                      _Row(
                        icon: Icons.calendar_today_outlined,
                        label: 'Date',
                        value: _dateChosen || _time != null
                            ? DateFormat('EEE, MMM d, y').format(_date)
                            : 'Not set',
                        onTap: _pickDate,
                      ),
                      _Row(
                        icon: Icons.schedule,
                        label: 'Time',
                        value: timeLabel,
                        onTap: _pickTime,
                        trailing: _time == null
                            ? null
                            : IconButton(
                                tooltip: 'Clear time',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() => _time = null),
                              ),
                      ),
                      if (_isTaskLike && _time != null)
                        _Row(
                          icon: Icons.timelapse,
                          label: 'Duration',
                          value: describeDuration(_durationMinutes),
                          onTap: _pickDuration,
                        ),
                      if (_isTaskLike && (_time != null || _dateChosen))
                        _Row(
                          icon: Icons.repeat,
                          label: 'Repeat',
                          value: _recurrence.label,
                          onTap: _pickRecurrence,
                        ),
                      if (_time != null && validation.startsInPast)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            'That time has already passed, so its reminders will not fire.',
                            style: TextStyle(fontSize: 12, color: palette.warning),
                          ),
                        ),
                    ],

                    if (_isTaskLike) ...[
                      const _SectionHeader('Organise'),
                      _Row(
                        icon: Icons.view_week_outlined,
                        label: 'List',
                        value: listName,
                        onTap: _pickList,
                      ),
                      _Row(
                        icon: Icons.label_outline,
                        label: 'Category',
                        value: categoryName,
                        onTap: () async {
                          final chosen = await showModalBottomSheet<Category?>(
                            context: context,
                            builder: (c) => SafeArea(
                              child: ListView(
                                shrinkWrap: true,
                                children: [
                                  ListTile(
                                    title: const Text('None'),
                                    onTap: () => Navigator.pop(c, null),
                                  ),
                                  for (final cat in categories)
                                    ListTile(
                                      leading: Icon(Icons.circle,
                                          size: 12, color: Color(cat.colorValue)),
                                      title: Text(cat.name),
                                      onTap: () => Navigator.pop(c, cat),
                                    ),
                                ],
                              ),
                            ),
                          );
                          setState(() => _categoryId = chosen?.id);
                        },
                      ),
                      // Both are watched so the stages are loaded by the time the
                      // picker opens, not read cold when it does.
                      if ((ref.watch(flowsProvider).value ?? const <ProjectFlow>[]).isNotEmpty &&
                          ref.watch(flowStagesProvider).hasValue)
                        _Row(
                          icon: Icons.rocket_launch_outlined,
                          label: 'Project Flow',
                          value: _flowStage == null ? 'None' : '$_flowName · ${_flowStage!.title}',
                          onTap: _pickFlowStage,
                        ),
                      _Row(
                        icon: Icons.flag_outlined,
                        label: 'Priority',
                        value: (_priority ?? ref.read(appPreferencesProvider).defaultPriority).label,
                        onTap: () async {
                          final chosen = await showModalBottomSheet<TaskPriority>(
                            context: context,
                            builder: (c) => SafeArea(
                              child: ListView(
                                shrinkWrap: true,
                                children: [
                                  for (final p in TaskPriority.values)
                                    ListTile(
                                      title: Text(p.label),
                                      onTap: () => Navigator.pop(c, p),
                                    ),
                                ],
                              ),
                            ),
                          );
                          if (chosen != null) setState(() => _priority = chosen);
                        },
                      ),

                      const _SectionHeader('Reminders'),
                      for (final r in _reminders)
                        _ReminderTile(
                          reminder: r,
                          onTap: () => _editReminder(r),
                          onDelete: () => setState(() => _reminders.removeWhere((x) => x.id == r.id)),
                        ),
                      _Row(
                        icon: Icons.add_alert_outlined,
                        label: _reminders.isEmpty ? 'Add a reminder' : 'Add another reminder',
                        value: _time == null
                            ? 'Pick a time first'
                            : 'Notification or alarm, with a sound',
                        onTap: _time == null ? null : _addReminder,
                      ),
                    ],

                    if (_kind == QuickAddKind.reminder) ...[
                      const _SectionHeader('Alert'),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: ReminderAlertOptions(
                          mode: _alertMode ?? _notificationPrefs.defaultAlertMode,
                          soundId: _soundId,
                          vibrate: _vibrate,
                          defaultVibrate:
                              _notificationPrefs.vibration != VibrationPattern.none,
                          onChanged: (mode, sound, vibrate) => setState(() {
                            _alertMode = mode;
                            _soundId = sound;
                            _vibrate = vibrate;
                          }),
                        ),
                      ),
                    ],

                    if (_kind == QuickAddKind.note)
                      _Row(
                        icon: Icons.label_outline,
                        label: 'Category',
                        value: categoryName,
                        onTap: () async {
                          final chosen = await showModalBottomSheet<Category?>(
                            context: context,
                            builder: (c) => SafeArea(
                              child: ListView(
                                shrinkWrap: true,
                                children: [
                                  ListTile(
                                    title: const Text('None'),
                                    onTap: () => Navigator.pop(c, null),
                                  ),
                                  for (final cat in categories)
                                    ListTile(
                                      title: Text(cat.name),
                                      onTap: () => Navigator.pop(c, cat),
                                    ),
                                ],
                              ),
                            ),
                          );
                          setState(() => _categoryId = chosen?.id);
                        },
                      ),

                    if (_kind != QuickAddKind.reminder) ...[
                      const _SectionHeader('Details'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Notes',
                            prefixIcon: Icon(Icons.notes, size: 20),
                          ),
                        ),
                      ),
                    ],

                    if (_isTaskLike) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: TextField(
                          controller: _url,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: InputDecoration(
                            hintText: 'Link (optional)',
                            prefixIcon: const Icon(Icons.link, size: 20),
                            errorText: validation.problem == QuickAddProblem.invalidUrl
                                ? QuickAddProblem.invalidUrl.message
                                : null,
                          ),
                        ),
                      ),
                      for (final (i, text) in _subtasks.indexed)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.check_box_outline_blank, size: 20),
                          title: Text(text),
                          trailing: IconButton(
                            tooltip: 'Remove subtask',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _subtasks.removeAt(i)),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _subtask,
                                textCapitalization: TextCapitalization.sentences,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  hintText: 'Add a subtask',
                                  prefixIcon: Icon(Icons.checklist, size: 20),
                                ),
                                onSubmitted: (_) => _addSubtask(),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Add subtask',
                              icon: const Icon(Icons.add_circle_outline),
                              color: AppColors.primary,
                              onPressed: _addSubtask,
                            ),
                          ],
                        ),
                      ),
                      for (final (i, f) in _files.indexed)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.attach_file, size: 20),
                          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: 'Remove attachment',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _files.removeAt(i)),
                          ),
                        ),
                      _Row(
                        icon: Icons.attach_file,
                        label: 'Attach a file',
                        value: 'Uploaded when you save',
                        onTap: _pickFiles,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ----- pinned footer: always reachable, whatever the keyboard does
            Container(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: palette.divider)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                10,
                20,
                // Clear the home indicator or gesture bar, but only when the
                // keyboard is closed: with it open the keyboard already sits
                // below this, and the extra padding would waste scarce room.
                12 + (keyboardOpen ? 0 : media.padding.bottom),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (validation.problem != null &&
                      validation.problem != QuickAddProblem.invalidUrl)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        validation.problem!.message,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: validation.problem == QuickAddProblem.emptyTitle
                              ? palette.textSecondary
                              : palette.danger,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: (_busy || !validation.canSave) ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.2, color: Colors.white),
                                )
                              : Text('Save $_noun'),
                        ),
                      ),
                    ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: context.palette.textSecondary,
          ),
        ),
      );
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.onTap, required this.onDelete});

  final task_reminder.Reminder reminder;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final alarm = reminder.alertMode == task_reminder.AlertMode.alarm;
    final sound = ReminderSounds.labelFor(
        reminder.soundId ?? ReminderSounds.defaultFor(reminder.alertMode));
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 10,
      leading: Icon(alarm ? Icons.alarm : Icons.notifications_active_outlined,
          size: 20, color: context.palette.accent),
      title: Text(reminder.label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text('${reminder.alertMode.label} · $sound',
          style: TextStyle(color: context.palette.textSecondary, fontSize: 12.5)),
      trailing: IconButton(
        tooltip: 'Remove reminder',
        icon: const Icon(Icons.close, size: 18),
        onPressed: onDelete,
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
        // Tall enough for a comfortable touch target.
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? context.palette.selected : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          border: selected ? Border.all(color: AppColors.primary, width: 1.4) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_icon,
                size: 20,
                color: selected ? context.palette.accent : context.palette.textSecondary),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? context.palette.accent : context.palette.textSecondary,
                )),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      enabled: onTap != null,
      minVerticalPadding: 10,
      leading: Icon(icon, size: 20, color: context.palette.textSecondary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(value, style: TextStyle(color: context.palette.textSecondary, fontSize: 12.5)),
      trailing: trailing ??
          Icon(Icons.chevron_right, size: 20, color: context.palette.textSecondary),
    );
  }
}

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/notifications.dart';
import '../../core/reminder_scheduler.dart';

/// Lets the user pick any number of reminders for a task, including a custom
/// offset. Permission is requested here, at the moment the first reminder is
/// added, rather than on app launch.
Future<List<int>?> showReminderPicker(
  BuildContext context, {
  required List<int> selected,
}) {
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ReminderSheet(initial: selected),
  );
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({required this.initial});
  final List<int> initial;

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late final Set<int> _selected = {...widget.initial};
  bool _permissionDenied = false;

  Future<void> _toggle(int minutes, bool on) async {
    if (on && _selected.isEmpty) {
      // First reminder on this task: explain, then ask the OS.
      final granted = await _ensurePermission();
      if (!granted) {
        setState(() => _permissionDenied = true);
        return;
      }
    }
    setState(() => on ? _selected.add(minutes) : _selected.remove(minutes));
  }

  Future<bool> _ensurePermission() async {
    if (!Notifications.supported) return true;
    if (await Notifications.hasPermission()) return true;
    if (!mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow notifications?'),
        content: const Text(
          'My scheduler needs notification permission to alert you before a '
          'task starts. Without it, reminders are saved but never appear.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (proceed != true) return false;
    return Notifications.requestPermissions();
  }

  Future<void> _addCustom() async {
    final controller = TextEditingController();
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom reminder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Minutes before',
            helperText: 'For example 90 for an hour and a half',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (minutes != null && minutes >= 0) await _toggle(minutes, true);
  }

  @override
  Widget build(BuildContext context) {
    final custom = _selected
        .where((m) => !ReminderOffset.presets.any((p) => p.minutes == m))
        .toList()
      ..sort();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text('Reminders',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Pick as many as you like. They fire before the task starts.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ),
          if (_permissionDenied)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Notifications are turned off, so reminders will not appear. '
                'You can enable them in your device settings.',
                style: TextStyle(color: AppColors.danger, fontSize: 12.5),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final preset in ReminderOffset.presets)
                  CheckboxListTile(
                    dense: true,
                    value: _selected.contains(preset.minutes),
                    title: Text(preset.label),
                    onChanged: (on) => _toggle(preset.minutes, on ?? false),
                  ),
                for (final minutes in custom)
                  CheckboxListTile(
                    dense: true,
                    value: true,
                    title: Text(ReminderOffset.labelFor(minutes)),
                    onChanged: (on) => _toggle(minutes, on ?? false),
                  ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.add, size: 20),
                  title: const Text('Custom…'),
                  onTap: _addCustom,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _selected.toList()..sort()),
                    child: const Text('Save'),
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

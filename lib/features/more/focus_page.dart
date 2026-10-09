import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import 'more_page.dart';

/// Screenshot 33: a 25-minute Pomodoro timer that records each finished
/// session, which the statistics screen then totals.
class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage> {
  static const _sessionMinutes = 25;

  Timer? _ticker;
  int _remaining = _sessionMinutes * 60;
  bool _running = false;
  Task? _focusTask;
  DateTime? _startedAt;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    if (_running) return;
    setState(() {
      _running = true;
      _startedAt ??= DateTime.now();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _finish();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  void _stop() {
    _ticker?.cancel();
    setState(() {
      _running = false;
      _remaining = _sessionMinutes * 60;
      _startedAt = null;
    });
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    final started = _startedAt ?? DateTime.now();
    setState(() {
      _running = false;
      _remaining = _sessionMinutes * 60;
      _startedAt = null;
    });

    await ref.read(repoProvider).addFocusSession(FocusSession(
          id: 'new',
          startedAt: started,
          minutes: _sessionMinutes,
          taskId: _focusTask?.id,
          taskTitle: _focusTask?.title ?? 'Focus session',
        ));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Focus session complete. Nice work.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(focusSessionsProvider).value ?? const <FocusSession>[];
    final today = sessions.where((s) => _isToday(s.startedAt)).toList();
    final totalMinutes = today.fold<int>(0, (sum, s) => sum + s.minutes);
    final tasks = (ref.watch(tasksProvider).value ?? const <Task>[]).where((t) => !t.completed).toList();

    final minutes = (_remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remaining % 60).toString().padLeft(2, '0');

    return SubPage(
      eyebrow: 'My Scheduler App',
      title: 'Focus',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              child: Column(
                children: [
                  Text('FOCUS SESSION',
                      style: TextStyle(fontSize: 10, letterSpacing: 1.4, color: context.palette.accent)),
                  const SizedBox(height: 16),
                  Text('$minutes:$seconds',
                      style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300, letterSpacing: -2)),
                  const SizedBox(height: 10),
                  Text('Ready when you are. Remove distractions and make it count.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
                  const SizedBox(height: 20),
                  Card(
                    margin: EdgeInsets.zero,
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: ListTile(
                      leading: const Icon(Icons.circle_outlined, size: 20),
                      title: Text('FOCUSING ON',
                          style: TextStyle(fontSize: 9.5, letterSpacing: 1.1, color: context.palette.textSecondary)),
                      subtitle: Text(_focusTask?.title ?? 'Pick a task',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      trailing: PopupMenuButton<Task?>(
                        icon: const Icon(Icons.more_horiz),
                        onSelected: (t) => setState(() => _focusTask = t),
                        itemBuilder: (context) => [
                          const PopupMenuItem<Task?>(value: null, child: Text('No task')),
                          for (final t in tasks.take(20)) PopupMenuItem<Task?>(value: t, child: Text(t.title)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _stop,
                        icon: const Icon(Icons.close),
                        label: const Text('Stop'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _running ? _finish : _start,
                        icon: Icon(_running ? Icons.check : Icons.play_arrow),
                        label: Text(_running ? 'Finish' : 'Start focus'),
                        style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text("Today's sessions", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Text('${totalMinutes ~/ 60}h ${totalMinutes % 60}m',
                  style: TextStyle(fontWeight: FontWeight.w700, color: context.palette.accent)),
            ],
          ),
          const SizedBox(height: 10),
          if (today.isEmpty)
            Text('No sessions yet today.', style: TextStyle(color: context.palette.textSecondary, fontSize: 13))
          else
            for (final s in today)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(DateFormat('HH:mm').format(s.startedAt),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                title: Text(s.taskTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                trailing: Text('${s.minutes} min', style: TextStyle(color: context.palette.textSecondary, fontSize: 12.5)),
              ),
        ],
      ),
    );
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

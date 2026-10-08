import 'package:flutter/material.dart';

/// The rules behind the Quick Add form, kept free of widgets so they can be
/// tested directly: how a date and a time become a start, what a duration does
/// to the end, when the form may be saved, and what makes a link valid.

/// Durations offered as one-tap choices, in minutes.
const List<int> kDurationPresets = [15, 30, 45, 60, 90, 120];

/// The duration a task gets when the user does not pick one.
const int kDefaultDurationMinutes = 60;

/// "30 minutes", "1 hour", "90 minutes", "2 hours", "1 hour 15 min".
String describeDuration(int minutes) {
  if (minutes < 60) return minutes == 1 ? '1 minute' : '$minutes minutes';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  // 90 minutes reads better as "90 minutes" than "1 hour 30 min", so a clean
  // half hour is left in minutes like the preset chips.
  if (rest == 30 && hours == 1) return '90 minutes';
  final h = hours == 1 ? '1 hour' : '$hours hours';
  return rest == 0 ? h : '$h $rest min';
}

/// A start from a chosen date and time, or null when there is no time.
///
/// A task given a date but no time is not "at midnight": it simply has no
/// schedule, which is what keeps it off the calendar's time grid.
DateTime? combineDateAndTime(DateTime date, TimeOfDay? time) =>
    time == null ? null : DateTime(date.year, date.month, date.day, time.hour, time.minute);

/// The end of a task that starts at [start] and lasts [durationMinutes].
DateTime? endFor(DateTime? start, int durationMinutes) =>
    start?.add(Duration(minutes: durationMinutes));

/// The time the picker opens on: the next full hour after [now].
///
/// Opening on "now to the minute" makes the user scroll the dial to reach a
/// sensible time; the next hour is almost always closer to what they want.
TimeOfDay defaultTimeAfter(DateTime now) {
  final next = DateTime(now.year, now.month, now.day, now.hour + 1);
  return TimeOfDay(hour: next.hour, minute: 0);
}

/// Why the form cannot be saved yet.
enum QuickAddProblem { emptyTitle, remindersNeedTime, invalidUrl, invalidDuration }

extension QuickAddProblemX on QuickAddProblem {
  String get message => switch (this) {
        QuickAddProblem.emptyTitle => 'Add a title to save.',
        QuickAddProblem.remindersNeedTime =>
          'Pick a time first. Reminders are counted from when the task starts.',
        QuickAddProblem.invalidUrl => 'That link does not look right.',
        QuickAddProblem.invalidDuration => 'Duration must be at least 1 minute.',
      };
}

class QuickAddValidation {
  const QuickAddValidation({this.problem, this.startsInPast = false});

  /// Non-null blocks saving, and is shown in words rather than by silently
  /// disabling the button.
  final QuickAddProblem? problem;

  /// A start that has already passed. It is allowed, since logging something
  /// after the fact is legitimate, but the user is told its reminders will not
  /// fire.
  final bool startsInPast;

  bool get canSave => problem == null;
}

QuickAddValidation validateQuickAdd({
  required String title,
  required String url,
  required DateTime? start,
  required int durationMinutes,
  required int reminderCount,
  required DateTime now,
}) {
  if (title.trim().isEmpty) {
    return const QuickAddValidation(problem: QuickAddProblem.emptyTitle);
  }
  if (reminderCount > 0 && start == null) {
    return const QuickAddValidation(problem: QuickAddProblem.remindersNeedTime);
  }
  if (url.trim().isNotEmpty && normalizeUrl(url) == null) {
    return const QuickAddValidation(problem: QuickAddProblem.invalidUrl);
  }
  if (start != null && durationMinutes < 1) {
    return const QuickAddValidation(problem: QuickAddProblem.invalidDuration);
  }
  return QuickAddValidation(startsInPast: start != null && start.isBefore(now));
}

/// A tidy, absolute http(s) URL, or null if [raw] is not one.
///
/// People type `example.com`, so a missing scheme is added rather than
/// rejected. A bare word with no dot is not a link and is refused.
String? normalizeUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text) ? text : 'https://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty || !uri.host.contains('.')) return null;
  return withScheme;
}

/// The task description: the notes, with the link on its own line so the card
/// can pick it up and show a preview.
String composeDescription({required String notes, required String? url}) {
  final parts = [
    if (notes.trim().isNotEmpty) notes.trim(),
    if (url != null && url.isNotEmpty) url,
  ];
  return parts.join('\n\n');
}

/// Stops a second submission while one is running.
///
/// The check and the set happen in the same synchronous step. That matters: a
/// `setState` flag is only visible after the next frame, so two quick taps (or
/// Save plus the keyboard's Done key) can both read "not busy" and both save.
class SubmitGuard {
  bool _running = false;

  bool get isRunning => _running;

  /// Runs [action] unless one is already running. Returns false if skipped.
  Future<bool> run(Future<void> Function() action) async {
    if (_running) return false;
    _running = true;
    try {
      await action();
      return true;
    } finally {
      _running = false;
    }
  }
}

/// What the chosen date and time mean for the task.
class QuickAddSchedule {
  const QuickAddSchedule({this.start, this.isAllDay = false});

  /// Null means the task is unscheduled and stays off the calendar.
  final DateTime? start;

  /// A date with no time: it belongs on the calendar's all-day row.
  final bool isAllDay;

  bool get isScheduled => start != null;
}

/// Turns the form's date and time into a schedule.
///
/// - a time was chosen: a timed task at that moment;
/// - a date was chosen but no time: an all-day task on that date, rather than
///   quietly discarding the date the user picked;
/// - neither: unscheduled.
///
/// [dateChosen] distinguishes "the user picked Oct 8" from "the date field just
/// defaulted to today", which must not turn every task into an all-day one.
QuickAddSchedule scheduleFor({
  required DateTime date,
  required bool dateChosen,
  required TimeOfDay? time,
}) {
  if (time != null) return QuickAddSchedule(start: combineDateAndTime(date, time));
  if (dateChosen) {
    return QuickAddSchedule(start: DateTime(date.year, date.month, date.day), isAllDay: true);
  }
  return const QuickAddSchedule();
}

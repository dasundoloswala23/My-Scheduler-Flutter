import 'dart:math' as math;

import '../models/task.dart';

/// The date of the occurrence after [from], or null when the task does not
/// repeat.
///
/// This is the one place the repeat rules live. The repository uses it to create
/// the next occurrence when a task is completed, and the reminder calculator
/// uses it to schedule a rolling window of alerts; before they shared it there
/// were two copies that had to be kept identical by hand.
///
/// Dates are advanced by **calendar** arithmetic, never by adding hours:
///
///  - Adding `Duration(days: 1)` adds 24 hours, which lands an hour off across a
///    daylight-saving change, so a 9:00 daily task would become 8:00 or 10:00.
///    Building a new local `DateTime` from year, month and day keeps 9:00.
///  - Adding a month to 31 January must not become 3 March. The day is clamped
///    to the length of the target month, so 31 January becomes 28 (or 29) February.
///
/// Known limitation: a monthly task started on the 31st drifts once it has been
/// clamped (31 Jan, 28 Feb, 28 Mar), because only the current date is stored,
/// not the day the series started on.
DateTime? nextOccurrence(DateTime from, Recurrence r) {
  switch (r) {
    case Recurrence.none:
      return null;
    case Recurrence.daily:
      return _addDays(from, 1);
    case Recurrence.weekdays:
      var next = _addDays(from, 1);
      while (next.weekday == DateTime.saturday || next.weekday == DateTime.sunday) {
        next = _addDays(next, 1);
      }
      return next;
    case Recurrence.weekly:
      return _addDays(from, 7);
    case Recurrence.monthly:
      return _addMonths(from, 1);
    case Recurrence.yearly:
      return _addMonths(from, 12);
  }
}

/// [days] later on the calendar, at the same wall-clock time.
DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second, d.millisecond);

/// [months] later, with the day clamped to the length of the target month.
DateTime _addMonths(DateTime d, int months) {
  final zeroBased = d.month - 1 + months;
  final year = d.year + zeroBased ~/ 12;
  final month = zeroBased % 12 + 1;
  // Day 0 of the following month is the last day of this one.
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(
    year,
    month,
    math.min(d.day, lastDay),
    d.hour,
    d.minute,
    d.second,
    d.millisecond,
  );
}

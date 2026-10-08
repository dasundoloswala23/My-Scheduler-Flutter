import 'package:flutter/material.dart';

import '../models/task.dart';

/// The task with its schedule set from a date, an optional time and a duration.
///
/// A time makes a timed task that ends [durationMinutes] later. No time makes
/// an all-day task on [date], which has no end and no duration. The same rules
/// as Quick Add, so a task reads the same however it was scheduled.
Task withSchedule(
  Task task, {
  required DateTime date,
  required TimeOfDay? time,
  required int durationMinutes,
}) {
  if (time == null) {
    return task.copyWith(
      startDateTime: DateTime(date.year, date.month, date.day),
      endDateTime: null,
      isAllDay: true,
    );
  }
  final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  return task.copyWith(
    startDateTime: start,
    endDateTime: start.add(Duration(minutes: durationMinutes)),
    isAllDay: false,
  );
}

/// The task taken off the calendar. Its reminders have nothing to count from,
/// so they stop with it.
Task withoutSchedule(Task task) =>
    task.copyWith(startDateTime: null, endDateTime: null, isAllDay: false);

/// A timed task's length in whole minutes, or the default when it has none.
int durationMinutesOf(Task task) => task.duration.inMinutes.clamp(1, 24 * 60 * 7);

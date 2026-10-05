# Notifications and reminders

## What a task can have

A task carries `reminderOffsets`: a list of minutes before `startDateTime`.
`0` means at the start time itself. Presets are 0, 5, 10, 15, 30, 60 and 1440
minutes, plus a custom value. A task may have as many as it likes.

Reminders need a start time to fire. The task sheet says so when offsets are
set but no time is.

## Scheduling

`ReminderScheduler.sync(task)` cancels the task's existing alerts and schedules
its current set. Every id comes from `Notifications.reminderId(taskId, offset)`,
a stable hash, which is what lets a reschedule replace a task's own alerts
instead of stacking duplicates. `cancelFor` clears every preset id as well as
the current ones, so an offset the user removed cannot survive as a ghost.

It runs automatically on create, update and completion:

- Completing a task cancels its reminders.
- Un-completing restores them.
- A repeating task spawns its next occurrence, which schedules its own.

## Actions

Android, iOS and macOS show three buttons. Windows shows the notification
without them.

| Action | Effect |
|---|---|
| Complete | marks the task done, no UI opened |
| Snooze 10 min | re-fires the reminder, id offset `-1` so it cannot clash |
| Open | deep-links to the task's detail sheet |

`NotificationRouter` wraps the app, listens to the event stream, and performs
these. A notification that launched a cold app is replayed once there is a UI
(`Notifications.launchEvent`).

Background action taps are received by `notificationBackgroundHandler`, which
deliberately does nothing but let the action be replayed on next launch. The
background isolate has no authenticated Firestore, so writing there would be
unreliable; replaying on the main isolate is predictable.

## Permission

Requested the first time a reminder is added, never at launch, and preceded by
a dialog explaining why. If it is denied the sheet says so plainly, because
reminders would otherwise be saved and silently never appear.

## Recurrence

`none`, `daily`, `weekdays`, `weekly`, `monthly`, `yearly`.

Completing a repeating task creates the next instance with subtasks reset.
"Skip this occurrence" moves the same task forward without completing it, so a
daily task never multiplies into hundreds of rows. "Stop repeating" keeps the
task and ends the series.

## Platform support

| Platform | Scheduled alerts | Actions | Verified |
|---|---|---|---|
| Android | yes | yes | **not runtime-tested** |
| iOS | yes | yes | **NOT TESTED — requires macOS** |
| macOS | yes | yes | **NOT TESTED — requires macOS** |
| Windows | yes | no | **not runtime-tested** |
| Web (Flutter) | no | no | plugin does not support it |
| Web (Next.js) | no | no | reminders are stored and listed only |

Scheduling is implemented and analyzes clean, but no notification has been
observed firing on a device from this machine. That needs a real device or
emulator.

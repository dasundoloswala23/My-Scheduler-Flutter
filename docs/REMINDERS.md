# Reminders: how they work, and what each platform can really do

This is the current model. [NOTIFICATIONS.md](NOTIFICATIONS.md) is the older, simpler
description (offset list only) and is kept for history.

## The model

A task carries a list of `Reminder` objects (`lib/core/notifications/models/reminder.dart`).
Each has its own id, a type (`atTime`, `beforeTask`, `customTime`, `recurring`), an offset
(minutes, hours or days before the start), an enabled flag, and its own alert settings:

- `alertMode`: `notification` (an ordinary notification) or `alarm`
- `soundId` and `vibrate`

Reminders are counted from the task's start. **A task with no start time cannot fire a
reminder**, and Quick Add says so before saving. A reminder switched off is kept and never
fires. Tasks written by older builds (a bare `reminderOffsets` list) are still read: the
list is used only when `reminders` is empty.

## Scheduling

`ReminderCalculator` turns a task, its reminders and the user's preferences into a **plan**:
the notifications to schedule and the ones skipped, each with a reason (already in the past,
quiet hours, disabled). The platform adapter then makes reality match the plan. Because the
calculator is pure it is tested without a device (`test/alarm_reminders_test.dart`,
`test/notifications/`).

Every scheduled notification has a stable id derived from the task, the reminder and the
occurrence, so rescheduling **replaces** a task's own alerts instead of stacking duplicates.

A **repeating** task gets a rolling window of the next 8 occurrences
(`ReminderCalculator.recurringWindow`), because platforms cap pending notifications (iOS
allows 64). The window is topped up whenever the task is synced.

## When reminders are re-synced

| Event | What happens |
|---|---|
| Task created | its reminders are scheduled (ids re-keyed to the real task id) |
| Time, duration or category changed (edit, calendar drag/resize, board move, undo) | old alerts cancelled, new ones scheduled (`Repo.moveTask` / `updateTask`) |
| Task completed | future alerts cancelled |
| Task re-opened | alerts restored |
| Repeating task completed | the current occurrence's alerts are cancelled; the **next occurrence** (created in the original list) schedules its own |
| Task deleted | alerts cancelled first, while the task is still readable |
| Account deleted | every alert scheduled on the device is cleared |

A scheduling failure never undoes the data change: it is logged and the save stands.

## Notification actions

Tapping a notification opens that exact task. **Complete** completes only that task (and for
a repeating task creates the next occurrence once). **Snooze** re-fires after the configured
minutes (default 10), moving only the reminder that fired. These run through
`NotificationRouter` when the app is alive and through `background_actions.dart` in a cold
isolate when it is not. `test/notification_router_test.dart` covers the router.

## Per platform: what is real

| | Android | iOS / macOS | Windows | Web |
|---|---|---|---|---|
| Local notification | yes | yes | yes | only while the site is open |
| Action buttons (Complete / Snooze) | yes | yes (Darwin category) | **no** (plugin has none) | no |
| Alarm-style alert | yes: alarm channel, insistent, ongoing | **no equivalent** without the Time Sensitive entitlement (not added) | no | no |
| Bundled sounds (`assets/sounds`) | yes (`res/raw`, kept by `reminder_sounds_keep.xml` so R8 does not strip them) | **not wired**: files must be added to the Xcode target | system sound only | no |
| Fires with the app closed | yes (exact alarms) | yes | yes while the machine is on | **no** |

Android channels are created per (mode, style, sound, vibration), because a channel's
importance and sound cannot be changed once created.

### Android permissions in the manifest

`POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`,
`VIBRATE`, `RECEIVE_BOOT_COMPLETED`. The release APK was inspected with `aapt2`: all seven
bundled sound resources are present.

## Adding the sounds on Apple platforms

The `.wav` files in `assets/sounds` are the source. In Xcode, add each file to the **Runner**
target (Copy Bundle Resources), then make `ReminderSounds.supportsBundledSounds` return true
for iOS/macOS. Notification sound names on Apple platforms are file names with extension.
Not done here; it needs a Mac.

## What has not been verified

Audible sound, vibration, and behaviour on a PIN-locked screen need a person. Windows toast
appearance was not inspected. See `WINDOWS_QA_REPORT.md` for what was and was not run on a
device.

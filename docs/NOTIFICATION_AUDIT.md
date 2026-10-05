# Notification audit

Audit of the notification subsystem before the Phase 2 rework. Everything here
was read from the repository, not assumed.

## Where notification code lives today

| File | Role |
|---|---|
| `lib/core/notifications.dart` | plugin wrapper: init, permissions, schedule, cancel, action parsing |
| `lib/core/reminder_scheduler.dart` | offsets → scheduled alerts, snooze |
| `lib/core/repository.dart` | calls the scheduler on create / update / complete |
| `lib/features/home/notification_router.dart` | handles taps and action buttons |
| `lib/features/task_detail/reminder_picker.dart` | offset picker, permission prompt |
| `lib/models/task.dart` | `reminderOffsets` (list of ints), legacy `reminderMinutesBefore` |
| `lib/models/collections.dart` | standalone `Reminder` documents, separate from tasks |

There is **one** notification system, not several. The rework extends it rather
than replacing it.

## Project QA conventions

`.claude/skills`, `.claude/agents`, `skills/` and `agents/` do not exist in this
repository, so there are no project-specific QA workflows to follow. The
existing convention is `tools/api-tests/` (live Firebase) plus `test/`
(Flutter unit tests); the new work follows both.

## Gap analysis

| Feature | Current | Platform | Working? | Missing | Risk | Solution | Test |
|---|---|---|---|---|---|---|---|
| Reminder identity | offsets are bare ints on the task | all | partly | no stable id, type or enabled flag per reminder | medium — cannot disable one reminder, or model an absolute-time reminder | first-class `Reminder` model | unit |
| Multiple reminders | yes, via `reminderOffsets` | all | yes | per-reminder edit/delete UI | low | list UI with edit and delete | unit + manual |
| Early reminder presets | 0/5/10/15/30/60/1440 | all | yes | 45 min, 2 h, 2 days; no unit picker | low | presets + value/unit entry | unit |
| Custom offsets | minutes only | all | partly | hours and days entry | low | unit selector | unit |
| Notification id scheme | hash of taskId + offset | all | yes | collisions unproven | low | keep, add a collision test | unit |
| Reschedule on edit | `sync()` cancels then reschedules | all | **unproven** | no test; cancel list is preset-bound | **high** — a stale alert after an edit is very visible | cancel by stored `notificationId` | unit |
| Cancel on delete | not wired to `deleteTask` | all | **no** | task delete leaves alerts scheduled | **high** | cancel in `deleteTask` | unit |
| Snooze | fixed 10 min | all | yes | no choice of duration | low | 5/10/15/30/60/custom | unit |
| Deep link | opens task sheet | all | code complete | never runtime-verified | medium | keep, document | manual |
| Recurrence | next instance on complete | all | yes | no rolling window for future occurrences | medium | schedule next N occurrences | unit |
| Quiet hours | none | all | **no** | entire feature | low | preference + suppression at schedule time | unit |
| Daily summary | none | all | **no** | entire feature | low | daily repeating notification, opt-in | unit |
| Per-category mute | none | all | **no** | entire feature | low | preference map consulted when scheduling | unit |
| Master/per-type toggles | none | all | **no** | entire feature | medium — no way to turn notifications off in-app | preferences model | unit |
| Default reminder | none | all | **no** | new tasks get no reminder | low | preference applied in quick add | unit |
| Sound / vibration / importance | fixed high importance | Android | partly | no user choice, one channel | low | channel per style | manual |
| Android channels | single `reminders` channel | Android | partly | no normal/important/urgent split | low | three channels | manual |
| **POST_NOTIFICATIONS** | merged from plugin manifest | Android | yes | — | — | — | — |
| **RECEIVE_BOOT_COMPLETED** | **absent** | Android | **no** | alerts are lost on reboot | **high** | permission + boot receiver | manual |
| **Boot receiver** | **absent from app manifest** | Android | **no** | same as above | **high** | declare the plugin's receivers | manual |
| **Exact alarm permission** | **absent** | Android | **no** | alerts drift under Doze | medium | `USE_EXACT_ALARM`, graceful fallback | manual |
| Timezone | `tz.local`, offsets computed in local time | all | partly | behaviour on timezone change undocumented | medium | document; reschedule on resume | unit |
| Offline scheduling | local, no network needed | all | yes | untested | low | test | unit |
| iOS categories/actions | registered | iOS | code complete | **NOT TESTED — requires macOS** | — | — | manual |
| macOS | registered | macOS | code complete | **NOT TESTED — requires macOS** | — | — | manual |
| Windows toast | plugin `WindowsInitializationSettings` | Windows | code complete | no actions; never runtime-verified | medium | document limits | manual |
| Web (Flutter + Next.js) | none | web | **no** | no web push | low | document as unsupported | — |
| Deterministic tests | none for notifications | all | **no** | cannot test timing without waiting | **high** | injectable clock + fake adapter | unit |

## Highest risks, in order

1. **Task deletion does not cancel its alerts.** A deleted task can still fire.
2. **No boot receiver.** Every scheduled reminder is lost when the phone
   restarts, silently.
3. **No deterministic tests.** Scheduling correctness is currently unverifiable
   without waiting real hours.
4. **Reschedule-on-edit is untested** and cancels by preset list rather than by
   the ids actually scheduled, so a custom offset could be orphaned.

## Decisions for the rework

- Keep the existing `Task` as the source of truth. Reminders stay embedded in
  the task document; they are meaningless without it and this keeps a move or
  edit atomic.
- Add a `Reminder` model with its own id and `notificationId`, so cancelling is
  exact rather than inferred.
- Keep `reminderOffsets` readable for documents written before this change.
- Put all timing logic in a pure calculator with an injectable clock, so the
  whole of Phases 23–25 can be tested in milliseconds instead of hours.
- Platform work that cannot be verified here is documented as such rather than
  claimed.

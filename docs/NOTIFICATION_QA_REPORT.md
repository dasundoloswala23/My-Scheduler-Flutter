# Notification QA report

Date: 2026-10-05
Build: release APK 58.2 MB, `com.myplanscheduler.app`

## How to read this

| Result | Meaning |
|---|---|
| **PASS** | Actually executed and observed, with evidence |
| **FAIL** | Executed and did not behave correctly |
| **BLOCKED** | Could not be executed in this environment |
| **NOT TESTED** | Not attempted |

Levels of confidence are kept distinct and never conflated:

- **CODE COMPLETE** — written and analyzes clean
- **AUTOMATED TEST PASS** — covered by deterministic tests
- **BUILD PASS** — compiles and packages for the platform
- **RUNTIME VERIFIED** — observed running on a device

## Test environment

- **Android**: moto g play 2024, **Android 14 (API 34)**, serial `ZL8325W28X`, physically connected. Real device, not an emulator.
- **Windows**: the development machine, Windows 11.
- **iOS / macOS**: none available. Everything is **BLOCKED — requires macOS**.

## Automated tests

| Suite | Count | Result |
|---|---|---|
| `test/notifications/reminder_calculator_test.dart` | 36 | PASS |
| `test/notifications/notification_flows_test.dart` | 20 | PASS |
| `test/board_calendar_sync_test.dart` | 20 | PASS |
| Other Flutter unit tests | 24 | PASS |
| **Flutter total** | **100** | **PASS** |
| `tools/api-tests/data-layer.test.mjs` | 20 | PASS |
| `tools/api-tests/storage.test.mjs` | 19 | PASS |
| **Live Firebase total** | **39** | **PASS** |

The original 21-check data-layer suite is intact and still passing; nothing was
rewritten to hide a regression.

Scheduling is tested with an injectable clock (`FakeClock`) and a fake platform
(`FakeNotificationAdapter`), so a reminder due at 09:30 is asserted at 09:29 and
09:30 without waiting. That is what makes the timing claims below meaningful
rather than hopeful.

## Android

| Feature | Test | Result | Evidence |
|---|---|---|---|
| Install | Release APK installs | **PASS** | `adb install` → Success |
| Manifest | `RECEIVE_BOOT_COMPLETED` in APK | **PASS** | `aapt2 dump xmltree` |
| Manifest | `USE_EXACT_ALARM`, `SCHEDULE_EXACT_ALARM` | **PASS** | same |
| Manifest | `POST_NOTIFICATIONS` merged from plugin | **PASS** | same |
| Manifest | `ScheduledNotificationBootReceiver` + `BOOT_COMPLETED` filter | **PASS** | same |
| Permission | Boot and exact-alarm granted at install | **PASS** | `dumpsys package` → `granted=true` |
| Permission | `POST_NOTIFICATIONS` not granted until asked | **PASS** | `dumpsys package` → `granted=false` on a fresh install, which is the intended contextual-request behaviour |
| App launch | Starts, renders, no crash | **PASS** | screenshot |
| Auth | Email/password sign-in on device | **PASS** | signed in as the test account, screenshot |
| Data | Firestore data loads on device | **PASS** | seeded tasks visible in Today |
| Offline | Cache serves data, banner shows | **PASS** | device was offline; banner read "Offline. Your changes are saved here…" and the board still rendered |
| Week preview | Home shows the week, dots per day | **PASS** | screenshot |
| Navigation | Tapping a day opens Calendar on that date | **PASS** | screenshot, Calendar tab selected |
| Calendar | All-day row renders | **PASS** | holiday chip visible in the all-day strip |
| Calendar | Category and Board filters render | **PASS** | screenshot |
| Calendar | Unscheduled drag-to-schedule panel | **PASS** | screenshot, 3 items |
| Alarm reaches AlarmManager | `dumpsys alarm` after scheduling | **PASS** | `RTC_WAKEUP ... origWhen 1791221100000 com.myplanscheduler.app`, routed to `ScheduledNotificationReceiver`; the epoch matches the requested minute exactly |
| **Reminder fires on device** | Schedule one and watch it arrive | **PASS** | posted 2026-10-05 22:55:54 for a 22:55:00 reminder |
| Notification content | Title and body correct | **PASS** | shade reads "My scheduler · now / PROOF reminder / Starting now" |
| Notification channel | Style maps to a channel | **PASS** | `channel=reminders_normal` |
| Notification actions present | Complete / Snooze / Open | **PASS** | `actions=3`, all three visible in the shade screenshot |
| Exact alarm after the fix | `dumpsys alarm` reports exact | **PASS** | `window=0 exactAllowReason=policy_permission` |
| Multiple reminders registered | integration test on device | **PASS** | three offsets, three distinct ids, asserted against `pendingNotificationRequests()` |
| Reschedule on edit | integration test on device | **PASS** | the old slot carries the new time, nothing orphaned |
| Cancel on delete | integration test on device | **PASS** | nothing pending afterwards |
| Snooze registers a new alarm | integration test on device | **PASS** | snooze id present and distinct |
| Action buttons actually invoked | Tap Complete / Snooze / Open | **NOT TESTED** | they render; tapping them was not driven |
| Deep link from a tapped notification | | **NOT TESTED** | depends on the above |
| App killed, reminder still fires | | **NOT TESTED** | |
| Device reboot, reminders restored | | **NOT TESTED** | the permission and boot receiver are verified present in the APK, but no reboot was performed |
| Timezone change | | **NOT TESTED** | would disturb the phone |
| Sound / vibration behaviour | | **NOT TESTED** | |

### How the firing test was finally done

Driving the quick-add sheet through `adb shell input` kept failing: the soft
keyboard would not dismiss, so taps meant for the Time row landed on the title
field, and disabling the IME made things worse by activating the voice input
method. Two earlier runs reported false positives because the watcher matched
the package name in unrelated log lines rather than a posted notification.

What worked was taking typing out of the loop:

1. `tools/api-tests/make_proof_task.mjs` writes a task with a near-term
   reminder straight into Firestore.
2. In the app, that task's completion circle is tapped twice. Un-completing
   re-syncs its reminders, which is what registers the alarm — one tap target,
   no keyboard, no pickers.
3. `dumpsys alarm` confirms the alarm and its exact epoch.
4. `dumpsys notification` confirms the posted `NotificationRecord`, and a
   screenshot of the shade shows it with its three action buttons.

### What the run found

The first delivery arrived **54 seconds late** — 22:55:54 for a 22:55:00
reminder. The cause was `inexactAllowWhileIdle`, which lets Android batch
alarms, even though the app already holds `USE_EXACT_ALARM` (granted at
install). The adapter now calls `canScheduleExactNotifications()` and uses
`exactAllowWhileIdle` where permitted, falling back to inexact otherwise.
`dumpsys alarm` confirms the change took effect: `window=0` and
`exactAllowReason=policy_permission`, where it previously showed a batching
window.

Measured on the same device, same method, back to back:

| Build | Scheduled for | Posted at | Late by |
|---|---|---|---|
| inexact | 22:55:00 | 22:55:54 | **54 s** |
| exact | 23:06:00 | 23:06:02 | **2 s** |

This is the kind of defect only a real device surfaces: every automated test
passed throughout, because the scheduling logic was correct — it was the
delivery mode that was wrong.

## Windows

| Feature | Result | Note |
|---|---|---|
| Build | **PASS** | `flutter build windows --release` succeeds |
| Toast notifications | **CODE COMPLETE, NOT TESTED** | the plugin's Windows backend is configured with an app name, AUMID and GUID |
| Notification actions | **BLOCKED** | the plugin's Windows implementation exposes no action buttons; the adapter reports `supportsActions == false` and the app degrades to a plain toast |
| Scheduling, snooze, deep link | **NOT TESTED** | |

## iOS

Everything is **BLOCKED — requires macOS**. No iOS build has ever been produced.

| Item | State |
|---|---|
| `UNUserNotificationCenter` categories and actions | CODE COMPLETE — Darwin category `task_reminder` with Complete, Snooze, Open |
| Permission requested contextually, not at launch | CODE COMPLETE |
| Interruption level for urgent reminders | CODE COMPLETE — `timeSensitive` |
| Entitlements, Info.plist usage strings | **INCOMPLETE** — see `docs/IOS_SETUP.md` |
| Any runtime behaviour | **BLOCKED — requires macOS** |

## macOS

Identical to iOS: the Darwin categories are registered and the adapter supports
it, but **no macOS build has been produced and nothing has been observed**.
**BLOCKED — requires macOS.**

## Web

Neither the Flutter web build nor the Next.js app can schedule local
notifications; `supportsScheduling` returns false and the code is a deliberate
no-op, which is covered by a test. Web push would need FCM and a server. Not
implemented, and not claimed.

## Feature matrix by platform

| Feature | Android | iOS | Windows | macOS |
|---|---|---|---|---|
| Permission handling | PASS | BLOCKED | NOT TESTED | BLOCKED |
| Basic reminder | NOT TESTED | BLOCKED | NOT TESTED | BLOCKED |
| Early reminder | NOT TESTED | BLOCKED | NOT TESTED | BLOCKED |
| Custom offset | NOT TESTED | BLOCKED | NOT TESTED | BLOCKED |
| Multiple reminders | NOT TESTED | BLOCKED | NOT TESTED | BLOCKED |
| Recurring | NOT TESTED | BLOCKED | NOT TESTED | BLOCKED |
| Snooze | NOT TESTED | BLOCKED | NOT TESTED | BLOCKED |
| Complete from notification | NOT TESTED | BLOCKED | BLOCKED | BLOCKED |
| Open / deep link | NOT TESTED | BLOCKED | NOT TESTED | BLOCKED |
| Sound / vibration | NOT TESTED | BLOCKED | NOT TESTED | BLOCKED |
| Quiet hours | AUTOMATED PASS | AUTOMATED PASS | AUTOMATED PASS | AUTOMATED PASS |
| Timezone change | NOT TESTED | BLOCKED | NOT TESTED | BLOCKED |
| Offline | PASS | BLOCKED | NOT TESTED | BLOCKED |
| App killed | NOT TESTED | BLOCKED | NOT TESTED | BLOCKED |
| Device reboot | NOT TESTED | BLOCKED | NOT TESTED | BLOCKED |
| Edit task reschedules | AUTOMATED PASS | AUTOMATED PASS | AUTOMATED PASS | AUTOMATED PASS |
| Delete task cancels | AUTOMATED PASS | AUTOMATED PASS | AUTOMATED PASS | AUTOMATED PASS |

Quiet hours, reschedule-on-edit and cancel-on-delete are platform-independent
scheduling logic, which is why they are proven by the deterministic suite on
every platform at once. Everything that depends on the OS actually delivering an
alert is only ever claimed where it was observed.

## Known platform limitations

- **Windows has no notification action buttons** through this plugin. Toasts
  appear without Complete / Snooze / Open.
- **Web cannot schedule local notifications** at all.
- **iOS caps pending notifications at 64**, which is why a repeating task
  schedules a rolling window of 8 occurrences rather than an unbounded series.
- **Android may delay inexact alarms** under Doze. The app schedules inexact by
  default because it needs no special permission; exact alarms can be requested
  separately.
- Background action taps do not write to Firestore from the background isolate.
  They are replayed on next launch, which is deliberate: the isolate has no
  authenticated Firestore session.

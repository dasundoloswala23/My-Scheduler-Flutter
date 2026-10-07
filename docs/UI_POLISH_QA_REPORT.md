# UI / Calendar / Holiday / Widgets polish — QA report

Date: 2026-10-07
Flutter 3.44.0 stable · Dart SDK ^3.12.0
Machine: Windows 11. No Mac, no Android device, no iOS device available.

## How to read this

| Result | Meaning |
|---|---|
| PASS | Exercised and observed to behave correctly. |
| FAIL | Exercised and found broken. |
| BLOCKED | Cannot be tested here — needs hardware, an OS, or a toolchain this machine does not have. |
| NOT TESTED | Built, but not exercised. Correctness is claimed by static analysis and tests only. |

Nothing below is marked PASS on the strength of "the code looks right".
Anything only verified by `flutter analyze`, `flutter test` or a compile is
NOT TESTED, because neither proves a pixel.

## Automated gates

| Gate | Result | Notes |
|---|---|---|
| `flutter analyze` | PASS | No issues found. |
| `flutter test` | PASS | 140/140 passing, up from 100. The 100 that existed before are unchanged and still pass. |
| `flutter build windows --release` | PASS | Compiles clean. See "Build" below if this line disagrees with your own run. |
| Web lint / typecheck / production build | BLOCKED | There is no separate web app in this repository. The web target is Flutter web, covered by `flutter analyze` and the Flutter build. The brief's "web lint, web typecheck, web production build" assume a TypeScript front end that does not exist here. |

### New test coverage

- `test/holiday_test.dart` — 14 tests. Fixed dates, nth-weekday (US Thanksgiving
  across three years), last-weekday (Memorial Day), Easter-derived dates
  (Good Friday / Easter Monday 2026), the Victoria Day edge case where 25 May
  is itself a Monday, unknown country codes, id stability, and every country /
  category filter combination the Holiday settings screen can produce.
- `test/app_preferences_test.dart` — 16 tests. Default values, full JSON
  round-trip, unknown-enum fallback, out-of-range clamping, `copyWith`
  null-clearing, density ordering, and link-preview parsing.

- `test/task_card_test.dart` — 10 widget tests driving a real `TaskCard` with
  every provider overridden, so no Firebase is involved: title and category
  chip, subtasks shown by default, subtasks hidden with the count still
  visible when the preference is off, the `+N more` collapse at the preview
  count, expanding and collapsing again, no expander on a short list, link
  previews for known and unknown hosts, no tile when there is no link, and
  the card taking the dark palette's surface under a dark theme.

One real bug was found by these tests and fixed: `LinkPreview.forUrl` accepted
`http://` (no host) and returned a preview with an empty domain.

Deliberately **not** covered: "ticking a subtask does not open the detail
sheet". The tick writes through `repoProvider`, and `Repo` cannot be
constructed without a Firebase app, so the tap raises an asynchronous provider
error that escapes the test body. Stubbing that out would prove nothing, so it
stays a manual check.

## Required QA tests (brief section 37)

| # | Feature | Platform | Result | Notes |
|---|---|---|---|---|
| 1 | Windows icon | Windows | PASS | Was already correct and is unchanged. `app_icon.ico` is 432 KB (the Flutter default is 33 KB), `Runner.rc` binds it to `IDI_APP_ICON`, `win32_window.cpp` loads it into the window class, and `ProductName` is "My Scheduler App". Covers the exe, taskbar, title bar, Start-menu shortcut and installed app. |
| — | Android launcher icon | Android | NOT TESTED | Branded assets present at all five densities plus adaptive fore/back layers; manifest points at `@mipmap/ic_launcher`. Not seen on a device. |
| — | iOS app icon | iOS | NOT TESTED | Full `AppIcon.appiconset` present. Needs Xcode to verify. |
| — | macOS app icon | macOS | NOT TESTED | The asset catalog is a combined set; it does contain the 10 `icon-mac-*` entries macOS requires, so it is correctly formed. Needs Xcode to verify. |
| 2 | Board card spacing | Windows | NOT TESTED | List columns now size to their cards instead of filling the viewport. Compiles and the card renders in a widget test, but the board layout itself was not seen. |
| 3 | Subtask display ON | — | PASS (widget) | Default is ON; the checklist renders on the card. |
| 4 | Subtask display OFF | — | PASS (widget) | Checklist hidden, `1/3 subtasks` meta chip still shown. |
| 5 | Subtask checkbox | — | NOT TESTED | The row has its own `InkWell`, so the tap is consumed before reaching the card — but this could not be unit-tested (see above). **Needs a manual check.** |
| 6 | Attachment preview | — | NOT TESTED | Needs a real upload against Firebase Storage. See "Known limitation" below. |
| 7 | URL preview | — | PASS (unit + widget) | Parsing and YouTube thumbnail derivation unit-tested; the rendered tile is widget-tested for known hosts, unknown hosts and no-link descriptions. |
| 8 | Calendar opens around 9 AM | — | NOT TESTED | Default `calendarScrollHour` is 9 and is unit-tested; the scroll itself is not. |
| 9 | Day view | — | NOT TESTED | Pre-existing, now density-aware. |
| 10 | 3-day view | — | NOT TESTED | Pre-existing. |
| 11 | Week view | — | NOT TESTED | Now honours week-start and show-weekends. |
| 12 | Month view | — | NOT TESTED | Now honours week-start and shows holiday names. |
| 13 | Agenda view | — | NOT TESTED | Now shows category and holiday category. |
| 14 | Calendar layout preference | — | NOT TESTED | Compact / Comfortable / Detailed; persisted. |
| 15 | Board → Calendar | — | NOT TESTED | Unchanged. Already one task record; `test/board_calendar_sync_test.dart` covers it and still passes. |
| 16 | Calendar → Board | — | NOT TESTED | As above. |
| 17 | Calendar drag | — | NOT TESTED | Unchanged apart from the hour height now being a variable. |
| 18 | Calendar resize | — | NOT TESTED | Resize maths updated to use the density's hour height. **This is the change most worth a manual check**, because an arithmetic error here silently sets wrong end times. |
| 19 | Reminder reschedule | — | PASS (unit) | `test/notifications/notification_flows_test.dart` unchanged and passing. Subtask ticks route through `updateTask` → `NotificationService.sync`, which is cancel-then-schedule over a deterministic id set, so it is idempotent. |
| 20 | Sri Lanka holidays | — | PASS (unit) | Covered by `holiday_test.dart`. |
| 21 | USA holidays | — | PASS (unit) | Covered, including the three moving-date rules. |
| 22 | Multiple countries | — | PASS (unit) | Covered. |
| 23 | Holiday category filtering | — | PASS (unit) | Covered. |
| 24 | Holiday disable | — | PASS (unit) | Unticking a country removes only its holidays; user-added ones survive. |
| 25 | Dark mode | — | PARTLY (widget) | A widget test asserts the card takes the dark palette surface under a dark theme. Everything else in the audit below is computed contrast, not eyeballed. |
| 26 | Light mode | — | NOT TESTED | Same palette system. |
| 27 | iOS widget | iOS | BLOCKED | Not built. See "Native widgets". |
| 28 | Windows widget / quick access | Windows | BLOCKED | Not built. See "Native widgets". |
| 29 | macOS widget | macOS | BLOCKED | Not built. See "Native widgets". |
| 30 | Mobile UI | Android / iOS | NOT TESTED | No device available. Board column width adapts below 420 px. |
| 31 | Desktop UI | Windows | NOT TESTED | Column width adapts at the 1400 px breakpoint. Not checked at each named resolution. |

## What changed, by brief section

| § | Item | State |
|---|---|---|
| 1 | Windows / Android / iOS / macOS icons | Verified already correct; no change needed |
| 2 | Board list empty space | Done — columns size to content, capped at viewport |
| 3 | Board card design | Done — category, title, date, time, priority, reminder, attachment, subtask progress |
| 4 | Subtasks on card front | Done — tickable, default ON |
| 5 | Subtask display setting | Done — persisted per account |
| 6 | Subtask card height | Done — first N shown, "+N more" / "Show less" |
| 7 | Attachment / URL preview | Partly done — see "Known limitation" |
| 8 | Calendar default scroll | Done — 9 AM default, configurable, earlier hours still reachable |
| 9 | Calendar view selector | Already existed; now persists |
| 10 | Calendar layout options | Done — three densities, persisted |
| 11 | One task, board and calendar | Already true; unchanged |
| 12 | Calendar category colours | Already true; now lifted for dark-mode legibility |
| 13 | No hard-coded holidays | Done — `HolidaysPage` no longer seeds anything |
| 14 | Holiday country selector | Done — 6 countries, multi-select |
| 15 | Holiday category filter | Done — 6 categories |
| 16 | Holiday display | Done — pill in the all-day row, name in month cells, card in agenda |
| 17 | Holiday persistence | Done — on the user document, so it syncs with the account |
| 18 | Holiday data architecture | Done — `HolidayData` + `HolidayService` + `HolidayEntry`; no dates in widgets |
| 19 | Holiday / task collision | Done — both render; holidays have no drag behaviour at all |
| 20–22 | Dark mode | Done — see audit below |
| 23–27 | Native widgets | **Not done** — see below |
| 28 | Responsive board | Partly — breakpoints added, not measured at each resolution |
| 29 | Card drag/drop | Preserved; drop-target feedback improved. Auto-scroll and the transactional move/version system untouched |
| 30 | Empty list UX | Done — "No tasks yet / Drop a task here" |
| 31 | Task action menu | Mostly — Open, Edit, Schedule, Reminder, Move, Change category, Priority, Duplicate, Delete (confirmed, in the danger colour). **Archive is not implemented** |
| 32 | Category filter | Done — button now names the active category |
| 33 | Global settings | Done — Appearance, Calendar, Tasks, Holidays, Notifications |
| 34 | Defaults | Done — System theme, Week, 9 AM, subtasks ON, no country assumed |
| 35 | Mobile responsiveness | Partly — layout adapts; not verified on a device |

## Dark mode audit (§ 20–22)

All light/dark colour decisions moved into one `AppPalette` theme extension in
`lib/app/theme.dart`, read as `context.palette.…`. 139 hard-coded colour call
sites across 21 files were converted. `AppColors.muted` is deprecated rather
than deleted, so nothing silently regresses.

Contrast, computed against the surfaces each colour actually sits on:

| Token | Dark value | On card `#1C1D23` | On page `#0F1014` |
|---|---|---|---|
| `textPrimary` | `#F2F3F5` | 15.1:1 | 17.9:1 |
| `textSecondary` | `#9CA3B0` | 6.3:1 | 7.5:1 |

The old fixed `#6B7280` scored 3.6:1 on the dark card — below AA for body
text, and the likely source of the reported readability problems.

Specific fixes:

- **White dropdown in dark mode** — `popupMenuTheme`, `menuTheme`,
  `dropdownMenuTheme` and `dialogTheme` had no explicit colour, so Material
  fell back to a light surface. All four are now bound to the palette. This is
  the bug visible in the supplied screenshot of the category dropdown.
- Grid lines, dividers and borders no longer use `Colors.black.withValues(…)`,
  which is invisible on a dark background.
- Category colours are lifted via `palette.onTint()` in dark mode, so a colour
  picked in light mode is still readable on a dark chip or event.
- Tint strength is 0.22 in dark vs 0.12 in light; the light value reads as
  nothing at all on a dark surface.
- Checkbox, switch, tooltip, snackbar, list tile, input border (enabled /
  focused / disabled) and disabled button states are all explicitly themed.
- The calendar gained a current-time line, themed to `palette.danger`.

**Not verified visually.** Every statement above is about the token values and
the theme bindings. Someone needs to run the app in both themes and look at it.

## Native widgets (§ 23–27) — BLOCKED, not built

No widget code was written, and no Flutter page is being passed off as a native
widget. The brief forbids that explicitly, and it remains the right call.

- **iOS and macOS WidgetKit** need a Swift/SwiftUI widget extension target, an
  App Group entitlement shared with the Runner, and Xcode to create and sign
  them. None of that can be done from Windows.
- **Windows** has no widget API that matches the concept. The nearest
  equivalents are a tray surface or a taskbar jump list, both of which need
  native C++ in the runner and a running app to test against.

`docs/WIDGETS.md` already describes the required work in detail and remains
accurate. This should be its own phase.

## Known limitation: attachment previews (§ 7)

Thumbnails are drawn from a new `attachmentPreview` field denormalised onto the
task document by `AttachmentService`, so a board of fifty cards does not issue
fifty subcollection reads.

Two consequences worth knowing:

1. **Existing tasks show no thumbnail until their attachments change.** The
   field is written by `_syncCount`, which only runs on upload or delete. A
   one-off backfill would populate older tasks; it was not written because it
   needs to run against live user data.
2. **URL previews do not fetch Open Graph metadata.** The web build cannot make
   that cross-origin request, and one request per card is not worth it
   elsewhere. Previews are derived from the URL alone: YouTube gets a real
   thumbnail, 13 known hosts get a friendly name, and everything else falls
   back to `🔗 domain.com` — which is the documented fallback the brief asks
   for, but it is a fallback, not full metadata.

## Regression check (§ 38)

| Area | State |
|---|---|
| Authentication | Untouched |
| Firestore security | Untouched. New data lives under `users/{uid}`, already covered by the existing rule |
| Task create / edit / delete | Untouched |
| Board drag/drop | Drop-target visuals changed; drop logic untouched |
| Undo | Untouched — still routed through `MoveController` |
| Version / concurrency control | Untouched |
| Calendar scheduling | Untouched |
| Calendar resize | Arithmetic now uses the density's hour height. Worth a manual check |
| Subtasks | Added a second place to tick them; the model is unchanged |
| Categories | Untouched |
| Reminders | Untouched |
| Attachments | One added denormalised field; upload and delete paths unchanged |
| Duplicate task/calendar records | None introduced. Holidays are metadata and are never written as tasks |

## What a human still has to do

In rough priority order:

1. Run the app in dark mode and in light mode and look at every screen.
2. Check calendar resize still sets the end time correctly, in all three
   layout densities.
3. Check the board at 1280×720, 1366×768, 1440×900 and 1920×1080.
4. Tick a subtask from the board and confirm the detail sheet does not open.
5. Upload an image to a task and confirm the thumbnail appears.
6. Run on an Android device and an iOS device.
7. Decide whether native widgets are worth their own phase.

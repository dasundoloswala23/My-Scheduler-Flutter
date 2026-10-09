# Windows QA report: stabilization pass (Phase 4 onward)

Statuses are only **PASS / FIXED / PARTIAL / FAILED / BLOCKED / NOT TESTED**. PASS means the check
was actually run and the evidence is named. Nothing here is rounded up.

Phases 0 to 3 (reminders follow the task, the Complete list and completion, board interactions)
were finished and committed earlier; Phase 3 is `9e4f23f`. This report covers what came after.

---

## 1. Executive summary

**WINDOWS STATUS: NOT READY FOR MAC.** The blockers are listed at the end of this section. The
code, the tests, the Windows app, the Flutter web build, the deployed Next.js site and the Firebase
rules are in good shape and verified as stated below; what stops a "ready" verdict is that the
**Android phone could not be reached this session** and a few interactive items need a person.

| Area | Result |
|---|---|
| `flutter analyze` | PASS: no issues |
| `flutter test` | PASS: 426 tests, 0 failed (Phase 3 board tests included, see section 9) |
| Windows desktop, real UI against live Firebase | PASS: integration tests 5/5, 1/1, 1/1 |
| Windows release exe launched, resized, screenshotted | PASS (see section 9) |
| Flutter web release build, driven in Chrome | PASS: boots, signs in, shows Today |
| Android release APK | PASS as a build; **BLOCKED** as a device run (no phone connected) |
| Next.js site | PASS: built, tested, **deployed**, and re-verified on the live URL |
| Firestore rules | PASS: tightened, deployed, 62 emulator + 30 live checks |

### Things you should know (disclosures)

1. **Git.** Nothing has been pushed since Phase 3 (`9e4f23f`), as you asked. All later work is in
   **local commits** in both repositories. **The deployed web site was built from a local,
   unpushed commit** (`ff420c0` in the Next.js repository).
2. **Live Firebase was changed**, with your earlier approval: the Firestore rules were deployed
   (rollback: `git show 07dd3c3:firestore.rules`), and Android certificates were registered (below).
3. **Android certificate registration had two mistakes of mine, both corrected.** I first registered
   the debug SHA-1 on the legacy app `com.dasun.myschedule`; I removed it and registered it on the
   real app `com.myplanscheduler.app`. Then I mistyped the release SHA-1; I deleted that entry and
   registered the correct values, read back with `apksigner` and listed with the CLI. Registered now
   on the real app: debug SHA-1 `17:EC:F5:5D:…:E8`, release SHA-1 `E6:AF:2F:94:…:3E:2E`, release
   SHA-256 `2C:D5:DF:EB:…:73:F4`. `android/app/google-services.json` now carries both Android OAuth
   clients.
4. **A baseline run wrote malformed test documents into the live test account.** I ran the new live
   rules suite against the *old* rules first, to prove it could tell the difference (10 of 30 checks
   failed, as they should). Those failures meant the old rules had accepted nine junk documents. I
   deleted them; the account is back to its original 13 tasks.
5. **Throwaway accounts** (`rules-check-*`, `delete-check-*`, `flutter-delete-*` at `example.test`)
   were created and deleted by the test runs. None remain.
6. **Test credentials were in git history.** They are out of the current tree (environment variables
   only), but they remain in history. They belong to a throwaway test account; change its password.
7. **Known conditions from earlier work, re-checked:**
   - The phone's app was uninstalled and reinstalled by Flutter's tooling on a signature mismatch and
     is signed in as the **test account**. *Not re-checked: the phone was not connected.*
   - The test account's "Done" lists were migrated to "Complete". *Re-verified live: one Complete list
     per board, idempotent on re-run (integration test).*
   - The deployed Next.js completion logic used to differ from Flutter's. **FIXED and deployed**
     (section 6).

### Blockers for "ready for Mac"

1. **Android device re-run** after this pass's changes: BLOCKED, the phone was not attached.
2. **Interactive Google sign-in** (needs a human consent tap); the configuration is registered.
3. **Calendar drag/resize through the real UI** and a **full dark-mode contrast sweep** of every
   screen were not done (see sections 3 and 5).

---

## 2. Phase 4: Quick Add, task detail, Inbox, Today

| Feature | Status | Evidence / notes |
|---|---|---|
| Quick Add: title, date, time, duration, reminders, subtasks, category, priority, board/list | PASS | existing 27 tests, plus new ones below |
| Quick Add: **repeat** (Daily, Weekdays, Weekly, Monthly, Yearly) | FIXED (was missing) | `quick_add_test`: each choice is saved as itself; no Repeat row without a date |
| Quick Add: **Project Flow link** | PASS | a task added to a flow stage is linked, not copied; no row when there are no flows |
| Save usable with the keyboard open; double submit guard | PASS | existing tests (small phone, very small screen, double tap = one task) |
| Keyboard "Done" saves | PARTIAL | the code submits on Done, but no test presses Done specifically |
| Saved task persists, lands in the right list, has its recurrence | PASS | Windows UI integration test: Quick Add with a time and *Weekdays* wrote one task with `recurrence: weekdays` to Firestore under the deployed rules |
| Appears on the calendar | PASS | scheduled tasks are the calendar's data; `board_calendar_sync_test` |
| Task detail: **date, time, duration editor** | FIXED (was missing) | "When" tile opens an editor; repo tests: new time and duration persist and the alert follows, duration-only change, remove from calendar cancels the alert, date without time is all-day |
| Task detail editor UI itself | PARTIAL | the logic is tested; the bottom sheet's widgets are not driven by a widget test |
| Inbox: unsorted list, complete, empty state | PASS | 4 widget tests (only tasks with no board and list; leaves the inbox once assigned; empty state; completes one task) |
| Inbox: assign board/list/category/priority/date, delete, edit | PARTIAL | uses the existing task menu; **not driven** in this pass |
| Today: select any date, previous and next day, "Today" button, date picker | FIXED (was missing) | 7 tests; the release exe shows the selector |
| Today: local-day correctness | PASS | tests: a 23:30 local task belongs to its own day; day arithmetic across month and year ends and DST |
| Today: complete, open, navigate to board | PARTIAL | pre-existing behaviour, not re-driven |
| Recurrence across several cycles, no duplicates | PASS | `completion_test` and `recurrence_test` (earlier phase) plus the live device test: one next occurrence even when completed twice from a stale snapshot |

## 3. Phase 5: Calendar

| Feature | Status | Evidence / notes |
|---|---|---|
| Opens at about 9 AM, earlier hours above | PASS | widget test measures the scroll offset = 9 × hour height; mutation-checked (offset 0 fails it) |
| Day / 3 days / Week / Month all draw the real task | PASS | widget test switches through all four views and finds the task in each |
| One task store, no second calendar database | PASS | the page reads `tasksProvider`; `board_calendar_sync_test` |
| Drag or resize changes Firestore **and reschedules reminders** | PARTIAL | verified at the repository level (`moveTask`, 13 tests); **not driven through a real drag in the UI** |
| Tasks at the correct times in Month and 3-Day | PARTIAL | the views render; per-view time positioning was not asserted |
| Restart keeps state | PARTIAL | the default view and scroll hour are saved preferences (tested); a restart was not performed |

## 4. Phase 6: Reminders and notifications

Architecture is written up in [docs/REMINDERS.md](docs/REMINDERS.md) (it did not exist before).

| Feature | Status | Evidence / notes |
|---|---|---|
| Lifecycle: create, retime, move, complete, reopen, delete, repeating | PASS | `repo_reminders_test` (17) with a fake notification platform; includes "platform failure never undoes a save" |
| Notification tap opens the **exact task**; Complete and Snooze act on that task only | PASS | `notification_router_test` (3), new this pass |
| Reminder ON/OFF, early/custom offsets, several reminders, alarm mode, sounds, snooze | PASS (logic) | `alarm_reminders_test` and `reminder_calculator_test` |
| Android: channels, importance, alarm flags, cold-isolate Complete/Snooze, on-device tests | **BLOCKED** this session | the phone was not connected. These were verified on the phone **earlier in this effort** (17 device tests; channel importance 5, alarm usage, cold-isolate Complete and Snooze) and **not re-run after the later changes** |
| Android release APK: sound resources, permissions | PASS | `aapt2`: seven raw sounds present; notification, exact-alarm, full-screen-intent, vibrate and boot permissions declared |
| Windows notification appearance, click, cancel, reschedule | NOT TESTED | the scheduling path is shared and unit-tested; a toast was not displayed or clicked. Windows toasts have no action buttons (plugin limitation, documented) |
| Sound audible, vibration felt, PIN-locked screen | BLOCKED | needs a person |

## 5. Phase 7: Theme, holidays, settings, account

| Feature | Status | Evidence / notes |
|---|---|---|
| Light / Dark / System preference persists | PASS | `app_preferences_test` (round trip) |
| System follows the OS | PARTIAL | the release exe opened in the dark theme (the default mode is System); it was **not** compared against a deliberate flip of the OS setting |
| Dark-mode contrast on all pages, dialogs, sheets, calendar, boards, Project Flow | PARTIAL | Quick Add, legal pages, Today and the flows UI render in dark without layout errors (tests / screenshots); **no systematic contrast review** of every screen |
| Holidays: country, multiple countries, Public / Bank / Mercantile / **Other** | FIXED | UI now groups the six stored categories into the four; tests: Other = national + religious + observance; toggling touches only its group; **Sri Lanka with Mercantile on and Public off shows only mercantile holidays, and survives a save and reload**; two countries |
| Privacy Policy and Terms | FIXED (were missing) | Settings → Legal and the sign-in screen; tests: render in light and dark, links open, no absolute promises ("100%", "guaranteed"…) |
| Account deletion, Flutter, **live** | PASS | device test with a throwaway account: data deleted (6 lists, task, flow, 2 stages, link all gone, user document gone), then the account deleted; sign-in afterwards fails |
| Account deletion: partial failure and retry | PASS | the data step ran alone first (account still existed), then the whole thing again |
| Deletion clears reminders scheduled on the device | PASS (unit) | `cancelLocalReminders` is called; a failure there does not fail the deletion |
| Deletion covers every collection the rules allow | PASS | a test reads `firestore.rules` and fails if a collection is not deleted |
| Deletion of Storage files with real attachments | NOT TESTED | the throwaway account had none; the Storage path is the existing, unchanged one |
| Shared holiday data untouched | PASS | nothing global is stored; a test seeds a shared document and checks it survives |
| Sign out, profile, reset password | NOT TESTED | unchanged by this pass |

## 6. Phase 8: Web / Next.js business-logic consistency

Full detail is in `WEB_DEPLOYMENT_REPORT.md` in the Next.js repository.

| Feature | Status | Evidence / notes |
|---|---|---|
| Completion moves the task to Complete, no duplicate | FIXED, deployed | live browser run: card moves, count unchanged |
| Recurrence: next occurrence in the original list, deterministic id, idempotent, reopen removes it | FIXED, deployed | live browser run read back from Firestore (12 checks), double click made one occurrence |
| Same rules as Flutter | PASS | the TypeScript is a port; its tests reuse the Dart vectors (completion 26, recurrence 15, flow engine 36) |
| Complete list migration, new boards get default lists | FIXED | `listsVersion: 2` flag shared with Flutter; verified on a brand-new account |
| List Move left/right, top and end drop zones | PASS / PARTIAL | Move verified in the browser; the zones render but a pointer drag onto them was not exercised |
| Holiday groups, Privacy, Terms, account deletion | FIXED | account deletion verified live with a throwaway account (13 checks) |
| Calendar on web | NOT TESTED | unchanged code; the page loads |

## 7. Phase 9: Project Flow

Planning layer only: a flow holds stages and links; **a task is never copied**.

| Feature | Status | Evidence / notes |
|---|---|---|
| Models: ProjectFlow, FlowStage, FlowTaskLink | PASS | `lib/models/project_flow.dart`; stored under `users/{uid}/projectFlows`, `flowStages`, `flowTaskLinks` (flat, so the owner rule covers them and no composite index is needed) |
| Sequential / Flexible / Dependency | PASS | 25 engine tests, mutation-checked twice |
| Stage states LOCKED / UPCOMING / ACTIVE / COMPLETED / BLOCKED; flow ACTIVE / COMPLETED / PAUSED / ARCHIVED | PASS | engine tests |
| Unlocking, dependency cycles (detected, blocked, edit refused), blocked propagation | PASS | engine and repository tests |
| Progress 4/9 and per-stage tasks | PASS | engine test with nine stages; UI shows "n/9 stages" |
| Link an existing task; no new task; completing it advances the stage | PASS | 21 repository tests against the real `Repo`; completion hook runs after the task write; also driven in the web UI |
| Delete a stage or flow keeps the tasks | PASS | repository tests |
| Repeating linked task | PASS | completing it completes its stage; the next occurrence is not linked (documented behaviour) |
| Six templates incl. Mobile App Launch with the nine agreed stages | PASS | tests; a template creates stages and **no tasks** (asserted) |
| Flow Advisor | PASS | `FlowAdvisor` interface and a keyword implementation that labels itself "keyword match, not AI"; unmatched goals give no suggestion; **Add all / Customize / Cancel**; accepting creates stages only |
| Project Flows page: filters All / Active / Blocked / Completed / Due soon, search, board and category | PASS | 10 filter tests and widget tests |
| Flow detail: vertical timeline, ✓ / highlighted / greyed / blocked | PASS | widget test; rendered in the browser |
| Navigation: More tab, desktop sidebar | PASS | sidebar entry seen in the release exe; More tile present; opened by the Windows UI test |
| Board card badge "Flow 4/9", small | PASS | widget tests; seen in the web UI |
| Create a flow through the real Windows UI | PASS | integration test: nine stages, no tasks created |
| Transactions | PARTIAL (by design) | not used: the engine is a pure function evaluated live by the screens, so a racing recompute cannot show a wrong state; the stored copy is repaired by the next change. This is a deliberate choice, stated in the code |
| Link-a-task and dependency-editing dialogs | PARTIAL | covered by repository tests, not by Flutter widget tests of the dialogs |

## 8. Phase 10: Android QA

| Item | Status | Evidence / notes |
|---|---|---|
| Release APK builds (R8) | PASS | 62.4 MB, `com.myplanscheduler.app` v1.1.0 (2), signed with the project's release key |
| Manifest permissions; bundled sounds kept | PASS | `aapt2` |
| Launch, login, board, drag/drop, CRUD, calendar, reminders, notifications, persistence on a device | **BLOCKED** | no device was attached (`adb devices` empty, also after restarting the server) |
| Google Sign-In | PARTIAL | both certificates and the SHA-256 are registered on the real app and the Android OAuth clients are in `google-services.json`; **the sign-in itself needs a human consent** and was not performed |
| Account deletion, Project Flow, holidays on the phone | BLOCKED | |
| The phone's current state (signed in as the test account; app reinstalled earlier) | NOT TESTED | not connected |

## 9. Phase 10: Windows QA

| Item | Status | Evidence / notes |
|---|---|---|
| Debug build runs; live integration tests | PASS | `completion_device_test` 5/5; `windows_ui_test` 1/1 (sign-in, Quick Add with a time and a Weekdays repeat → Firestore, Project Flows → New flow from the Mobile App Launch template → nine stages, no tasks created); `account_deletion_device_test` 1/1 |
| Release build | PASS | `flutter build windows --release` |
| Release exe launches signed in, responds | PASS | process responding after resizes |
| Resize | PASS | 1280×720 and 1000×680 show the desktop sidebar layout; **480×760 switches to the compact layout with the bottom bar** and no overflow (window-only, DPI-aware screenshots) |
| Dark theme appears (mode is System) | PARTIAL | see section 5 |
| Today date selector present | PASS | seen in the exe |
| Board, list reorder, drag/drop, calendar, theme switch, holidays, settings **driven through the UI** on Windows | PARTIAL | covered by widget tests and the repository tests; the UI test covers Quick Add and Project Flows only |
| Keyboard and mouse | PARTIAL | shortcuts exist (Ctrl+N); not exercised this pass |
| Toast notifications | NOT TESTED | see section 4 |
| **Phase 3 regression** (commit `9e4f23f`) | PASS | `board_interactions_test` re-run inside the full suite: `planListMove` vectors (5), `Repo.moveListBy` (4, including 40 back-and-forth moves), and the widget test that a drag onto the **top drop zone** inserts at position 0 (mutation-checked). The recurrence chip and the animated drop-zone overflow fix are covered. |

## 10. Web QA

| Item | Status | Evidence |
|---|---|---|
| Next.js: live site, 47 browser checks | PASS | after deploy, https://myscheduleplanner-e22f3.web.app |
| Recurrence and account deletion on the live site | PASS | 12 and 13 checks |
| Flutter web release build | PASS | boots in Chrome, sign-in screen shows Terms and Privacy, signing in via the UI reaches Today with the date selector (5/5) |
| Flutter web: drive beyond sign-in | NOT TESTED | the canvas UI was only driven through sign-in |
| Dark mode, tablet screenshots reviewed by eye | PARTIAL | measured and captured; not all reviewed |

## 11. Firebase and security QA

| Item | Status | Evidence |
|---|---|---|
| Emulator rules suite | PASS | 62/62: owner allowed, other user and signed-out denied, per collection; malformed refused; unknown collection closed; mutation-checked (a weakened rule fails a test) |
| Live: before deploying | PASS | existing suites 20 + 19 green; new suite **20 pass, 10 fail on the old rules** (the new checks have teeth) |
| Rules deployed | FIXED | per-collection validators; **no wildcard** under `users/{uid}` (it would have defeated the validators); no secrets; owner check kept |
| Live: after deploying | PASS | 20 + 19 + 30, all green, with two real accounts: A cannot read, list, overwrite, delete or create into B; B cannot read A; signed-out refused |
| Both clients still write under the stricter rules | PASS | Flutter device tests and the web browser runs (cards, completion, flows, deletion) all succeeded after the deploy |
| Storage rules | PASS | existing 19-check suite, unchanged |
| Firestore indexes | NOT TESTED | no index file changes were needed (queries sort client-side); nothing deployed |
| Stale iOS app id in `firebase.json` | PARTIAL | the Android id was fixed; the iOS ids in `firebase.json` and `firebase_options.dart` disagree and can only be settled against the console (see Mac handoff) |

## 12. Automated tests

| Suite | Result |
|---|---|
| `flutter analyze` | no issues |
| `flutter test` | **426 passed**, 0 failed |
| Integration on Windows (live Firebase) | 5/5 + 1/1 + 1/1 |
| Rules, emulator (`tools/rules-tests`, needs JDK 21: a portable one was used from a scratch folder) | 62/62 |
| Live API suites (`tools/api-tests`) | 20 + 19 + 30, all passed |
| Next.js `npm test` | 126 passed |
| Next.js `tsc`, `lint`, `build` | clean, clean, built |
| Playwright (`tools/web-e2e`) | Next.js local 47/47 and live 47/47; recurrence 12/12 and 12/12; deletion 13/13 and 13/13; Flutter web 5/5 |

New this pass: board interactions 10, calendar page 2, Today date 7, Inbox 4, notification router 3,
legal pages 5, account deletion 7, Project Flow engine 25, repository 21, UI 19, holiday groups 5,
and additions to Quick Add, task card and repo reminders. Where a test was meant to detect a bug,
a mutation check confirmed it does (engine rules, rules deployment, calendar 9 AM, top drop zone).

## 13. Bugs found

1. A repeating task with nothing else on its card showed **no repeat chip** (the Phase 3 chip was
   only shown when other metadata existed).
2. The release app showed a false **"Offline"** banner while online.
3. Today's week strip header overflowed on a narrow width.
4. The first Quick Add flow picker read the stages cold and showed none.
5. The board's list-creation flow on the **web** created default lists in a second step, and had no
   Complete list at all.
6. The **web had no account deletion** and no Privacy/Terms.
7. The web and Flutter disagreed on completion (section 6).
8. The old Firestore rules **accepted malformed documents** (proved by the live baseline).
9. The live API suite looked for a list named "Done".
10. Test credentials were committed.
11. My two Android-certificate mistakes (disclosure 3).

## 14. Bugs fixed

1. Repeat chip now shows (`hasMeta` includes repeat and flow badge). 2. Offline banner fixed
(`snapshots(includeMetadataChanges: true)`; the first snapshot comes from the cache and a confirming
server snapshot has no data change, so no second event arrived); before/after seen in the release exe.
3. Header made flexible. 4. Providers watched. 5-7. Web ported and deployed. 8. Rules tightened and
deployed. 9. Suite updated. 10. Removed from the tree (history remains). 11. Corrected and verified.

## 15. Known limitations

- A monthly task started on the 31st drifts after clamping (31 Jan, 28 Feb, 28 Mar); both clients.
- Windows toasts have no action buttons; web reminders only work while the site is open.
- Bundled sounds are Android-only (Apple: files must be added to Xcode; Windows: system sounds).
- A deleted account's ID token stays valid for up to an hour (Firebase).
- The deployed site answers unknown URLs with HTTP 200 (pre-existing rewrite).
- Project Flow state is derived live; the stored copy can lag by one change.
- The Flow Advisor is keyword matching over templates, not AI, and says so.
- Flutter web was driven only through sign-in; its interactive features were not.

## 16. Blocked items

Android device run (phone not connected); interactive Google sign-in; audible sound and vibration;
PIN-locked lock screen; Windows toast display; anything on iOS or macOS (no Mac).

## 17. Mac handoff requirements

See [docs/MAC_HANDOFF.md](docs/MAC_HANDOFF.md). In short: the toolchain and commands, the Firebase
plist and the iOS app-id mismatch to settle, Sign in with Apple capability, Time Sensitive and
Info.plist decisions, the bundled-sound step, and a checklist of what to test on a Mac. Everything
Apple-specific is **NOT TESTED**.

---

**WINDOWS STATUS: NOT READY FOR MAC.** Exact blockers: (1) re-run the Android device tests and the
cold-isolate Complete/Snooze check on the phone, (2) complete one interactive Google sign-in on
Android, (3) drive the calendar drag/resize and a dark-mode contrast sweep through the real UI.

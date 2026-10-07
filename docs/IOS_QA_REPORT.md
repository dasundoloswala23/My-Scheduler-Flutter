# iOS QA Report — MyPlanScheduler

Date: 2026-10-07 · Bundle ID `com.myplanscheduler.app` · Team `66FLAFF9SU` · Min iOS 15.0
See `docs/IOS_AUDIT.md` for config findings and fixes.

**Environment: SIMULATOR ONLY** (iPhone 17 Pro, iOS 26.1). A physical iPhone was detected but is not in Developer Mode, so nothing ran on it.

## Summary

| Area | Result | Evidence |
|---|---|---|
| Build | **PASS** | `flutter build ios --release` → signed `Runner.app` (58.8 MB). Bundle ID, display name `MyPlanScheduler`, MinimumOS 15.0 and the `applesignin` entitlement verified with `plutil` / `codesign`. |
| Automated tests | **PASS** | `flutter analyze`: no issues. `flutter test`: 100/100. Live API suite `node tools/api-tests/run-all.mjs`: data layer 20/20 and storage 19/19 (this is what used to be the 21/21 baseline, now larger). |
| Simulator | **PASS** (for what was exercised) | `integration_test/notification_device_test.dart`: 6/6 on the simulator. |
| Physical iPhone | NOT TESTED | Device isn't in Developer Mode. |
| Firebase | **PASS** | Email/password sign-in plus Firestore reads/writes from the iOS app in the simulator (integration setUpAll + repo calls). |
| Email/password sign-in | **PASS** | Same evidence as Firebase. |
| Google Sign-In | **FAIL** (config) / NOT TESTED | No iOS OAuth client ID and no reversed-client-ID URL scheme. Expected to fail at runtime. |
| Apple Sign-In | NOT TESTED | Entitlement is now in the signed binary. The flow wasn't run, and the Firebase Apple provider wasn't checked. |
| Notifications | **PASS** (scheduling) | On the simulator, the OS accepted: one reminder; several reminders on one task; a time change that cancels the old alarm and sets a new one; delete clearing alarms; a reminder under 1 minute; snooze. Alert delivery and action-button taps weren't watched. |
| Notification permission | PARTIAL | Seen: the native prompt appears, the app is labelled "MyPlanScheduler", and the app doesn't prompt at init. Allow was tapped. Denied and re-enabled-in-Settings paths: NOT TESTED by hand. Code fixed so a denial is detected and the user is told where to re-enable. |
| Notification actions (Complete/Snooze/Open) | NOT TESTED by hand | Code check: Open routes to the task's detail sheet. Open now brings the app to the foreground (fixed). |
| Calendar / Task → Calendar sync | PASS (unit level) | `test/board_calendar_sync_test.dart` and recurrence tests pass. Not exercised in the UI on iOS. |
| Calendar drag/drop | NOT TESTED | Needs a manual long-press drag on a device or simulator. |
| Attachments | PASS (backend) / NOT TESTED (UI) | Storage suite 19/19 covers upload, ownership, delete, and cross-user denial. The iOS picker UI wasn't run. |
| Security | **PASS** | Live rules tests: another user's tasks or attachments → 403, signed-out → 403. |
| Offline | NOT TESTED | |
| App lifecycle / lock / terminate | NOT TESTED | |
| Deep links | FAIL / not implemented | No URL scheme or universal links exist. Only notification → task routing. |
| Dark mode, safe areas, sizes, accessibility | NOT TESTED | |
| Performance (100+ tasks) | NOT TESTED | Note: the full per-user `tasks` collection is streamed, with no paging. |

## Changes made
- Display name and CFBundleName → `MyPlanScheduler`.
- Deployment target 13.0 → 15.0. Needed because `cloud_firestore` blocked `pod install`.
- `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` wired in. Sign in with Apple was missing from the signed app.
- Notifications: real permission check (`checkPermissions`), Open action launches the app to the foreground, denial messages explain how to re-enable.

## Remaining issues / manual release steps
1. **Google Sign-In:** in Firebase, enable the Google provider and download the iOS `GoogleService-Info.plist`. Add `GIDClientID` = `CLIENT_ID` and a `CFBundleURLTypes` entry = `REVERSED_CLIENT_ID` to `ios/Runner/Info.plist`, or re-run `flutterfire configure`.
2. **Apple Sign-In:** confirm the Apple provider is enabled in Firebase Auth (Service ID, key), then test on a device.
3. Turn on Developer Mode on the iPhone (Settings › Privacy & Security). Then run the manual checklist: login, board, drag/drop, reminder delivery and actions, deny then re-enable in Settings, dark mode, logout.
4. App Store: archive in Xcode with a distribution profile. Only a development-signed build was produced here.
5. Deep links aren't implemented. Decide whether release needs them.

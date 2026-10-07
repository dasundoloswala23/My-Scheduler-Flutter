# macOS QA Report — MyPlanScheduler

Date: 2026-10-07 · Bundle ID `com.myplanscheduler.app` · Team `66FLAFF9SU` · Min macOS 10.15
See `docs/MACOS_AUDIT.md` for config findings and fixes.

## Results

| Area | Result | Evidence / reason |
|---|---|---|
| Build: signed release | **BLOCKED** | `xcodebuild -allowProvisioningUpdates`: "Device 'Dasun's MacBook Pro' isn't registered in your developer account". The keychain-sharing entitlement needs a provisioning profile, and none can be made until this Mac is registered (or a Developer ID / App Store profile is used). |
| Build: ad-hoc release (verification) | **PASS** | Release config built with ad-hoc signing and without keychain-access-groups. Output `MyPlanScheduler.app`, bundle ID and name checked, sandbox + network.client entitlements in the binary. |
| Automated tests | **PASS** | analyze clean; `flutter test` 100/100; live API 20/20 + storage 19/19. |
| Runtime | PARTIAL | The ad-hoc release app launched, stayed running, and opened an 800×628 window with the MyPlanScheduler menu bar. The window contents couldn't be checked: screen capture has no Screen Recording permission. No UI flows were run. |
| Notifications | NOT TESTED on macOS | `flutter test -d macos` needs the signed Debug build, which is blocked as above. The same adapter passed 6/6 on the iOS simulator. |
| Calendar | PASS (unit) / NOT TESTED (UI) | |
| Board | NOT TESTED | |
| Drag/drop (mouse/trackpad, resize) | NOT TESTED | Code has Draggable/DragTarget and a resize handle. |
| Attachments | PASS (backend) / NOT TESTED (UI) | Storage suite 19/19. The file-picker entitlement was added but the picker wasn't exercised. |
| Firebase | BLOCKED (on macOS) | Network entitlement is in place. Sign-in on macOS needs keychain access, and therefore a signed build. |
| Security | **PASS** | Rules tests: cross-user and signed-out access → 403. |
| Performance | NOT TESTED | |
| Dark mode | NOT TESTED | |
| Keyboard | NOT TESTED | Added Cmd/Ctrl+K (search) and Cmd/Ctrl+N (new task). They compile and analyze clean, but weren't pressed in a running app. |
| Trackpad | NOT TESTED | |
| Recurring / offline / lifecycle / restart | NOT TESTED | |

## Changes made
- Entitlements (Debug + Release): `network.client`, `files.user-selected.read-only`, `keychain-access-groups`. Before this, a sandboxed release could not reach Firebase at all.
- Product name `myschedule` → `MyPlanScheduler`, plus the display name, RunnerTests bundle ID (`com.dasun.*` was removed), scheme and copyright.
- Signing: team `66FLAFF9SU`, Automatic, Apple Development.
- Keyboard shortcuts in `home_shell.dart`.

## Remaining issues / manual release requirements
1. Register this Mac in the Apple Developer account (Xcode › Settings › Accounts, or the portal), then run `flutter build macos --release`. For distribution, create a Developer ID or Mac App Store profile, and notarize for Developer ID.
2. Then run `flutter test integration_test/notification_device_test.dart -d macos` and the manual checklist: login, board/calendar drag and resize, reminder delivery, Complete/Snooze/Open, deny then re-enable in System Settings, attachments, dark mode, shortcuts, window sizes, logout.
3. Google sign-in on macOS uses the browser provider flow. Untested.
4. Deep links aren't implemented.

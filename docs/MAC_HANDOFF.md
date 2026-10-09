# Mac handoff: what is left for iOS and macOS

> **Everything Apple-specific is NOT TESTED.** It was prepared on a Windows machine. No
> iOS or macOS build has ever been made or run. The Windows, Android phone, Flutter web
> and Next.js sides have been exercised; see `WINDOWS_QA_REPORT.md` for exactly how far.

The details of each Apple step already exist in [IOS_SETUP.md](IOS_SETUP.md),
[IOS_AUDIT.md](IOS_AUDIT.md), [MACOS_AUDIT.md](MACOS_AUDIT.md) and the two Apple QA reports.
This page is the short path through them, plus what changed in this stabilization pass.

## Toolchain

| Item | Value |
|---|---|
| Flutter | 3.44.0 (stable), Dart ^3.12 |
| Xcode | A version that supports iOS 13+ / macOS 10.15+ deployment targets; CocoaPods installed |
| Firebase project | `myscheduleplanner-e22f3` |
| Bundle id | `com.myplanscheduler.app` (iOS and macOS) |

```bash
flutter pub get
cd ios && pod install && cd ..
cd macos && pod install && cd ..
flutter analyze
flutter test                       # 400+ unit/widget tests, none need a device
flutter build ios --release        # needs signing
flutter build macos --release
```

## Files a Mac needs that are not in a clean checkout

- `ios/Runner/GoogleService-Info.plist` and the macOS equivalent: download from the Firebase
  console for the iOS app (`1:455014733188:ios:...`). `lib/firebase_options.dart` already
  carries the iOS and macOS options for Dart; the plist is what the native side reads.
  **Check which iOS app id is registered**: `firebase.json` and `firebase_options.dart`
  currently name different iOS app ids (`...94eedd0bc0c749d2a1f9d1` vs `...d8e53fcbff8720aaa1f9d1`).
  This was seen, not resolved, because it can only be settled against the console.
- A signing team and provisioning profile. The macOS project names team `66FLAFF9SU`
  (see MACOS_AUDIT.md); confirm it is yours.

## Capabilities and entitlements

- **Sign in with Apple**: add the capability to the Runner target so Xcode wires
  `ios/Runner/Runner.entitlements` in (the file exists but the project does not reference it).
  Needs a paid Apple Developer account. Enable the Apple provider in Firebase Authentication.
- **macOS**: `DebugProfile.entitlements` and `Release.entitlements` already carry network client,
  keychain access group and user-selected file read. Keychain access needs a real certificate
  and profile. Apple sign-in is deliberately not offered on macOS.
- **Time Sensitive notifications**: **not added**. Reminders flagged as alarms on Android use
  the alarm stream; iOS has no equivalent without the Time Sensitive entitlement. Decide
  whether to add it; without it an "alarm" reminder is an ordinary notification on iOS.
- **Info.plist usage strings** for photo library, camera and microphone are **not added**
  (see IOS_SETUP.md section 5); the App Store rejects attachment-capable builds without them.

## Reminders on Apple platforms

Described in [REMINDERS.md](REMINDERS.md). Specifics for a Mac:

- Permission is requested contextually the first time a reminder is created.
- Complete / Snooze / Open actions are registered as a Darwin notification category.
- **Bundled alert sounds (`assets/sounds`, `android/.../res/raw`) work on Android only.** To
  use them on iOS/macOS the `.wav` files must be added to the Xcode target and referenced by
  file name. Until then Apple devices use the default notification sound.
- Notification tap opens the exact task through `NotificationRouter`; verify on a device.

## What changed in this pass that a Mac must re-check

- **Project Flow** screens (More tab and, on macOS, the sidebar): layout only, no platform code.
- **Legal pages** under Settings and on the sign-in screen.
- **Account deletion** now clears every collection (incl. flows) and cancels device reminders.
  On Apple platforms re-authentication for Apple-provider accounts uses a fresh nonce
  (`AccountService.reauthenticateWithAppleCredential`): **never exercised**.
- **Firestore rules were tightened** (shape validators, no wildcard). Any client write that
  does not match fails with permission-denied. The Flutter repositories were run against the
  deployed rules from Windows; an Apple build should be run once the same way.

## Must be tested on a Mac

- [ ] Launch on a simulator and a physical iPhone; launch on macOS
- [ ] Email, Google and Apple sign-in; sign out; relaunch keeps the session
- [ ] Create a task in Quick Add (with repeat), see it on the board and the calendar
- [ ] Board drag and drop (touch on iOS, trackpad on macOS), top drop zone, list Move left/right
- [ ] Completing moves a task to Complete; a repeating task leaves one next occurrence in the original list
- [ ] Project Flows: create from a template, link a task, complete it, stage unlocks
- [ ] A reminder fires; Complete, Snooze and Open actions work; Open lands on the right task
- [ ] Attach a photo from the library and the camera
- [ ] Account deletion with each sign-in method (use a throwaway account)
- [ ] Light, Dark and System themes follow the OS; holiday settings persist

## Things this pass could not verify, for context

Interactive Google sign-in on Android, audible sound and vibration, a PIN-locked lock
screen, and Windows toast action buttons were also out of reach; see the Blocked section of
`WINDOWS_QA_REPORT.md`.

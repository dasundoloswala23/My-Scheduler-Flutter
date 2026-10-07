# macOS Audit — MyPlanScheduler

Audited 2026-10-06. Facts come from the repo and build output.

| Item | Finding | Status |
|---|---|---|
| Bundle ID | `com.myplanscheduler.app` (AppInfo.xcconfig, all configs) | OK |
| RunnerTests bundle ID | Was `com.dasun.myschedule.RunnerTests` | **Fixed** → `com.myplanscheduler.app.RunnerTests` |
| Product/app name | Was `myschedule` (`myschedule.app`) | **Fixed** → `MyPlanScheduler` (xcconfig, pbxproj product refs, shared scheme) |
| Display name | Missing | **Added** `CFBundleDisplayName = MyPlanScheduler` |
| Copyright | `com.dasun` | Fixed → `MyPlanScheduler` |
| Deployment target | macOS 10.15 | OK |
| Signing | Had no team (ad-hoc `-`) | **Set** team `66FLAFF9SU`, Automatic, "Apple Development" |
| App icon | `AppIcon` with all mac sizes 16–1024 | OK |
| Firebase | `DefaultFirebaseOptions.macos` reuses iOS app (same bundle ID) | OK |

## Entitlements (critical)

Before this audit both `DebugProfile.entitlements` and `Release.entitlements` only had the sandbox (+ JIT/server in Debug). In a sandboxed app that means:

1. **No `com.apple.security.network.client`** → Release build could not reach Firebase at all. **Fixed** (both files).
2. **No `keychain-access-groups`** → Firebase Auth on macOS cannot store the session in the keychain. **Fixed** (`$(AppIdentifierPrefix)com.myplanscheduler.app`). Requires a real signing certificate + provisioning profile.
3. **No `com.apple.security.files.user-selected.read-only`** → file_picker cannot read the chosen attachment. **Fixed**.

## Auth

- Email/password: works through Firebase Auth.
- Google: desktop uses `FirebaseAuth.signInWithProvider` (browser flow), not the native SDK.
- Apple: deliberately not offered on macOS (`supportsAppleSignIn` is iOS-only) — no entitlement added.

## Notifications

Same adapter as iOS (`lib/core/notifications/platform/local_notification_adapter.dart`): Complete / Snooze / Open actions, contextual permission, task-specific open routing. Permission detection and Open-foreground fixes from the iOS audit apply to macOS too.

## Desktop input

- Calendar events have a bottom-edge resize handle with a resize cursor (`calendar_page.dart`).
- Board/calendar drag and drop: `Draggable`/`DragTarget` widgets (8 uses) — mouse-compatible.
- Keyboard shortcuts: none existed. **Added** in `lib/features/home/home_shell.dart`: Cmd/Ctrl+K → Search, Cmd/Ctrl+N → New task. Escape closes dialogs/sheets via Flutter defaults. No destructive shortcut was added.

## Not implemented

- Deep links / URL schemes (none on any platform).

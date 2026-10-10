# Apple QA Report — My Scheduler App (iOS / macOS)

Date: 2026-10-09 · Working tree: `main` @ `678f710` + 8 uncommitted files (preserved, not pushed).

Statuses used: **PASS · FIXED · PARTIAL · FAILED · BLOCKED · NOT TESTED**.
Nothing is marked PASS without a command run in this session.

---

## 1. Environment and toolchain — PASS

| Item | Value |
|---|---|
| Flutter | 3.44.0 stable (rev 559ffa3f75) |
| Dart | 3.12.0 |
| Xcode | 26.1.1 (17B100) |
| CocoaPods | 1.16.2 |
| macOS host | 15.7.9 (arm64) |
| iOS simulators | 6 available |
| Physical iPhone | "Tharindu's iPhone", iPhone 17 Pro, iOS 27.0, `available (paired)` — **wireless only** |

## 2. Source commit — PASS

`1031c52` (the Windows handoff commit) is present and is an ancestor of HEAD; `9e4f23f` also
present. `WINDOWS_QA_REPORT.md`, `docs/MAC_HANDOFF.md`, `docs/REMINDERS.md`, `assets/logo.png`
all present. No source transfer was required.

## 3. Static analysis and unit tests — PASS

- `flutter analyze` → **No issues found!**
- `flutter test` → **548/548 passing** (545 inherited baseline + 3 added here for provider gating).

## 4. iOS build — PASS

`flutter build ipa --release` → `build/ios/ipa/My Scheduler App.ipa` (51.2 MB).
Verified by unzipping the artifact and reading its own metadata, not the project files:

| Check | Value |
|---|---|
| `CFBundleShortVersionString` | **1.1.0** |
| `CFBundleVersion` | **2** |
| `CFBundleIdentifier` | `com.myplanscheduler.app` |
| `CFBundleDisplayName` | My Scheduler App |
| `MinimumOSVersion` | 15.0 |
| Signing authority | `Apple Distribution: Dasun Doloswala (66FLAFF9SU)` |
| `get-task-allow` | `0` |
| `com.apple.developer.applesignin` | present |
| Export method | `app-store-connect` |
| `REPLACE_WITH_*` / `GIDClientID` / `CFBundleURLTypes` | **none** |

## 5. Version override removal — FIXED

The marketing version was being forced to 1.0.1 from **two** places, not one:

1. `MARKETING_VERSION = 1.0.1` in the three iOS Runner configs — removed.
2. `FLUTTER_BUILD_NAME = 1.0.1` and `FLUTTER_BUILD_NUMBER = 2` written directly into the same
   configs by Xcode — removed. **This was the effective override**, since a target build setting
   beats Flutter's `Generated.xcconfig`. Removing only (1) did not change the artifact.

`pubspec.yaml` (`1.1.0+2`) is now the single source of truth, proven by the artifact above.
Remaining `MARKETING_VERSION = 1.0` entries belong to the **RunnerTests** target and do not
affect the app.

### macOS version — FIXED (stale generated config), with one latent item

`xcodebuild -showBuildSettings` first resolved macOS to **1.0.0 / 1**. The cause was a **stale
`macos/Flutter/ephemeral/Flutter-Generated.xcconfig`** dated Oct 7 (from when pubspec was
`1.0.0+1`), not `MARKETING_VERSION`. After regeneration it resolves to **1.1.0 / 2**.

**Latent, deliberately not edited:** the macOS Runner target still carries
`MARKETING_VERSION = 1.0.0`. It is inert because `macos/Runner/Info.plist` reads
`$(FLUTTER_BUILD_NAME)`, which now resolves to 1.1.0. Left in place rather than changed, since
evidence showed it is not the active source. Worth removing during a future cleanup so it cannot
become one.

## 6. macOS build and signing — FIXED / PASS

### Root cause

The macOS Runner **Release** config carried no `CODE_SIGN_IDENTITY`, so it inherited the Flutter
template's project-level `CODE_SIGN_IDENTITY = "-"` — **ad-hoc signing**, which cannot carry
profile-backed entitlements (`keychain-access-groups`, `com.apple.developer.applesignin`). Xcode
reported this as the misleading *"entitlements require signing with a development certificate."*
Debug and Profile already specified `"Apple Development"`; only Release was missing it.

**Fix** (one line, macOS only, `macos/Runner.xcodeproj/project.pbxproj`):
`CODE_SIGN_IDENTITY = "Apple Development";` added to the Runner Release config.
No entitlement was removed and no signing was weakened.

A second, independent blocker was that team `66FLAFF9SU` had no registered Mac, surfaced only
after the first fix as `Communication with Apple failed: Your team has no devices…`. The user
registered the Mac (UDID `00008103-0002199C3ED3001E`) on 2026-10-09.

### Archive — PASS

```
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  archive -archivePath <path>/Mac.xcarchive \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration
→ exit 0
```

Verified in the archived app:

| Check | Value |
|---|---|
| Bundle ID | `com.myplanscheduler.app` |
| Display name | My Scheduler App |
| Version / build | **1.1.0 / 2** (confirms the macOS version fix end to end) |
| Signing authority | `Apple Development: Dasun Doloswala` |
| Team identifier | `66FLAFF9SU` |
| Entitlements | sandbox, network.client, user-selected files, keychain-access-groups, applesignin — **all five intact** |
| Embedded profile | `Mac Team Provisioning Profile: com.myplanscheduler.app`, Platform `OSX`, team `66FLAFF9SU`, 1 device, expires 2027-10-09 |

### App Store category validation — FIXED

App Store Connect rejected the first package:

> *The product archive is invalid. The Info.plist must contain a LSApplicationCategoryType key,
> whose value is the UTI for a valid category.*

**Root cause:** the macOS target had
`INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.lifestyle` in its build settings,
but `INFOPLIST_KEY_*` only takes effect when Xcode **generates** the Info.plist. This target sets
`GENERATE_INFOPLIST_FILE = NO` with `INFOPLIST_FILE = Runner/Info.plist`, so the setting was
silently ignored and the key never reached the built app — confirmed absent from the first
archive's `Info.plist`. (Third instance of this class of trap in this project, after
`FLUTTER_BUILD_NAME` and the stale ephemeral xcconfig.)

**Fix:** added `LSApplicationCategoryType = public.app-category.productivity` to
`macos/Runner/Info.plist` — the file that actually ships — and aligned the three inert
`INFOPLIST_KEY_` entries to `productivity` so the dead setting cannot contradict the live one.
`productivity` also suits a task planner better than `lifestyle`. iOS was not touched.

**Verified in the shipped artifact**, not the source: the app expanded out of the exported
`.pkg` payload reports `LSApplicationCategoryType => public.app-category.productivity`, with
`com.myplanscheduler.app`, 1.1.0 / 2 intact.

Rebuilt archive `exit 0`; fresh export `exit 0` → `build/macos/dist-v2/My Scheduler App.pkg`
(112,245,313 bytes). The earlier artifact is preserved at `build/macos/dist/`.

**Server-side App Store validation: NOT TESTED** — `altool --validate-app` needs App Store
Connect credentials, which are not present here and were not requested. The specific category
error is resolved by artifact inspection; only Apple can confirm the package passes every other
check.

### Distribution export — PASS

```
xcodebuild -exportArchive -archivePath <path>/Mac.xcarchive \
  -exportOptionsPlist <path>/ExportOptions.plist -exportPath <path>/MacExport \
  -allowProvisioningUpdates          # method: app-store-connect
→ exit 0
```

Artifact: **`build/macos/dist/My Scheduler App.pkg`** (112 MB), signed
`3rd Party Mac Developer Installer: Dasun Doloswala (66FLAFF9SU)`.
The archive is kept at `build/macos/dist/Mac.xcarchive`. **Not uploaded or published.**

> **Note on the installer certificate:** `pkgutil` reports the package as signed by a
> *Development* installer certificate. That is what automatic signing issued here. Before App
> Store submission, confirm App Store Connect accepts it; if it is rejected, the archive needs
> re-exporting through Xcode Organizer with a Mac App Store distribution certificate. The export
> itself is proven to work.

## 7. Authentication

| Item | iOS | macOS |
|---|---|---|
| Email/password | NOT TESTED (no device run) | NOT TESTED |
| Apple Sign-In | NOT TESTED (entitlement present in artifact) | BLOCKED (signing) |
| Google Sign-In | **FIXED — provider hidden** | **FIXED — provider hidden** |
| Sign-out / session persistence | NOT TESTED | NOT TESTED |
| Account deletion | NOT TESTED on device | NOT TESTED |

### Google Sign-In — FIXED (hidden, not broken)

iOS/macOS had no `GIDClientID`, so the button threw on tap — a Guideline 2.1 rejection risk, and
its placeholder previously caused a real App Store validator rejection. Added
`AuthService.supportsGoogleSignIn`, which gates per platform on actual configuration, reusing the
existing `DesktopGoogleAuth.isConfigured` for Windows and a new `GOOGLE_IOS_CLIENT_ID`
dart-define for Apple platforms. The button and its "or" divider are omitted when no provider
follows. **Windows desktop OAuth is unchanged.** Re-enabling is configuration, not a code edit.

Covered by 3 new tests in `test/sign_in_page_test.dart`.

## 8. Physical device — install PASS, integration tests BLOCKED

### Device deployment — PASS

`flutter build ios --debug` → `build/ios/iphoneos/Runner.app`, then
`flutter install -d 00008150-000869EE0EE2401C` → **exit 0**.

Confirmed present on the handset with `xcrun devicectl device info apps`:

```
My Scheduler App    com.myplanscheduler.app    1.1.0    2
```

The app therefore **builds, signs (`Apple Development: Dasun Doloswala`) and installs on a real
iPhone 17 Pro running iOS 27.0**, at the correct version. Launch-and-drive behaviour was still
not exercised — see below.

> **Cleanup item:** the same query shows a stale leftover from the abandoned rebrand —
> `My Plan Scheduler · com.myplanscheduler.diwlara · 1.0.0 (1)`. It is a different bundle ID, so
> it will sit alongside the real app. Delete it from the phone to avoid confusion during testing.

### Integration tests — BLOCKED

| Command | Result |
|---|---|
| `flutter test integration_test/notification_device_test.dart -d 00008150-…` | **FAILED to start**: `Cannot start app on wirelessly tethered iOS device. Try running again with the --publish-port flag` |
| same, `--publish-port` | **FAILED**: `Could not find an option named "--publish-port"` — the flag does not exist in Flutter 3.44's `flutter test` (the error message's advice is stale) |

Two independent blockers:

1. **The iPhone is tethered wirelessly.** `flutter test -d <device>` cannot launch on it.
   → **Connect the iPhone by USB cable.**
2. **Test credentials are absent by design.** The suites read `MYS_TEST_EMAIL` /
   `MYS_TEST_PASSWORD` from the environment (`docs/SECURITY.md`); nothing in the tree holds them,
   and they were not requested. Auth-dependent assertions cannot run until those are exported in
   the shell.

Not applicable on Apple platforms, recorded as **NOT TESTED** rather than failures:
`alarm_device_test.dart` (written against Android, reads channels back from Android itself),
`windows_ui_test.dart` and `windows_visual_sweep_test.dart` (Windows-only).

## 9. Calendar, Project Flow, core functionality — PARTIAL

Covered by the 548-test suite, including `test/calendar_interaction_test.dart` (drag to another
time, bottom-edge resize, persistence, reminder rescheduling). **No on-device UI verification was
possible**, so real touch drag/resize, keyboard behaviour and safe-area checks are **NOT TESTED**.

## 10. Notifications — NOT TESTED on Apple platforms

Scheduling logic is covered by unit tests, but every device-level behaviour (permission prompt,
delivery foreground/background/terminated, actions, taps opening the right task) is gated behind
the device-test blockers in §8.

## 11. Widgets / lock-screen — NOT IMPLEMENTED

No iOS widget or app-extension target exists in `ios/`. Nothing is claimed.

## 12. Firebase and security — PASS (static) / NOT TESTED (runtime)

- No secrets in the tree: the desktop OAuth secret is read via
  `String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET')`; no `.p8`/`.p12`/`.pem`/service-account
  files are tracked.
- Firebase config targets `myscheduleplanner-e22f3`, bundle `com.myplanscheduler.app`.
- Runtime Firestore/Storage rule behaviour was **not** re-exercised this session.

**Outstanding credential rotation (user action, not performed here):** the exposed desktop OAuth
secret, the Apple `.p8`, and two Firebase service-account private keys pasted into chat earlier —
the production `myscheduleplanner-e22f3` one most urgently. A desktop app cannot keep a bundled
client secret confidential, so that flow should be reviewed regardless.

## 13. Regression — PASS

`flutter analyze` clean and `flutter test` 548/548 after all changes. Changes touched only
iOS/macOS config plus the shared auth-provider gating; Android, Windows and Web source were not
modified and no web deploy was performed.

---

## Bugs found and fixed this session

1. **FIXED** — iOS version pinned to 1.0.1 by `FLUTTER_BUILD_NAME`/`FLUTTER_BUILD_NUMBER`
   hardcoded in the Xcode project, overriding pubspec. Artifact now 1.1.0 (2).
2. **FIXED** — macOS resolving to 1.0.0/1 from a stale generated xcconfig.
3. **FIXED** — Google button offered on platforms where it cannot complete.
4. **FIXED (earlier)** — `REPLACE_WITH_*` placeholders shipped in the IPA, causing an App Store
   validator rejection on URL-scheme format.

## Remaining blockers

| # | Blocker | Owner |
|---|---|---|
| 1 | iPhone connected wirelessly — blocks all device integration tests | User (USB cable) |
| 2 | `MYS_TEST_EMAIL` / `MYS_TEST_PASSWORD` not exported | User |
| 3 | App Store Connect version still shows 1.0 — must be **1.1.0** to match the build | User |
| 4 | Credential rotation (OAuth secret, `.p8`, two Firebase service-account keys) | User |
| 5 | macOS `.pkg` carries a *Development* installer certificate — confirm App Store Connect accepts it | User |

## Store-readiness

- **iOS**: the artifact is valid and uploadable — correct identifier, version, signing,
  entitlements and no placeholders — and the app installs on a real iPhone at 1.1.0 (2).
  Not yet *driven* on device, and not reviewed by Apple.
- **macOS**: archives and exports a signed `.pkg` at 1.1.0 (2). Never launched or exercised as a Release build, and the installer certificate is a Development one (see §6).

## APPLE STATUS: NOT READY

Both platforms now produce correctly signed 1.1.0 (2) artifacts — iOS an App Store IPA that
installs on a physical iPhone 17 Pro, macOS an archive and exported `.pkg` with all five
entitlements and a real team-66FLAFF9SU profile. **Signing and packaging are no longer blockers.**

It is still NOT READY because no behaviour was verified: nothing was *driven* on the iPhone, so
notifications, calendar interaction and every authentication flow (email/password, Apple
Sign-In) remain unexercised on Apple platforms, and the macOS Release build was never launched.
A successful build, install and export is not a substitute for behavioural evidence.

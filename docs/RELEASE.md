# Release

## Before every release

```bash
flutter analyze                      # must be clean
flutter test                         # widget tests
node tools/api-tests/run-all.mjs     # live API + security suite
```

In the web repository:

```bash
npm run lint
npm run build
```

## Builds

| Target | Command | Output | Buildable here |
|---|---|---|---|
| Android APK | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` | yes |
| Android bundle | `flutter build appbundle --release` | `build/app/outputs/bundle/release/` | yes |
| Windows | `flutter build windows --release` | `build/windows/x64/runner/Release/` | yes |
| Flutter Web | `flutter build web --release` | `build/web/` | yes |
| Next.js | `npm run build` | `out/` | yes |
| iOS | `flutter build ios --release` | — | **NOT TESTED — requires macOS** |
| macOS | `flutter build macos --release` | — | **NOT TESTED — requires macOS** |

## Signing

The Android release currently signs with the **debug key**
(`android/app/build.gradle.kts`). This is fine for sideloading and testing and
**must be replaced before publishing**. See `docs/ANDROID_SETUP.md`.

## Deploy

```bash
# Rules
firebase deploy --only firestore:rules --project myscheduleplanner-e22f3
firebase deploy --only storage        --project myscheduleplanner-e22f3

# Web app, from the web repository
npm run build
firebase deploy --only hosting --project myscheduleplanner-e22f3
```

## Version

`pubspec.yaml` holds `version: 1.0.0+1` — name plus build number. Raise the
build number on every store upload.

## Not implemented

- **No CI.** Nothing runs these checks automatically.
- **No in-app update check** (Remote Config / version gate).
- **No in-app review prompt.**
- **No crash reporting.** Crashlytics is not wired up.

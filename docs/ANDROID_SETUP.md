# Android setup

## Google Sign-In needs your signing fingerprints

Email/password sign-in already works on Android. **Google Sign-In will fail
until the app's SHA fingerprints are registered in Firebase.** This is not
something that can be faked or worked around in code — Google matches the
signature of the installed APK against what the project knows about.

These fingerprints have **not** been generated or added yet. Nothing in this
repository contains them.

### 1. Get the debug fingerprints

From the repository root:

```bash
cd android
./gradlew signingReport
```

On Windows without a POSIX shell:

```powershell
cd android
.\gradlew.bat signingReport
```

Look for the `debug` variant and copy the `SHA1` and `SHA-256` lines. They look
like `AB:CD:EF:...` with 20 (SHA-1) or 32 (SHA-256) byte pairs.

If Gradle is unavailable, the same values come from the keystore directly:

```bash
keytool -list -v \
  -alias androiddebugkey \
  -keystore ~/.android/debug.keystore \
  -storepass android -keypass android
```

On Windows the keystore lives at `%USERPROFILE%\.android\debug.keystore`.

### 2. Get the release fingerprints

The release build currently signs with the debug key (see
`android/app/build.gradle.kts`), which is fine for testing but **must not ship
to Play**. When you create a real upload keystore:

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload

keytool -list -v -keystore upload-keystore.jks -alias upload
```

If you use Play App Signing, Google re-signs your app, so you must also copy the
**App signing key certificate** SHA-1 and SHA-256 from
Play Console → Release → Setup → App signing.

### 3. Register them in Firebase

1. https://console.firebase.google.com/project/myscheduleplanner-e22f3/settings/general
2. Scroll to **Your apps** → the Android app (`com.dasun.myschedule`)
3. **Add fingerprint**, paste SHA-1, save. Repeat for SHA-256.
4. Download the refreshed `google-services.json` and replace
   `android/app/google-services.json`.
5. Rebuild: `flutter clean && flutter build apk --release`

### 4. Verify

Install the APK, open it, and tap **Continue with Google**. A working setup
shows the account chooser and returns to the app signed in. The usual failure,
`ApiException: 10`, means the fingerprint does not match — recheck steps 1–3,
and confirm you registered the fingerprint of the *same* build you installed.

## Notification permission

Android 13 and newer require runtime permission. The app asks the first time a
reminder is created, not at launch, and explains why beforehand. The manifest
permission is added by `flutter_local_notifications`.

## Core library desugaring

`android/app/build.gradle.kts` enables `isCoreLibraryDesugaringEnabled` with
`desugar_jdk_libs`. `flutter_local_notifications` requires it; without it the
release build fails at `:app:checkReleaseAarMetadata`. Do not remove it.

## Build commands

```bash
flutter build apk --release          # single APK
flutter build appbundle --release    # Play Store upload
```

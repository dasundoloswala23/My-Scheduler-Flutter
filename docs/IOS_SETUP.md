# iOS and macOS setup

> **NOT TESTED — requires macOS.** Everything in this file was prepared on a
> Windows machine. The iOS and macOS targets have never been built, run, or
> signed. Treat each step as unverified until someone completes it on a Mac
> with Xcode.

## What is already in the repository

- `ios/Runner/Runner.entitlements` exists and declares the Sign in with Apple
  entitlement.
- `lib/features/auth/auth_service.dart` implements Apple sign-in with a nonce
  (SHA-256 hashed for Apple, raw for Firebase), and shows the button only on
  iOS.
- `lib/core/notifications.dart` registers a Darwin notification category with
  Complete, Snooze and Open actions for iOS and macOS.
- `lib/firebase_options.dart` carries the iOS and macOS Firebase options.

## What still has to be done on a Mac

### 1. Attach the entitlements file to the Xcode target

The file exists but is **not referenced by the Xcode project**. Until it is,
Apple sign-in will fail at runtime.

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the **Runner** target → **Signing & Capabilities**.
3. Press **+ Capability** and add **Sign in with Apple**.
   Xcode will wire `Runner.entitlements` into `CODE_SIGN_ENTITLEMENTS` itself.
4. Confirm your Team is selected and the bundle identifier matches the one
   registered in Firebase.

### 2. Enable the Apple provider in Firebase

https://console.firebase.google.com/project/myscheduleplanner-e22f3/authentication/providers
→ **Apple** → enable. For iOS-only sign-in no Services ID is needed. Android,
web and Windows would additionally need a Services ID, key and return URL,
which is out of scope for the current build.

### 3. Apple Developer Program

Sign in with Apple requires a **paid** Apple Developer account. Without one the
capability cannot be added and the button stays hidden at runtime by design.

### 4. Notification permission

`Notifications.requestPermissions()` is called the first time a reminder is
created. No Info.plist key is required for local notifications, but confirm
the request appears on a real device.

### 5. Attachments

`file_picker` and `image_picker` need usage descriptions in
`ios/Runner/Info.plist` before the App Store will accept a build:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Attach photos to your tasks.</string>
<key>NSCameraUsageDescription</key>
<string>Take a photo to attach to a task.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Record audio to attach to a task.</string>
```

These have **not** been added yet, because they could not be verified here.

### 6. Minimum deployment target

`sign_in_with_apple` and the Firebase pods need iOS 13 or newer and macOS 10.15
or newer. Check `ios/Podfile` and `macos/Podfile` and raise `platform :ios` if
CocoaPods complains.

## Build commands (on a Mac)

```bash
cd ios && pod install && cd ..
flutter build ios --release
flutter build macos --release
```

## Verification checklist for whoever has the Mac

- [ ] App launches on a simulator and a physical device
- [ ] Apple sign-in button appears and completes sign-in
- [ ] Google and email sign-in still work
- [ ] A reminder fires and its Complete / Snooze / Open actions behave
- [ ] Tapping a notification deep-links to the right task
- [ ] Attaching a photo from the library and the camera both work
- [ ] Drag and drop works with touch on iOS and trackpad on macOS

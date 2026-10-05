# My scheduler

A Trello-style task manager and scheduler: boards with drag-and-drop lists, a
calendar you can drag tasks onto, subtasks, reminders, attachments, focus
timer, Eisenhower matrix and statistics.

Two clients share one Firebase project, so a card moved in one appears moved in
the other within a second.

| Client | Repository | Platforms |
|---|---|---|
| Flutter | this one | Android, iOS, Windows, macOS, Flutter Web |
| Next.js | [`-My-Scheduler-Web`](https://github.com/dasundoloswala23/-My-Scheduler-Web) | Browsers — https://myscheduleplanner-e22f3.web.app |

The web app is a native React client, not Flutter Web.

## Running it

```bash
flutter pub get
flutter run -d windows     # or -d chrome, or a connected device
```

Firebase is already configured (`lib/firebase_options.dart`). Google Sign-In on
Android additionally needs your signing fingerprints registered — see
[docs/ANDROID_SETUP.md](docs/ANDROID_SETUP.md).

## Tests

```bash
flutter analyze
flutter test
node tools/api-tests/run-all.mjs   # live Firebase: data layer + storage security
```

The API suite runs against the real project through the same API the apps use,
so it covers the security rules as well as the data.

## Documentation

| Document | Covers |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | layers, drag-and-drop, ordering, concurrency |
| [FIREBASE.md](docs/FIREBASE.md) | data model, deploys, enabling services |
| [SECURITY.md](docs/SECURITY.md) | rules, what is tested, known gaps |
| [ATTACHMENTS.md](docs/ATTACHMENTS.md) | Storage layout, upload, clean-up |
| [NOTIFICATIONS.md](docs/NOTIFICATIONS.md) | reminders, actions, recurrence |
| [ANDROID_SETUP.md](docs/ANDROID_SETUP.md) | SHA fingerprints, desugaring |
| [IOS_SETUP.md](docs/IOS_SETUP.md) | Apple sign-in, what still needs a Mac |
| [WIDGETS.md](docs/WIDGETS.md) | native widgets — not implemented, and why |
| [RELEASE.md](docs/RELEASE.md) | build and deploy |

## Status

Built and verified on Windows: Android APK, Windows desktop, Flutter Web, and
the Next.js production build. 39 automated checks pass against live Firebase.

**iOS and macOS have never been built or tested** — they need a Mac. Native
widgets, in-app update checks and in-app review are not implemented. See the
documents above for specifics.

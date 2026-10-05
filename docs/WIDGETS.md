# Native widgets

> **NOT IMPLEMENTED.** This document records what was asked for and what it
> would take, so nobody mistakes the current state for a partial build. There
> is no widget code in this repository.

Requested: Android App Widget, iOS and macOS WidgetKit, and a Windows
quick-access surface, in small (next task), medium (today's tasks) and large
(today's schedule plus progress) sizes, each deep-linking into the right task.

## Why it is not done

Widgets are not Flutter screens. Each platform needs native code in its own
language and UI framework, plus a way to get data out of Flutter and into the
widget process:

| Platform | Needs |
|---|---|
| Android | Kotlin `AppWidgetProvider`, XML layouts, `SharedPreferences` bridge |
| iOS / macOS | Swift + SwiftUI WidgetKit extension, App Group shared container |
| Windows | No real widget API; the nearest equivalents are a system tray surface or a taskbar jump list |

The usual bridge is the `home_widget` package, which writes shared values the
native widget reads. The deep link then arrives as a URI the app routes.

## Sketch of the work

1. Add `home_widget`, write today's tasks to shared storage after each
   Firestore snapshot.
2. Android: widget provider, three layouts, a receiver for refreshes, and a
   `PendingIntent` carrying the task id.
3. iOS/macOS: WidgetKit extension with a timeline provider, App Group entitlement
   shared with the Runner target, `widgetURL` per row.
4. Deep links: a route like `myscheduler://task/{id}`, handled where
   `NotificationRouter` already handles notification taps — that plumbing is
   reusable.
5. Windows: decide between a tray icon and a jump list; neither matches the
   widget concept directly.

Steps 3 and 5 cannot be built or tested on this Windows machine at all.

## Honest estimate

This is a self-contained project of its own, comparable in size to the
attachments work, and it needs a Mac for half of it. It should be its own
phase, after the Flutter app has been verified on real devices — widgets that
deep-link into unverified screens are not worth building yet.

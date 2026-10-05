# Architecture

Two clients, one Firebase project, one data model.

| Client | Path | Platforms |
|---|---|---|
| Flutter app | this repository | Android, iOS, Windows, macOS, Flutter Web |
| Next.js web app | `My-Scheduler-Web` repository | Browsers, deployed to Firebase Hosting |

The web app is **not** Flutter Web. It is a native React client that reads and
writes the same Firestore documents, so a card dragged in one appears moved in
the other within a second.

## Layers (Flutter)

```
lib/
  app/           theme
  core/          repository, providers, services  ← all business logic
  models/        task, attachment, collections    ← plain data classes
  features/      one folder per screen            ← UI only
```

- `core/repository.dart` — every Firestore read and write. Screens never touch
  Firestore directly.
- `core/providers.dart` — Riverpod providers that stream collections and merge
  optimistic overrides.
- `core/move_controller.dart` — the single path every drag-and-drop move takes.
- `core/attachment_service.dart` — Storage uploads, downloads and clean-up.
- `core/reminder_scheduler.dart` — turns a task's reminder offsets into
  scheduled notifications.

The web app mirrors this: `lib/repo.ts`, `lib/hooks.ts`, `lib/use-move.ts`.

## Why moves go through one controller

Every drag — board reorder, between lists, onto the calendar, across days,
resize, Eisenhower quadrant — calls `MoveController.run` (`useMove` on web).
That one place is responsible for:

1. Writing an optimistic copy into local state so the card moves instantly.
2. Running a Firestore transaction that re-reads `version`, writes only the
   changed fields, and increments `version`.
3. Clearing the override so the live stream takes over.
4. Rolling back and showing an error if the write fails.
5. Offering Undo for five seconds.

Keeping this in one function is why a failed drag can never leave the board in
a half-moved state, and why adding a new drag surface costs a few lines.

## Ordering

Cards carry a `position` double. A drop writes the midpoint between its new
neighbours, so **one drop writes one document** rather than renumbering a list.
When two neighbours get too close for a double to split, the list is
renumbered once (`Position.rebalanced`). The web app uses the identical
algorithm in `lib/position.ts`, so both clients agree on order.

## Concurrency

Each task carries an integer `version`. A move reads it inside the transaction
and writes `version + 1`. If another device wrote in between, the transaction
retries against fresh data rather than clobbering it. Tests cover this
(`tools/api-tests/data-layer.test.mjs`).

## Offline

Both clients keep a persistent local cache — Firestore's own on mobile and
desktop, IndexedDB with a multi-tab manager on web. Reads are served from cache
when the network is gone and writes queue and replay on reconnect. A banner
tells the user when this is happening.

## Data model

Everything lives under `users/{uid}/`, which is what makes the security rules a
single ownership check. See `docs/FIREBASE.md`.

## Testing

`tools/api-tests/` runs against the real project through the public API key and
a signed-in user's token — the same path the apps take — so it covers the
security rules too, not just data shapes.

```bash
node tools/api-tests/run-all.mjs
```

# Firebase

Project: `myscheduleplanner-e22f3` (project number `455014733188`)

| Service | State |
|---|---|
| Authentication | Enabled — Email/Password and Google |
| Cloud Firestore | Enabled, **us-central1**, rules deployed |
| Cloud Storage | Enabled, rules deployed |
| Hosting | Deployed — https://myscheduleplanner-e22f3.web.app |

The Firestore location is permanent and cannot be changed.

## Data model

Everything is scoped to one user, which is what lets the rules be a single
ownership check.

```
users/{uid}
  bootstrapped: bool            set once the defaults are seeded
  boards/{id}                   name, colorValue, position, workspace
  lists/{id}                    boardId, name, position, colorValue, isSystem
  categories/{id}               name, colorValue, position, iconCode
  tasks/{id}
    title, description
    boardId, listId, categoryId, parentTaskId
    position            double, fractional index for ordering
    completed, priority
    startDateTime, endDateTime, hasSchedule
    recurrence                  none|daily|weekdays|weekly|monthly|yearly
    reminderOffsets             list of minutes before the start time
    reminderMinutesBefore       legacy single-reminder field
    subtasks[]                  {id, title, done, position}
    attachments[]               legacy filename strings
    attachmentCount             count of real attachments
    createdAt, updatedAt, completedAt
    version                     int, incremented on every write
    attachments/{id}            real attachment metadata, see ATTACHMENTS.md
  notes/{id}                    title, body, categoryId, updatedAt
  reminders/{id}                title, remindAt, done, notificationId
  holidays/{id}                 name, date, region
  focusSessions/{id}            startedAt, minutes, taskId, taskTitle
```

Both clients write these exact shapes. Changing one without the other breaks
cross-device sync.

## Seeding

The first time a user signs in, either client creates a Personal Board, six
lists (Inbox, Todo, In progress, Waiting, Done, Someday) and twelve categories,
then sets `bootstrapped: true`. Whichever client opens first wins; the other
sees the flag and leaves it alone.

## Deploying rules

```bash
firebase deploy --only firestore:rules --project myscheduleplanner-e22f3
firebase deploy --only storage        --project myscheduleplanner-e22f3
```

## Deploying the web app

From the web repository:

```bash
npm run build          # static export to out/
firebase deploy --only hosting --project myscheduleplanner-e22f3
```

The site is a static export, so there is no server. That is why the board route
is `/board?id=…` rather than `/boards/[id]` — a dynamic segment would need
every board id at build time, and those belong to each user.

## Enabling services from scratch

If a service shows `CONFIGURATION_NOT_FOUND` or "API has not been used":

```bash
# APIs
firebase deploy --only firestore:rules   # auto-enables firestore.googleapis.com

# Firestore database (location is permanent)
firebase firestore:databases:create "(default)" --location us-central1
```

**Authentication cannot be enabled from the CLI.** The Identity Platform API
path requires billing; the free path is the console:
Authentication → Get started → enable the providers.

## Costs

Everything currently in use fits the free Spark plan. Cloud Functions, which
would be needed for server-side image thumbnails, require Blaze.

/**
 * Signs in the test account, seeds realistic data in the exact schema both
 * apps use, then exercises the system: a transactional drag-and-drop move,
 * a subtask toggle, and the security rules.
 *
 * Everything goes through the public API key and the user's own ID token, so
 * this is the same path the real apps take.
 */
const KEY = "AIzaSyAqNL0cPUS0hthRLh3OQvOIGueFDZOMLQ0";
const PROJECT = "myscheduleplanner-e22f3";
const EMAIL = "dasuntest3@gmail.com";
const PASSWORD = "123456";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

// This machine's connection drops requests now and then (ECONNRESET /
// ENOTFOUND), so every call retries with backoff instead of killing the run.
const rawFetch = globalThis.fetch;
globalThis.fetch = async (url, options = {}) => {
  let lastError;
  for (let attempt = 1; attempt <= 6; attempt++) {
    try {
      return await rawFetch(url, { ...options, signal: AbortSignal.timeout(30000) });
    } catch (e) {
      lastError = e;
      const wait = 1000 * attempt;
      console.log(`  (network hiccup, retry ${attempt}/6 in ${wait}ms)`);
      await new Promise((r) => setTimeout(r, wait));
    }
  }
  throw lastError;
};

const pass = [];
const fail = [];
function check(name, ok, detail = "") {
  (ok ? pass : fail).push(name);
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
}

// ----------------------------------------------------------- firestore types
function toValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number")
    return Number.isInteger(v) && Math.abs(v) < 2 ** 31
      ? { integerValue: String(v) }
      : { doubleValue: v };
  if (typeof v === "string") return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  return { mapValue: { fields: toFields(v) } };
}
const toFields = (obj) => Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, toValue(v)]));

function fromValue(v) {
  if (!v) return null;
  if ("nullValue" in v) return null;
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("timestampValue" in v) return new Date(v.timestampValue);
  if ("arrayValue" in v) return (v.arrayValue.values ?? []).map(fromValue);
  if ("mapValue" in v) return fromFields(v.mapValue.fields ?? {});
  return null;
}
const fromFields = (f) => Object.fromEntries(Object.entries(f).map(([k, v]) => [k, fromValue(v)]));

// ------------------------------------------------------------------- helpers
let token = "";
const authHeaders = () => ({ Authorization: `Bearer ${token}`, "Content-Type": "application/json" });

async function createDoc(path, data, docId) {
  const url = `${BASE}/${path}${docId ? `?documentId=${docId}` : ""}`;
  const res = await fetch(url, {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify({ fields: toFields(data) }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`${path}: ${json.error?.message ?? res.status}`);
  return json.name.split("/").pop();
}

async function patchDoc(path, data) {
  const mask = Object.keys(data)
    .map((k) => `updateMask.fieldPaths=${k}`)
    .join("&");
  const res = await fetch(`${BASE}/${path}?${mask}`, {
    method: "PATCH",
    headers: authHeaders(),
    body: JSON.stringify({ fields: toFields(data) }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`patch ${path}: ${json.error?.message ?? res.status}`);
  return json;
}

async function getDoc(path) {
  const res = await fetch(`${BASE}/${path}`, { headers: authHeaders() });
  const json = await res.json();
  return res.ok ? fromFields(json.fields ?? {}) : null;
}

async function listDocs(path) {
  const res = await fetch(`${BASE}/${path}?pageSize=300`, { headers: authHeaders() });
  const json = await res.json();
  if (!res.ok) return [];
  return (json.documents ?? []).map((d) => ({ id: d.name.split("/").pop(), ...fromFields(d.fields ?? {}) }));
}

// --------------------------------------------------------------------- 1. auth
let r = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${KEY}`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ email: EMAIL, password: PASSWORD, returnSecureToken: true }),
});
let auth = await r.json();

if (!r.ok && auth.error?.message === "EMAIL_EXISTS") {
  r = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD, returnSecureToken: true }),
  });
  auth = await r.json();
  check("Sign in with existing email/password", r.ok, r.ok ? "" : auth.error?.message);
} else {
  check("Create account with email/password", r.ok, r.ok ? "" : auth.error?.message);
}

if (!r.ok) {
  console.log("\nCannot continue without authentication.");
  process.exit(1);
}

token = auth.idToken;
const uid = auth.localId;
console.log(`\nSigned in as ${EMAIL}\nuid: ${uid}\n`);

// Give the account a display name, like the sign-up screen does.
await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:update?key=${KEY}`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ idToken: token, displayName: "Dasun Test", returnSecureToken: false }),
});

// ---------------------------------------------------------------- 2. bootstrap
const existingBoards = await listDocs(`users/${uid}/boards`);
let boardId;
let listIds = {};
let categoryIds = {};

if (existingBoards.length === 0) {
  boardId = await createDoc(`users/${uid}/boards`, {
    name: "Personal Board",
    colorValue: 0x6c5ce7,
    position: 1000,
    workspace: "Personal workspace",
    updatedAt: new Date(),
  });

  const listDefs = [
    ["Inbox", 0x9ca3af],
    ["Todo", 0x6c5ce7],
    ["In progress", 0xe8a33d],
    ["Waiting", 0x3b82f6],
    ["Done", 0x30a46c],
    ["Someday", 0xa78bfa],
  ];
  for (let i = 0; i < listDefs.length; i++) {
    const [name, colorValue] = listDefs[i];
    listIds[name] = await createDoc(`users/${uid}/lists`, {
      boardId,
      name,
      position: (i + 1) * 1000,
      colorValue,
      isSystem: true,
      updatedAt: new Date(),
    });
  }

  const cats = [
    ["Job", 0x3b82f6], ["Personal", 0x30a46c], ["Company", 0x6c5ce7], ["Apps", 0x8b5cf6],
    ["YouTube", 0xe5484d], ["TikTok", 0x111827], ["Facebook", 0x1877f2], ["Nail Art", 0xec4899],
    ["Hair Style", 0xe8a33d], ["Kitty Meow", 0xf59e0b], ["Pirith", 0x14b8a6], ["Other", 0x6b7280],
  ];
  for (let i = 0; i < cats.length; i++) {
    const [name, colorValue] = cats[i];
    categoryIds[name] = await createDoc(`users/${uid}/categories`, {
      name,
      colorValue,
      position: (i + 1) * 1000,
      iconCode: 0,
      updatedAt: new Date(),
    });
  }

  await patchDoc(`users/${uid}`, { bootstrapped: true, createdAt: new Date() });
  check("Seed default board, 6 lists and 12 categories", true);
} else {
  boardId = existingBoards[0].id;
  for (const l of await listDocs(`users/${uid}/lists`)) listIds[l.name] = l.id;
  for (const c of await listDocs(`users/${uid}/categories`)) categoryIds[c.name] = c.id;
  check("Workspace already seeded, reusing it", true);
}

// -------------------------------------------------------------------- 3. tasks
const today = new Date();
const at = (dayOffset, hour, minute = 0) => {
  const d = new Date(today);
  d.setDate(d.getDate() + dayOffset);
  d.setHours(hour, minute, 0, 0);
  return d;
};
const sub = (title, done, i) => ({ id: `s${i}-${Math.random().toString(36).slice(2, 8)}`, title, done, position: (i + 1) * 1000 });

const existingTasks = await listDocs(`users/${uid}/tasks`);
if (existingTasks.length === 0) {
  const taskDefs = [
    {
      title: "Launch app beta", description: "Make the next step clear and move this work forward.",
      list: "In progress", category: "Apps", priority: "high", start: at(0, 9), end: at(0, 10),
      subtasks: [sub("Find idea", true, 0), sub("Write script", true, 1), sub("Record", true, 2),
                 sub("Edit", false, 3), sub("Create thumbnail", false, 4), sub("Upload", false, 5), sub("SEO", false, 6)],
      attachments: ["video-cover-final.jpg"],
    },
    {
      title: "Kitty Meow video", description: "Make the next step clear and move this work forward.",
      list: "In progress", category: "Kitty Meow", priority: "medium", start: at(0, 14), end: at(0, 15, 30),
      subtasks: [sub("Script", true, 0), sub("Shoot", true, 1), sub("Edit", true, 2), sub("Thumbnail", false, 3),
                 sub("Upload", false, 4), sub("Describe", false, 5), sub("Share", false, 6)],
      attachments: ["thumb.png", "raw.mp4"],
    },
    {
      title: "Q4 content calendar", description: "Plan the next quarter of posts.",
      list: "In progress", category: "Company", priority: "medium", start: at(1, 11), end: at(1, 12),
      subtasks: [],
    },
    {
      title: "Update portfolio", description: "Refresh the case studies and screenshots.",
      list: "Waiting", category: "Personal", priority: "low", start: at(2, 10), end: at(2, 11),
      subtasks: [sub("Collect shots", true, 0), sub("Write copy", true, 1), sub("Publish", false, 2), sub("Share", false, 3)],
    },
    {
      title: "Morning team stand-up", description: "Daily sync with the team.",
      list: "Todo", category: "Job", priority: "high", start: at(0, 8, 30), end: at(0, 9),
      subtasks: [], recurrence: "weekdays",
    },
    {
      title: "Review FlowBoard onboarding", description: "Check the first-run experience end to end.",
      list: "Todo", category: "Apps", priority: "high", start: at(0, 11), end: at(0, 12),
      subtasks: [sub("Sign-up flow", false, 0), sub("Empty states", false, 1)],
    },
    {
      title: "Record productivity setup", description: "Film the desk tour for the channel.",
      list: "Todo", category: "YouTube", priority: "medium", start: at(1, 15), end: at(1, 17),
      subtasks: [],
    },
    { title: "Send invoice to Studio North", list: null, category: null, priority: "none", subtasks: [] },
    { title: "Research microphone for videos", list: null, category: null, priority: "none", subtasks: [] },
    { title: "Book dentist appointment", list: null, category: "Personal", priority: "low", subtasks: [] },
    {
      title: "Set up analytics events", description: "Done last week.",
      list: "Done", category: "Apps", priority: "medium", completed: true,
      subtasks: [sub("Plan", true, 0), sub("Implement", true, 1), sub("Verify", true, 2), sub("Document", true, 3)],
    },
    {
      title: "Pirith recording", description: "Evening listening session.",
      list: "Someday", category: "Pirith", priority: "none", subtasks: [],
    },
  ];

  let created = 0;
  for (let i = 0; i < taskDefs.length; i++) {
    const t = taskDefs[i];
    await createDoc(`users/${uid}/tasks`, {
      title: t.title,
      description: t.description ?? "",
      boardId: t.list ? boardId : null,
      listId: t.list ? listIds[t.list] : null,
      categoryId: t.category ? categoryIds[t.category] : null,
      parentTaskId: null,
      position: (i + 1) * 1000,
      completed: !!t.completed,
      priority: t.priority ?? "none",
      startDateTime: t.start ?? null,
      endDateTime: t.end ?? null,
      hasSchedule: !!t.start,
      recurrence: t.recurrence ?? "none",
      reminderMinutesBefore: null,
      subtasks: t.subtasks ?? [],
      attachments: t.attachments ?? [],
      createdAt: new Date(),
      updatedAt: new Date(),
      completedAt: t.completed ? new Date() : null,
      version: 1,
    });
    created++;
  }
  check(`Create ${created} tasks across lists, calendar and inbox`, created === taskDefs.length);

  // Notes, reminders, holidays, focus sessions.
  await createDoc(`users/${uid}/notes`, { title: "Video ideas", body: "Desk tour, keyboard review, Kitty Meow part 2.", categoryId: categoryIds["YouTube"], updatedAt: new Date() });
  await createDoc(`users/${uid}/notes`, { title: "Client brief", body: "Studio North wants the rebrand by December.", categoryId: categoryIds["Job"], updatedAt: new Date() });
  await createDoc(`users/${uid}/reminders`, { title: "Pay internet bill", remindAt: at(1, 9), done: false, notificationId: Math.floor(+at(1, 9) / 1000), updatedAt: new Date() });
  await createDoc(`users/${uid}/reminders`, { title: "Call the dentist", remindAt: at(3, 10), done: false, notificationId: Math.floor(+at(3, 10) / 1000), updatedAt: new Date() });
  const year = today.getFullYear();
  for (const [m, d, name] of [[1, 15, "Tamil Thai Pongal Day"], [2, 4, "Independence Day"], [5, 1, "May Day"], [10, 5, "World Teachers' Day"], [12, 25, "Christmas Day"]]) {
    await createDoc(`users/${uid}/holidays`, { name, date: new Date(year, m - 1, d), region: "Sri Lanka" });
  }
  await createDoc(`users/${uid}/focusSessions`, { startedAt: at(0, 9, 10), minutes: 25, taskId: null, taskTitle: "Launch app beta" });
  await createDoc(`users/${uid}/focusSessions`, { startedAt: at(0, 10, 45), minutes: 50, taskId: null, taskTitle: "Kitty Meow video" });
  check("Create notes, reminders, holidays and focus sessions", true);
} else {
  check(`Tasks already present (${existingTasks.length}), skipping seed`, true);
}

// ------------------------------------------------------- 4. exercise the system
console.log("\n--- exercising the system ---");

const tasks = await listDocs(`users/${uid}/tasks`);
const lists = await listDocs(`users/${uid}/lists`);
check("Read tasks back", tasks.length > 0, `${tasks.length} tasks`);
check("Read lists back", lists.length === 6, `${lists.length} lists`);
check("Read categories back", (await listDocs(`users/${uid}/categories`)).length === 12);

// 4a. A drag-and-drop move, done the way the apps do it: read the current
// version inside a transaction, write the new list/position, bump the version.
const moving = tasks.find((t) => t.title === "Q4 content calendar");
// The completed list was called "Done" before the Complete list existed.
const targetList = lists.find((l) => l.name === "Complete" || l.name === "Done");
const docPath = `projects/${PROJECT}/databases/(default)/documents/users/${uid}/tasks/${moving.id}`;

const txRes = await fetch(
  `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:beginTransaction`,
  { method: "POST", headers: authHeaders(), body: "{}" },
);
const { transaction } = await txRes.json();

const readRes = await fetch(
  `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:batchGet`,
  {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify({ documents: [docPath], transaction }),
  },
);
const readJson = await readRes.json();
const beforeVersion = Number(readJson[0]?.found?.fields?.version?.integerValue ?? 0);

const newPosition = 500; // midpoint ahead of the first card, like a drop at the top
const commitRes = await fetch(
  `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:commit`,
  {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify({
      transaction,
      writes: [
        {
          update: {
            name: docPath,
            fields: toFields({
              listId: targetList.id,
              position: newPosition,
              updatedAt: new Date(),
              version: beforeVersion + 1,
            }),
          },
          updateMask: { fieldPaths: ["listId", "position", "updatedAt", "version"] },
        },
      ],
    }),
  },
);
check("Transactional drag-and-drop move commits", commitRes.ok, commitRes.ok ? "" : JSON.stringify(await commitRes.json()).slice(0, 160));

const afterMove = await getDoc(`users/${uid}/tasks/${moving.id}`);
check("Moved task landed in the target list", afterMove.listId === targetList.id, `now in "${targetList.name}"`);
check("Position updated for ordering", afterMove.position === newPosition, `position ${afterMove.position}`);
check("Version bumped for conflict detection", afterMove.version === beforeVersion + 1, `${beforeVersion} -> ${afterMove.version}`);

// 4b. Undo: write the previous values back, exactly like the Undo snackbar.
await patchDoc(`users/${uid}/tasks/${moving.id}`, {
  listId: moving.listId,
  position: moving.position,
  version: afterMove.version + 1,
  updatedAt: new Date(),
});
const afterUndo = await getDoc(`users/${uid}/tasks/${moving.id}`);
check("Undo restores the original list", afterUndo.listId === moving.listId);
check("Task still exists after move and undo (never destructive)", afterUndo.title === moving.title);

// 4c. Scheduling a task by dropping it on a calendar slot.
const unscheduled = tasks.find((t) => t.title === "Send invoice to Studio North");
const slot = at(1, 14, 30);
await patchDoc(`users/${uid}/tasks/${unscheduled.id}`, {
  startDateTime: slot,
  endDateTime: new Date(+slot + 3600000),
  hasSchedule: true,
  version: unscheduled.version + 1,
  updatedAt: new Date(),
});
const afterSchedule = await getDoc(`users/${uid}/tasks/${unscheduled.id}`);
check("Drag to calendar sets the start time", +afterSchedule.startDateTime === +slot, afterSchedule.startDateTime?.toISOString());
check("Duration kept as one hour", +afterSchedule.endDateTime - +afterSchedule.startDateTime === 3600000);

// 4d. Resize: change only the end time.
await patchDoc(`users/${uid}/tasks/${unscheduled.id}`, {
  endDateTime: new Date(+slot + 5400000),
  version: afterSchedule.version + 1,
  updatedAt: new Date(),
});
const afterResize = await getDoc(`users/${uid}/tasks/${unscheduled.id}`);
check("Resize changes duration to 90 minutes", (+afterResize.endDateTime - +afterResize.startDateTime) / 60000 === 90);

// 4e. Ticking a subtask. Pick one that is NOT already done, otherwise the
// count cannot rise and the check would fail for the wrong reason.
const withSubs = tasks.find((t) => (t.subtasks ?? []).some((s) => !s.done));
const beforeDone = withSubs.subtasks.filter((s) => s.done).length;
const targetIndex = withSubs.subtasks.findIndex((s) => !s.done);
const toggled = withSubs.subtasks.map((s, i) => (i === targetIndex ? { ...s, done: true } : s));
await patchDoc(`users/${uid}/tasks/${withSubs.id}`, { subtasks: toggled, updatedAt: new Date() });
const afterSub = await getDoc(`users/${uid}/tasks/${withSubs.id}`);
const doneNow = afterSub.subtasks.filter((s) => s.done).length;
check("Subtask toggle saves progress", doneNow === beforeDone + 1,
  `${doneNow}/${afterSub.subtasks.length} done`);
// Put it back so repeated runs start from the same place.
await patchDoc(`users/${uid}/tasks/${withSubs.id}`, { subtasks: withSubs.subtasks });

// ------------------------------------------------------------ 5. security rules
console.log("\n--- security rules ---");

const otherUid = "someone-elses-uid-000000";
const foreign = await fetch(`${BASE}/users/${otherUid}/tasks`, { headers: authHeaders() });
check("Cannot read another user's tasks", foreign.status === 403, `HTTP ${foreign.status}`);

const foreignWrite = await fetch(`${BASE}/users/${otherUid}/tasks`, {
  method: "POST",
  headers: authHeaders(),
  body: JSON.stringify({ fields: toFields({ title: "should not be allowed" }) }),
});
check("Cannot write into another user's space", foreignWrite.status === 403, `HTTP ${foreignWrite.status}`);

const anon = await fetch(`${BASE}/users/${uid}/tasks`);
check("Signed-out access is refused", anon.status === 401 || anon.status === 403, `HTTP ${anon.status}`);

const ownRead = await fetch(`${BASE}/users/${uid}/tasks`, { headers: authHeaders() });
check("Own data is readable while signed in", ownRead.status === 200);

// -------------------------------------------------------------------- summary
console.log(`\n================ ${pass.length} passed, ${fail.length} failed ================`);
if (fail.length) {
  console.log("Failures:");
  fail.forEach((f) => console.log(" - " + f));
}
const finalTasks = await listDocs(`users/${uid}/tasks`);
console.log(`\nAccount: ${EMAIL} / ${PASSWORD}`);
console.log(`Tasks: ${finalTasks.length} | scheduled: ${finalTasks.filter((t) => t.startDateTime).length} | inbox: ${finalTasks.filter((t) => !t.listId).length} | completed: ${finalTasks.filter((t) => t.completed).length}`);
console.log(`Notes: ${(await listDocs(`users/${uid}/notes`)).length} | Reminders: ${(await listDocs(`users/${uid}/reminders`)).length} | Holidays: ${(await listDocs(`users/${uid}/holidays`)).length} | Focus: ${(await listDocs(`users/${uid}/focusSessions`)).length}`);
process.exit(fail.length ? 1 : 0);
